import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:arrive_alert/services/live_vehicles_service.dart';

List<int> _varint(int value) {
  final out = <int>[];
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

List<int> _tag(int field, int wireType) => _varint(field << 3 | wireType);

List<int> _message(int field, List<int> body) =>
    [..._tag(field, 2), ..._varint(body.length), ...body];

List<int> _string(int field, String value) =>
    _message(field, utf8.encode(value));

List<int> _uint(int field, int value) => [..._tag(field, 0), ..._varint(value)];

List<int> _float(int field, double value) {
  final bytes = ByteData(4)..setFloat32(0, value, Endian.little);
  return [..._tag(field, 5), ...bytes.buffer.asUint8List()];
}

/// A FeedMessage carrying one vehicle, plus a header and spare fields the
/// parser is expected to skip.
Uint8List _feed({
  required String routeId,
  required String vehicleId,
  required double lat,
  required double lon,
}) {
  final header = [
    ..._string(1, '2.0'),
    ..._uint(2, 0),
    ..._uint(3, 1757000000),
  ];
  final position = [
    ..._float(1, lat),
    ..._float(2, lon),
    ..._float(3, 217.5),
  ];
  final vehiclePosition = [
    ..._message(1, _string(5, routeId)),
    ..._message(2, position),
    ..._uint(3, 12), // current_stop_sequence, unread
    ..._message(8, _string(1, vehicleId)),
  ];
  final entity = [
    ..._string(1, 'entity-1'),
    ..._message(4, vehiclePosition),
  ];
  return Uint8List.fromList([
    ..._message(1, header),
    ..._message(2, entity),
  ]);
}

void main() {
  test('reads a vehicle out of a GTFS-Realtime feed', () {
    final vehicles = parseVehiclePositionsFeed(_feed(
      routeId: '12151',
      vehicleId: 'BUS-7',
      lat: 4.6486,
      lon: -74.0629,
    ));

    expect(vehicles, hasLength(1));
    expect(vehicles.single.routeId, '12151');
    expect(vehicles.single.id, 'BUS-7');
    expect(vehicles.single.point.latitude, closeTo(4.6486, 0.0001));
    expect(vehicles.single.point.longitude, closeTo(-74.0629, 0.0001));
    expect(vehicles.single.bearing, closeTo(217.5, 0.01));
  });

  test('reads the real TransMilenio feed', () {
    // 25 entities captured verbatim from
    // https://gtfs.transmilenio.gov.co/positions.pb - the endpoint the app
    // polls. Guards the decoder against the shape of the actual payload,
    // not just a hand-built one.
    final bytes = File('test/fixtures/positions_sample.pb').readAsBytesSync();
    final vehicles = parseVehiclePositionsFeed(bytes);

    expect(vehicles, hasLength(25));
    for (final vehicle in vehicles) {
      expect(vehicle.id, isNotEmpty);
      expect(vehicle.routeId, isNotEmpty);
      // Bogota's bounding box - a decoder reading the wrong field would put
      // buses in the Gulf of Guinea.
      expect(vehicle.point.latitude, inInclusiveRange(4.3, 4.9));
      expect(vehicle.point.longitude, inInclusiveRange(-74.3, -73.9));
      expect(vehicle.reportedAt, isNotNull);
    }
  });

  test('an empty or truncated feed yields no vehicles, not a crash', () {
    expect(parseVehiclePositionsFeed(Uint8List(0)), isEmpty);
    final full = _feed(
      routeId: '1',
      vehicleId: 'x',
      lat: 4.6,
      lon: -74.1,
    );
    expect(
      parseVehiclePositionsFeed(full.sublist(0, full.length ~/ 2)),
      isEmpty,
    );
  });
}
