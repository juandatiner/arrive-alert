import 'dart:async';
import 'package:flutter/material.dart';
import '../models/saved_trip.dart';
import '../models/transit_route.dart';
import '../services/saved_trips_service.dart';
import '../services/transit_service.dart';

/// What the picker handed back: either a route to explore from scratch, or a
/// saved leg to reopen with its stops already chosen.
class RoutePickerResult {
  final TransitRouteSummary summary;
  final SavedTrip? savedTrip;

  const RoutePickerResult({required this.summary, this.savedTrip});
}

/// Route search: pick the service type, type the route code, get the route.
Future<RoutePickerResult?> showRoutePickerSheet(BuildContext context) {
  return showModalBottomSheet<RoutePickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _RoutePickerSheet(),
  );
}

class _RoutePickerSheet extends StatefulWidget {
  const _RoutePickerSheet();

  @override
  State<_RoutePickerSheet> createState() => _RoutePickerSheetState();
}

class _RoutePickerSheetState extends State<_RoutePickerSheet> {
  final _controller = TextEditingController();
  TransitKind _kind = TransitKind.troncal;
  List<TransitRouteSummary> _results = [];
  List<SavedTrip> _saved = [];
  bool _loading = true;
  Timer? _debounce;

  /// Saved legs are only useful as a shortcut on the untouched sheet; once
  /// the rider starts typing they're looking for something else.
  bool get _showSaved => _saved.isNotEmpty && _controller.text.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _runSearch();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await SavedTripsService.load();
    if (!mounted) return;
    setState(() => _saved = saved);
  }

  Future<void> _openSaved(SavedTrip trip) async {
    final index = await TransitService.loadIndex();
    final summary = index.where((r) => r.id == trip.routeId).firstOrNull;
    if (!mounted) return;
    if (summary == null) {
      // The bundled data was rebuilt and this route id no longer exists.
      await SavedTripsService.remove(trip);
      if (!mounted) return;
      _loadSaved();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Esa ruta ya no existe en los datos actuales.'),
      ));
      return;
    }
    Navigator.of(context).pop(
      RoutePickerResult(summary: summary, savedTrip: trip),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final results = await TransitService.search(
      query: _controller.text,
      kind: _kind,
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _runSearch);
  }

  void _onKindChanged(TransitKind kind) {
    setState(() {
      _kind = kind;
      _loading = true;
    });
    _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.directions_bus_rounded,
                        color: scheme.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Buscar ruta',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              _buildKindSelector(scheme),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: _hintForKind(),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: _onQueryChanged,
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty && !_showSaved
                        ? _buildEmpty()
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.only(bottom: 24),
                            children: [
                              if (_showSaved) ...[
                                _sectionLabel('RUTAS FAVORITAS'),
                                ..._saved.map(_buildSavedCard),
                                const SizedBox(height: 8),
                                _sectionLabel('TODAS LAS RUTAS'),
                              ],
                              ..._results.map((r) => _buildRouteRow(r, scheme)),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _hintForKind() {
    switch (_kind) {
      case TransitKind.troncal:
        return 'Ej: B13, K86, M80';
      case TransitKind.alimentador:
        return 'Ej: 10-1, 6-4';
      case TransitKind.zonal:
        return 'Ej: H710, K305';
      case TransitKind.cable:
        return 'TransMiCable';
    }
  }

  Widget _buildKindSelector(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<TransitKind>(
        segments: const [
          ButtonSegment(
            value: TransitKind.troncal,
            label: Text('TransMi', style: TextStyle(fontSize: 12)),
            icon: Icon(Icons.directions_transit_rounded, size: 16),
          ),
          ButtonSegment(
            value: TransitKind.alimentador,
            label: Text('Alimentador', style: TextStyle(fontSize: 12)),
            icon: Icon(Icons.airport_shuttle_rounded, size: 16),
          ),
          ButtonSegment(
            value: TransitKind.zonal,
            label: Text('Bus', style: TextStyle(fontSize: 12)),
            icon: Icon(Icons.directions_bus_rounded, size: 16),
          ),
        ],
        selected: {_kind},
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 6),
          ),
        ),
        onSelectionChanged: (s) => _onKindChanged(s.first),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              'Ninguna ruta ${_kind.label} coincide con "${_controller.text.trim()}".',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildSavedCard(SavedTrip trip) {
    final color = _kindColor(trip.kind);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openSaved(trip),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    trip.routeShortName,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.originName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Row(
                        children: [
                          Icon(Icons.arrow_downward_rounded,
                              size: 13, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              trip.destinationName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  tooltip: 'Quitar',
                  color: Colors.grey.shade600,
                  onPressed: () async {
                    await SavedTripsService.remove(trip);
                    _loadSaved();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Stop count plus today's hours, so a rider searching at 21:30 can see at
  /// a glance which of two same-code services is still running. The hours are
  /// dropped rather than faked when the bundled pack predates them.
  static String _subtitle(TransitRouteSummary route, ServiceWindow? window) {
    final stops = '${route.stopCount} paraderos';
    return window == null ? stops : '$stops  ·  ${window.label}';
  }

  /// What a service that is not running right now is waiting for. M86 runs
  /// 22:10-23:00, so for most of the day the useful thing to say is not its
  /// hours but that it has not started.
  static String? _statusNote(ServiceStatus status, ServiceWindow? window) {
    switch (status) {
      case ServiceStatus.notYet:
        return 'Desde las ${window!.firstClock}';
      case ServiceStatus.finished:
        return 'Terminó a las ${window!.lastClock}';
      case ServiceStatus.running:
      case ServiceStatus.unknown:
        return null;
    }
  }

  Widget _buildRouteRow(TransitRouteSummary route, ColorScheme scheme) {
    final now = route.schedule.statusAt(DateTime.now());
    final note = _statusNote(now.status, now.window);
    // Still tappable: a rider can plan the last bus home at six in the
    // evening. Dimmed, because the one thing they must not do is walk to the
    // stop expecting it now.
    final dimmed = note != null;

    return InkWell(
      onTap: () =>
          Navigator.of(context).pop(RoutePickerResult(summary: route)),
      child: Opacity(
        opacity: dimmed ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: _kindColor(route.kind).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                // Codes run from "2" to "M86-K86", so shrink rather than clip:
                // the code is the whole point of the row.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    route.shortName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _kindColor(route.kind),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.longName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(route, now.window),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        note,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  static Color _kindColor(TransitKind kind) {
    switch (kind) {
      case TransitKind.troncal:
        return const Color(0xFFD32F2F);
      case TransitKind.alimentador:
        return const Color(0xFF2E7D32);
      case TransitKind.zonal:
        return const Color(0xFF1565C0);
      case TransitKind.cable:
        return const Color(0xFF6A1B9A);
    }
  }
}

Color kindColor(TransitKind kind) => _RoutePickerSheetState._kindColor(kind);
