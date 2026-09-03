import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/alert_settings.dart';
import '../models/place.dart';
import '../models/route_info.dart';
import '../services/location_service.dart';
import '../services/places_history_service.dart';
import '../services/routing_service.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';
import 'settings_screen.dart';
import 'trip_screen.dart';

/// Shows the trip confirmation as a blurred card floating over the current
/// screen (usually the map), instead of pushing a new route.
Future<void> showConfirmTripSheet(
  BuildContext context, {
  required LatLng destination,
  required String destinationLabel,
}) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'Confirmar viaje',
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, secondaryAnim) => _ConfirmTripSheet(
      destination: destination,
      destinationLabel: destinationLabel,
    ),
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ConfirmTripSheet extends StatefulWidget {
  final LatLng destination;
  final String destinationLabel;

  const _ConfirmTripSheet({
    required this.destination,
    required this.destinationLabel,
  });

  @override
  State<_ConfirmTripSheet> createState() => _ConfirmTripSheetState();
}

class _ConfirmTripSheetState extends State<_ConfirmTripSheet> {
  AlertSettings _settings = const AlertSettings();
  RouteInfo? _route;
  bool _loading = true;
  bool _isFavorite = false;
  String? _error;

  Place get _place => Place(
        name: widget.destinationLabel,
        lat: widget.destination.latitude,
        lon: widget.destination.longitude,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _settings = await SettingsService.load();
    _isFavorite = await PlacesHistoryService.isFavorite(_place);
    try {
      final pos = await LocationService.getCurrentPosition();
      final route = await RoutingService.getRoute(
        origin: LatLng(pos.latitude, pos.longitude),
        destination: widget.destination,
      );
      if (!mounted) return;
      setState(() {
        _route = route;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo calcular la ruta. Revisa tu conexion.';
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final nowFavorite = await PlacesHistoryService.toggleFavorite(_place);
    if (!mounted) return;
    setState(() => _isFavorite = nowFavorite);
    if (nowFavorite) await _promptNickname();
  }

  Future<void> _promptNickname() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apodo para este lugar (opcional)'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ej: Casa, Trabajo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Omitir'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    await PlacesHistoryService.setNickname(_place, result);
  }

  Future<void> _confirm() async {
    await PlacesHistoryService.addRecent(_place);
    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripScreen(
          destination: widget.destination,
          destinationLabel: widget.destinationLabel,
        ),
      ),
    );
  }

  void _dismiss() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _dismiss,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withValues(alpha: 0.28)),
            ),
          ),
        ),
        Center(
          child: GestureDetector(
            onTap: () {}, // absorb taps so they don't dismiss via the backdrop
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 380),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                        )
                      : _error != null
                          ? _buildError()
                          : _buildContent(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 40),
        const SizedBox(height: 10),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _dismiss,
                child: const Text('Cerrar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Text('Reintentar'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final route = _route!;
    final minutes = (route.durationSeconds / 60).ceil();
    final km = route.distanceMeters / 1000;
    final arrival = DateTime.now().add(
      Duration(seconds: route.durationSeconds.round()),
    );
    final arrivalLabel =
        '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Confirmar viaje',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            IconButton(
              icon: Icon(
                _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: _isFavorite ? Colors.amber.shade600 : null,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: _toggleFavorite,
              tooltip: 'Agregar a favoritos',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              visualDensity: VisualDensity.compact,
              onPressed: _dismiss,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(Icons.access_time_filled_rounded,
                color: scheme.primary, size: 26),
            const SizedBox(width: 8),
            Text(
              arrivalLabel,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '~${formatDuration(minutes)} · ${km.toStringAsFixed(1)} km',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.location_on, size: 15, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.destinationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_settings.firstEnabled)
              _alertChip('${_settings.firstMinutes} min', Icons.notifications_none),
            if (_settings.secondEnabled)
              _alertChip('${_settings.secondMinutes} min', Icons.notifications_none),
            _alertChip(
              'Alarma ${_settings.alarmMinutes} min',
              Icons.notifications_active,
              accent: true,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              _settings.soundEnabled
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              size: 16,
              color: Colors.grey,
            ),
            const SizedBox(width: 6),
            Icon(
              _settings.vibrationEnabled
                  ? Icons.vibration
                  : Icons.mobile_off_outlined,
              size: 16,
              color: Colors.grey,
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ).then((_) => _load());
              },
              child: const Text('Editar alertas', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4F86FF), Color(0xFF2451B5)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2451B5).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _confirm,
                child: const Center(
                  child: Text(
                    'Confirmar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _alertChip(String label, IconData icon, {bool accent = false}) {
    final color = accent ? Colors.red.shade600 : Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: accent ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
