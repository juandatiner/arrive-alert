import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert_settings.dart';

class SettingsService {
  static const _key = 'alert_settings';

  static Future<AlertSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const AlertSettings();
    try {
      return AlertSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AlertSettings();
    }
  }

  static Future<void> save(AlertSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
