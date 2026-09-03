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
  static Future<List<TransitRouteSummary>> search({
    required String query,
    TransitKind? kind,
  }) async {
    final index = await loadIndex();
    final q = query.trim().toLowerCase();
    final pool = kind == null
        ? index
        : index.where((r) => r.kind == kind).toList();
    if (q.isEmpty) return pool.take(60).toList();

    final byCode = <TransitRouteSummary>[];
    final byName = <TransitRouteSummary>[];
    for (final r in pool) {
      final short = r.shortName.toLowerCase();
      if (short == q) {
        byCode.insert(0, r);
      } else if (short.startsWith(q)) {
        byCode.add(r);
      } else if (short.contains(q) || r.longName.toLowerCase().contains(q)) {
        byName.add(r);
      }
    }
    return [...byCode, ...byName].take(60).toList();
  }

  static Future<TransitRoute> loadRoute(String id) async {
    final cached = _routeCache[id];
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/transit/routes/$id.json');
    final route =
        TransitRoute.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    // Small cache: routes are a few KB each and users bounce between a
    // handful of them, but there's no reason to hold all 1044.
    if (_routeCache.length > 12) _routeCache.clear();
    _routeCache[id] = route;
    return route;
  }
}
