import 'package:latlong2/latlong.dart';

const _distance = Distance();

/// A polyline with precomputed cumulative lengths, so "how far along is this
/// point" and "how long is the leg between these two" are cheap lookups.
///
/// Stops don't sit exactly on the shape's vertices, so positions are snapped
/// to the nearest vertex rather than assumed to match one.
class RoutePath {
  final List<LatLng> points;
  final List<double> _cumulative;

  RoutePath(this.points) : _cumulative = _buildCumulative(points);

  static List<double> _buildCumulative(List<LatLng> points) {
    final cumulative = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      cumulative[i] =
          cumulative[i - 1] + _distance.as(LengthUnit.Meter, points[i - 1], points[i]);
    }
    return cumulative;
  }

  double get totalMeters => _cumulative.isEmpty ? 0 : _cumulative.last;

  int nearestIndex(LatLng point) {
    var best = 0;
    var bestMeters = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final meters = _distance.as(LengthUnit.Meter, points[i], point);
      if (meters < bestMeters) {
        bestMeters = meters;
        best = i;
      }
    }
    return best;
  }

  /// Metres walked along the polyline between two vertex indices, in either
  /// order.
  double metersBetween(int a, int b) {
    if (points.isEmpty) return 0;
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    return _cumulative[hi] - _cumulative[lo];
  }

  double metersFromStart(int index) =>
      points.isEmpty ? 0 : _cumulative[index];

  /// The stretch of the polyline between two vertex indices, oriented from
  /// [a] towards [b] so it can be drawn as the rider's actual leg.
  List<LatLng> slice(int a, int b) {
    if (points.isEmpty) return const [];
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    final segment = points.sublist(lo, hi + 1);
    return a <= b ? segment : segment.reversed.toList();
  }
}
