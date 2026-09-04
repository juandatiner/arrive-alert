import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Where a pin sits relative to the spot it marks.
///
/// Stops sit [onSpot], right on the drawn line, so they read as beads on the
/// route. Buses lean off it on a thin stem, so a bus standing at its own stop
/// is still two things you can tell apart, and neither hides the other.
enum PinLean {
  onSpot,
  upLeft,
  upRight,
  downLeft,
  downRight;

  bool get isUp => this == upLeft || this == upRight;

  bool get isLeft => this == upLeft || this == downLeft;
}

/// Green is where you get on, red is where you get off, black is the end of
/// the whole trip. Kept together so the three maps cannot drift apart.
const boardingColor = Color(0xFF2E7D32);
const alightColor = Color(0xFFC62828);
const destinationColor = Color(0xFF1B1B1F);

/// Plain stops are slate, not the service's colour: the live buses on the
/// same map already carry that colour, and two things in one colour on one
/// street is two things you cannot tell apart.
const stopColor = Color(0xFF37474F);

/// Where the trip starts. Amber rather than green, because green is already
/// "get on this bus here" and the start of a walk is not a bus.
const originColor = Color(0xFFF9A825);

/// Not buses: the live buses on the same map are bus icons, and a third one
/// meant nothing. Getting on and getting off mirror each other; the flag is
/// kept for the end of the whole trip, which is not a bus at all.
const boardingIcon = Icons.login_rounded;
const alightIcon = Icons.logout_rounded;
const destinationIcon = Icons.flag_rounded;

class MapPin extends StatelessWidget {
  /// How far the body sits from the spot, along both axes.
  static const _stem = 11.0;

  final Widget? child;
  final Color color;
  final Color borderColor;

  /// The stem's own colour. Defaults to the body's fill, which is wrong for a
  /// pin filled white - there the border colour is what carries the meaning.
  final Color? stemColor;
  final double width;
  final double height;
  final PinLean lean;
  final VoidCallback? onTap;

  const MapPin({
    super.key,
    this.child,
    required this.color,
    this.borderColor = Colors.white,
    this.stemColor,
    required this.width,
    required this.height,
    this.lean = PinLean.upLeft,
    this.onTap,
  });

  /// The marker box a pin of this size and lean needs.
  static Size boxFor(double width, double height, PinLean lean) =>
      lean == PinLean.onSpot
      ? Size(width, height)
      : Size(width + _stem, height + _stem);

  /// flutter_map reads `alignment` as where the widget sits *relative to the
  /// point* - `Alignment.topLeft` puts the whole widget up and left of it, so
  /// the spot lands on the widget's bottom-right corner, which is exactly
  /// where [_StemPainter] draws the tip. Getting this backwards detaches the
  /// stem from the route entirely.
  static Alignment alignmentFor(PinLean lean) {
    switch (lean) {
      case PinLean.onSpot:
        return Alignment.center;
      case PinLean.upLeft:
        return Alignment.topLeft;
      case PinLean.upRight:
        return Alignment.topRight;
      case PinLean.downLeft:
        return Alignment.bottomLeft;
      case PinLean.downRight:
        return Alignment.bottomRight;
    }
  }

  /// The body's rectangle on screen when the spot lands at [spot]. Used to
  /// work out which pins would sit on top of each other.
  static Rect bodyRect({
    required Offset spot,
    required double width,
    required double height,
    required PinLean lean,
  }) {
    if (lean == PinLean.onSpot) {
      return Rect.fromCenter(center: spot, width: width, height: height);
    }
    final left = lean.isLeft ? spot.dx - _stem - width : spot.dx + _stem;
    final top = lean.isUp ? spot.dy - _stem - height : spot.dy + _stem;
    return Rect.fromLTWH(left, top, width, height);
  }

