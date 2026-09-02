class Place {
  final String name;
  final double lat;
  final double lon;

  const Place({required this.name, required this.lat, required this.lon});

  factory Place.fromNominatim(Map<String, dynamic> json) {
    return Place(
      name: json['display_name'] as String,
      lat: double.parse(json['lat'] as String),
      lon: double.parse(json['lon'] as String),
    );
  }

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lon': lon};

  /// Same physical spot, tolerant to tiny float differences.
  bool sameSpotAs(Place other) {
    return (lat - other.lat).abs() < 0.0001 &&
        (lon - other.lon).abs() < 0.0001;
  }
}
