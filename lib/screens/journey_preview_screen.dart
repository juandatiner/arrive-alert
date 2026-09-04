import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/journey.dart';
import '../models/transit_route.dart';
import 'dart:async';

import '../services/live_vehicles_feed.dart';
import '../services/live_vehicles_service.dart';
import '../services/transit_service.dart';
import '../utils/format.dart';
import '../widgets/live_bus_marker.dart';
import '../widgets/map_style.dart';
import '../widgets/route_lines.dart';
import '../widgets/route_badge.dart';
import 'route_map_screen.dart';
import 'route_picker_sheet.dart' show kindColor;
import 'trip_screen.dart';

/// One planned option, drawn and spelled out step by step, before the rider
/// commits to it.
class JourneyPreviewScreen extends StatefulWidget {
  final Journey journey;
  final LatLng origin;
  final LatLng destination;
  final String destinationLabel;

  const JourneyPreviewScreen({
    super.key,
    required this.journey,
    required this.origin,
    required this.destination,
    required this.destinationLabel,
  });

  @override
  State<JourneyPreviewScreen> createState() => _JourneyPreviewScreenState();
}

class _JourneyPreviewScreenState extends State<JourneyPreviewScreen> {
  final _mapController = MapController();

  /// The drawn legs, in the same order as [Journey.rides]. Loaded from the
  /// per-route assets, which the planner index deliberately doesn't carry.
  List<TransitTripPlan>? _legs;
  List<TransitRouteSummary>? _summaries;
  String? _error;

  List<LiveVehicle> _liveVehicles = const [];
  StreamSubscription<List<LiveVehicle>>? _liveSub;
  final _liveSnack = LiveBusSnackController();

  @override
  void initState() {
    super.initState();
    _loadLegs();
  }

  Future<void> _loadLegs() async {
    try {
      final index = await TransitService.loadIndex();
      final legs = <TransitTripPlan>[];
      final summaries = <TransitRouteSummary>[];
      for (final ride in widget.journey.rides) {
        final route = await TransitService.loadRoute(ride.routeId);
        legs.add(route.legBetween(ride.boardSeq, ride.alightSeq));
        summaries.add(index.firstWhere((r) => r.id == ride.routeId));
      }
      if (!mounted) return;
      setState(() {
        _legs = legs;
        _summaries = summaries;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitJourney());
      _startLiveVehicles();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar el trazado de la ruta.');
    }
  }

  void _startLiveVehicles() {
    final wanted = {for (final ride in widget.journey.rides) ride.routeId};
    _liveSub?.cancel();
    LiveVehiclesFeed.instance.fetching.addListener(_onFetchingChanged);
    _onFetchingChanged();
    _liveSub = LiveVehiclesFeed.instance.subscribe((vehicles) {
      if (!mounted) return;
      setState(() => _liveVehicles =
          vehicles.where((v) => wanted.contains(v.routeId)).toList());
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    LiveVehiclesFeed.instance.fetching.removeListener(_onFetchingChanged);
    _liveSnack.dispose();
    super.dispose();
  }

  void _onFetchingChanged() {
    if (!mounted) return;
    _liveSnack.update(
      context,
      fetching: LiveVehiclesFeed.instance.fetching.value,
      hasVehicles: _liveVehicles.isNotEmpty,
      bottomInset: 60,
    );
  }

  void _fitJourney() {
    final legs = _legs;
    if (legs == null) return;
    final points = <LatLng>[
      widget.origin,
      widget.destination,
      for (final leg in legs) ...leg.path,
    ];
    if (points.length < 2) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(36, 60, 36, 40),
      ),
    );
  }

  void _startTrip() {
    final legs = _legs;
    if (legs == null || legs.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripScreen(
          destination: legs.last.destinationStop.point,
          destinationLabel: legs.last.destinationStop.name,
          legs: legs,
        ),
      ),
    );
  }

