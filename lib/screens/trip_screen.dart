import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vibration/vibration.dart';
import '../models/alert_settings.dart';
import '../models/route_info.dart';
import '../models/transit_route.dart';
import '../services/alarm_player.dart';
import '../services/alert_service.dart';
import '../services/live_vehicles_feed.dart';
import '../services/live_vehicles_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/routing_service.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';
import '../utils/path_geometry.dart';
import '../widgets/live_bus_marker.dart';
import '../widgets/map_style.dart';
import '../widgets/route_lines.dart';
import 'route_map_screen.dart' show arrivalColor;
import 'route_picker_sheet.dart' show kindColor;

class TripScreen extends StatefulWidget {
  final LatLng destination;
  final String destinationLabel;

  /// When set, the trip follows published transit routes instead of a routed
  /// path: the geometry is fixed and only the remaining distance along it is
  /// recomputed as the rider moves. More than one leg means a transfer.
  final List<TransitTripPlan> legs;

  const TripScreen({
    super.key,
    required this.destination,
    required this.destinationLabel,
    this.legs = const [],
  });

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen>
    with SingleTickerProviderStateMixin {
  final _mapController = MapController();

  AlertSettings _settings = const AlertSettings();
  RouteInfo? _route;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSub;

  DateTime? _lastRouteFetch;
  LatLng? _lastRouteOrigin;
  bool _firstFired = false;
  bool _secondFired = false;

  /// The alarm fires once per target. Without this, stopping it only silences
  /// it until the next position arrives and the threshold is still met.
  bool _alarmFired = false;
  bool _alarmActive = false;
  bool _arrived = false;
  bool _loading = true;
  LocationAccessResult? _accessError;
  String? _genericError;
  Timer? _vibrationLoop;
  bool _hasAlwaysPermission = true;
  bool _bannerDismissed = false;

  /// Which leg of the journey the rider is on, and how far along its drawn
  /// path they have got. The path itself is never trimmed: the stops behind
  /// the rider stay on the map, greyed out.
  int _legIndex = 0;
  int _passedIndex = 0;

  /// Where the rider currently intends to get off, as a position in the
  /// leg's stop list. Starts at the planned stop and moves when they tap an
  /// earlier one.
  late int _alightIndex;
  RoutePath? _legPath;

  /// Set when the alarm is for a transfer rather than the final stop.
  bool _transferPending = false;

  List<LiveVehicle> _liveVehicles = const [];
  StreamSubscription<List<LiveVehicle>>? _liveSub;
  final _liveSnack = LiveBusSnackController();

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  bool get _isTransit => widget.legs.isNotEmpty;

  TransitTripPlan get _leg => widget.legs[_legIndex];

  bool get _isLastLeg => _legIndex == widget.legs.length - 1;

  TransitStop get _alightStop => _leg.stops[_alightIndex];

  String get _targetLabel =>
      _isTransit ? _alightStop.name : widget.destinationLabel;

  @override
  void initState() {
    super.initState();
    _alightIndex = _isTransit ? widget.legs.first.stops.length - 1 : 0;
    _start();
  }

  Future<void> _start() async {
    _settings = await SettingsService.load();

    final result = await LocationService.ensurePermissions(background: true);
    if (result == LocationAccessResult.serviceDisabled ||
        result == LocationAccessResult.denied ||
        result == LocationAccessResult.deniedForever) {
      setState(() {
        _loading = false;
        _accessError = result;
      });
      return;
    }
    _hasAlwaysPermission = result == LocationAccessResult.always;

    if (_isTransit) {
      _legPath = RoutePath(_leg.path);
      try {
        final pos = await LocationService.getCurrentPosition();
        if (!mounted) return;
        setState(() {
          _currentPosition = pos;
          _loading = false;
        });
        _updateTransitProgress(pos);
      } catch (_) {
        // No fix yet: show the whole leg until the first position arrives.
        if (!mounted) return;
        setState(() {
          _route = _transitRouteInfo(_leg.stopMeters[_alightIndex]);
          _loading = false;
        });
      }
      _positionSub = LocationService.watchPosition().listen(_handlePosition);
      _startLiveVehicles();
      return;
    }

    try {
      final pos = await LocationService.getCurrentPosition();
      final origin = LatLng(pos.latitude, pos.longitude);
      final route = await RoutingService.getRoute(
        origin: origin,
        destination: widget.destination,
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _route = route;
        _loading = false;
      });
      _lastRouteOrigin = origin;
      _lastRouteFetch = DateTime.now();
      _checkThresholds(route);
    } catch (e) {
      setState(() {
        _loading = false;
        _genericError = 'No se pudo calcular la ruta. Revisa tu conexion.';
      });
      return;
    }

    _positionSub = LocationService.watchPosition().listen(_handlePosition);
  }

