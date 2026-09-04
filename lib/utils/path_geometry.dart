import 'package:latlong2/latlong.dart';

const _distance = Distance();

/// A polyline with precomputed cumulative lengths, so "how far along is this
/// point" is a cheap lookup while a trip is being tracked.
///
/// Where stops sit on a route is not worked out here - see
/// tool/shape_snap.py and [TransitRoute.stopShapeIndices], which get it
/// right for simplified shapes and loop routes.
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

  double metersFromStart(int index) =>
      points.isEmpty ? 0 : _cumulative[index];
}
