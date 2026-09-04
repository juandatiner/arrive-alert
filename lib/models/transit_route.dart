import 'package:latlong2/latlong.dart';

const _distance = Distance();

/// The three buckets the route picker offers, plus the cable car.
enum TransitKind { troncal, alimentador, zonal, cable }

TransitKind transitKindFromKey(String key) {
  switch (key) {
    case 'troncal':
      return TransitKind.troncal;
    case 'alimentador':
      return TransitKind.alimentador;
    case 'cable':
      return TransitKind.cable;
    default:
      return TransitKind.zonal;
  }
}

extension TransitKindLabel on TransitKind {
  String get label {
    switch (this) {
      case TransitKind.troncal:
        return 'TransMilenio';
      case TransitKind.alimentador:
        return 'Alimentador';
      case TransitKind.zonal:
        return 'Bus SITP';
      case TransitKind.cable:
        return 'TransMiCable';
    }
  }

  /// Rough operating speed used to turn "metres left along the route" into
  /// minutes - the app never asks a router for transit ETAs.
  double get averageKmh {
    switch (this) {
      case TransitKind.troncal:
        return 24;
      case TransitKind.cable:
        return 14;
      case TransitKind.alimentador:
        return 17;
      case TransitKind.zonal:
        return 15;
    }
  }
}

/// One day's service: when the first bus leaves the route's first stop, when
/// the last one does, and how many run in between.
///
/// Minutes are counted from midnight and may run past it - the agency
/// publishes a last departure of "00:30" as 24:30, and a rider reading
/// "18:43 - 00:30" needs the second number to still mean the small hours.
class ServiceWindow {
  final int firstMinute;
  final int lastMinute;
  final int trips;

  const ServiceWindow({
    required this.firstMinute,
    required this.lastMinute,
    required this.trips,
  });

  static String _clock(int minute) {
    final hour = (minute ~/ 60) % 24;
    final minutes = minute % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  String get label => '${_clock(firstMinute)} - ${_clock(lastMinute)}';

  String get firstClock => _clock(firstMinute);

  String get lastClock => _clock(lastMinute);

  /// Whether a bus is leaving within this window at [minute] of the day.
  ///
  /// A window that runs to "00:30" is stored as 1470, past the end of its own
  /// day, so a service still going in the small hours is asked about with
  /// [minute] pushed a day forward - see [RouteSchedule.statusAt].
  bool covers(int minute) => minute >= firstMinute && minute <= lastMinute;
}

/// Where a service stands relative to right now.
enum ServiceStatus {
  /// Buses are leaving.
  running,

  /// Runs today, but the first bus has not left yet - M86 starts at 22:10.
  notYet,

  /// Ran today and is done.
  finished,

  /// Hours unknown, which is what a pack built before schedules gives.
  unknown,
}

/// The days a route runs and its hours on each of them.
///
/// TransMilenio publishes one `route_id` per direction *and* per slice of the
/// day, all under the same code: "MK86" is one id from 04:30 to 21:03 and
/// another from 21:13 to 22:00. tool/build_transit_data.py folds the ones a
/// busier sibling already covers into it and keeps the rest, so what is left
/// is the set of genuinely catchable services - which only makes sense if
/// the app then shows the rider the ones running on the day they are asking
/// about.
class RouteSchedule {
  /// Bit 0 is Monday, bit 6 is Sunday - the order [DateTime.weekday] uses,
  /// one-indexed there and zero-indexed here.
  final int dayMask;

  /// One window per set bit in [dayMask], in day order.
  final List<ServiceWindow> windows;

  const RouteSchedule({required this.dayMask, required this.windows});

  /// What a pack built before schedules existed gets: runs every day, hours
  /// unknown. Better than hiding every route on a stale bundle.
  static const always = RouteSchedule(dayMask: 0x7F, windows: []);

