import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One bus as the agency last reported it.
class LiveVehicle {
  final String id;
  final String routeId;
  final LatLng point;
  final double? bearing;

  /// When the agency says this position was taken. The feed's own header
  /// timestamp is stuck at a fixed value, so freshness has to come from
  /// here.
  final DateTime? reportedAt;

  const LiveVehicle({
    required this.id,
    required this.routeId,
    required this.point,
    this.bearing,
    this.reportedAt,
  });

  bool get isStale {
    final at = reportedAt;
    return at != null && DateTime.now().difference(at) > const Duration(minutes: 5);
  }
}

/// Live bus positions from TransMilenio's GTFS-Realtime feed.
///
/// The feed is public and needs no key. It republishes about every 15
/// seconds and carries the whole fleet - roughly 6400 buses across 630
/// services - as one 830 KB protobuf, with no way to ask for a single route,
/// which is why polling is deliberately slow and can be switched off.
///
/// Everything here is best-effort: a failure returns an empty list and the
/// app carries on with the GPS-only tracking it has always used. Nothing in
/// the trip flow depends on this.
///
/// Only four fields deep in the payload are needed - the vehicle's id, its
/// route, its position and its timestamp - so it is read with the small
/// decoder below instead of pulling in a code-generated schema.
class LiveVehiclesService {
  /// The feed moved here in 2026; the old gis.transmilenio.gov.co/gtfs/
  /// endpoints answer 500 and are not coming back.
  static const _vehiclePositionsUrl =
      'https://gtfs.transmilenio.gov.co/positions.pb';

  static const _timeout = Duration(seconds: 20);

  /// Screens poll independently but must not each pull 830 KB. A fetch this
  /// recent is reused as-is.
  static const _cacheTtl = Duration(seconds: 12);

  static List<LiveVehicle> _cached = const [];
  static DateTime? _cachedAt;
  static String? _etag;
  static Future<List<LiveVehicle>>? _inFlight;

  /// Turned off from settings by riders who would rather not spend the data.
  static bool enabled = true;

  static DateTime? _lastFailure;

  /// Whether the last attempt failed. The maps use it to say "no disponible"
  /// instead of silently showing an empty sky.
  static bool _lastAttemptFailed = false;

  static bool get feedUnavailable => _lastAttemptFailed;

  /// A short rest after a failure, so a blip does not turn into a retry
  /// storm on a metered connection.
  static const _backoff = Duration(seconds: 90);

  static bool get _inBackoff {
    final last = _lastFailure;
    return last != null && DateTime.now().difference(last) < _backoff;
  }

  /// Every reported vehicle, or an empty list if the feed can't be read.
  static Future<List<LiveVehicle>> fetchAll() {
    if (!enabled || _inBackoff) return Future.value(const []);
    final at = _cachedAt;
    if (at != null && DateTime.now().difference(at) < _cacheTtl) {
      return Future.value(_cached);
    }
    return _inFlight ??= _fetchAll().whenComplete(() => _inFlight = null);
  }

  static Future<List<LiveVehicle>> _fetchAll() async {
    try {
      final etag = _etag;
      final response = await http.get(
        Uri.parse(_vehiclePositionsUrl),
        headers: {'If-None-Match': ?etag},
      ).timeout(_timeout);

      // Unchanged since the last poll: keep what we have and spend nothing.
      if (response.statusCode == 304) {
        _cachedAt = DateTime.now();
        _lastAttemptFailed = false;
        return _cached;
      }
      if (response.statusCode != 200) {
        _lastFailure = DateTime.now();
        _lastAttemptFailed = true;
        return const [];
      }
      _lastFailure = null;
      _lastAttemptFailed = false;
      _etag = response.headers['etag'];
      _cached = parseVehiclePositionsFeed(response.bodyBytes)
          .where((v) => !v.isStale)
          .toList();
      _cachedAt = DateTime.now();
      return _cached;
    } catch (_) {
      _lastFailure = DateTime.now();
      _lastAttemptFailed = true;
      return const [];
    }
  }

  /// Every reported vehicle running any of [routeIds], wherever it is. Used
  /// when looking at a whole route rather than at one rider's leg.
  static Future<List<LiveVehicle>> fetchForRoutes(Set<String> routeIds) async {
    if (routeIds.isEmpty) return const [];
    final all = await fetchAll();
    return all.where((v) => routeIds.contains(v.routeId)).toList();
  }

}

