import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Plain OpenStreetMap raster tiles: the only free, no-API-key basemap that
/// actually works reliably from a mobile app. CARTO's prettier Voyager/
/// Positron styles now require a paid API key, and Wikimedia's tile server
/// returns 403 for non-browser clients - both were tried and dropped.
/// A closer-to-Google-Maps look (e.g. Stadia Maps, MapTiler) is possible
/// later, but needs the user to sign up for a free-tier API key.
class MapTileLayer extends TileLayer {
  MapTileLayer({super.key})
      : super(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.cosmodavid.arrive_alert',
          maxNativeZoom: 19,
        );
}

class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return RichAttributionWidget(
      alignment: AttributionAlignment.bottomLeft,
      attributions: const [
        TextSourceAttribution('OpenStreetMap contributors'),
      ],
    );
  }
}
