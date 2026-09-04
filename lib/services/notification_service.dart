import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _alarmChannelId = 'arrival_alerts';
  static const _alarmChannelName = 'Alarma de llegada';
  static const _alarmChannelDescription =
      'Alarma final al llegar a tu destino';

  // v2: the first channel was created silent *and* non-vibrating, and Android
  // freezes a channel's sound/vibration at creation time - an existing install
  // would never start buzzing. A new id is the only way to change it.
  static const _alertChannelId = 'trip_alerts_v2';
  static const _alertChannelName = 'Avisos de llegada';
  static const _alertChannelDescription =
      'Avisos con vibracion larga de cuanto falta para llegar a tu destino';
  static const _legacyAlertChannelId = 'trip_alerts_silent';

  /// Long enough to wake someone: three long buzzes and a very long one,
  /// rather than the single tick a default notification gives.
  static final _alertVibrationPattern =
      Int64List.fromList([0, 900, 400, 900, 400, 1400]);

  /// Bundled in the iOS app (not in Flutter assets - UNNotificationSound can
  /// only see the main bundle). 28 s, which is just under iOS's 30 s cap, so
  /// the alarm keeps sounding on the lock screen instead of blipping once.
  static const _iosAlarmSound = 'alarm_long.caf';
  static const _iosAlertSound = 'alert_pulse.caf';

  // Fixed id so the alarm notification can be updated/cancelled deterministically.
  static const _alarmNotificationId = 7001;

  /// iOS has no equivalent of Android's full-screen intent, so the alarm is
  /// re-posted while it is running: each repeat sounds and vibrates again.
  /// Distinct ids because replacing a delivered notification in place does
  /// not always re-alert.
  static const _alarmRepeatIds = [7002, 7003, 7004, 7005, 7006, 7007];
  static Timer? _alarmRepeat;
  static int _alarmRepeatCursor = 0;

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// True once iOS has granted the Critical Alerts permission, which needs an
  /// entitlement Apple grants case by case. Everything degrades to
  /// `timeSensitive` while it is false.
  static bool _criticalGranted = false;

  static bool get criticalAlertsGranted => _criticalGranted;

  static InterruptionLevel get _urgentLevel =>
      _criticalGranted ? InterruptionLevel.critical : InterruptionLevel.timeSensitive;

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
    // Deliberately silent but strongly vibrating: the early alerts are meant
    // to be felt by someone dozing off, not to wake the whole bus.
    final alertChannel = AndroidNotificationChannel(
      _alertChannelId,
      _alertChannelName,
      description: _alertChannelDescription,
      importance: Importance.high,
      playSound: false,
      enableVibration: true,
      vibrationPattern: _alertVibrationPattern,
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(alarmChannel);
    await androidPlugin?.createNotificationChannel(alertChannel);
    await androidPlugin?.deleteNotificationChannel(
      channelId: _legacyAlertChannelId,
    );
  }

  static Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
    // Asked separately: without the entitlement iOS just declines this one,
    // and asking for it alongside the rest can cost the whole prompt.
    _criticalGranted = await ios?.requestPermissions(critical: true) ?? false;
  }

  /// Mid-trip threshold alert. Silent on Android and carried by the channel's
  /// long vibration; on iOS it needs a sound, because a soundless iOS
  /// notification does not vibrate at all - so [withSound] is really "may
  /// this alert make the phone buzz", and the caller passes it as
  /// sound-or-vibration rather than sound alone.
  static Future<void> showAlertNotification({
    required String title,
    required String body,
    bool withSound = true,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      channelDescription: _alertChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
      enableVibration: true,
      vibrationPattern: _alertVibrationPattern,
      category: AndroidNotificationCategory.reminder,
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: withSound,
      sound: withSound ? _iosAlertSound : null,
      interruptionLevel: _urgentLevel,
    );
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails:
          NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// Full-screen, persistent notification backing the final arrival alarm.
  static Future<void> showAlarmNotification({
    required String title,
    required String body,
    bool soundEnabled = true,
  }) async {
    await _postAlarm(
      id: _alarmNotificationId,
      title: title,
      body: body,
      soundEnabled: soundEnabled,
      ongoing: true,
    );
    if (_isIOS) _startAlarmRepeat(title, body, soundEnabled);
  }

  static Future<void> _postAlarm({
    required int id,
    required String title,
    required String body,
    required bool soundEnabled,
    required bool ongoing,
  }) {
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
      ongoing: ongoing,
      autoCancel: false,
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
      sound: soundEnabled ? _iosAlarmSound : null,
      // Ignored unless the Critical Alerts entitlement is in place; harmless
      // otherwise.
      criticalSoundVolume: _criticalGranted ? 1.0 : null,
      interruptionLevel: _urgentLevel,
    );
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails:
          NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  static void _startAlarmRepeat(String title, String body, bool soundEnabled) {
    _alarmRepeat?.cancel();
    _alarmRepeatCursor = 0;
    // Just longer than the 28 s sound, so the repeats butt up against each
    // other instead of overlapping.
    _alarmRepeat = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_alarmRepeatCursor >= _alarmRepeatIds.length) {
        timer.cancel();
        return;
      }
      _postAlarm(
        id: _alarmRepeatIds[_alarmRepeatCursor++],
        title: title,
        body: body,
        soundEnabled: soundEnabled,
        ongoing: false,
      );
    });
  }

  static Future<void> cancelAlarmNotification() async {
    _alarmRepeat?.cancel();
    _alarmRepeat = null;
    _alarmRepeatCursor = 0;
    await _plugin.cancel(id: _alarmNotificationId);
    for (final id in _alarmRepeatIds) {
      await _plugin.cancel(id: id);
    }
  }
}
