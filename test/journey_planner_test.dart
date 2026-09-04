import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:arrive_alert/models/journey.dart';
import 'package:arrive_alert/services/journey_planner.dart';
import 'package:arrive_alert/services/transit_index_service.dart';
import 'package:arrive_alert/services/transit_service.dart';

const _portalNorte = LatLng(4.7540, -74.0460);
const _portalSur = LatLng(4.5960, -74.1470);
const _chapinero = LatLng(4.6480, -74.0630);
const _universidadNacional = LatLng(4.6360, -74.0830);
const _twoBlocksFromChapinero = LatLng(4.6495, -74.0640);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the planner index covers the whole bundled network', () async {
    final index = await TransitIndexService.load();
    expect(index.routes.length, 1044);
    expect(index.stops.length, 8172);
    expect(index.routeStops.length, index.routes.length);
    expect(index.routeMeters.length, index.routes.length);
    for (var r = 0; r < index.routes.length; r++) {
      expect(index.routeMeters[r].length, index.routeStops[r].length);
    }
  });

  test('every route measures as monotonically longer along its stops',
      () async {
    final index = await TransitIndexService.load();
    for (var r = 0; r < index.routes.length; r++) {
      final meters = index.routeMeters[r];
      for (var i = 1; i < meters.length; i++) {
        expect(meters[i], greaterThanOrEqualTo(meters[i - 1]),
            reason: '${index.routes[r].shortName} stop $i goes backwards');
      }
    }
  });

  test('a cross-city trip plans as a believable transit journey', () async {
    final journeys = await JourneyPlanner.plan(
      origin: _portalNorte,
      destination: _portalSur,
    );
    expect(journeys, isNotEmpty);

    final best = journeys.first;
    expect(best.rides, isNotEmpty);
    // Portal Norte to Portal Sur is about 25 km of riding and takes over an
    // hour in practice; anything under half that means a broken measurement.
    expect(best.totalSeconds / 60, greaterThan(35));
    expect(best.totalSeconds / 60, lessThan(180));
    expect(best.rides.fold<double>(0, (sum, r) => sum + r.meters),
        greaterThan(15000));
  });

  test('rides never cover many stops in zero metres', () async {
    for (final pair in [
      [_portalNorte, _portalSur],
      [_chapinero, _universidadNacional],
    ]) {
      final journeys =
          await JourneyPlanner.plan(origin: pair[0], destination: pair[1]);
      for (final journey in journeys) {
        for (final ride in journey.rides) {
          expect(ride.meters, greaterThan(50 * ride.stopCount / 10),
              reason: '${ride.routeShortName} claims ${ride.stopCount} stops '
                  'in ${ride.meters} m');
        }
      }
    }
  });

  test('walking wins over taking a bus two blocks', () async {
    final journeys = await JourneyPlanner.plan(
      origin: _chapinero,
      destination: _twoBlocksFromChapinero,
    );
    expect(journeys.first.rides, isEmpty);
    expect(journeys.first.legs.single, isA<WalkLeg>());
  });

  test('a planned ride maps onto the drawn route it came from', () async {
    final journeys = await JourneyPlanner.plan(
      origin: _chapinero,
      destination: _universidadNacional,
    );
    final ride = journeys.expand((j) => j.rides).first;
    final route = await TransitService.loadRoute(ride.routeId);

    expect(route.stops[ride.boardSeq].name, ride.boardStopName);
    expect(route.stops[ride.alightSeq].name, ride.alightStopName);

    final leg = route.legBetween(ride.boardSeq, ride.alightSeq);
    expect(leg.stops.first.name, ride.boardStopName);
    expect(leg.stops.last.name, ride.alightStopName);
    expect(leg.meters, closeTo(ride.meters, 1));
    expect(leg.stopPathIndices.length, leg.stops.length);
    expect(leg.stopPathIndices.first, 0);
    expect(leg.stopPathIndices.last, leg.path.length - 1);
    // The drawn line has to start and end on the stops themselves, not on the
    // nearest vertex of the route's shape.
    expect(leg.path.first, route.stops[ride.boardSeq].point);
    expect(leg.path.last, route.stops[ride.alightSeq].point);
    for (var i = 1; i < leg.stopPathIndices.length; i++) {
      expect(leg.stopPathIndices[i],
          greaterThanOrEqualTo(leg.stopPathIndices[i - 1]));
      expect(leg.stopMeters[i], greaterThanOrEqualTo(leg.stopMeters[i - 1]));
    }
  });

  test('every leg of every route starts and ends on its two stops', () async {
    for (final id in ['10039', '12151', '12237', '12083', '10082']) {
      final route = await TransitService.loadRoute(id);
      final last = route.stops.length - 1;
      for (final pair in [[0, last], [0, 1], [last ~/ 3, last], [2, last - 1]]) {
        if (pair[0] >= pair[1]) continue;
        final leg = route.legBetween(pair[0], pair[1]);
        expect(leg.path.first, route.stops[pair[0]].point, reason: '$id $pair');
        expect(leg.path.last, route.stops[pair[1]].point, reason: '$id $pair');
        expect(leg.path.length, greaterThanOrEqualTo(2), reason: '$id $pair');
        for (var i = 1; i < leg.stopPathIndices.length; i++) {
          expect(leg.stopPathIndices[i],
              greaterThanOrEqualTo(leg.stopPathIndices[i - 1]),
              reason: '$id $pair');
        }
      }
    }
  });

  test('a leg picked backwards along a route still runs board to alight',
      () async {
    final route = await TransitService.loadRoute('10039');
    final last = route.stops.length - 1;
    final leg = route.legBetween(last, 0);

    expect(leg.stops.first.name, route.stops[last].name);
    expect(leg.stops.last.name, route.stops.first.name);
    expect(leg.stopPathIndices.first, 0);
    expect(leg.stopPathIndices.last, leg.path.length - 1);
    expect(leg.path.first, route.stops[last].point);
    expect(leg.path.last, route.stops.first.point);
    expect(leg.meters, closeTo(route.metersBetweenStops(0, last), 1));
  });
}