  factory RouteSchedule.fromJson(Map<String, dynamic> json) {
    final mask = json['d'] as int?;
    if (mask == null) return always;
    return RouteSchedule(
      dayMask: mask,
      windows: [
        for (final w in (json['h'] as List? ?? []))
          ServiceWindow(
            firstMinute: (w as List)[0] as int,
            lastMinute: w[1] as int,
            trips: w[2] as int,
          ),
      ],
    );
  }

  /// [weekday] is [DateTime.weekday]: Monday is 1, Sunday is 7.
  bool runsOn(int weekday) => dayMask >> (weekday - 1) & 1 == 1;

  /// The service on [weekday], or null when the route does not run that day
  /// (or when the bundle predates schedules).
  ServiceWindow? windowFor(int weekday) {
    if (!runsOn(weekday)) return null;
    // Windows are stored per set bit in day order, so the slot is the number
    // of days set below this one.
    var slot = 0;
    for (var day = 0; day < weekday - 1; day++) {
      if (dayMask >> day & 1 == 1) slot++;
    }
    return slot < windows.length ? windows[slot] : null;
  }

  /// How often the route runs on [weekday], for ranking same-code services.
  int tripsOn(int weekday) => windowFor(weekday)?.trips ?? 0;

  /// Where this service stands at [now], and the window that decided it.
  ///
  /// Yesterday is consulted too: a route whose last bus leaves at "00:30" is
  /// still running at ten past midnight, and by then [DateTime.weekday] has
  /// already moved on.
  ({ServiceStatus status, ServiceWindow? window}) statusAt(DateTime now) {
    final minute = now.hour * 60 + now.minute;

    final yesterday = windowFor(now.weekday == DateTime.monday
        ? DateTime.sunday
        : now.weekday - 1);
    if (yesterday != null && yesterday.covers(minute + Duration.minutesPerDay)) {
      return (status: ServiceStatus.running, window: yesterday);
    }

    final today = windowFor(now.weekday);
    if (today == null) {
      return (status: ServiceStatus.unknown, window: null);
    }
    if (today.covers(minute)) {
      return (status: ServiceStatus.running, window: today);
    }
    return (
      status: minute < today.firstMinute
          ? ServiceStatus.notYet
          : ServiceStatus.finished,
      window: today,
    );
  }
}

/// One row of the bundled route index - enough to search and list, without
/// paying to parse the route's full geometry.
class TransitRouteSummary {
  final String id;
  final String shortName;
  final String longName;
  final TransitKind kind;
  final int stopCount;
  final RouteSchedule schedule;

  const TransitRouteSummary({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.kind,
    required this.stopCount,
    this.schedule = RouteSchedule.always,
  });

  factory TransitRouteSummary.fromJson(Map<String, dynamic> json) {
    return TransitRouteSummary(
      id: json['id'] as String,
      shortName: json['s'] as String,
      longName: json['l'] as String,
      kind: transitKindFromKey(json['k'] as String),
      stopCount: json['n'] as int,
      schedule: RouteSchedule.fromJson(json),
    );
  }
}

/// The leg the rider actually plans to travel: a slice of one route's drawn
/// path between the stop they board at and the stop they get off at. The
/// path is taken verbatim from the agency's data - nothing is routed.
///
/// Every stop in between comes along, because the rider may well decide to
/// get off early, and because the trip map greys out the ones already
/// passed.
class TransitTripPlan {
  final String routeId;
  final String routeShortName;
  final String routeLongName;
  final TransitKind kind;
  final List<LatLng> path;

  /// The whole published route, drawn behind [path] so the rider can see
  /// where the bus came from and where it carries on to.
  final List<LatLng> routePath;

  /// Stops of this leg in ride order, starting where the rider boards and
  /// ending where they planned to get off.
  final List<TransitStop> stops;

  /// For each stop, its position in [path] and how far along the leg it is.
  final List<int> stopPathIndices;
  final List<double> stopMeters;

  const TransitTripPlan({
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.kind,
    required this.path,
    required this.routePath,
    required this.stops,
    required this.stopPathIndices,
    required this.stopMeters,
  });

  TransitStop get originStop => stops.first;

  TransitStop get destinationStop => stops.last;

  double get meters => stopMeters.last;

