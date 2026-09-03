import 'transit_route.dart';

/// A route leg the rider keeps around - "B13 from Calle 161 to Calle 22" -
/// so a daily commute is two taps instead of picking stops again each time.
class SavedTrip {
  final String routeId;
  final String routeShortName;
  final TransitKind kind;
  final int originIndex;
  final String originName;
  final int destinationIndex;
  final String destinationName;

  const SavedTrip({
    required this.routeId,
    required this.routeShortName,
    required this.kind,
    required this.originIndex,
    required this.originName,
    required this.destinationIndex,
    required this.destinationName,
  });

  /// Same route and same pair of stops, in the same direction.
  String get key => '$routeId:$originIndex:$destinationIndex';

  Map<String, dynamic> toJson() => {
        'routeId': routeId,
        'short': routeShortName,
        'kind': kind.name,
        'oi': originIndex,
        'on': originName,
        'di': destinationIndex,
        'dn': destinationName,
      };

  factory SavedTrip.fromJson(Map<String, dynamic> json) {
    return SavedTrip(
      routeId: json['routeId'] as String,
      routeShortName: json['short'] as String,
      kind: transitKindFromKey(json['kind'] as String),
      originIndex: json['oi'] as int,
      originName: json['on'] as String,
      destinationIndex: json['di'] as int,
      destinationName: json['dn'] as String,
    );
  }
}
