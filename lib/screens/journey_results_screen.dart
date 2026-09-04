import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/journey.dart';
import '../services/journey_planner.dart';
import '../utils/format.dart';
import '../widgets/route_badge.dart';
import 'journey_preview_screen.dart';

/// The options for getting to a destination by bus, ranked by how long they
/// take door to door.
class JourneyResultsScreen extends StatefulWidget {
  final LatLng origin;
  final LatLng destination;
  final String destinationLabel;

  const JourneyResultsScreen({
    super.key,
    required this.origin,
    required this.destination,
    required this.destinationLabel,
  });

  @override
  State<JourneyResultsScreen> createState() => _JourneyResultsScreenState();
}

class _JourneyResultsScreenState extends State<JourneyResultsScreen> {
  List<Journey>? _journeys;
  String? _error;

  @override
  void initState() {
    super.initState();
    _plan();
  }

  Future<void> _plan() async {
    setState(() {
      _journeys = null;
      _error = null;
    });
    try {
      final journeys = await JourneyPlanner.plan(
        origin: widget.origin,
        destination: widget.destination,
      );
      if (!mounted) return;
      setState(() => _journeys = journeys);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudieron calcular las rutas.');
    }
  }

  void _open(Journey journey) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JourneyPreviewScreen(
          journey: journey,
          origin: widget.origin,
          destination: widget.destination,
          destinationLabel: widget.destinationLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journeys = _journeys;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Como llegar'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.location_on, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.destinationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _error != null
          ? _buildError()
          : journeys == null
              ? const Center(child: CircularProgressIndicator())
              : journeys.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: journeys.length,
                      itemBuilder: (context, i) =>
                          _buildJourneyCard(journeys[i]),
                    ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 44),
          const SizedBox(height: 10),
          Text(_error!),
          const SizedBox(height: 12),
          TextButton(onPressed: _plan, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'No encontramos rutas de TransMilenio o SITP cerca del origen o '
          'del destino. Puedes iniciar el viaje libre y la app te avisa '
          'igual antes de llegar.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildJourneyCard(Journey journey) {
    final scheme = Theme.of(context).colorScheme;
    final minutes = (journey.totalSeconds / 60).ceil();
    final arrival = DateTime.now().add(Duration(minutes: minutes));
    final arrivalLabel =
        '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}';
    final walkOnly = journey.rides.isEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _open(journey),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatDuration(minutes),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      'llegas ~$arrivalLabel',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 8),
              _buildLegStrip(journey),
              const SizedBox(height: 8),
              Text(
                walkOnly
                    ? 'A pie, sin transporte'
                    : '${journey.transfers == 0 ? 'Directo' : '${journey.transfers} transbordo'}'
                        ' · ${journey.walkMeters.round()} m caminando',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegStrip(Journey journey) {
    final children = <Widget>[];
    for (final leg in journey.legs) {
      if (children.isNotEmpty) {
        children.add(const Icon(Icons.chevron_right, size: 16, color: Colors.grey));
      }
      if (leg is WalkLeg) {
        children.add(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_walk_rounded, size: 16),
            Text(' ${leg.meters.round()} m',
                style: const TextStyle(fontSize: 11.5)),
          ],
        ));
      } else if (leg is RideLeg) {
        children.add(RouteBadge(shortName: leg.routeShortName, kind: leg.kind));
        for (final alternative in leg.alsoServedBy.take(2)) {
          children.add(Padding(
            padding: const EdgeInsets.only(left: 3),
            child: RouteBadge(
              shortName: alternative,
              kind: leg.kind,
              compact: true,
            ),
          ));
        }
      }
    }
    return Wrap(
      spacing: 4,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