  /// Transit ETAs come from distance and a per-service average speed, since
  /// no router models a bus route's actual stops and dwell time.
  double secondsFor(double meters) => meters / (kind.averageKmh / 3.6);

  double get totalSeconds => secondsFor(meters);
}

/// TransMilenio station names carry the boarding bay in the feed - "Flores
/// B - 4 ó 6-T", "Portal Norte T5A". Riders call the place "Flores", so the
/// bay is dropped for display.
final _bayPattern = RegExp(
  r'\s+(?:[A-Z]\s*-\s*\d+(?:\s*ó\s*\d+)?(?:\s*-\s*[A-Z])?|T\d+[A-Z]?)$',
);

String cleanStopName(String raw) {
  final cleaned = raw.replaceAll(_bayPattern, '').trim();
  return cleaned.isEmpty ? raw.trim() : cleaned;
}

class TransitStop {
  final String id;
  final String name;
  final LatLng point;

  const TransitStop({
    required this.id,
    required this.name,
    required this.point,
  });

  factory TransitStop.fromJson(Map<String, dynamic> json) {
    return TransitStop(
      id: json['id'] as String,
      name: cleanStopName(json['n'] as String),
      point: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lon'] as num).toDouble(),
      ),
    );
  }
}

/// A route with its full drawn path and ordered stop list.
class TransitRoute {
  final String id;
  final String shortName;
  final String longName;
  final TransitKind kind;
  final List<LatLng> shape;
  final List<TransitStop> stops;

  /// Where each stop sits on [shape], and how far along the route it is.
  /// Both are precomputed by tool/shape_snap.py: stops don't land on shape
  /// vertices, the shapes are simplified, and loop routes pass their own
  /// terminal twice, so working this out on the phone gets it wrong.
  final List<int> stopShapeIndices;
  final List<double> stopMeters;

  /// The days and hours this particular service runs - see [RouteSchedule]
  /// for why one route code carries several of them.
  final RouteSchedule schedule;

  List<double>? _cumulativeCache;

  TransitRoute({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.kind,
    required this.shape,
    required this.stops,
    required this.stopShapeIndices,
    required this.stopMeters,
    this.schedule = RouteSchedule.always,
  });

  factory TransitRoute.fromJson(Map<String, dynamic> json) {
    return TransitRoute(
      id: json['id'] as String,
      shortName: json['short'] as String,
      longName: json['long'] as String,
      kind: transitKindFromKey(json['kind'] as String),
      shape: (json['shape'] as List)
          .map((p) => LatLng(
                ((p as List)[0] as num).toDouble(),
                (p[1] as num).toDouble(),
              ))
          .toList(),
      stops: (json['stops'] as List)
          .map((s) => TransitStop.fromJson(s as Map<String, dynamic>))
          .toList(),
      stopShapeIndices: (json['si'] as List).cast<int>(),
      stopMeters:
          (json['sm'] as List).map((m) => (m as num).toDouble()).toList(),
      schedule: RouteSchedule.fromJson(json),
    );
  }

  /// Metres along the route between two stops, in either order.
  double metersBetweenStops(int a, int b) =>
      (stopMeters[b] - stopMeters[a]).abs();

  /// Metres from the start of [shape] to each of its vertices. Built once per
  /// loaded route, and only when a leg is actually drawn.
  List<double> get _cumulative {
    final cached = _cumulativeCache;
    if (cached != null) return cached;
    final cumulative = List<double>.filled(shape.length, 0);
    for (var i = 1; i < shape.length; i++) {
      cumulative[i] = cumulative[i - 1] +
          _distance.as(LengthUnit.Meter, shape[i - 1], shape[i]);
    }
    return _cumulativeCache = cumulative;
  }

