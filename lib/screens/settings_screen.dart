import 'package:flutter/material.dart';
import '../models/alert_settings.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AlertSettings _settings = const AlertSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await SettingsService.load();
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _update(AlertSettings settings) async {
    setState(() => _settings = settings);
    await SettingsService.save(settings);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('Configuracion de avisos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _sectionHeader('CUANDO AVISAR'),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text(
                    'Cada aviso debe ser mayor al siguiente. La alarma final '
                    'siempre esta activa.',
                    style: TextStyle(color: Colors.grey, fontSize: 12.5),
                  ),
                ),
                _groupCard([
                  _thresholdRow(
                    label: 'Primer aviso',
                    minutes: _settings.firstMinutes,
                    enabled: _settings.firstEnabled,
                    canToggle: true,
                    onToggle: (v) => _update(_settings.copyWith(firstEnabled: v)),
                    onChange: (v) => _update(_settings.copyWith(firstMinutes: v)),
                  ),
                  _divider(),
                  _thresholdRow(
                    label: 'Segundo aviso',
                    minutes: _settings.secondMinutes,
                    enabled: _settings.secondEnabled,
                    canToggle: true,
                    onToggle: (v) =>
                        _update(_settings.copyWith(secondEnabled: v)),
                    onChange: (v) =>
                        _update(_settings.copyWith(secondMinutes: v)),
                  ),
                ]),
                const SizedBox(height: 14),
                _groupCard([
                  _thresholdRow(
                    label: 'Alarma final',
                    sublabel: 'Siempre activa',
                    minutes: _settings.alarmMinutes,
                    enabled: true,
                    canToggle: false,
                    onToggle: null,
                    onChange: (v) => _update(_settings.copyWith(alarmMinutes: v)),
                    accent: true,
                  ),
                ]),
                const SizedBox(height: 28),
                _sectionHeader('COMO AVISAR'),
                _groupCard([
                  _switchRow(
                    icon: Icons.volume_up_rounded,
                    label: 'Sonido',
                    sublabel: 'Reproducir sonido en cada aviso',
                    value: _settings.soundEnabled,
                    onChanged: (v) =>
                        _update(_settings.copyWith(soundEnabled: v)),
                  ),
                  _divider(),
                  _switchRow(
                    icon: Icons.vibration_rounded,
                    label: 'Vibracion',
                    sublabel: 'Vibrar en cada aviso',
                    value: _settings.vibrationEnabled,
                    onChanged: (v) =>
                        _update(_settings.copyWith(vibrationEnabled: v)),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _groupCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Colors.grey.withValues(alpha: 0.15),
    );
  }

  Widget _thresholdRow({
    required String label,
    String? sublabel,
    required int minutes,
    required bool enabled,
    required bool canToggle,
    required ValueChanged<bool>? onToggle,
    required ValueChanged<int> onChange,
    bool accent = false,
  }) {
    final color = accent ? Colors.red.shade600 : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: enabled ? 0.12 : 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              accent ? Icons.notifications_active_rounded : Icons.schedule_rounded,
              size: 17,
              color: enabled ? color : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: enabled ? null : Colors.grey,
                  ),
                ),
                if (sublabel != null)
                  Text(
                    sublabel,
                    style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
                  ),
              ],
            ),
          ),
          _stepper(
            value: minutes,
            enabled: enabled,
            onChange: onChange,
          ),
          if (canToggle) ...[
            const SizedBox(width: 4),
            Transform.scale(
              scale: 0.8,
              child: Switch(value: enabled, onChanged: onToggle),
            ),
          ] else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _stepper({
    required int value,
    required bool enabled,
    required ValueChanged<int> onChange,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepperButton(
            Icons.remove_rounded,
            enabled ? () => onChange(value - 1) : null,
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value min',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: enabled ? null : Colors.grey,
              ),
            ),
          ),
          _stepperButton(
            Icons.add_rounded,
            enabled ? () => onChange(value + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback? onPressed) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String label,
    required String sublabel,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
                Text(sublabel,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
