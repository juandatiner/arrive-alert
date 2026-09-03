import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/place.dart';

class PlacesHistoryService {
  static const _recentKey = 'recent_places';
  static const _favoriteKey = 'favorite_places';
  static const _maxRecents = 8;

  static Future<List<Place>> loadRecents() => _loadList(_recentKey);
  static Future<List<Place>> loadFavorites() => _loadList(_favoriteKey);

  static Future<void> addRecent(Place place) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadList(_recentKey);
    list.removeWhere((p) => p.sameSpotAs(place));
    list.insert(0, place);
    if (list.length > _maxRecents) {
      list.removeRange(_maxRecents, list.length);
    }
    await _saveList(prefs, _recentKey, list);
  }

  static Future<bool> isFavorite(Place place) async {
    final favorites = await _loadList(_favoriteKey);
    return favorites.any((p) => p.sameSpotAs(place));
  }

  static Future<bool> toggleFavorite(Place place) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadList(_favoriteKey);
    final existed = list.any((p) => p.sameSpotAs(place));
    if (existed) {
      list.removeWhere((p) => p.sameSpotAs(place));
    } else {
      list.insert(0, place);
    }
    await _saveList(prefs, _favoriteKey, list);
    return !existed;
  }

  static Future<void> removeFavorite(Place place) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadList(_favoriteKey);
    list.removeWhere((p) => p.sameSpotAs(place));
    await _saveList(prefs, _favoriteKey, list);
  }

  static Future<void> setNickname(Place place, String? nickname) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadList(_favoriteKey);
    final index = list.indexWhere((p) => p.sameSpotAs(place));
    if (index == -1) return;
    list[index] = list[index].copyWith(nickname: nickname ?? '');
    await _saveList(prefs, _favoriteKey, list);
  }

  static Future<void> setIcon(Place place, String? icon) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadList(_favoriteKey);
    final index = list.indexWhere((p) => p.sameSpotAs(place));
    if (index == -1) return;
    list[index] = list[index].copyWith(icon: icon ?? '');
    await _saveList(prefs, _favoriteKey, list);
  }

  static Future<List<Place>> _loadList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(key);
    if (raw == null) return [];
    return raw
        .map((s) => Place.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> _saveList(
    SharedPreferences prefs,
    String key,
    List<Place> list,
  ) async {
    await prefs.setStringList(
      key,
      list.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }
}
