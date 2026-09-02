import 'package:latlong2/latlong.dart';

class RouteInfo {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const RouteInfo({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}
