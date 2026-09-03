import 'dart:async';
import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';

/// Outcome of a permission check/request cycle, granular enough for the UI
/// to pick the right recovery action instead of a single dead-end error.
enum LocationAccessResult {
  /// GPS/location services are off at the OS level - not an app permission.
  serviceDisabled,

  /// Denied, but the system is still allowed to show the prompt again.
  denied,

  /// Denied permanently (or restricted) - only the app settings screen can
  /// fix this, requesting again will not show a system dialog.
  deniedForever,

  /// Granted for foreground use only.
  whileInUse,

  /// Granted for foreground + background use.
  always,
}

class LocationService {
  /// Runs the full permission cycle: checks service availability, requests
  /// permission if not yet decided, and asks a second time for background
  /// upgrade when needed. Never leaves the caller without an actionable
  /// result - every case maps to a message + button the UI can show.
  static Future<LocationAccessResult> ensurePermissions({
    required bool background,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccessResult.serviceDisabled;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // First denial (or first-ever ask): the system is still willing to
      // show its native prompt, so ask right away.
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationAccessResult.deniedForever;
    }
    if (permission == LocationPermission.denied) {
      // Denied a second time: some platforms still allow another prompt
      // later (e.g. Android "deny" vs "deny forever" as separate taps), but
      // for now there's nothing more we can request programmatically.
      return LocationAccessResult.denied;
    }

    if (background && permission == LocationPermission.whileInUse) {
      // Best-effort only: some Android versions/OEMs upgrade in-place, but
      // iOS won't show a second system prompt once whileInUse is granted -
      // the caller should nudge the user to Settings if this stays whileInUse.
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always
        ? LocationAccessResult.always
        : LocationAccessResult.whileInUse;
  }

  static Future<void> openSettings() => Geolocator.openAppSettings();

  /// Opens the OS location/GPS settings screen (not the app's settings) -
  /// use this for [LocationAccessResult.serviceDisabled].
  static Future<void> openLocationSettings() =>
      Geolocator.openLocationSettings();

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
