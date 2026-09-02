import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vibration/vibration.dart';
import '../models/alert_settings.dart';
import '../models/route_info.dart';
import '../services/alarm_player.dart';
import '../services/alert_service.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';
import '../services/settings_service.dart';

class TripScreen extends StatefulWidget {
  final LatLng destination;
  final String destinationLabel;

  const TripScreen({
    super.key,
    required this.destination,
    required this.destinationLabel,
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
  bool _alarmActive = false;
  bool _arrived = false;
  bool _loading = true;
  String? _error;
  Timer? _vibrationLoop;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _settings = await SettingsService.load();

    final hasPermission =
        await LocationService.ensurePermissions(background: true);
    if (!hasPermission) {
      setState(() {
        _loading = false;
        _error =
            'Necesitamos permiso de ubicacion (idealmente "siempre") para '
            'avisarte incluso con la pantalla apagada.';
      });
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
        _error = 'No se pudo calcular la ruta. Revisa tu conexion.';
      });
      return;
    }

    _positionSub = LocationService.watchPosition().listen(_handlePosition);
  }

  Future<void> _handlePosition(Position pos) async {
    if (!mounted) return;
    setState(() => _currentPosition = pos);

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
        soundEnabled: _settings.soundEnabled,
        vibrationEnabled: _settings.vibrationEnabled,
        destinationLabel: widget.destinationLabel,
      );
    }

    if (_settings.secondEnabled &&
        !_secondFired &&
        remainingMinutes <= _settings.secondMinutes) {
      _secondFired = true;
      AlertService.fireThresholdAlert(
        minutesLeft: _settings.secondMinutes,
        soundEnabled: _settings.soundEnabled,
        vibrationEnabled: _settings.vibrationEnabled,
        destinationLabel: widget.destinationLabel,
      );
    }

    final arrived = route.distanceMeters < 40 || remainingMinutes <= 0.5;

    if ((remainingMinutes <= _settings.alarmMinutes || arrived) &&
        !_alarmActive) {
      setState(() => _alarmActive = true);
      if (_settings.soundEnabled) AlarmPlayer.start();
      if (_settings.vibrationEnabled) _startVibrationLoop();
    }
    if (arrived && !_arrived) {
      setState(() => _arrived = true);
    }
  }

  void _startVibrationLoop() {
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
    _vibrationLoop?.cancel();
    _vibrationLoop = null;
    setState(() => _alarmActive = false);
  }

  Future<void> _endTrip() async {
    await _positionSub?.cancel();
    await AlarmPlayer.stop();
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
                  widget.destinationLabel,
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
            : _error != null
                ? _buildError()
                : _alarmActive
                    ? _buildAlarmOverlay()
                    : _buildTracking(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _start();
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmOverlay() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _arrived
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
              _buildPulsingIcon(),
              const SizedBox(height: 28),
              Text(
                _arrived ? '¡Llegaste!' : '¡Despierta!',
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
                  widget.destinationLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
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
                    foregroundColor: Colors.red.shade800,
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

  Widget _buildPulsingIcon() {
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
                  _arrived
                      ? Icons.flag_rounded
                      : Icons.notifications_active_rounded,
                  color: _arrived ? Colors.teal.shade700 : Colors.red.shade700,
                  size: 52,
                ),
              ),
            ],
          );
        },
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
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.cosmodavid.arrive_alert',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: route.points,
                        strokeWidth: 4,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: origin,
                        width: 36,
                        height: 36,
                        child: const Icon(Icons.my_location,
                            color: Colors.blue, size: 28),
                      ),
                      Marker(
                        point: widget.destination,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on,
                            color: Colors.red, size: 40),
                      ),
                    ],
                  ),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _infoTile('$remainingMinutes min', 'restantes'),
                  _infoTile('${remainingKm.toStringAsFixed(1)} km', 'distancia'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
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
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thresholdChip(String label, bool done, {bool accent = false}) {
    return Chip(
      avatar: Icon(
        done ? Icons.check_circle : Icons.schedule,
        size: 18,
        color: done ? Colors.green : (accent ? Colors.red : null),
      ),
      label: Text(label),
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
