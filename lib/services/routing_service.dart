import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/route_info.dart';

class RoutingService {
  static const _baseUrl = 'https://router.project-osrm.org';

  /// profile: driving | walking | cycling
  static Future<RouteInfo> getRoute({
    required LatLng origin,
    required LatLng destination,
    String profile = 'driving',
  }) async {
    final coords =
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
    final uri = Uri.parse('$_baseUrl/route/v1/$profile/$coords').replace(
      queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Error calculando ruta (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
      throw Exception('No se encontro ruta');
    }
    final route = (data['routes'] as List).first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;
    final points = coordinates.map((c) {
      final pair = c as List;
      return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList();
    return RouteInfo(
      points: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
    );
  }
}
