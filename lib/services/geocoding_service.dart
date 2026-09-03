import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/place.dart';

/// Result of resolving an address for a raw map point.
class ReverseGeocodeResult {
  final String label;
  final bool isWater;

  const ReverseGeocodeResult({required this.label, required this.isWater});
}

class GeocodingService {
  static const _baseUrl = 'https://nominatim.openstreetmap.org';

  // Nominatim's `category`/`type` for a reverse-geocoded point that's over
  // open water instead of land - used to reject the sea/ocean/lake/river as
  // a destination before the user gets further into the trip flow.
  static const _waterCategories = {'water', 'waterway'};
  static const _waterTypes = {
    'water',
    'bay',
    'strait',
    'coastline',
    'ocean',
    'sea',
    'river',
    'stream',
    'canal',
    'lake',
  };

  static Future<List<Place>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'q': query,
      'format': 'jsonv2',
      'limit': '6',
    });
    final response = await http.get(
      uri,
      headers: {'User-Agent': 'ArriveAlertApp/1.0'},
    );
    if (response.statusCode != 200) {
      throw Exception('Error buscando direccion (${response.statusCode})');
    }
    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => Place.fromNominatim(e as Map<String, dynamic>))
        .toList();
  }

  static Future<ReverseGeocodeResult> reverse(double lat, double lon) async {
    final uri = Uri.parse('$_baseUrl/reverse').replace(queryParameters: {
      'lat': '$lat',
      'lon': '$lon',
      'format': 'jsonv2',
    });
    final response = await http.get(
      uri,
      headers: {'User-Agent': 'ArriveAlertApp/1.0'},
    );
    if (response.statusCode != 200) {
      throw Exception('Error obteniendo direccion (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final label = data['display_name'] as String?;
    if (label == null || label.isEmpty) {
      throw Exception('Direccion no encontrada');
    }
    final category = data['category'] as String?;
    final type = data['type'] as String?;
    final isWater =
        _waterCategories.contains(category) || _waterTypes.contains(type);
    return ReverseGeocodeResult(label: label, isWater: isWater);
  }
}
