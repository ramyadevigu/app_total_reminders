import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plays the short interface click. Playback is best effort: failures are
/// ignored so sounds never block the interaction that triggered them.
class UiSoundService {
  UiSoundService._();

  static final UiSoundService instance = UiSoundService._();

  static const enabledKey = 'ui_sounds_enabled_v1';
  static const _assetPath = 'sounds/ding.mp3';
  static const _minInterval = Duration(milliseconds: 80);

  AudioPlayer? _player;
  DateTime? _lastPlayedAt;
  bool? _enabled;
  Future<void>? _preloading;

  Future<bool> isEnabled() async {
    final cached = _enabled;
    if (cached != null) return cached;
    final preferences = await SharedPreferences.getInstance();
    return _enabled = preferences.getBool(enabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) await _player?.stop();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(enabledKey, value);
  }

  Future<void> preload() => _preloading ??= _preloadAll();

  Future<void> _preloadAll() async {
    try {
      final player = _playerFor();
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setSource(AssetSource(_assetPath));
    } on Object {
      // Preloading is an optimization; play() loads the asset on demand.
    }
  }

  Future<void> play() async {
    if (!await isEnabled()) return;
    final now = DateTime.now();
    final lastPlayedAt = _lastPlayedAt;
    if (lastPlayedAt != null && now.difference(lastPlayedAt) < _minInterval) {
      return;
    }
    _lastPlayedAt = now;
    try {
      final player = _playerFor();
      await player.stop();
      await player.play(AssetSource(_assetPath), mode: PlayerMode.lowLatency);
    } on Object {
      // Sound is non-critical; the interaction itself has already succeeded.
    }
  }

  AudioPlayer _playerFor() => _player ??= AudioPlayer()..positionUpdater = null;
}
