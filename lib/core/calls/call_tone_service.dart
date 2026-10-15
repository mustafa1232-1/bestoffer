import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final callToneServiceProvider = Provider<CallToneService>((ref) {
  final service = CallToneService();
  ref.onDispose(service.dispose);
  return service;
});

enum CallToneKind { incoming, outgoing }

/// Owns the short-lived sounds heard before a social call is connected.
///
/// Android incoming calls use the device's configured phone ringtone through
/// a native bridge. Other platforms fall back to Maslaki's neutral ringback
/// cadence because they do not expose the selected phone ringtone to apps.
class CallToneService {
  static const MethodChannel _native = MethodChannel('maslaki/call_tones');

  final AudioPlayer _fallbackPlayer = AudioPlayer();
  CallToneKind? _current;
  int _revision = 0;
  bool _disposed = false;

  CallToneKind? get current => _current;

  Future<void> startIncoming() => _start(CallToneKind.incoming);

  Future<void> startOutgoing() => _start(CallToneKind.outgoing);

  Future<void> _start(CallToneKind kind) async {
    if (_disposed || _current == kind) return;
    final revision = ++_revision;
    await _stopOutputs();
    if (_disposed || revision != _revision) return;
    _current = kind;

    if (kind == CallToneKind.incoming &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      try {
        final started =
            await _native.invokeMethod<bool>('startIncomingRingtone') ?? false;
        if (_disposed || revision != _revision) {
          await _native.invokeMethod<void>('stopCallTones');
          return;
        }
        if (started) return;
      } catch (_) {
        // Fall back to the bundled cadence when the device has no ringtone.
      }
    }

    try {
      await _fallbackPlayer.setReleaseMode(ReleaseMode.loop);
      await _fallbackPlayer.play(
        AssetSource('audio/call_ringback.wav'),
        volume: kind == CallToneKind.incoming ? 0.72 : 0.42,
        mode: PlayerMode.mediaPlayer,
      );
      if (_disposed || revision != _revision) {
        await _fallbackPlayer.stop();
      }
    } catch (_) {
      // Call signaling and the visible controls remain usable without audio.
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    ++_revision;
    _current = null;
    await _stopOutputs();
  }

  Future<void> _stopOutputs() async {
    try {
      await _fallbackPlayer.stop();
    } catch (_) {}
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _native.invokeMethod<void>('stopCallTones');
      } catch (_) {}
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_revision;
    _current = null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_native.invokeMethod<void>('stopCallTones').catchError((_) {}));
    }
    unawaited(_fallbackPlayer.stop().catchError((_) {}));
    _fallbackPlayer.dispose();
  }
}
