import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final attentionAlertServiceProvider = Provider<AttentionAlertService>((ref) {
  final service = AttentionAlertService();
  ref.onDispose(service.dispose);
  return service;
});

class AttentionAlertService {
  final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  DateTime? _lastPlayedAt;
  bool _disposed = false;

  Future<void> play() async {
    if (_disposed) return;
    final now = DateTime.now();
    if (_lastPlayedAt != null &&
        now.difference(_lastPlayedAt!) < const Duration(milliseconds: 1200)) {
      return;
    }
    _lastPlayedAt = now;

    try {
      await _player.stop();
      await _player.play(
        AssetSource('audio/attention_alert.wav'),
        volume: 1,
        mode: PlayerMode.mediaPlayer,
      );
    } catch (_) {
      // Best effort only; the notification itself still appears.
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    try {
      await _player.stop();
    } catch (_) {
      // Best effort only.
    }
  }

  void dispose() {
    _disposed = true;
    _player.dispose();
  }
}
