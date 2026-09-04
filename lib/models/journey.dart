import 'package:latlong2/latlong.dart';
import 'transit_route.dart';

/// One step of a planned journey. Walking and riding carry different data,
/// so they're separate types rather than one class full of nullable fields.
sealed class JourneyLeg {
  final double meters;
  final double seconds;

  const JourneyLeg({required this.meters, required this.seconds});
}

class WalkLeg extends JourneyLeg {
  final LatLng from;
  final LatLng to;

  /// Where the walk ends - a stop name, or the trip's destination.
  final String toLabel;

  const WalkLeg({
    required this.from,
    required this.to,
    required this.toLabel,
    required super.meters,
    required super.seconds,
  });
}

class RideLeg extends JourneyLeg {
  final String routeId;
  final String routeShortName;
  final String routeLongName;
  final TransitKind kind;

  /// Positions in the route's own stop list, so they can be handed straight
  /// to [RouteMapScreen] and to the bundled per-route file.
  final int boardSeq;
  final int alightSeq;

  final String boardStopName;
  final String alightStopName;
  final LatLng boardPoint;
  final LatLng alightPoint;

  /// Padding for the wait at the stop. There are no timetables in the
  /// bundled pack, so this is a per-service average, not a departure time.
  final double waitSeconds;

  /// Other service codes that run the same stretch between the same two
  /// stops. Riders take whichever shows up first, so they belong on the
  /// same row rather than as four near-identical options.
  final List<String> alsoServedBy;

  const RideLeg({
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.kind,
    required this.boardSeq,
    required this.alightSeq,
    required this.boardStopName,
    required this.alightStopName,
    required this.boardPoint,
    required this.alightPoint,
    required this.waitSeconds,
    required super.meters,
    required super.seconds,
    this.alsoServedBy = const [],
  });

  int get stopCount => (alightSeq - boardSeq).abs();

  RideLeg withAlternatives(List<String> codes) => RideLeg(
        routeId: routeId,
        routeShortName: routeShortName,
        routeLongName: routeLongName,
        kind: kind,
        boardSeq: boardSeq,
        alightSeq: alightSeq,
        boardStopName: boardStopName,
        alightStopName: alightStopName,
        boardPoint: boardPoint,
        alightPoint: alightPoint,
        waitSeconds: waitSeconds,
        meters: meters,
        seconds: seconds,
        alsoServedBy: codes,
      );
}

/// A full door-to-door option: walk, ride, maybe transfer, walk.
class Journey {
  final List<JourneyLeg> legs;

  const Journey(this.legs);

  List<RideLeg> get rides => legs.whereType<RideLeg>().toList();

  int get transfers => rides.isEmpty ? 0 : rides.length - 1;

  double get totalSeconds =>
      legs.fold(0.0, (sum, leg) => sum + leg.seconds) +
      rides.fold(0.0, (sum, leg) => sum + leg.waitSeconds);

  double get walkMeters =>
      legs.whereType<WalkLeg>().fold(0.0, (sum, leg) => sum + leg.meters);

  /// Same service codes in the same order. The feed carries each direction
  /// and each variant of a service as its own route id, so ids would let
  /// three rows of "the B13" through; riders read them as one option.
  String get signature => rides.map((r) => r.routeShortName).join('>');

  /// Same stops in the same order, whatever the service codes. Four routes
  /// down one avenue produce four of these, and they are one option to a
  /// rider - see [RideLeg.alsoServedBy].
  String get stopSignature =>
      rides.map((r) => '${r.boardStopName}>${r.alightStopName}').join('|');
}
