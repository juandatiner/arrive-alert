import 'package:vibration/vibration.dart';
import 'notification_service.dart';

class AlertService {
  /// Vibrates in a strong repeating pattern meant to be noticeable even
  /// half-asleep, and fires a high-priority notification with sound.
  static Future<void> fireThresholdAlert({
    required int minutesLeft,
    required bool soundEnabled,
    required bool vibrationEnabled,
    required String destinationLabel,
  }) async {
    final title = minutesLeft <= 0
        ? 'Llegaste a destino'
        : 'Faltan ~$minutesLeft min';
    final body = 'Te acercas a $destinationLabel. Prepara tu bajada.';

    await NotificationService.showArrivalAlert(
      title: title,
      body: body,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
    );

    if (vibrationEnabled && await Vibration.hasVibrator()) {
      final pattern = [0, 600, 300, 600, 300, 600, 300, 900];
      await Vibration.vibrate(pattern: pattern);
    }
  }
}