// --- GTFS-Realtime protobuf, only the fields this app reads ---
//
// FeedMessage.entity = 2, FeedEntity.vehicle = 4,
// VehiclePosition.trip = 1 / .position = 2 / .vehicle = 8,
// TripDescriptor.route_id = 5, VehicleDescriptor.id = 1,
// Position.latitude = 1 / .longitude = 2 / .bearing = 3.
//
// Everything else in the message is skipped by wire type, so extra fields in
// a future version of the feed are ignored rather than fatal.

List<LiveVehicle> parseVehiclePositionsFeed(Uint8List bytes) {
  final vehicles = <LiveVehicle>[];
  final reader = _ProtoReader(bytes);
  while (reader.hasMore) {
    final field = reader.readTag();
    if (field.number == 2 && field.wireType == 2) {
      final vehicle = _parseEntity(reader.readLengthDelimited());
      if (vehicle != null) vehicles.add(vehicle);
    } else {
      reader.skip(field.wireType);
    }
  }
  return vehicles;
}

LiveVehicle? _parseEntity(_ProtoReader reader) {
  while (reader.hasMore) {
    final field = reader.readTag();
    if (field.number == 4 && field.wireType == 2) {
      return _parseVehiclePosition(reader.readLengthDelimited());
    }
    reader.skip(field.wireType);
  }
  return null;
}

LiveVehicle? _parseVehiclePosition(_ProtoReader reader) {
  var routeId = '';
  var id = '';
  double? lat;
  double? lon;
  double? bearing;
  int? timestamp;
  while (reader.hasMore) {
    final field = reader.readTag();
    if (field.wireType != 2) {
      // VehiclePosition.timestamp = 5, the only scalar this app reads.
      if (field.number == 5 && field.wireType == 0) {
        timestamp = reader.readVarint();
      } else {
        reader.skip(field.wireType);
      }
      continue;
    }
    final nested = reader.readLengthDelimited();
    switch (field.number) {
      case 1:
        routeId = _parseStringField(nested, 5);
      case 2:
        while (nested.hasMore) {
          final f = nested.readTag();
          if (f.wireType == 5 && f.number == 1) {
            lat = nested.readFloat();
          } else if (f.wireType == 5 && f.number == 2) {
            lon = nested.readFloat();
          } else if (f.wireType == 5 && f.number == 3) {
            bearing = nested.readFloat();
          } else {
            nested.skip(f.wireType);
          }
        }
      case 8:
        id = _parseStringField(nested, 1);
      default:
        break;
    }
  }
  if (lat == null || lon == null) return null;
  return LiveVehicle(
    id: id,
    routeId: routeId,
    point: LatLng(lat, lon),
    bearing: bearing,
    reportedAt: timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
  );
}

String _parseStringField(_ProtoReader reader, int number) {
  while (reader.hasMore) {
    final field = reader.readTag();
    if (field.number == number && field.wireType == 2) {
      return reader.readString();
    }
    reader.skip(field.wireType);
  }
  return '';
}

typedef _Field = ({int number, int wireType});

class _ProtoReader {
  final Uint8List _bytes;
  final ByteData _view;
  int _offset;
  final int _end;

  _ProtoReader(Uint8List bytes, [int start = 0, int? end])
    : _bytes = bytes,
      _view = ByteData.sublistView(bytes),
      _offset = start,
      _end = end ?? bytes.length;

  bool get hasMore => _offset < _end;

  int readVarint() => _readVarint();

  int _readVarint() {
    var result = 0;
    var shift = 0;
    while (_offset < _end) {
      final byte = _bytes[_offset++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) break;
      shift += 7;
    }
    return result;
  }

  _Field readTag() {
    final tag = _readVarint();
    return (number: tag >> 3, wireType: tag & 0x7);
  }

  _ProtoReader readLengthDelimited() {
    final length = _readVarint();
    final start = _offset;
    _offset = (start + length).clamp(start, _end);
    return _ProtoReader(_bytes, start, _offset);
  }

  String readString() {
    final length = _readVarint();
    final start = _offset;
    _offset = (start + length).clamp(start, _end);
    return String.fromCharCodes(_bytes, start, _offset);
  }

  double readFloat() {
    final value = _view.getFloat32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        _readVarint();
      case 1:
        _offset += 8;
      case 2:
        final length = _readVarint();
        _offset = (_offset + length).clamp(_offset, _end);
      case 5:
        _offset += 4;
      default:
        _offset = _end;
    }
  }
}
