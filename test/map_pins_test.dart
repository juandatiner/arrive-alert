import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arrive_alert/widgets/map_pins.dart';

void main() {
  // The stem is the whole point of a leaning pin: it ties the body, which
  // sits off to one side, back to the exact coordinate. Get the alignment
  // backwards and the tip lands somewhere else entirely on the map, which is
  // silent - nothing errors, the pins just stop meaning anything.
  group('a leaning pin puts its stem tip on the marker point', () {
    const width = 30.0;
    const height = 30.0;

    Alignment expectedFor(PinLean lean) {
      final box = MapPin.boxFor(width, height, lean);
      return Marker.computePixelAlignment(
        width: box.width,
        height: box.height,
        left: lean.isLeft ? box.width : 0,
        top: lean.isUp ? box.height : 0,
      );
    }

    for (final lean in [
      PinLean.upLeft,
      PinLean.upRight,
      PinLean.downLeft,
      PinLean.downRight,
    ]) {
      test('$lean anchors on the corner its stem points at', () {
        expect(MapPin.alignmentFor(lean), expectedFor(lean));
      });
    }

    test('a pin on the spot is simply centred, with no room for a stem', () {
      expect(MapPin.alignmentFor(PinLean.onSpot), Alignment.center);
      expect(MapPin.boxFor(width, height, PinLean.onSpot),
          const Size(width, height));
    });

    test('a leaning box leaves equal room on both axes', () {
      final box = MapPin.boxFor(width, height, PinLean.upLeft);
      expect(box.width, greaterThan(width));
      expect(box.width - width, box.height - height);
    });
  });

  group('bodyRect follows the lean', () {
    const spot = Offset(100, 100);
    Rect rectFor(PinLean lean) =>
        MapPin.bodyRect(spot: spot, width: 20, height: 20, lean: lean);

    test('opposite leans never overlap, so a bus never hides its stop', () {
      expect(
        rectFor(PinLean.upLeft).overlaps(rectFor(PinLean.downRight)),
        isFalse,
      );
      expect(
        rectFor(PinLean.upRight).overlaps(rectFor(PinLean.downLeft)),
        isFalse,
      );
    });

    test('each lean puts the body on its own side of the spot', () {
      expect(rectFor(PinLean.upLeft).right, lessThan(spot.dx));
      expect(rectFor(PinLean.upLeft).bottom, lessThan(spot.dy));
      expect(rectFor(PinLean.downRight).left, greaterThan(spot.dx));
      expect(rectFor(PinLean.downRight).top, greaterThan(spot.dy));
      expect(rectFor(PinLean.upRight).left, greaterThan(spot.dx));
      expect(rectFor(PinLean.downLeft).right, lessThan(spot.dx));
    });

    test('a pin on the spot straddles it', () {
      expect(rectFor(PinLean.onSpot).center, spot);
    });
  });
}
