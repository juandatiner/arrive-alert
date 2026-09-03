import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_trip.dart';

class SavedTripsService {
  static const _key = 'saved_transit_trips';
  static const _max = 12;

  static Future<List<SavedTrip>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null) return [];
    return raw
        .map((s) => SavedTrip.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  static Future<bool> isSaved(SavedTrip trip) async {
    final list = await load();
    return list.any((t) => t.key == trip.key);
  }

  /// Saves the leg, or removes it if it was already there. Returns whether
  /// it is saved afterwards.
  static Future<bool> toggle(SavedTrip trip) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final existed = list.any((t) => t.key == trip.key);
    if (existed) {
      list.removeWhere((t) => t.key == trip.key);
    } else {
      list.insert(0, trip);
      if (list.length > _max) list.removeRange(_max, list.length);
    }
    await _save(prefs, list);
    return !existed;
  }

  static Future<void> remove(SavedTrip trip) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((t) => t.key == trip.key);
    await _save(prefs, list);
  }

  static Future<void> _save(
      SharedPreferences prefs, List<SavedTrip> list) async {
    await prefs.setStringList(
      _key,
      list.map((t) => jsonEncode(t.toJson())).toList(),
    );
  }
}
