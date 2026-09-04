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

  group('a service that is not running right now says so', () {
    // M86 runs 22:10-23:00 every day.
    final m86 = _summary('M86', 0x7F, [
      for (var i = 0; i < 7; i++) [1330, 1380, 6],
    ]);

    test('before the first bus it is waiting, not running', () {
      final at = m86.schedule.statusAt(DateTime(2026, 9, 7, 18, 0));
      expect(at.status, ServiceStatus.notYet);
      expect(at.window!.firstClock, '22:10');
    });

    test('between first and last bus it is running', () {
      expect(m86.schedule.statusAt(DateTime(2026, 9, 7, 22, 30)).status,
          ServiceStatus.running);
    });

    test('after the last bus it is finished', () {
      final at = m86.schedule.statusAt(DateTime(2026, 9, 7, 23, 30));
      expect(at.status, ServiceStatus.finished);
      expect(at.window!.lastClock, '23:00');
    });
  });

  test('a service running past midnight is still running after midnight', () {
    // Monday 18:43 to 00:30, which the feed stores as 24:30.
    final route = _summary('6-4', 1, [
      [1123, 1470, 9],
    ]);
    // Tuesday at 00:10 - the route does not run Tuesdays, but Monday's last
    // buses are still out.
    final at = route.schedule.statusAt(DateTime(2026, 9, 8, 0, 10));
    expect(at.status, ServiceStatus.running);
    expect(at.window!.lastClock, '00:30');
    // By 01:00 Monday's service is over and Tuesday has none.
    expect(route.schedule.statusAt(DateTime(2026, 9, 8, 1, 0)).status,
        ServiceStatus.unknown);
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
    // Hours unknown is not the same as "not running": the row stays lit.
    expect(route.schedule.statusAt(DateTime(2026, 9, 7, 3, 0)).status,
        ServiceStatus.unknown);
  });
}
