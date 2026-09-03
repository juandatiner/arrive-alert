import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _alarmChannelId = 'arrival_alerts';
  static const _alarmChannelName = 'Alarma de llegada';
  static const _alarmChannelDescription =
      'Alarma final al llegar a tu destino';

  static const _alertChannelId = 'trip_alerts_silent';
  static const _alertChannelName = 'Avisos de llegada';
  static const _alertChannelDescription =
      'Avisos silenciosos de cuanto falta para llegar a tu destino';

  // Fixed id so the alarm notification can be updated/cancelled deterministically.
  static const _alarmNotificationId = 7001;

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Android channel importance/sound/vibration are locked in at creation
    // time, so alert vs alarm need separate channels rather than per-call params.
    const alarmChannel = AndroidNotificationChannel(
      _alarmChannelId,
      _alarmChannelName,
      description: _alarmChannelDescription,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    const alertChannel = AndroidNotificationChannel(
      _alertChannelId,
      _alertChannelName,
      description: _alertChannelDescription,
      importance: Importance.high,
      playSound: false,
      enableVibration: false,
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(alarmChannel);
    await androidPlugin?.createNotificationChannel(alertChannel);
  }

  static Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Silent notification for the mid-trip threshold alerts. Vibration is
  /// handled separately by the caller via the vibration package.
  static Future<void> showAlertNotification({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      channelDescription: _alertChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
      enableVibration: false,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
      interruptionLevel: InterruptionLevel.active,
    );
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails:
          const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// Full-screen, persistent notification backing the final arrival alarm.
  static Future<void> showAlarmNotification({
    required String title,
    required String body,
    bool soundEnabled = true,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _alarmChannelId,
      _alarmChannelName,
      channelDescription: _alarmChannelDescription,
      importance: Importance.max,
      priority: Priority.max,
      // Android locks sound/vibration to the channel once created; kept here
      // for clarity/consistency even though it's ignored after first install.
      playSound: soundEnabled,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      ongoing: true,
      autoCancel: false,
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    await _plugin.show(
      id: _alarmNotificationId,
      title: title,
      body: body,
      notificationDetails:
          NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  static Future<void> cancelAlarmNotification() =>
      _plugin.cancel(id: _alarmNotificationId);
}
