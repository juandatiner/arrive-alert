import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/transit_route.dart';

/// Reads the bundled TransMilenio/SITP route data (built offline from the
/// agency's GTFS feed). Everything is local, so route lookup keeps working
/// on a bus with no signal.
class TransitService {
  static const _indexPath = 'assets/transit/routes_index.json';

  static List<TransitRouteSummary>? _index;
  static final Map<String, TransitRoute> _routeCache = {};

  static Future<List<TransitRouteSummary>> loadIndex() async {
    if (_index != null) return _index!;
    final raw = await rootBundle.loadString(_indexPath);
    final list = jsonDecode(raw) as List;
    _index = list
        .map((e) => TransitRouteSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    return _index!;
  }

  /// Matches on the route code first (what riders actually know - "B13",
  /// "K86"), then falls back to the destination text.
  ///
  /// Only services running on [on] (today by default) are returned: a rider
  /// searching on a Monday has no use for the Sunday-only variant of a code,
  /// and showing both is what made "M86" come back five times.
  static Future<List<TransitRouteSummary>> search({
    required String query,
    TransitKind? kind,
    DateTime? on,
  }) async {
    final index = await loadIndex();
    final weekday = (on ?? DateTime.now()).weekday;
    final q = query.trim().toLowerCase();
    final pool = [
      for (final r in index)
        if ((kind == null || r.kind == kind) && r.schedule.runsOn(weekday)) r,
    ];
    if (q.isEmpty) return _byFrequency(pool, weekday).take(60).toList();

    final byCode = <TransitRouteSummary>[];
    final exact = <TransitRouteSummary>[];
    final byName = <TransitRouteSummary>[];
    for (final r in pool) {
      final short = r.shortName.toLowerCase();
      if (short == q) {
        exact.add(r);
      } else if (short.startsWith(q)) {
        byCode.add(r);
      } else if (short.contains(q) || r.longName.toLowerCase().contains(q)) {
        byName.add(r);
      }
    }
    return [
      ..._byFrequency(exact, weekday),
      ..._byFrequency(byCode, weekday),
      ..._byFrequency(byName, weekday),
    ].take(60).toList();
  }

  /// Codes stay together so a rider comparing "M86" against "MK86" reads two
  /// blocks rather than an interleaving, and inside a code the service that
  /// runs most often comes first - its late-night or early-morning sibling
  /// sits under it, which is the order the rider wants to skim.
  static List<TransitRouteSummary> _byFrequency(
    List<TransitRouteSummary> routes,
    int weekday,
  ) {
    final sorted = [...routes];
    sorted.sort((a, b) {
      final byCode = a.shortName.compareTo(b.shortName);
      if (byCode != 0) return byCode;
      return b.schedule.tripsOn(weekday).compareTo(a.schedule.tripsOn(weekday));
    });
    return sorted;
  }

  static Future<TransitRoute> loadRoute(String id) async {
    final cached = _routeCache[id];
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/transit/routes/$id.json');
    final route =
        TransitRoute.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    // Small cache: routes are a few KB each and users bounce between a
    // handful of them, but there's no reason to hold the whole pack.
    if (_routeCache.length > 12) _routeCache.clear();
    _routeCache[id] = route;
    return route;
  }
}
