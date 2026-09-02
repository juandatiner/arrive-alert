import 'dart:async';
import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<bool> ensurePermissions({required bool background}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    if (background && permission != LocationPermission.always) {
      // On Android/iOS this prompts for "Allow all the time" when supported.
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<Position> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } on TimeoutException {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;
      rethrow;
    }
  }

  /// Position stream that keeps working with the screen off / app backgrounded.
  /// Android: runs as a foreground service with a persistent notification.
  /// iOS: requires "Always" location permission + Background Modes > Location.
  static Stream<Position> watchPosition() {
    late final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Vigilando tu llegada',
          notificationText: 'Rastreando ubicacion para avisarte a tiempo',
          enableWakeLock: true,
        ),
      );
    } else if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
