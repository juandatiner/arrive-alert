import 'package:audioplayers/audioplayers.dart';

class AlarmPlayer {
  static final AudioPlayer _player = AudioPlayer();
  static bool _playing = false;

  static Future<void> start() async {
    if (_playing) return;
    _playing = true;
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
