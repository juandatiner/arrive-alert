import 'package:audioplayers/audioplayers.dart';

class AlarmPlayer {
  static final AudioPlayer _player = AudioPlayer();
  static bool _playing = false;
  static bool _contextConfigured = false;

  static Future<void> _ensureAudioContext() async {
    if (_contextConfigured) return;
    _contextConfigured = true;
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gain,
        stayAwake: true,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
    ));
  }

  static Future<void> start() async {
    if (_playing) return;
    _playing = true;
    await _ensureAudioContext();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource('sounds/alarm.wav'));
  }

  static Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    await _player.stop();
  }

  static bool get isPlaying => _playing;
}
