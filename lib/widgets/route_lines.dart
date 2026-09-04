import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// How a bus route is drawn, so the three maps that draw one agree.
///
/// Two lines share the map: the whole published route, and the stretch the
/// rider is actually on. Drawing both at the same weight makes them one
/// indistinguishable smear, so the context line is thin and washed out while
/// the leg is thick and carries a white casing that lifts it off whatever it
/// crosses - including the context line itself.
class RouteLines {
  /// The stretch the rider actually travels gets its own colour rather than a
  /// thicker version of the service's. Sharing the colour meant the leg and
  /// the route it sits on read as one line; orange belongs to no service
  /// (red troncal, green alimentador, blue zonal, purple cable) so it can
  /// only mean "this part is yours".
  static const legColor = Color(0xFFFF6D00);

  /// The full route is a thin thread in the service's colour: present enough
  /// to say where the bus goes, never loud enough to compete with the leg.
  static const _contextWidth = 3.0;
  static const _contextAlpha = 0.45;

  static const _legWidth = 6.0;
  static const _casingWidth = 2.5;

  /// The full route, as background. Never the thing the eye lands on.
  static Polyline context(List<LatLng> points, Color color) => Polyline(
        points: points,
        strokeWidth: _contextWidth,
        color: color.withValues(alpha: _contextAlpha),
        strokeCap: StrokeCap.round,
      );

  /// The whole route when no leg is picked yet - then it *is* the subject.
  static Polyline whole(List<LatLng> points, Color color) => Polyline(
        points: points,
        strokeWidth: 5,
        color: color.withValues(alpha: 0.85),
        strokeCap: StrokeCap.round,
      );

  /// Where the rider boards to where they get off, in [legColor] over
  /// whatever service colour runs underneath.
  static Polyline leg(List<LatLng> points) => Polyline(
        points: points,
        strokeWidth: _legWidth,
        color: legColor,
        borderStrokeWidth: _casingWidth,
        borderColor: Colors.white,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      );

  /// The part of the leg already behind the rider.
  static Polyline travelled(List<LatLng> points) => Polyline(
        points: points,
        strokeWidth: _legWidth - 0.5,
        color: Colors.grey.shade500,
        borderStrokeWidth: _casingWidth,
        borderColor: Colors.white,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      );

  /// Walking, in blue and dotted. Dotted because the app does not route on
  /// foot - it is a hint at the connection, not a claim about which streets
  /// to take - and blue because no bus service is that colour at this
  /// weight.
  static const walkColor = Color(0xFF1E88E5);

  static Polyline walk(List<LatLng> points) => Polyline(
        points: points,
        strokeWidth: 3.5,
        color: walkColor,
        pattern: StrokePattern.dotted(spacingFactor: 2.4),
        strokeCap: StrokeCap.round,
      );
}
