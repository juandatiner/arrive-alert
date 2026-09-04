import 'package:latlong2/latlong.dart';
import '../models/journey.dart';
import '../models/transit_route.dart';
import 'transit_index_service.dart';

const _distance = Distance();

/// Best option found so far for boarding one route and riding it to a stop.
class _Reach {
  final int routeIndex;
  final int boardSeq;
  final int atSeq;
  final double seconds;
  final double accessMeters;

  const _Reach({
    required this.routeIndex,
    required this.boardSeq,
    required this.atSeq,
    required this.seconds,
    required this.accessMeters,
  });
}

/// Door-to-door transit options over the bundled network.
///
/// There are no timetables in the pack (one representative trip per route is
/// all that survives the GTFS build), so this ranks by distance and a
/// per-service average speed plus an average wait - never by departure time.
/// It searches direct rides and one transfer, which covers virtually every
/// trip inside Bogota.
class JourneyPlanner {
  static const _walkKmh = 4.5;
  static const _accessWalkMeters = 700.0;
  static const _accessWalkMetersFallback = 1500.0;
  static const _transferWalkMeters = 400.0;

  /// Charged on top of the second ride's own wait: a transfer costs the
  /// rider more than the same minutes spent seated.
  static const _transferPenaltySeconds = 90.0;

  /// Walking the whole way is worth offering instead of a bus for short
  /// hops, the way Maps does.
  static const _walkOnlyMeters = 1400.0;

  /// Under half a kilometre, no bus is worth it: the walk is over before the
  /// service turns up. Below this the planner offers walking and nothing
  /// else, and no single ride shorter than this is ever suggested.
  static const _minimumRideMeters = 500.0;

  static const _maxAccessStops = 24;
  static const _maxJoinCandidates = 1500;

  static double _walkSeconds(double meters) => meters / (_walkKmh / 3.6);

  /// Average headway per service, standing in for a departure time.
  static double _waitSeconds(TransitKind kind) {
    switch (kind) {
      case TransitKind.troncal:
        return 240;
      case TransitKind.cable:
        return 240;
      case TransitKind.alimentador:
        return 420;
      case TransitKind.zonal:
        return 480;
    }
  }

  static double _rideSeconds(TransitKind kind, double meters) =>
      meters / (kind.averageKmh / 3.6);

  static Future<List<Journey>> plan({
    required LatLng origin,
    required LatLng destination,
    int limit = 5,
  }) async {
    final index = await TransitIndexService.load();

    final walkAll = _distance.as(LengthUnit.Meter, origin, destination);
    final journeys = <Journey>[];
    if (walkAll <= _walkOnlyMeters) {
      journeys.add(Journey([
        WalkLeg(
          from: origin,
          to: destination,
          toLabel: 'Destino',
          meters: walkAll,
          seconds: _walkSeconds(walkAll),
        ),
      ]));
    }
    // Too close to be a bus trip at all.
    if (walkAll < _minimumRideMeters) return journeys;

    var originStops = index.stopsNear(origin, _accessWalkMeters);
    if (originStops.isEmpty) {
      originStops = index.stopsNear(origin, _accessWalkMetersFallback);
    }
    var destStops = index.stopsNear(destination, _accessWalkMeters);
    if (destStops.isEmpty) {
      destStops = index.stopsNear(destination, _accessWalkMetersFallback);
    }
    if (originStops.isEmpty || destStops.isEmpty) return journeys;

    originStops = originStops.take(_maxAccessStops).toList();
    destStops = destStops.take(_maxAccessStops).toList();

    // (route, position) -> shortest walk that reaches/leaves it.
    final boardings = _accessPairs(index, originStops);
    final alightings = _accessPairs(index, destStops);

    journeys.addAll(_direct(index, origin, destination, boardings, alightings));
    journeys.addAll(
      _oneTransfer(index, origin, destination, boardings, alightings),
    );

    // A ride of a couple of blocks is not a recommendation, it is noise.
    journeys.removeWhere(
      (journey) => journey.rides.any((r) => r.meters < _minimumRideMeters),
    );

    // Two options that differ only by which bay of a station they board at
    // are the same trip to a rider, so keep the cheapest of each.
    final best = <String, Journey>{};
    for (final journey in journeys) {
      final current = best[journey.signature];
      if (current == null || journey.totalSeconds < current.totalSeconds) {
        best[journey.signature] = journey;
      }
    }
    final ranked = best.values.toList()
      ..sort((a, b) => a.totalSeconds.compareTo(b.totalSeconds));
    return _mergeSharedCorridors(ranked).take(limit).toList();
  }