  /// Remaining leg for a transit trip. No router involved.
  RouteInfo _transitRouteInfo(double remainingMeters) {
    return RouteInfo(
      points: _leg.path,
      distanceMeters: remainingMeters,
      durationSeconds: _leg.secondsFor(remainingMeters),
    );
  }

  void _updateTransitProgress(Position pos) {
    final path = _legPath;
    if (path == null || path.points.isEmpty) return;
    final here = LatLng(pos.latitude, pos.longitude);
    final index = path.nearestIndex(here);
    final remaining = math.max(
      0.0,
      _leg.stopMeters[_alightIndex] - path.metersFromStart(index),
    );
    final route = _transitRouteInfo(remaining);
    if (!mounted) return;
    setState(() {
      // Progress only moves forward: a noisy fix that snaps to an earlier
      // part of the path must not un-grey stops the rider already passed.
      _passedIndex = math.max(_passedIndex, index);
      _route = route;
    });
    _checkThresholds(route);
  }

  Future<void> _handlePosition(Position pos) async {
    if (!mounted) return;
    setState(() => _currentPosition = pos);

    if (_isTransit) {
      _updateTransitProgress(pos);
      return;
    }

    final origin = LatLng(pos.latitude, pos.longitude);
    final now = DateTime.now();
    final movedEnough = _lastRouteOrigin == null ||
        Geolocator.distanceBetween(
              _lastRouteOrigin!.latitude,
              _lastRouteOrigin!.longitude,
              origin.latitude,
              origin.longitude,
            ) >
            40;
    final longEnough = _lastRouteFetch == null ||
        now.difference(_lastRouteFetch!) > const Duration(seconds: 15);
    if (!movedEnough && !longEnough) return;

    _lastRouteOrigin = origin;
    _lastRouteFetch = now;

    try {
      final route = await RoutingService.getRoute(
        origin: origin,
        destination: widget.destination,
      );
      if (!mounted) return;
      setState(() => _route = route);
      _checkThresholds(route);
    } catch (_) {
      // Network hiccup: keep last known route/countdown.
    }
  }

  void _checkThresholds(RouteInfo route) {
    final remainingMinutes = route.durationSeconds / 60;

    if (_settings.firstEnabled &&
        !_firstFired &&
        remainingMinutes <= _settings.firstMinutes) {
      _firstFired = true;
      AlertService.fireThresholdAlert(
        minutesLeft: _settings.firstMinutes,
        vibrationEnabled: _settings.vibrationEnabled,
        soundEnabled: _settings.soundEnabled,
        destinationLabel: _targetLabel,
      );
    }

    if (_settings.secondEnabled &&
        !_secondFired &&
        remainingMinutes <= _settings.secondMinutes) {
      _secondFired = true;
      AlertService.fireThresholdAlert(
        minutesLeft: _settings.secondMinutes,
        vibrationEnabled: _settings.vibrationEnabled,
        soundEnabled: _settings.soundEnabled,
        destinationLabel: _targetLabel,
      );
    }

    final arrived = route.distanceMeters < 40 || remainingMinutes <= 0.5;

    if ((remainingMinutes <= _settings.alarmMinutes || arrived) &&
        !_alarmFired) {
      // On every leg but the last one, "arriving" means getting off to
      // catch the next service, not being done.
      final transfer = _isTransit && !_isLastLeg;
      setState(() {
        _alarmFired = true;
        _alarmActive = true;
        _transferPending = transfer;
      });
      if (_settings.soundEnabled) AlarmPlayer.start();
      if (_settings.vibrationEnabled) _startVibrationLoop();
      AlertService.fireAlarmNotification(
        destinationLabel: _targetLabel,
        arrived: arrived,
        soundEnabled: _settings.soundEnabled,
      );
    }
    if (arrived && !_arrived) {
      setState(() => _arrived = true);
    }
  }

