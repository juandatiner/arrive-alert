class AlertSettings {
  final int firstMinutes;
  final bool firstEnabled;
  final int secondMinutes;
  final bool secondEnabled;
  final int alarmMinutes;
  final bool soundEnabled;
  final bool vibrationEnabled;

  /// The live-bus feed has no per-route endpoint: every poll pulls the whole
  /// fleet, about 830 KB. Worth having, worth being able to turn off.
  final bool liveVehiclesEnabled;

  const AlertSettings({
    this.firstMinutes = 10,
    this.firstEnabled = true,
    this.secondMinutes = 5,
    this.secondEnabled = true,
    this.alarmMinutes = 2,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.liveVehiclesEnabled = true,
  });

  /// Enforces alarmMinutes >= 1, and when the second alert is enabled,
  /// firstMinutes > secondMinutes > alarmMinutes. A *disabled* second alert
  /// keeps its own stored value clamped above the alarm, but must never
  /// constrain firstMinutes - a disabled threshold shouldn't limit anything.
  /// The alarm threshold can never be disabled or skipped.
  static AlertSettings normalized({
    required int firstMinutes,
    required bool firstEnabled,
    required int secondMinutes,
    required bool secondEnabled,
    required int alarmMinutes,
    required bool soundEnabled,
    required bool vibrationEnabled,
    required bool liveVehiclesEnabled,
  }) {
    final alarm = alarmMinutes.clamp(1, 90);
    final int first;
    final int second;
    if (secondEnabled) {
      second = secondMinutes.clamp(alarm + 1, 90);
      first = firstMinutes.clamp(second + 1, 120);
    } else {
      first = firstMinutes.clamp(alarm + 1, 120);
      second = secondMinutes.clamp(alarm + 1, 90);
    }
    return AlertSettings(
      firstMinutes: first,
      firstEnabled: firstEnabled,
      secondMinutes: second,
      secondEnabled: secondEnabled,
      alarmMinutes: alarm,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
      liveVehiclesEnabled: liveVehiclesEnabled,
    );
  }

  AlertSettings copyWith({
    int? firstMinutes,
    bool? firstEnabled,
    int? secondMinutes,
    bool? secondEnabled,
    int? alarmMinutes,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? liveVehiclesEnabled,
  }) {
    return AlertSettings.normalized(
      firstMinutes: firstMinutes ?? this.firstMinutes,
      firstEnabled: firstEnabled ?? this.firstEnabled,
      secondMinutes: secondMinutes ?? this.secondMinutes,
      secondEnabled: secondEnabled ?? this.secondEnabled,
      alarmMinutes: alarmMinutes ?? this.alarmMinutes,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      liveVehiclesEnabled: liveVehiclesEnabled ?? this.liveVehiclesEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'firstMinutes': firstMinutes,
        'firstEnabled': firstEnabled,
        'secondMinutes': secondMinutes,
        'secondEnabled': secondEnabled,
        'alarmMinutes': alarmMinutes,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
        'liveVehiclesEnabled': liveVehiclesEnabled,
      };

  factory AlertSettings.fromJson(Map<String, dynamic> json) {
    return AlertSettings.normalized(
      firstMinutes: json['firstMinutes'] as int? ?? 10,
      firstEnabled: json['firstEnabled'] as bool? ?? true,
      secondMinutes: json['secondMinutes'] as int? ?? 5,
      secondEnabled: json['secondEnabled'] as bool? ?? true,
      alarmMinutes: json['alarmMinutes'] as int? ?? 2,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
      liveVehiclesEnabled: json['liveVehiclesEnabled'] as bool? ?? true,
    );
  }
}