  /// Where a stop falls on the drawn line, as a point on it plus how far
  /// along it is.
  ///
  /// [stopShapeIndices] gives the nearest vertex; the real position is
  /// somewhere on one of the two segments touching it, which is what makes
  /// the difference between a line that ends at the stop and one that
  /// overshoots it by half a block.
  ({double meters, LatLng point}) _projectStop(int stopIndex) {
    final cumulative = _cumulative;
    if (shape.length < 2) {
      return (meters: 0, point: shape.isEmpty ? stops[stopIndex].point : shape.first);
    }
    final target = stops[stopIndex].point;
    final hint = stopShapeIndices[stopIndex].clamp(0, shape.length - 1);
    final first = (hint - 1).clamp(0, shape.length - 2);
    final last = hint.clamp(0, shape.length - 2);

    var bestMeters = cumulative[hint];
    var bestPoint = shape[hint];
    var bestDistance = double.infinity;
    for (var i = first; i <= last; i++) {
      final a = shape[i];
      final b = shape[i + 1];
      // Degrees are near enough to a flat plane over one segment of a city
      // street, and only the ratio along the segment is taken from this.
      final dx = b.longitude - a.longitude;
      final dy = b.latitude - a.latitude;
      final lengthSq = dx * dx + dy * dy;
      final t = lengthSq == 0
          ? 0.0
          : (((target.longitude - a.longitude) * dx +
                      (target.latitude - a.latitude) * dy) /
                  lengthSq)
              .clamp(0.0, 1.0);
      final point =
          LatLng(a.latitude + t * dy, a.longitude + t * dx);
      final distance = _distance.as(LengthUnit.Meter, point, target);
      if (distance >= bestDistance) continue;
      bestDistance = distance;
      bestPoint = point;
      bestMeters =
          cumulative[i] + t * (cumulative[i + 1] - cumulative[i]);
    }
    return (meters: bestMeters, point: bestPoint);
  }

  /// The leg between two stops, carrying every stop in between so the trip
  /// screen can show them and the rider can get off early.
  ///
  /// The drawn line starts and ends on the two stops themselves, not on the
  /// nearest shape vertex, so it lines up with the markers instead of
  /// running past them.
  TransitTripPlan legBetween(int originIndex, int destinationIndex) {
    final forwards = originIndex <= destinationIndex;
    final lo = forwards ? originIndex : destinationIndex;
    final hi = forwards ? destinationIndex : originIndex;

    final nodes = <({double meters, LatLng point, int? stop})>[];
    for (var i = lo; i <= hi; i++) {
      final projected = _projectStop(i);
      nodes.add((meters: projected.meters, point: projected.point, stop: i));
    }
    final startMeters = nodes.first.meters;
    final endMeters = nodes.last.meters;
    final cumulative = _cumulative;
    for (var v = 0; v < shape.length; v++) {
      if (cumulative[v] > startMeters && cumulative[v] < endMeters) {
        nodes.add((meters: cumulative[v], point: shape[v], stop: null));
      }
    }
    nodes.sort((a, b) => a.meters.compareTo(b.meters));

    final path = <LatLng>[];
    final pathIndexOfStop = <int, int>{};
    for (final node in nodes) {
      if (node.stop != null) pathIndexOfStop[node.stop!] = path.length;
      path.add(node.point);
    }
    // The ends are pinned to the stops' own coordinates: a stop sits a few
    // metres off the corridor (its bay), and the line has to reach it.
    path[0] = stops[lo].point;
    path[path.length - 1] = stops[hi].point;
    pathIndexOfStop[lo] = 0;
    pathIndexOfStop[hi] = path.length - 1;

    final order = forwards
        ? [for (var i = lo; i <= hi; i++) i]
        : [for (var i = hi; i >= lo; i--) i];

    return TransitTripPlan(
      routeId: id,
      routeShortName: shortName,
      routeLongName: longName,
      kind: kind,
      path: forwards ? path : path.reversed.toList(),
      routePath: shape,
      stops: [for (final i in order) stops[i]],
      stopPathIndices: [
        for (final i in order)
          forwards
              ? pathIndexOfStop[i]!
              : path.length - 1 - pathIndexOfStop[i]!,
      ],
      stopMeters: [
        for (final i in order) (stopMeters[i] - stopMeters[originIndex]).abs(),
      ],
    );
  }
}
