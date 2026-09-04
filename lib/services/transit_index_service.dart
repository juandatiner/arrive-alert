import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import '../models/transit_route.dart';

const _distance = Distance();

class PlannerStop {
  final String name;
  final LatLng point;

  const PlannerStop({required this.name, required this.point});
}

class PlannerRoute {
  final String id;
  final String shortName;
  final String longName;
  final TransitKind kind;

  const PlannerRoute({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.kind,
  });
}

/// The whole network flattened into lookup tables: which routes touch a
/// stop, and how far along each route that stop sits.
///
/// The per-route asset files answer "draw route X"; this answers the
/// opposite question over all 1044 routes at once, which is what a journey
/// planner needs. Built offline by tool/build_planner_index.py, and the
/// stop positions here are parallel to each route's own stop list, so an
/// index found on this side can be handed straight to [RouteMapScreen].
class TransitIndex {
  /// Packing factor for a (route, stop position) pair inside one int. The
  /// longest bundled route has well under 4096 stops.
  static const _seqBase = 4096;

  /// ~555 m at Bogota's latitude - big enough that a 400 m transfer search
  /// touches 9 cells at most, small enough that a cell holds a handful of
  /// stops.
  static const _cellDegrees = 0.005;

  final List<PlannerRoute> routes;
  final List<PlannerStop> stops;
  final List<Int32List> routeStops;
  final List<Int32List> routeMeters;
  final List<Int32List> stopRoutes;
  final Map<int, List<int>> _grid;

  TransitIndex._({
    required this.routes,
    required this.stops,
    required this.routeStops,
    required this.routeMeters,
    required this.stopRoutes,
  }) : _grid = _buildGrid(stops);

  static int routeOf(int packed) => packed ~/ _seqBase;

  static int seqOf(int packed) => packed % _seqBase;

  static int _cellKey(int latCell, int lonCell) =>
      ((latCell + 40000) << 20) | (lonCell + 40000);

  static Map<int, List<int>> _buildGrid(List<PlannerStop> stops) {
    final grid = <int, List<int>>{};
    for (var i = 0; i < stops.length; i++) {
      final p = stops[i].point;
      final key = _cellKey(
        (p.latitude / _cellDegrees).floor(),
        (p.longitude / _cellDegrees).floor(),
      );
      (grid[key] ??= <int>[]).add(i);
    }
    return grid;
  }

  /// Stop indices within [meters] of [point], each paired with its real
  /// distance so callers don't measure twice.
  List<({int stop, double meters})> stopsNear(LatLng point, double meters) {
    final rings = (meters / (_cellDegrees * 111320)).ceil();
    final latCell = (point.latitude / _cellDegrees).floor();
    final lonCell = (point.longitude / _cellDegrees).floor();
    final found = <({int stop, double meters})>[];
    for (var dLat = -rings; dLat <= rings; dLat++) {
      for (var dLon = -rings; dLon <= rings; dLon++) {
        final bucket = _grid[_cellKey(latCell + dLat, lonCell + dLon)];
        if (bucket == null) continue;
        for (final i in bucket) {
          final d = _distance.as(LengthUnit.Meter, point, stops[i].point);
          if (d <= meters) found.add((stop: i, meters: d));
        }
      }
    }
    found.sort((a, b) => a.meters.compareTo(b.meters));
    return found;
  }

  double metersBetweenStops(int routeIndex, int fromSeq, int toSeq) {
    final meters = routeMeters[routeIndex];
    return (meters[toSeq] - meters[fromSeq]).toDouble().abs();
  }
}

class TransitIndexService {
  static const _path = 'assets/transit/planner.json';

  static TransitIndex? _cached;
  static Future<TransitIndex>? _loading;

  /// Roughly 1 MB of JSON, so the decode runs off the UI thread and the
  /// result is kept for the rest of the session.
  static Future<TransitIndex> load() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _loading ??= _load();
  }

  static Future<TransitIndex> _load() async {
    final raw = await rootBundle.loadString(_path);
    final json = await compute(_decode, raw);

    final routes = (json['routes'] as List)
        .map((r) => PlannerRoute(
              id: (r as List)[0] as String,
              shortName: r[1] as String,
              longName: r[2] as String,
              kind: transitKindFromKey(r[3] as String),
            ))
        .toList();
    final stops = (json['stops'] as List)
        .map((s) => PlannerStop(
              name: cleanStopName((s as List)[0] as String),
              point: LatLng((s[1] as num).toDouble(), (s[2] as num).toDouble()),
            ))
        .toList();
    final routeStops = (json['rs'] as List)
        .map((l) => Int32List.fromList((l as List).cast<int>()))
        .toList();
    final routeMeters = (json['rm'] as List)
        .map((l) => Int32List.fromList((l as List).cast<int>()))
        .toList();

    final index = TransitIndex._(
      routes: routes,
      stops: stops,
      routeStops: routeStops,
      routeMeters: routeMeters,
      stopRoutes: _invert(routeStops, stops.length),
    );
    _cached = index;
    _loading = null;
    return index;
  }

  static Map<String, dynamic> _decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  /// stop -> the (route, position) pairs that serve it. Counting first lets
  /// every bucket be an exactly-sized typed list instead of 8172 growable
  /// lists.
  static List<Int32List> _invert(List<Int32List> routeStops, int stopCount) {
    final counts = Int32List(stopCount);
    for (final stops in routeStops) {
      for (final stop in stops) {
        counts[stop]++;
      }
    }
    final buckets = List<Int32List>.generate(
      stopCount,
      (i) => Int32List(counts[i]),
      growable: false,
    );
    final filled = Int32List(stopCount);
    for (var r = 0; r < routeStops.length; r++) {
      final stops = routeStops[r];
      for (var seq = 0; seq < stops.length; seq++) {
        final stop = stops[seq];
        buckets[stop][filled[stop]++] = r * TransitIndex._seqBase + seq;
      }
    }
    return buckets;
  }
}
