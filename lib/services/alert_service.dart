import 'package:vibration/vibration.dart';
import 'notification_service.dart';

class AlertService {
  /// Mid-trip threshold alert: vibration + a silent notification only.
  static Future<void> fireThresholdAlert({
    required int minutesLeft,
    required bool vibrationEnabled,
    required String destinationLabel,
  }) async {
    final title = 'Faltan ~$minutesLeft min';
    final body = 'Te acercas a $destinationLabel. Prepara tu bajada.';

    await NotificationService.showAlertNotification(title: title, body: body);

    if (vibrationEnabled && await Vibration.hasVibrator()) {
      final pattern = [0, 600, 300, 600, 300, 600, 300, 900];
      await Vibration.vibrate(pattern: pattern);
    }
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
