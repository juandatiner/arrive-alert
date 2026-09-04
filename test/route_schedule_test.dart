import 'package:flutter_test/flutter_test.dart';
import 'package:arrive_alert/models/transit_route.dart';

TransitRouteSummary _summary(String short, int dayMask, List<List<int>> hours) {
  return TransitRouteSummary.fromJson({
    'id': short,
    's': short,
    'l': 'x',
    'k': 'troncal',
    'n': 10,
    'd': dayMask,
    'h': hours,
  });
}

void main() {
  test('a weekday-only service is hidden on the day it does not run', () {
    // Monday to Saturday: bits 0..5.
    final route = _summary('MK86', 0x3F, [
      for (var i = 0; i < 6; i++) [270, 1263, 276],
    ]);
    expect(route.schedule.runsOn(DateTime.monday), isTrue);
    expect(route.schedule.runsOn(DateTime.saturday), isTrue);
    expect(route.schedule.runsOn(DateTime.sunday), isFalse);
    expect(route.schedule.windowFor(DateTime.sunday), isNull);
  });

  test('each day reads its own hours, not the first day it runs', () {
    // Friday and Sunday only: bits 4 and 6.
    final route = _summary('K86', 1 << 4 | 1 << 6, [
      [250, 1260, 125],
      [250, 410, 18],
    ]);
    expect(route.schedule.windowFor(DateTime.friday)!.trips, 125);
    expect(route.schedule.windowFor(DateTime.sunday)!.trips, 18);
    expect(route.schedule.windowFor(DateTime.sunday)!.label, '04:10 - 06:50');
  });

  test('a last departure past midnight reads as the small hours', () {
    final route = _summary('6-4', 1, [
      [1123, 1470, 9],
    ]);
    expect(route.schedule.windowFor(DateTime.monday)!.label, '18:43 - 00:30');
  });

  test('a pack built before schedules existed still shows every route', () {
    final route = TransitRouteSummary.fromJson({
      'id': '1',
      's': 'B13',
      'l': 'x',
      'k': 'zonal',
      'n': 10,
    });
    for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
      expect(route.schedule.runsOn(day), isTrue);
    }
    expect(route.schedule.windowFor(DateTime.monday), isNull);
  });
}
