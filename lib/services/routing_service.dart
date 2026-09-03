import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/route_info.dart';

class RoutingService {
  static const _baseUrl = 'https://router.project-osrm.org';

  // Techo heuristico para manejo urbano real; OSRM ignora trafico del todo,
  // asi que la duracion cruda es irrealmente rapida - ajustar esta constante si hace falta.
  static const double _urbanDrivingCeilingKmh = 28;

  // Margen deliberado: avisar de mas es barato, avisar tarde hace que el
  // usuario se pase la parada. Duplicar la ETA dispara los avisos temprano.
  static const double _safetyFactor = 2.0;

  static double _applyUrbanTrafficHeuristic(
    double distanceMeters,
    double durationSeconds,
    String profile,
  ) {
    if (profile != 'driving' || durationSeconds <= 0) return durationSeconds;
    final impliedKmh = (distanceMeters / 1000) / (durationSeconds / 3600);
    if (impliedKmh <= _urbanDrivingCeilingKmh) return durationSeconds;
    return durationSeconds * (impliedKmh / _urbanDrivingCeilingKmh);
  }

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
    final rawDistance = (route['distance'] as num).toDouble();
    final rawDuration = (route['duration'] as num).toDouble();
    return RouteInfo(
      points: points,
      distanceMeters: rawDistance,
      durationSeconds:
          _applyUrbanTrafficHeuristic(rawDistance, rawDuration, profile) *
              _safetyFactor,
    );
  }
}
