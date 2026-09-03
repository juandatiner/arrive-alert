import 'package:latlong2/latlong.dart';

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

/// One row of the bundled route index - enough to search and list, without
/// paying to parse the route's full geometry.
class TransitRouteSummary {
  final String id;
  final String shortName;
  final String longName;
  final TransitKind kind;
  final int stopCount;

  const TransitRouteSummary({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.kind,
    required this.stopCount,
  });

  factory TransitRouteSummary.fromJson(Map<String, dynamic> json) {
    return TransitRouteSummary(
      id: json['id'] as String,
      shortName: json['s'] as String,
      longName: json['l'] as String,
      kind: transitKindFromKey(json['k'] as String),
      stopCount: json['n'] as int,
    );
  }
}

/// The leg the rider actually plans to travel: a slice of one route's drawn
/// path between the stop they board at and the stop they get off at. The
/// path is taken verbatim from the agency's data - nothing is routed.
class TransitTripPlan {
  final String routeShortName;
  final TransitKind kind;
  final List<LatLng> path;
  final TransitStop originStop;
  final TransitStop destinationStop;
  final double meters;

  const TransitTripPlan({
    required this.routeShortName,
    required this.kind,
    required this.path,
    required this.originStop,
    required this.destinationStop,
    required this.meters,
  });

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

  const TransitRoute({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.kind,
    required this.shape,
    required this.stops,
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
    );
  }
}
