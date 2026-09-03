import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Freshness check for the bundled route data.
///
/// TransMilenio republishes its full GTFS feed daily, but that feed is a
/// ~110MB zip that expands past 600MB - far too heavy to download and parse
/// on a phone. So the app ships a pre-built pack (see tool/build_transit_data.py)
/// and this service only compares dates, so a stale pack can be surfaced to
/// the user instead of silently rotting.
class TransitUpdateService {
  static const _bucketUrl = 'https://storage.googleapis.com/gtfs-estaticos';
  static const _lastCheckKey = 'transit_feed_last_check';
  static const _latestSeenKey = 'transit_feed_latest_seen';

  /// Bundled data older than this is worth telling the user about; route
  /// changes in Bogota are frequent but not daily.
  static const staleAfter = Duration(days: 45);

  static String? _bundledFeedDate;

  /// Feed date the bundled pack was built from, as `yyyyMMdd`.
  static Future<String> bundledFeedDate() async {
    if (_bundledFeedDate != null) return _bundledFeedDate!;
    final raw = await rootBundle.loadString('assets/transit/version.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    _bundledFeedDate = json['feed'] as String;
    return _bundledFeedDate!;
  }

  static DateTime? _parseFeedDate(String yyyymmdd) {
    if (yyyymmdd.length != 8) return null;
    return DateTime.tryParse(
      '${yyyymmdd.substring(0, 4)}-${yyyymmdd.substring(4, 6)}-${yyyymmdd.substring(6)}',
    );
  }

  /// Newest `GTFS_yyyyMMdd.zip` the public bucket lists, or null if the
  /// listing can't be read (offline, format changed, ...).
  static Future<String?> fetchLatestFeedDate() async {
    try {
      final response = await http
          .get(Uri.parse(_bucketUrl))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final matches = RegExp(r'GTFS_(\d{8})\.zip').allMatches(response.body);
      if (matches.isEmpty) return null;
      final dates = matches.map((m) => m.group(1)!).toList()..sort();
      return dates.last;
    } catch (_) {
      return null;
    }
  }

  /// How far behind the bundled pack is, using the last successfully seen
  /// remote feed date. Null when it has never managed to check.
  static Future<Duration?> bundledDataAge() async {
    final prefs = await SharedPreferences.getInstance();
    final latestSeen = prefs.getString(_latestSeenKey);
    if (latestSeen == null) return null;
    final bundled = _parseFeedDate(await bundledFeedDate());
    final remote = _parseFeedDate(latestSeen);
    if (bundled == null || remote == null) return null;
    final age = remote.difference(bundled);
    return age.isNegative ? Duration.zero : age;
  }

  /// Checks the bucket at most once a day and remembers what it saw.
  /// Returns true when the published feed is newer than the bundled pack.
  static Future<bool> checkForUpdate({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckMillis = prefs.getInt(_lastCheckKey);
    final now = DateTime.now();
    if (!force && lastCheckMillis != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastCheckMillis);
      if (now.difference(last) < const Duration(days: 1)) {
        final age = await bundledDataAge();
        return age != null && age > staleAfter;
      }
    }

    final latest = await fetchLatestFeedDate();
    if (latest == null) return false;
    await prefs.setInt(_lastCheckKey, now.millisecondsSinceEpoch);
    await prefs.setString(_latestSeenKey, latest);

    final bundled = _parseFeedDate(await bundledFeedDate());
    final remote = _parseFeedDate(latest);
    if (bundled == null || remote == null) return false;
    return remote.difference(bundled) > staleAfter;
  }
}