  /// Collapses options that ride between the same stops on different
  /// services into one, listing the rest as alternatives.
  static List<Journey> _mergeSharedCorridors(List<Journey> ranked) {
    final groups = <String, List<Journey>>{};
    for (final journey in ranked) {
      (groups[journey.stopSignature] ??= []).add(journey);
    }
    final merged = <Journey>[];
    for (final group in groups.values) {
      final winner = group.first;
      if (group.length == 1) {
        merged.add(winner);
        continue;
      }
      final legs = <JourneyLeg>[];
      var rideIndex = 0;
      for (final leg in winner.legs) {
        if (leg is! RideLeg) {
          legs.add(leg);
          continue;
        }
        final alternatives = <String>{
          for (final other in group.skip(1))
            other.rides[rideIndex].routeShortName,
        }..remove(leg.routeShortName);
        legs.add(leg.withAlternatives(alternatives.toList()));
        rideIndex++;
      }
      merged.add(Journey(legs));
    }
    merged.sort((a, b) => a.totalSeconds.compareTo(b.totalSeconds));
    return merged;
  }

  static Map<int, double> _accessPairs(
    TransitIndex index,
    List<({int stop, double meters})> stops,
  ) {
    final pairs = <int, double>{};
    for (final entry in stops) {
      for (final packed in index.stopRoutes[entry.stop]) {
        final current = pairs[packed];
        if (current == null || entry.meters < current) {
          pairs[packed] = entry.meters;
        }
      }
    }
    return pairs;
  }

  static Map<int, List<({int seq, double meters})>> _byRoute(
    Map<int, double> pairs,
  ) {
    final grouped = <int, List<({int seq, double meters})>>{};
    pairs.forEach((packed, meters) {
      (grouped[TransitIndex.routeOf(packed)] ??= [])
          .add((seq: TransitIndex.seqOf(packed), meters: meters));
    });
    return grouped;
  }

  static List<Journey> _direct(
    TransitIndex index,
    LatLng origin,
    LatLng destination,
    Map<int, double> boardings,
    Map<int, double> alightings,
  ) {
    final boardByRoute = _byRoute(boardings);
    final alightByRoute = _byRoute(alightings);
    final journeys = <Journey>[];

    boardByRoute.forEach((routeIndex, boards) {
      final alights = alightByRoute[routeIndex];
      if (alights == null) return;
      final kind = index.routes[routeIndex].kind;

      double? bestSeconds;
      Journey? bestJourney;
      for (final board in boards) {
        for (final alight in alights) {
          // Routes are one-directional in the feed, so riding backwards
          // along the stop list is not a trip that exists.
          if (alight.seq <= board.seq) continue;
          final rideMeters =
              index.metersBetweenStops(routeIndex, board.seq, alight.seq);
          final seconds = _walkSeconds(board.meters) +
              _waitSeconds(kind) +
              _rideSeconds(kind, rideMeters) +
              _walkSeconds(alight.meters);
          if (bestSeconds != null && seconds >= bestSeconds) continue;
          bestSeconds = seconds;
          bestJourney = Journey([
            ..._accessWalk(index, origin, routeIndex, board.seq, board.meters),
            _rideLeg(index, routeIndex, board.seq, alight.seq),
            ..._egressWalk(
                index, destination, routeIndex, alight.seq, alight.meters),
          ]);
        }
      }
      if (bestJourney != null) journeys.add(bestJourney);
    });
    return journeys;
  }