  @override
  Widget build(BuildContext context) {
    final box = boxFor(width, height, lean);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: box.width,
        height: box.height,
        child: Stack(
          children: [
            if (lean != PinLean.onSpot)
              Positioned.fill(
                child: CustomPaint(
                  painter: _StemPainter(
                    color: stemColor ?? color,
                    bodyWidth: width,
                    bodyHeight: height,
                    lean: lean,
                  ),
                ),
              ),
            Positioned(
              left: lean.isLeft || lean == PinLean.onSpot ? 0 : _stem,
              top: lean.isUp || lean == PinLean.onSpot ? 0 : _stem,
              width: width,
              height: height,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(height / 2),
                  border: Border.all(color: borderColor, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StemPainter extends CustomPainter {
  /// The casing is always white: it exists to keep the stem readable over
  /// dark streets, whatever the pin itself is coloured.
  static const _casing = Colors.white;

  final Color color;
  final double bodyWidth;
  final double bodyHeight;
  final PinLean lean;

  const _StemPainter({
    required this.color,
    required this.bodyWidth,
    required this.bodyHeight,
    required this.lean,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final body = Offset(
      lean.isLeft ? bodyWidth / 2 : size.width - bodyWidth / 2,
      lean.isUp ? bodyHeight / 2 : size.height - bodyHeight / 2,
    );
    final spot = Offset(
      lean.isLeft ? size.width : 0,
      lean.isUp ? size.height : 0,
    );

    canvas.drawLine(
      body,
      spot,
      Paint()
        ..color = _casing
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      body,
      spot,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    // A dot on the exact coordinate, which is the whole point of the stem.
    canvas.drawCircle(spot, 2.6, Paint()..color = _casing);
    canvas.drawCircle(spot, 1.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StemPainter old) =>
      old.color != color ||
      old.bodyWidth != bodyWidth ||
      old.bodyHeight != bodyHeight ||
      old.lean != lean;
}

/// A pin that names the service you board or leave there.
///
/// At a transfer two of these land on the same corner, and "which bus, and
/// am I getting on or off it" is the only question that corner asks.
MapPin routeCodePin({
  required String code,
  required bool boarding,
  PinLean lean = PinLean.upLeft,
  VoidCallback? onTap,
}) {
  return MapPin(
    // Codes run from "2" to "M86-K86", so the pill grows with the text.
    width: 32.0 + code.length * 8.5,
    height: 26,
    color: boarding ? boardingColor : alightColor,
    lean: lean,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            boarding ? boardingIcon : alightIcon,
            size: 13,
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              code,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A plain stop: a bead sitting on the drawn line, no stem, because the line
/// is exactly where it belongs.
MapPin stopPin({
  required double size,
  Color color = stopColor,
  VoidCallback? onTap,
}) => MapPin(
  width: size,
  height: size,
  color: color,
  lean: PinLean.onSpot,
  onTap: onTap,
);

/// The two ends of the whole trip: plain dots. No bus is involved at either
/// end, so neither wears a service icon, and neither is green - green already
/// means "get on here".
MapPin endpointPin({required Color color, PinLean lean = PinLean.onSpot}) =>
    MapPin(width: 19, height: 19, color: color, lean: lean);

MapPin originPin({PinLean lean = PinLean.onSpot}) =>
    endpointPin(color: originColor, lean: lean);

MapPin destinationPin({PinLean lean = PinLean.onSpot}) =>
    endpointPin(color: destinationColor, lean: lean);

/// Wraps a [MapPin] in the marker box and alignment it needs so the stem's
/// tip lands on [point].
Marker pinMarker({
  required LatLng point,
  required MapPin pin,
  double opacity = 1,
}) {
  final box = MapPin.boxFor(pin.width, pin.height, pin.lean);
  return Marker(
    point: point,
    width: box.width,
    height: box.height,
    alignment: MapPin.alignmentFor(pin.lean),
    child: opacity == 1 ? pin : Opacity(opacity: opacity, child: pin),
  );
}

/// One pin that wants a place on the map without landing on another.
class PinPlacement {
  final LatLng point;

  /// Built once per candidate lean, because the lean changes the pin's shape.
  final MapPin Function(PinLean lean) build;

  /// Leans to try, best first.
  final List<PinLean> preferences;

  const PinPlacement({
    required this.point,
    required this.build,
    this.preferences = const [
      PinLean.upLeft,
      PinLean.upRight,
      PinLean.downRight,
      PinLean.downLeft,
    ],
  });
}

/// Draws pins so they never sit on top of each other.
///
/// Two stops a block apart are the same pixel when zoomed out, and at a
/// transfer the stop you leave and the stop you board are the same corner -
/// so a fixed lean guarantees that at some zoom one pin hides another. This
/// projects every pin to screen space at the current zoom and gives each the
/// first of its leans that is still free, which re-solves itself on every
/// pan and zoom because reading the camera makes this rebuild.
class DeclutteredPinLayer extends StatelessWidget {
  /// Breathing room between two pins before they count as colliding.
  static const _margin = 3.0;

  final List<PinPlacement> placements;

  const DeclutteredPinLayer({super.key, required this.placements});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final taken = <Rect>[];
    final markers = <Marker>[];

    for (final placement in placements) {
      final spot = camera.latLngToScreenOffset(placement.point);
      MapPin? chosen;
      Rect? chosenRect;

      for (final lean in placement.preferences) {
        final pin = placement.build(lean);
        final rect = MapPin.bodyRect(
          spot: spot,
          width: pin.width,
          height: pin.height,
          lean: lean,
        ).inflate(_margin);
        chosen ??= pin;
        chosenRect ??= rect;
        if (taken.every((other) => !other.overlaps(rect))) {
          chosen = pin;
          chosenRect = rect;
          break;
        }
      }

      if (chosen == null || chosenRect == null) continue;
      taken.add(chosenRect);
      markers.add(pinMarker(point: placement.point, pin: chosen));
    }
    return MarkerLayer(markers: markers);
  }
}
