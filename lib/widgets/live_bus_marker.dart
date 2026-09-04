import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/live_vehicles_feed.dart';
import '../services/live_vehicles_service.dart';
import 'map_pins.dart';

/// A bus where the agency last reported it. Pointed when the feed carries a
/// bearing, so a glance says which way it is heading.
List<Marker> liveBusMarkers(
  List<LiveVehicle> vehicles,
  Color color, {
  void Function(LiveVehicle vehicle)? onTap,
}) {
  return [
    for (final vehicle in vehicles)
      _busMarker(vehicle, color, onTap == null ? null : () => onTap(vehicle)),
  ];
}

/// Buses lean down-right, the mirror of the stops' up-left, so a bus sitting
/// on top of its own stop is still two distinguishable things.
Marker _busMarker(LiveVehicle vehicle, Color color, VoidCallback? onTap) {
  final bearing = vehicle.bearing;
  // Inverted against the stops on purpose: a bus is a white body with a
  // coloured bus in it, a stop is a solid slate body. Same map, no confusion.
  final pin = MapPin(
    width: 27,
    height: 27,
    color: Colors.white,
    borderColor: color,
    stemColor: color,
    lean: PinLean.downRight,
    onTap: onTap,
    child: bearing == null
        ? Icon(Icons.directions_bus_rounded, size: 15, color: color)
        : Transform.rotate(
            angle: bearing * 3.1415926535 / 180,
            child: Icon(Icons.navigation_rounded, size: 15, color: color),
          ),
  );
  return pinMarker(point: vehicle.point, pin: pin);
}

/// What a tapped bus says about itself: its fleet number, the service it is
/// running, and how old the position is.
void showLiveBusDetails(
  BuildContext context,
  LiveVehicle vehicle, {
  required String routeShortName,
}) {
  final reportedAt = vehicle.reportedAt;
  final age = reportedAt == null
      ? null
      : DateTime.now().difference(reportedAt).inSeconds;
  final number = vehicle.id.isEmpty ? 'sin numero' : 'Bus ${vehicle.id}';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          '$number · $routeShortName'
          '${age == null ? '' : ' · reportado hace ${age}s'}',
          style: const TextStyle(fontSize: 13),
        ),
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
        duration: const Duration(seconds: 4),
      ),
    );
}

/// One line telling the rider whether live positions are coming through.
/// The feed is public but often down, and an empty map with no explanation
/// reads as a bug in the app.
class LiveBusStatus extends StatelessWidget {
  final int count;

  const LiveBusStatus({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final off = !LiveVehiclesService.enabled;
    final unavailable =
        !off && count == 0 && LiveVehiclesService.feedUnavailable;
    final updatedAt = LiveVehiclesFeed.instance.updatedAt;
    final age = updatedAt == null
        ? null
        : DateTime.now().difference(updatedAt).inSeconds;
    return Row(
      children: [
        Icon(
          off
              ? Icons.sensors_off_rounded
              : unavailable
              ? Icons.cloud_off_rounded
              : Icons.sensors_rounded,
          size: 14,
          color: off || unavailable ? Colors.grey : Colors.green.shade600,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            off
                ? 'Buses en vivo apagados en Ajustes'
                : unavailable
                ? 'Buses en vivo no disponibles (no responde TransMilenio)'
                : count == 0
                ? 'Buscando buses en vivo...'
                : '$count ${count == 1 ? 'bus' : 'buses'} en vivo'
                      '${age == null ? '' : ' · hace ${age}s'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: off || unavailable ? Colors.grey : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// A deliberately dull "buscando buses" snack.
///
/// The fetch is normally quick enough that nothing shows at all; this only
/// appears when it drags, and it is grey, small and actionless so it never
/// competes with the map or the trip card for attention.
class LiveBusSnackController {
  /// Below this, a snack would flash past and read as a glitch.
  static const _slowAfter = Duration(milliseconds: 1200);

  Timer? _delay;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _shown;

  /// [bottomInset] lifts the snack above whatever card the screen keeps at
  /// the bottom, so it never covers a button.
  void update(
    BuildContext context, {
    required bool fetching,
    required bool hasVehicles,
    double bottomInset = 0,
  }) {
    // Once buses are on the map, later refreshes are silent.
    if (!fetching || hasVehicles) {
      _delay?.cancel();
      _delay = null;
      _shown?.close();
      _shown = null;
      return;
    }
    if (_delay != null || _shown != null) return;
    _delay = Timer(_slowAfter, () {
      _delay = null;
      if (!context.mounted) return;
      _shown = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: Colors.white70,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Buscando buses...',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: const Color(0xCC4A4A4F),
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: bottomInset + 12,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: const StadiumBorder(),
          duration: const Duration(minutes: 5),
        ),
      );
    });
  }

  void dispose() {
    _delay?.cancel();
    _delay = null;
    _shown?.close();
    _shown = null;
  }
}