  void _openRouteMap(int rideIndex) {
    final summaries = _summaries;
    if (summaries == null) return;
    final ride = widget.journey.rides[rideIndex];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteMapScreen(
          summary: summaries[rideIndex],
          initialOriginStop: ride.boardSeq,
          initialDestinationStop: ride.alightSeq,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (widget.journey.totalSeconds / 60).ceil();
    return Scaffold(
      appBar: AppBar(title: Text('Ruta · ${formatDuration(minutes)}')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _legs == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(flex: 5, child: _buildMap()),
                    Expanded(flex: 4, child: _buildSteps()),
                  ],
                ),
    );
  }

  Widget _buildMap() {
    final legs = _legs!;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.origin,
        initialZoom: 12,
      ),
      children: [
        MapTileLayer(),
        PolylineLayer(
          polylines: [
            // Each bus's whole line first, so the ridden stretches stand out
            // against it rather than floating on their own.
            for (final leg in legs)
              RouteLines.context(leg.routePath, kindColor(leg.kind)),
            for (final leg in widget.journey.legs)
              if (leg is WalkLeg) RouteLines.walk([leg.from, leg.to]),
            for (final leg in legs) RouteLines.leg(leg.path, kindColor(leg.kind)),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.origin,
              width: 20,
              height: 20,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.shade600,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
            for (final leg in legs) ...[
              Marker(
                point: leg.originStop.point,
                width: 26,
                height: 26,
                child: _pin(Icons.directions_bus_rounded, Colors.green.shade600),
              ),
              Marker(
                point: leg.destinationStop.point,
                width: 26,
                height: 26,
                child: _pin(Icons.flag_rounded, arrivalColor),
              ),
            ],
            Marker(
              point: widget.destination,
              width: 36,
              height: 36,
              child: const Icon(Icons.location_on, color: arrivalColor, size: 34),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final ride in widget.journey.rides)
              ...liveBusMarkers(
                _liveVehicles.where((v) => v.routeId == ride.routeId).toList(),
                kindColor(ride.kind),
              ),
          ],
        ),
        const MapAttribution(),
      ],
    );
  }

  Widget _pin(IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2.5),
      ),
      child: Icon(icon, size: 13, color: Colors.white),
    );
  }

  Widget _buildSteps() {
    final scheme = Theme.of(context).colorScheme;
    var rideIndex = 0;
    final rows = <Widget>[];
    for (final leg in widget.journey.legs) {
      if (leg is WalkLeg) {
        rows.add(_walkRow(leg));
      } else if (leg is RideLeg) {
        rows.add(_rideRow(leg, rideIndex));
        rideIndex++;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              children: rows,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LiveBusStatus(count: _liveVehicles.length),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_legs?.isEmpty ?? true) ? null : _startTrip,
                icon: const Icon(Icons.notifications_active_rounded, size: 18),
                label: const Text('Avisarme antes de bajar'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _walkRow(WalkLeg leg) {
    final minutes = (leg.seconds / 60).ceil();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 34,
            child: Icon(Icons.directions_walk_rounded, size: 20),
          ),
          Expanded(
            child: Text(
              'Camina ${leg.meters.round()} m hasta ${leg.toLabel} '
              '(~$minutes min)',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rideRow(RideLeg leg, int rideIndex) {
    final scheme = Theme.of(context).colorScheme;
    final minutes = ((leg.seconds + leg.waitSeconds) / 60).ceil();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Icon(Icons.directions_bus_rounded,
                size: 20, color: kindColor(leg.kind)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RouteBadge(shortName: leg.routeShortName, kind: leg.kind),
                    Text(
                      leg.kind.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Sube en ${leg.boardStopName}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Bajate en ${leg.alightStopName}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${leg.stopCount} paraderos · '
                  '${(leg.meters / 1000).toStringAsFixed(1)} km · ~$minutes min '
                  'con espera',
                  style:
                      TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                if (leg.alsoServedBy.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Tambien sirve:',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant)),
                        for (final code in leg.alsoServedBy)
                          RouteBadge(
                              shortName: code, kind: leg.kind, compact: true),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _openRouteMap(rideIndex),
                    child: const Text('Ver todos los paraderos',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
