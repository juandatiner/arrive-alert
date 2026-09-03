import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/place.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../services/places_history_service.dart';
import '../widgets/map_style.dart';
import 'confirm_trip_screen.dart';
import 'settings_screen.dart';

/// Icon choices for a favorite place, keyed by what gets persisted in
/// `Place.icon`. Order here is the order shown in the picker.
const _favoritePlaceIcons = <String, IconData>{
  'home': Icons.home_rounded,
  'work': Icons.work_rounded,
  'school': Icons.school_rounded,
  'gym': Icons.fitness_center_rounded,
  'restaurant': Icons.restaurant_rounded,
  'shopping': Icons.shopping_cart_rounded,
  'health': Icons.local_hospital_rounded,
  'transit': Icons.directions_bus_rounded,
  'heart': Icons.favorite_rounded,
  'star': Icons.star_rounded,
};

IconData _iconForPlace(Place place) =>
    _favoritePlaceIcons[place.icon] ?? Icons.star_rounded;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  LatLng? _currentLatLng;
  LatLng? _destinationLatLng;
  String? _destinationLabel;

  List<Place> _results = [];
  List<Place> _recents = [];
  List<Place> _favorites = [];
  bool _searching = false;
  bool _loadingLocation = true;
  bool _showFavoritesPanel = false;
  LocationAccessResult? _locationAccessError;
  String? _genericLocationError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadPlaces();
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus && _showFavoritesPanel) {
        setState(() => _showFavoritesPanel = false);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _initLocation() async {
    final result = await LocationService.ensurePermissions(background: false);
    if (result == LocationAccessResult.serviceDisabled ||
        result == LocationAccessResult.denied ||
        result == LocationAccessResult.deniedForever) {
      setState(() {
        _loadingLocation = false;
        _locationAccessError = result;
      });
      return;
    }
    try {
      final pos = await LocationService.getCurrentPosition();
      setState(() {
        _currentLatLng = LatLng(pos.latitude, pos.longitude);
        _loadingLocation = false;
        _locationAccessError = null;
      });
    } catch (e) {
      setState(() {
        _loadingLocation = false;
        _locationAccessError = null;
        _genericLocationError = 'No se pudo obtener tu ubicacion.';
      });
    }
  }

  Future<void> _loadPlaces() async {
    final recents = await PlacesHistoryService.loadRecents();
    final favorites = await PlacesHistoryService.loadFavorites();
    if (!mounted) return;
    setState(() {
      _recents = recents;
      _favorites = favorites;
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.trim().length < 3) {
        setState(() => _results = []);
        return;
      }
      setState(() => _searching = true);
      try {
        final results = await GeocodingService.search(query);
        if (!mounted) return;
        setState(() {
          _results = results;
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _searching = false);
      }
    });
  }

  void _selectPlace(Place place) {
    setState(() {
      _destinationLatLng = LatLng(place.lat, place.lon);
      _destinationLabel = place.displayLabel;
      _results = [];
      _showFavoritesPanel = false;
      _searchController.text = place.displayLabel;
    });
    _searchFocus.unfocus();
    _mapController.move(_destinationLatLng!, 15);
  }

  void _clearDestination() {
    setState(() {
      _destinationLatLng = null;
      _destinationLabel = null;
      _searchController.clear();
      _results = [];
    });
  }

  void _toggleFavoritesPanel() {
    _searchFocus.unfocus();
    setState(() => _showFavoritesPanel = !_showFavoritesPanel);
  }

  void _selectOnMap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _destinationLatLng = point;
      _destinationLabel = null; // null == loading the address
      _results = [];
      _searchController.clear();
    });
    _searchFocus.unfocus();
    _reverseGeocode(point);
  }

  Future<void> _reverseGeocode(LatLng point) async {
    try {
      final result =
          await GeocodingService.reverse(point.latitude, point.longitude);
      if (!mounted || _destinationLatLng != point) return;
      if (result.isWater) {
        setState(() {
          _destinationLatLng = null;
          _destinationLabel = null;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Ese punto esta sobre el agua. Elige un lugar en tierra.'),
          ));
        return;
      }
      setState(() => _destinationLabel = result.label);
    } catch (_) {
      if (!mounted || _destinationLatLng != point) return;
      setState(() => _destinationLabel =
          '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}');
    }
  }

  Future<void> _recenterOnMe() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() => _currentLatLng = latLng);
      _mapController.move(latLng, 16);
    } catch (_) {
      if (_currentLatLng != null) _mapController.move(_currentLatLng!, 16);
    }
  }

  void _goToConfirm() {
    if (_destinationLatLng == null || _destinationLabel == null) return;
    showConfirmTripSheet(
      context,
      destination: _destinationLatLng!,
      destinationLabel: _destinationLabel!,
    ).then((_) => _loadPlaces());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          enabled: !_loadingLocation &&
              _locationAccessError == null &&
              _genericLocationError == null,
          decoration: InputDecoration(
            hintText: 'Buscar destino (o toca el mapa)',
            filled: true,
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
          onChanged: _onSearchChanged,
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showFavoritesPanel ? Icons.star_rounded : Icons.star_border_rounded,
              color: _showFavoritesPanel ? Colors.amber.shade600 : null,
            ),
            tooltip: 'Favoritos',
            onPressed: _toggleFavoritesPanel,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _loadingLocation
          ? const Center(child: CircularProgressIndicator())
          : (_locationAccessError != null || _genericLocationError != null)
              ? _buildError()
              : _buildMapAndSearch(),
    );
  }

  String get _locationErrorMessage {
    if (_genericLocationError != null) return _genericLocationError!;
    switch (_locationAccessError!) {
      case LocationAccessResult.serviceDisabled:
        return 'El GPS esta desactivado. Activalo para poder usar la app.';
      case LocationAccessResult.deniedForever:
        return 'Denegaste el permiso de ubicacion de forma permanente. '
            'Actívalo en los ajustes de la app para poder usarla.';
      case LocationAccessResult.denied:
        return 'Necesitamos permiso de ubicacion para funcionar.';
      case LocationAccessResult.whileInUse:
      case LocationAccessResult.always:
        return '';
    }
  }

  void _retryLocation() {
    setState(() {
      _loadingLocation = true;
      _genericLocationError = null;
    });
    _initLocation();
  }

  Widget _buildError() {
    final needsAppSettings =
        _locationAccessError == LocationAccessResult.deniedForever;
    final needsSystemSettings =
        _locationAccessError == LocationAccessResult.serviceDisabled;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, size: 48),
            const SizedBox(height: 12),
            Text(_locationErrorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (needsAppSettings)
              ElevatedButton(
                onPressed: () async {
                  await LocationService.openSettings();
                  _retryLocation();
                },
                child: const Text('Abrir ajustes de la app'),
              )
            else if (needsSystemSettings)
              ElevatedButton(
                onPressed: () async {
                  await LocationService.openLocationSettings();
                  _retryLocation();
                },
                child: const Text('Abrir ajustes de ubicacion'),
              ),
            if (needsAppSettings || needsSystemSettings)
              const SizedBox(height: 8),
            TextButton(
              onPressed: _retryLocation,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  bool get _showRecents =>
      _searchFocus.hasFocus &&
      _results.isEmpty &&
      _searchController.text.trim().length < 3 &&
      _recents.isNotEmpty;

  Widget _buildMapAndSearch() {
    return Column(
      children: [
        if (_showFavoritesPanel) _buildFavoritesPanel(),
        if (_results.isNotEmpty) _buildCompactList(_results, icon: Icons.location_on_outlined),
        if (_showRecents) _buildRecentsList(),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLatLng!,
                  initialZoom: 14,
                  onTap: _selectOnMap,
                ),
                children: [
                  MapTileLayer(),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentLatLng!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 30,
                        ),
                      ),
                      if (_destinationLatLng != null)
                        Marker(
                          point: _destinationLatLng!,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                    ],
                  ),
                  const MapAttribution(),
                ],
              ),
              Positioned(
                right: 12,
                bottom: _destinationLatLng != null ? 92 : 12,
                child: FloatingActionButton.small(
                  heroTag: 'home_locate_me',
                  onPressed: _recenterOnMe,
                  child: const Icon(Icons.my_location),
                ),
              ),
              if (_destinationLatLng != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _buildDestinationCard(context),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactList(
    List<Place> places, {
    required IconData icon,
    Color? iconColor,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: places.length * 40.0 + 8),
      child: Material(
        elevation: 2,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: places.length,
          itemBuilder: (context, index) {
            final place = places[index];
            return _compactRow(
              icon: icon,
              iconColor: iconColor,
              label: place.name,
              onTap: () => _selectPlace(place),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecentsList() {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: _recents.length * 40.0 + 32),
      child: Material(
        elevation: 2,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          children: [
            _sectionLabel('Recientes'),
            ..._recents.map(
              (p) => _compactRow(
                icon: Icons.history,
                iconColor: Colors.grey,
                label: p.displayLabel,
                onTap: () => _selectPlace(p),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesPanel() {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: _favorites.isEmpty ? 76 : _favorites.length * 40.0 + 32,
      ),
      child: Material(
        elevation: 2,
        child: _favorites.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Sin favoritos todavia. Marca uno con la estrella al '
                  'confirmar un viaje.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: [
                  _sectionLabel('Favoritos'),
                  ..._favorites.map(
                    (p) => _compactRow(
                      icon: _iconForPlace(p),
                      iconColor: Colors.amber.shade600,
                      label: p.displayLabel,
                      onTap: () => _selectPlace(p),
                      onEdit: () => _editFavorite(p),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDestinationCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.location_on_rounded,
                    color: scheme.primary, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _destinationLabel == null
                    ? Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Buscando direccion...',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        _destinationLabel!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 17),
                  padding: EdgeInsets.zero,
                  tooltip: 'Quitar destino',
                  onPressed: _clearDestination,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStartButton(),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return SizedBox(
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
            onTap: _goToConfirm,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Iniciar viaje',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactRow({
    required IconData icon,
    Color? iconColor,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onEdit,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: onEdit != null ? 4 : 16),
          child: Row(
            children: [
              Icon(icon, size: 17, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (onEdit != null)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    padding: EdgeInsets.zero,
                    tooltip: 'Editar apodo',
                    onPressed: onEdit,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editFavorite(Place place) async {
    final controller = TextEditingController(text: place.nickname ?? '');
    String? selectedIcon = place.icon;
    bool deleted = false;
    bool saved = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar favorito'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration:
                    const InputDecoration(hintText: 'Apodo: Casa, Trabajo'),
              ),
              const SizedBox(height: 14),
              const Text('Icono',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _favoritePlaceIcons.entries.map((entry) {
                  final isSelected = selectedIcon == entry.key;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setDialogState(
                        () => selectedIcon = isSelected ? null : entry.key),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Colors.amber.withValues(alpha: 0.25)
                            : Colors.grey.withValues(alpha: 0.08),
                        border: isSelected
                            ? Border.all(color: Colors.amber.shade600, width: 1.5)
                            : null,
                      ),
                      child: Icon(entry.value, size: 19),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                deleted = true;
                Navigator.of(context).pop();
              },
              child: const Text('Eliminar'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                saved = true;
                Navigator.of(context).pop();
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (deleted) {
      await PlacesHistoryService.removeFavorite(place);
    } else if (saved) {
      final nickname = controller.text.trim();
      if (nickname != (place.nickname ?? '')) {
        await PlacesHistoryService.setNickname(place, nickname);
      }
      if (selectedIcon != place.icon) {
        await PlacesHistoryService.setIcon(place, selectedIcon);
      }
    }
    _loadPlaces();
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
