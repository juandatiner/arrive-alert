import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/place.dart';

class GeocodingService {
  static const _baseUrl = 'https://nominatim.openstreetmap.org';

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
}