  /// Riders change their mind mid-ride - a stop before the one they planned
  /// is closer to where they are actually going, or they see their street.
  Future<void> _onStopTapped(int index) async {
    if (!_isTransit || index == _alightIndex) return;
    if (_leg.stopPathIndices[index] <= _passedIndex) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Ya pasaste ${_leg.stops[index].name}.'),
        ));
      return;
    }
    final stop = _leg.stops[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar donde te bajas'),
        content: Text('Te avisamos antes de ${stop.name} en vez de '
            '${_alightStop.name}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bajarme aqui'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _alightIndex = index;
      // The countdown restarts against a different stop, so the alerts that
      // already fired have to be allowed to fire again.
      _firstFired = false;
      _secondFired = false;
      _alarmFired = false;
      _arrived = false;
    });
    final pos = _currentPosition;
    if (pos != null) _updateTransitProgress(pos);
  }

  /// Only the buses on the leg being ridden, and only near the rider - the
  /// rest of the route's fleet is noise once the trip has started.
  static const _liveBusRadiusMeters = 6000.0;

  void _startLiveVehicles() {
    _liveSub?.cancel();
    LiveVehiclesFeed.instance.fetching.addListener(_onFetchingChanged);
    _onFetchingChanged();
    _liveSub = LiveVehiclesFeed.instance.subscribe((vehicles) {
      if (!mounted) return;
      const distance = Distance();
      final pos = _currentPosition;
      final here = pos == null ? null : LatLng(pos.latitude, pos.longitude);
      setState(() {
        _liveVehicles = vehicles
            .where((v) =>
                v.routeId == _leg.routeId &&
                (here == null ||
                    distance.as(LengthUnit.Meter, here, v.point) <=
                        _liveBusRadiusMeters))
            .toList();
      });
    });
  }

  void _onFetchingChanged() {
    if (!mounted) return;
    _liveSnack.update(
      context,
      fetching: LiveVehiclesFeed.instance.fetching.value,
      hasVehicles: _liveVehicles.isNotEmpty,
      bottomInset: 150,
    );
  }

  void _startVibrationLoop() {
    // The alarm takes over from whatever threshold burst is still running.
    AlertService.stopInsistentVibration();
    _vibrationLoop?.cancel();
    _vibrationLoop = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(pattern: const [0, 500, 300, 500]);
      }
    });
  }

  // The alarm itself is intentionally not dismissible from here: only
  // stopping the sound/vibration (still counts as "woke up") or ending
  // the trip closes it.
  Future<void> _stopAlarm() async {
    await AlarmPlayer.stop();
    await NotificationService.cancelAlarmNotification();
    _vibrationLoop?.cancel();
    _vibrationLoop = null;
    setState(() => _alarmActive = false);
  }

  /// Called once the rider is on the next service, so tracking restarts
  /// against that leg's own stops.
  Future<void> _startNextLeg() async {
    await _stopAlarm();
    if (!mounted) return;
    setState(() {
      _legIndex++;
      _alightIndex = _leg.stops.length - 1;
      _legPath = RoutePath(_leg.path);
      _passedIndex = 0;
      _firstFired = false;
      _secondFired = false;
      _alarmFired = false;
      _arrived = false;
      _transferPending = false;
      _liveVehicles = const [];
    });
    final pos = _currentPosition;
    if (pos != null) _updateTransitProgress(pos);
    _startLiveVehicles();
  }

  Future<void> _endTrip() async {
    await _positionSub?.cancel();
    AlertService.stopInsistentVibration();
    await AlarmPlayer.stop();
    await NotificationService.cancelAlarmNotification();
    _vibrationLoop?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmEndTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar viaje'),
        content: const Text('Se detendra el seguimiento de ubicacion.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirmed == true) _endTrip();
  }

  void _recenterMap() {
    if (_currentPosition == null) return;
    _mapController.move(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      16,
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _vibrationLoop?.cancel();
    AlertService.stopInsistentVibration();
    _liveSub?.cancel();
    LiveVehiclesFeed.instance.fetching.removeListener(_onFetchingChanged);
    _liveSnack.dispose();
    _pulseController.dispose();
    AlarmPlayer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_alarmActive,
      child: Scaffold(
        extendBodyBehindAppBar: _alarmActive,
        appBar: _alarmActive
            ? null
            : AppBar(
                title: Text(
                  _targetLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined),
                    onPressed: _confirmEndTrip,
                  ),
                ],
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_accessError != null || _genericError != null)
                ? _buildError()
                : _alarmActive
                    ? _buildAlarmOverlay()
                    : _buildTracking(),
      ),
    );
  }

  String get _errorMessage {
    if (_genericError != null) return _genericError!;
    switch (_accessError!) {
      case LocationAccessResult.serviceDisabled:
        return 'El GPS esta desactivado. Activalo para poder rastrear el viaje.';
      case LocationAccessResult.deniedForever:
        return 'Denegaste el permiso de ubicacion de forma permanente. '
            'Actívalo en los ajustes de la app (idealmente "siempre") para '
            'avisarte incluso con la pantalla apagada.';
      case LocationAccessResult.denied:
        return 'Necesitamos permiso de ubicacion (idealmente "siempre") para '
            'avisarte incluso con la pantalla apagada.';
      case LocationAccessResult.whileInUse:
      case LocationAccessResult.always:
        return '';
    }
  }

  void _retryStart() {
    setState(() {
      _loading = true;
      _accessError = null;
      _genericError = null;
    });
    _start();
  }

  Widget _buildError() {
    final needsAppSettings =
        _accessError == LocationAccessResult.deniedForever;
    final needsSystemSettings =
        _accessError == LocationAccessResult.serviceDisabled;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (needsAppSettings)
              ElevatedButton(
                onPressed: () async {
                  await LocationService.openSettings();
                  _retryStart();
                },
                child: const Text('Abrir ajustes de la app'),
              )
            else if (needsSystemSettings)
              ElevatedButton(
                onPressed: () async {
                  await LocationService.openLocationSettings();
                  _retryStart();
                },
                child: const Text('Abrir ajustes de ubicacion'),
              ),
            if (needsAppSettings || needsSystemSettings)
              const SizedBox(height: 8),
            TextButton(
              onPressed: _retryStart,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmOverlay() {
    final nextLeg = _transferPending ? widget.legs[_legIndex + 1] : null;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: nextLeg != null
              ? [Colors.indigo.shade500, Colors.indigo.shade900]
              : _arrived
                  ? [Colors.teal.shade600, Colors.teal.shade900]
                  : [Colors.deepOrange.shade400, Colors.red.shade900],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              _buildPulsingIcon(nextLeg != null),
              const SizedBox(height: 28),
              Text(
                nextLeg != null
                    ? 'Transbordo'
                    : _arrived
                        ? '¡Llegaste!'
                        : '¡Despierta!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  nextLeg != null
                      ? 'Bajate en $_targetLabel y toma la '
                          '${nextLeg.routeShortName} hacia '
                          '${nextLeg.destinationStop.name}'
                      : _targetLabel,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: nextLeg != null
                        ? Colors.indigo.shade700
                        : Colors.red.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 6,
                  ),
                  onPressed: _stopAlarm,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off_rounded),
                      SizedBox(width: 10),
                      Text(
                        'Detener alarma',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (nextLeg != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _startNextLeg,
                    icon: const Icon(Icons.directions_bus_rounded, size: 18),
                    label: Text('Ya me subi a la ${nextLeg.routeShortName}'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextButton(
                onPressed: _endTrip,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                ),
                child: const Text('Finalizar viaje'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPulsingIcon(bool transfer) {
    return SizedBox(
      width: 180,
      height: 180,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final delay in [0.0, 0.33, 0.66])
                Builder(builder: (context) {
                  final t = (_pulseController.value + delay) % 1.0;
                  return Opacity(
                    opacity: (1 - t) * 0.5,
                    child: Transform.scale(
                      scale: 0.5 + t * 0.9,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                }),
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.95),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  transfer
                      ? Icons.transfer_within_a_station_rounded
                      : _arrived
                          ? Icons.flag_rounded
                          : Icons.notifications_active_rounded,
                  color: transfer
                      ? Colors.indigo.shade700
                      : _arrived
                          ? Colors.teal.shade700
                          : Colors.red.shade700,
                  size: 52,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAlwaysBanner() {
    return Material(
      color: Colors.amber.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.location_disabled, size: 18, color: Colors.black87),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Para recibir avisos con la pantalla apagada, activa '
                '"Siempre" en Ajustes de ubicacion.',
                style: TextStyle(fontSize: 12.5, color: Colors.black87),
              ),
            ),
            TextButton(
              onPressed: () => LocationService.openSettings(),
              child: const Text('Abrir ajustes', style: TextStyle(fontSize: 12.5)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _bannerDismissed = true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTracking() {
    final route = _route!;
    final pos = _currentPosition!;
    final origin = LatLng(pos.latitude, pos.longitude);
    final remainingMinutes = (route.durationSeconds / 60).ceil();
    final remainingKm = (route.distanceMeters / 1000);

    return Column(
      children: [
        if (!_hasAlwaysPermission && !_bannerDismissed) _buildAlwaysBanner(),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: origin,
                  initialZoom: 14,
                ),
                children: [
                  MapTileLayer(),
                  PolylineLayer(polylines: _buildPolylines(route)),
                  MarkerLayer(markers: _buildMarkers(origin)),
                  const MapAttribution(),
                ],
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: FloatingActionButton.small(
                  heroTag: 'trip_locate_me',
                  onPressed: _recenterMap,
                  child: const Icon(Icons.my_location),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              if (_isTransit) _buildLegHeader(),
              if (_transferPending) _buildTransferPrompt(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _infoTile(formatDuration(remainingMinutes), 'restantes'),
                  _infoTile('${remainingKm.toStringAsFixed(1)} km', 'distancia'),
                  if (_isTransit)
                    _infoTile('${_stopsLeft()}', 'paraderos'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  if (_settings.firstEnabled)
                    _thresholdChip('${_settings.firstMinutes} min', _firstFired),
                  if (_settings.secondEnabled)
                    _thresholdChip(
                        '${_settings.secondMinutes} min', _secondFired),
                  _thresholdChip(
                    '${_settings.alarmMinutes} min (alarma)',
                    _alarmActive || _arrived,
                    accent: true,
                  ),
                  if (_liveVehicles.isNotEmpty)
                    _thresholdChip(
                      '${_liveVehicles.length} buses en vivo',
                      true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _stopsLeft() {
    var left = 0;
    for (var i = 0; i <= _alightIndex; i++) {
      if (_leg.stopPathIndices[i] > _passedIndex) left++;
    }
    return left;
  }

  /// Stays on screen after the transfer alarm is silenced, so the hand-off
  /// to the next service is never lost with it.
  Widget _buildTransferPrompt() {
    final next = widget.legs[_legIndex + 1];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _startNextLeg,
          icon: const Icon(Icons.directions_bus_rounded, size: 18),
          label: Text('Ya me subi a la ${next.routeShortName}'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.indigo.shade600,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegHeader() {
    final color = kindColor(_leg.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _leg.routeShortName,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.legs.length > 1
                  ? 'Tramo ${_legIndex + 1} de ${widget.legs.length} · bajas en '
                      '${_alightStop.name}'
                  : 'Bajas en ${_alightStop.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Toca un paradero del mapa para bajarte antes',
            child: Icon(Icons.touch_app_outlined,
                size: 16, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  List<Polyline> _buildPolylines(RouteInfo route) {
    if (!_isTransit) {
      return [
        Polyline(points: route.points, strokeWidth: 4, color: Colors.blue),
      ];
    }
    final leg = _leg;
    final color = kindColor(leg.kind);
    final alightPathIndex = leg.stopPathIndices[_alightIndex];
    final passed = math.min(_passedIndex, alightPathIndex);
    return [
      // The bus's whole line, so the rider can see where it came from and
      // where it goes on to after their stop.
      RouteLines.context(leg.routePath, color),
      // What is already behind them, greyed, so the stops they passed still
      // read as part of the trip.
      if (passed > 0) RouteLines.travelled(leg.path.sublist(0, passed + 1)),
      if (alightPathIndex > passed)
        RouteLines.leg(leg.path.sublist(passed, alightPathIndex + 1)),
    ];
  }

  List<Marker> _buildMarkers(LatLng origin) {
    final markers = <Marker>[
      Marker(
        point: origin,
        width: 36,
        height: 36,
        child: const Icon(Icons.my_location, color: Colors.blue, size: 28),
      ),
    ];

    if (!_isTransit) {
      markers.add(
        Marker(
          point: widget.destination,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: arrivalColor, size: 40),
        ),
      );
      return markers;
    }

    final leg = _leg;
    final color = kindColor(leg.kind);
    for (var i = 0; i < leg.stops.length; i++) {
      final passed = leg.stopPathIndices[i] <= _passedIndex;
      final isAlight = i == _alightIndex;
      // Past the chosen stop there is no drawn line any more, so those stops
      // fade - but stay tappable, which is how the rider moves their stop
      // further along again.
      final beyond = i > _alightIndex;
      markers.add(
        Marker(
          point: leg.stops[i].point,
          width: isAlight ? 32 : 15,
          height: isAlight ? 32 : 15,
          child: GestureDetector(
            onTap: () => _onStopTapped(i),
            child: Opacity(
              opacity: beyond ? 0.3 : 1,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isAlight
                      ? arrivalColor
                      : passed
                          ? Colors.grey.shade400
                          : Colors.white,
                  border: Border.all(
                    color: isAlight
                        ? Colors.white
                        : passed
                            ? Colors.grey.shade500
                            : color,
                    width: isAlight ? 3 : 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: passed ? 0.12 : 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: isAlight
                    ? const Icon(Icons.flag_rounded,
                        size: 17, color: Colors.white)
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    markers.addAll(liveBusMarkers(
      _liveVehicles,
      color,
      onTap: (vehicle) => showLiveBusDetails(
        context,
        vehicle,
        routeShortName: leg.routeShortName,
      ),
    ));
    return markers;
  }

  Widget _thresholdChip(String label, bool done, {bool accent = false}) {
    return Chip(
      avatar: Icon(
        done ? Icons.check_circle : Icons.schedule,
        size: 18,
        color: done ? Colors.green : (accent ? Colors.red : null),
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _infoTile(String value, String label) {
    return Column(
      children: [
        Text(value,
            style:
                const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
