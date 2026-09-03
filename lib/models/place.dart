class Place {
  final String name;
  final double lat;
  final double lon;
  final String? nickname;

  /// Key into [placeIconChoices] - null means the default (star) look.
  final String? icon;

  const Place({
    required this.name,
    required this.lat,
    required this.lon,
    this.nickname,
    this.icon,
  });

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
      nickname: json['nickname'] as String?,
      icon: json['icon'] as String?,
    );
  }

  /// Nickname if the user set one, otherwise the address.
  String get displayLabel =>
      (nickname != null && nickname!.trim().isNotEmpty) ? nickname! : name;

  Place copyWith({
    String? name,
    double? lat,
    double? lon,
    String? nickname,
    String? icon,
  }) {
    return Place(
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      nickname: nickname ?? this.nickname,
      icon: icon ?? this.icon,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lon': lon,
        if (nickname != null && nickname!.trim().isNotEmpty)
          'nickname': nickname,
        if (icon != null) 'icon': icon,
      };

  /// Same physical spot, tolerant to tiny float differences.
  bool sameSpotAs(Place other) {
    return (lat - other.lat).abs() < 0.0001 &&
        (lon - other.lon).abs() < 0.0001;
  }
}
