import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/saved_trip.dart';
import '../models/transit_route.dart';
import '../services/location_service.dart';
import '../services/saved_trips_service.dart';
import '../services/transit_service.dart';
import '../utils/format.dart';
import '../utils/path_geometry.dart';
import '../widgets/map_style.dart';
import 'route_picker_sheet.dart' show kindColor;
import 'trip_screen.dart';

/// Draws one route exactly as the agency publishes it and lets the rider tap
/// the stop they board at and the stop they get off at.
class RouteMapScreen extends StatefulWidget {
  final TransitRouteSummary summary;

  /// Set when opening a saved leg, so the rider lands on their usual trip
  /// already selected.
  final int? initialOriginStop;
  final int? initialDestinationStop;

  const RouteMapScreen({
    super.key,
    required this.summary,
    this.initialOriginStop,
    this.initialDestinationStop,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final _mapController = MapController();

  TransitRoute? _route;
  RoutePath? _path;
  List<int>? _stopShapeIndices;
  String? _error;

  int? _originStop;
  int? _destinationStop;
  LatLng? _myLocation;
  bool _isSaved = false;


  @override
  void initState() {
    super.initState();
    _originStop = widget.initialOriginStop;
    _destinationStop = widget.initialDestinationStop;
    _load();
    _locateMe();
  }

  SavedTrip? get _currentTrip {
    final route = _route;
    final origin = _originStop;
    final destination = _destinationStop;
    if (route == null || origin == null || destination == null) return null;
    return SavedTrip(
      routeId: route.id,
      routeShortName: route.shortName,
      kind: route.kind,
      originIndex: origin,
      originName: route.stops[origin].name,
      destinationIndex: destination,
      destinationName: route.stops[destination].name,
    );
  }

  Future<void> _refreshSavedState() async {
    final trip = _currentTrip;
    final saved = trip == null ? false : await SavedTripsService.isSaved(trip);
    if (!mounted) return;
    setState(() => _isSaved = saved);
  }

  Future<void> _toggleSaved() async {
    final trip = _currentTrip;
    if (trip == null) return;
    final saved = await SavedTripsService.toggle(trip);
    if (!mounted) return;
    setState(() => _isSaved = saved);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(saved
            ? 'Ruta guardada: ${trip.routeShortName} · ${trip.originName} a ${trip.destinationName}'
            : 'Ruta quitada de guardadas'),
      ));
  }