  static List<Journey> _oneTransfer(
    TransitIndex index,
    LatLng origin,
    LatLng destination,
    Map<int, double> boardings,
    Map<int, double> alightings,
  ) {
    final forward = _expand(index, boardings, forwards: true);
    final backward = _expand(index, alightings, forwards: false);
    if (forward.isEmpty || backward.isEmpty) return const [];

    final candidates = forward.entries.toList()
      ..sort((a, b) => a.value.seconds.compareTo(b.value.seconds));

    // Keyed by the pair of services, so the same transfer found at three
    // different bays of one station collapses to its cheapest version.
    final bestByPair = <String, Journey>{};
    for (final entry in candidates.take(_maxJoinCandidates)) {
      final fromStop = entry.key;
      final first = entry.value;
      for (final near
          in index.stopsNear(index.stops[fromStop].point, _transferWalkMeters)) {
        final second = backward[near.stop];
        if (second == null) continue;
        if (second.routeIndex == first.routeIndex) continue;

        final journey = Journey([
          ..._accessWalk(
              index, origin, first.routeIndex, first.boardSeq, first.accessMeters),
          _rideLeg(index, first.routeIndex, first.boardSeq, first.atSeq),
          if (near.meters > 20)
            WalkLeg(
              from: index.stops[fromStop].point,
              to: index.stops[near.stop].point,
              toLabel: index.stops[near.stop].name,
              meters: near.meters,
              seconds: _walkSeconds(near.meters) + _transferPenaltySeconds,
            ),
          _rideLeg(index, second.routeIndex, second.atSeq, second.boardSeq),
          ..._egressWalk(index, destination, second.routeIndex, second.boardSeq,
              second.accessMeters),
        ]);
        final key = '${first.routeIndex}>${second.routeIndex}';
        final current = bestByPair[key];
        if (current == null || journey.totalSeconds < current.totalSeconds) {
          bestByPair[key] = journey;
        }
      }
    }
    return bestByPair.values.toList();
  }

  /// Every stop reachable by boarding once (forwards) or every stop that can
  /// still reach the destination with one ride (backwards), keeping the
  /// cheapest way to each.
  ///
  /// Backwards, [_Reach.atSeq] is where the rider would board and
  /// [_Reach.boardSeq] is where they get off - the fields keep their forward
  /// meaning of "the end the walk is attached to".
  static Map<int, _Reach> _expand(
    TransitIndex index,
    Map<int, double> pairs, {
    required bool forwards,
  }) {
    final reached = <int, _Reach>{};
    pairs.forEach((packed, walkMeters) {
      final routeIndex = TransitIndex.routeOf(packed);
      final seq = TransitIndex.seqOf(packed);
      final kind = index.routes[routeIndex].kind;
      final stops = index.routeStops[routeIndex];
      final base = _walkSeconds(walkMeters) + _waitSeconds(kind);

      final from = forwards ? seq + 1 : 0;
      final to = forwards ? stops.length - 1 : seq - 1;
      for (var i = from; i <= to; i++) {
        final seconds =
            base + _rideSeconds(kind, index.metersBetweenStops(routeIndex, seq, i));
        final stop = stops[i];
        final current = reached[stop];
        if (current != null && current.seconds <= seconds) continue;
        reached[stop] = _Reach(
          routeIndex: routeIndex,
          boardSeq: seq,
          atSeq: i,
          seconds: seconds,
          accessMeters: walkMeters,
        );
      }
    });
    return reached;
  }

  static List<JourneyLeg> _accessWalk(
    TransitIndex index,
    LatLng origin,
    int routeIndex,
    int boardSeq,
    double meters,
  ) {
    final stop = index.stops[index.routeStops[routeIndex][boardSeq]];
    if (meters < 20) return const [];
    return [
      WalkLeg(
        from: origin,
        to: stop.point,
        toLabel: stop.name,
        meters: meters,
        seconds: _walkSeconds(meters),
      ),
    ];
  }

  static List<JourneyLeg> _egressWalk(
    TransitIndex index,
    LatLng destination,
    int routeIndex,
    int alightSeq,
    double meters,
  ) {
    if (meters < 20) return const [];
    final stop = index.stops[index.routeStops[routeIndex][alightSeq]];
    return [
      WalkLeg(
        from: stop.point,
        to: destination,
        toLabel: 'Destino',
        meters: meters,
        seconds: _walkSeconds(meters),
      ),
    ];
  }

  static RideLeg _rideLeg(
    TransitIndex index,
    int routeIndex,
    int boardSeq,
    int alightSeq,
  ) {
    final route = index.routes[routeIndex];
    final stops = index.routeStops[routeIndex];
    final board = index.stops[stops[boardSeq]];
    final alight = index.stops[stops[alightSeq]];
    final meters = index.metersBetweenStops(routeIndex, boardSeq, alightSeq);
    return RideLeg(
      routeId: route.id,
      routeShortName: route.shortName,
      routeLongName: route.longName,
      kind: route.kind,
      boardSeq: boardSeq,
      alightSeq: alightSeq,
      boardStopName: board.name,
      alightStopName: alight.name,
      boardPoint: board.point,
      alightPoint: alight.point,
      waitSeconds: _waitSeconds(route.kind),
      meters: meters,
      seconds: _rideSeconds(route.kind, meters),
    );
  }
}
