import 'dart:async';
import 'package:vibration/vibration.dart';
import 'notification_service.dart';

class AlertService {
  /// One burst: three long buzzes and a very long one, ~4.5 s. A single
  /// notification tick is nothing to someone dozing off.
  static const _burst = [0, 900, 400, 900, 400, 1400];
  static const _burstGap = Duration(seconds: 6);

  /// Four bursts spread over ~20 s. Long enough to be noticed through a
  /// pocket, short enough not to run into the next alert.
  static const _burstCount = 4;

  static Timer? _burstTimer;

  /// Mid-trip threshold alert: a notification plus an insistent, repeated
  /// vibration.
  ///
  /// The vibration is driven from two sides on purpose. The Android
  /// notification channel carries its own long pattern, so it fires even if
  /// the process is dozing; the loop below adds the repeats. On iOS the loop
  /// only runs while the app is in the foreground - Core Haptics does not
  /// play in the background - so there the notification's own sound is what
  /// makes the phone buzz on a locked screen.
  static Future<void> fireThresholdAlert({
    required int minutesLeft,
    required bool vibrationEnabled,
    required bool soundEnabled,
    required String destinationLabel,
  }) async {
    final title = 'Faltan ~$minutesLeft min';
    final body = 'Te acercas a $destinationLabel. Prepara tu bajada.';

    await NotificationService.showAlertNotification(
      title: title,
      body: body,
      // On iOS a soundless notification is also a vibrationless one, so a
      // rider who wants to be buzzed has to let this one make a sound.
      withSound: soundEnabled || vibrationEnabled,
    );

    if (vibrationEnabled) await startInsistentVibration();
  }

  static Future<void> startInsistentVibration() async {
    if (!await Vibration.hasVibrator()) return;
    final custom = await Vibration.hasCustomVibrationsSupport();

    stopInsistentVibration();
    var fired = 0;

    Future<void> buzz() async {
      if (custom) {
        await Vibration.vibrate(pattern: _burst);
      } else {
        // No pattern support: three plain buzzes stand in for one.
        for (var i = 0; i < 3; i++) {
          await Vibration.vibrate(duration: 900);
          await Future<void>.delayed(const Duration(milliseconds: 1300));
        }
      }
    }

    await buzz();
    fired++;
    _burstTimer = Timer.periodic(_burstGap, (timer) {
      if (fired >= _burstCount) {
        timer.cancel();
        _burstTimer = null;
        return;
      }
      fired++;
      buzz();
    });
  }

  static void stopInsistentVibration() {
    _burstTimer?.cancel();
    _burstTimer = null;
    Vibration.cancel();
  }

  /// Final alarm: loud, persistent, full-screen notification. Sound/vibration
  /// looping itself is driven separately (AlarmPlayer + vibration timer).
  static Future<void> fireAlarmNotification({
    required String destinationLabel,
    required bool arrived,
    required bool soundEnabled,
  }) async {
    final title = arrived ? 'Llegaste a destino' : 'Alarma: ya casi llegas';
    final body = arrived
        ? 'Llegaste a $destinationLabel.'
        : 'Te acercas a $destinationLabel. Prepara tu bajada.';

    await NotificationService.showAlarmNotification(
      title: title,
      body: body,
      soundEnabled: soundEnabled,
    );
  }
}