  Future<void> _load() async {
    try {
      final route = await TransitService.loadRoute(widget.summary.id);
      final path = RoutePath(route.shape);
      // Stops sit near, not exactly on, the drawn shape - snap each one once
      // so every later measurement is a cheap index lookup.
      final indices =
          route.stops.map((s) => path.nearestIndex(s.point)).toList();
      if (!mounted) return;
      setState(() {
        _route = route;
        _path = path;
        _stopShapeIndices = indices;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
      _refreshSavedState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar la ruta.');
    }
  }

  Future<void> _locateMe() async {
    final access = await LocationService.ensurePermissions(background: false);
    if (access != LocationAccessResult.whileInUse &&
        access != LocationAccessResult.always) {
      return;
    }
    try {
      final pos = await LocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      // Location is a convenience here (suggesting the nearest stop), not a
      // requirement - the rider can always pick both stops by hand.
    }
  }

  void _fitRoute() {
    final route = _route;
    if (route == null || route.shape.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(route.shape),
        padding: const EdgeInsets.fromLTRB(40, 60, 40, 220),
      ),
    );
  }

  DateTime? _lastStopTapAt;
  int? _lastStopTapIndex;

  void _onStopTapped(int index) {
    // A marker tap can arrive twice in quick succession; without this guard
    // the duplicate immediately undoes the selection the first one made.
    final now = DateTime.now();
    if (_lastStopTapIndex == index &&
        _lastStopTapAt != null &&
        now.difference(_lastStopTapAt!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastStopTapAt = now;
    _lastStopTapIndex = index;

    setState(() {
      if (index == _originStop) {
        _originStop = null;
      } else if (index == _destinationStop) {
        _destinationStop = null;
      } else if (_originStop == null) {
        _originStop = index;
      } else {
        // Origin already set: further taps move where you get off, which is
        // the choice riders actually adjust.
        _destinationStop = index;
      }
    });
    _refreshSavedState();
  }

  void _useNearestStopAsOrigin() {
    final route = _route;
    final me = _myLocation;
    if (route == null || me == null) return;
    const distance = Distance();
    var best = 0;
    var bestMeters = double.infinity;
    for (var i = 0; i < route.stops.length; i++) {
      final meters = distance.as(LengthUnit.Meter, route.stops[i].point, me);
      if (meters < bestMeters) {
        bestMeters = meters;
        best = i;
      }
    }
    setState(() {
      _originStop = best;
      if (_destinationStop == best) _destinationStop = null;
    });
  }

  void _reset() {
    setState(() {
      _originStop = null;
      _destinationStop = null;
    });
  }

  double? get _legMeters {
    final path = _path;
    final indices = _stopShapeIndices;
    final origin = _originStop;
    final destination = _destinationStop;
    if (path == null || indices == null || origin == null || destination == null) {
      return null;
    }
    return path.metersBetween(indices[origin], indices[destination]);
  }

  List<LatLng> get _legPath {
    final path = _path;
    final indices = _stopShapeIndices;
    final origin = _originStop;
    final destination = _destinationStop;
    if (path == null || indices == null || origin == null || destination == null) {
      return const [];
    }
    return path.slice(indices[origin], indices[destination]);
  }

  void _startTrip() {
    final route = _route;
    final origin = _originStop;
    final destination = _destinationStop;
    final meters = _legMeters;
    if (route == null || origin == null || destination == null || meters == null) {
      return;
    }
    final plan = TransitTripPlan(
      routeShortName: route.shortName,
      kind: route.kind,
      path: _legPath,
      originStop: route.stops[origin],
      destinationStop: route.stops[destination],
      meters: meters,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripScreen(
          destination: plan.destinationStop.point,
          destinationLabel: plan.destinationStop.name,
          transitPlan: plan,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ruta: ${widget.summary.shortName}'),
        actions: [
          if (_currentTrip != null)
            IconButton(
              icon: Icon(
                _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                color: _isSaved ? Colors.amber.shade600 : null,
              ),
              tooltip: _isSaved ? 'Quitar de guardadas' : 'Guardar esta ruta',
              onPressed: _toggleSaved,
            ),
          if (_originStop != null)
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded),
              tooltip: 'Reiniciar seleccion',
              onPressed: _reset,
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : _route == null
              ? const Center(child: CircularProgressIndicator())
              : _buildMap(),
    );
  }

  Widget _buildMap() {
    final route = _route!;
    final color = kindColor(route.kind);
    final leg = _legPath;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: route.shape.first,
            initialZoom: 12,
          ),
          children: [
            MapTileLayer(),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: route.shape,
                  strokeWidth: 5,
                  color: color.withValues(alpha: leg.isEmpty ? 0.85 : 0.25),
                ),
                if (leg.isNotEmpty)
                  Polyline(points: leg, strokeWidth: 7, color: color),
              ],
            ),
            MarkerLayer(markers: _buildStopMarkers(route, color)),
            const MapAttribution(),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _buildBottomCard(route),
        ),
        if (_myLocation != null && _originStop == null)
          Positioned(
            right: 12,
            bottom: 190,
            child: FloatingActionButton.small(
              heroTag: 'route_nearest_stop',
              tooltip: 'Paradero mas cercano',
              onPressed: _useNearestStopAsOrigin,
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }

  List<Marker> _buildStopMarkers(TransitRoute route, Color color) {
    final markers = <Marker>[];
    for (var i = 0; i < route.stops.length; i++) {
      final isOrigin = i == _originStop;
      final isDestination = i == _destinationStop;
      final selected = isOrigin || isDestination;

      markers.add(
        Marker(
          point: route.stops[i].point,
          width: selected ? 34 : 20,
          height: selected ? 34 : 20,
          child: GestureDetector(
            onTap: () => _onStopTapped(i),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOrigin
                    ? Colors.green.shade600
                    : isDestination
                        ? Colors.red.shade600
                        : Colors.white,
                border: Border.all(
                  color: selected ? Colors.white : color,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: selected
                  ? Icon(
                      isOrigin ? Icons.directions_bus_rounded : Icons.flag_rounded,
                      size: 17,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
        ),
      );
    }
    if (_myLocation != null) {
      markers.add(
        Marker(
          point: _myLocation!,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.shade600,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Widget _buildBottomCard(TransitRoute route) {
    final scheme = Theme.of(context).colorScheme;
    final meters = _legMeters;
    final origin = _originStop;
    final destination = _destinationStop;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            route.longName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _buildStopLine(
            icon: Icons.directions_bus_rounded,
            color: Colors.green.shade600,
            label: origin == null
                ? 'Toca en el mapa donde te subes'
                : route.stops[origin].name,
            placeholder: origin == null,
          ),
          const SizedBox(height: 6),
          _buildStopLine(
            icon: Icons.flag_rounded,
            color: Colors.red.shade600,
            label: destination == null
                ? 'Ahora toca donde te bajas'
                : route.stops[destination].name,
            placeholder: destination == null,
          ),
          if (meters != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '~${formatDuration(_minutesFor(route.kind, meters))}'
                  ' · ${(meters / 1000).toStringAsFixed(1)} km'
                  ' · ${(destination! - origin!).abs()} paraderos',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: meters == null ? null : _startTrip,
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
        ],
      ),
    );
  }

  int _minutesFor(TransitKind kind, double meters) =>
      (meters / (kind.averageKmh / 3.6) / 60).ceil();

  Widget _buildStopLine({
    required IconData icon,
    required Color color,
    required String label,
    required bool placeholder,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: placeholder ? Colors.grey : color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: placeholder ? FontWeight.normal : FontWeight.w600,
              color: placeholder ? Colors.grey.shade600 : null,
            ),
          ),
        ),
      ],
    );
  }
}
