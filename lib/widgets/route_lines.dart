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
  static const _contextWidth = 3.5;
  static const _contextAlpha = 0.28;
  static const _legWidth = 7.0;
  static const _casingWidth = 3.0;

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

  /// Where the rider boards to where they get off.
  static Polyline leg(List<LatLng> points, Color color) => Polyline(
        points: points,
        strokeWidth: _legWidth,
        color: color,
        borderStrokeWidth: _casingWidth,
        borderColor: Colors.white,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      );

  /// The part of the leg already behind the rider.
  static Polyline travelled(List<LatLng> points) => Polyline(
        points: points,
        strokeWidth: _legWidth - 1,
        color: Colors.grey.shade500,
        borderStrokeWidth: _casingWidth,
        borderColor: Colors.white,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      );

  /// Walking, which the app does not route - a straight hint, not a claim
  /// about which streets to take.
  static Polyline walk(List<LatLng> points) => Polyline(
        points: points,
        strokeWidth: 3,
        color: Colors.grey.shade600,
        pattern: StrokePattern.dotted(spacingFactor: 2.2),
        strokeCap: StrokeCap.round,
      );
}
