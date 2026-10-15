import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/state/social_call_voice_controller.dart';

class _Audio implements SocialCallAudioSession {
  @override
  bool connected = false;
  @override
  bool reconnecting = false;
  @override
  bool canPlaybackAudio = false;
  @override
  bool peerPresent = true;
  @override
  bool remoteAudioReady = true;
  Completer<void>? joinGate;
  Completer<void>? micGate;
  final micCalls = <bool>[];
  int inFlight = 0;
  int maximumInFlight = 0;
  int closes = 0;
  bool rejectAutoplay = false;
  bool rejectMicrophone = false;
  bool rejectSpeaker = false;
  VoidCallback? changed;
  @override
  void onChanged(VoidCallback callback) => changed = callback;
  @override
  Future<void> connect(String url, String token) async {
    await joinGate?.future;
    connected = true;
    changed?.call();
  }

  @override
  Future<void> microphone(bool enabled) async {
    if (rejectMicrophone) throw StateError('permission denied');
    inFlight++;
    if (inFlight > maximumInFlight) maximumInFlight = inFlight;
    micCalls.add(enabled);
    await micGate?.future;
    inFlight--;
  }

  @override
  Future<void> speaker(bool enabled) async {
    if (rejectSpeaker) throw StateError('unsupported route');
  }

  @override
  Future<void> startAudio() async {
    if (rejectAutoplay) throw StateError('gesture required');
    canPlaybackAudio = true;
  }

  @override
  Future<void> close() async {
    closes++;
    connected = false;
  }
}

Future<Map<String, dynamic>> _access() async => {
  'url': 'wss://test',
  'token': 'test',
};

void main() {
  test(
    'room connection alone is not a conversation with working audio',
    () async {
      final audio = _Audio()
        ..peerPresent = false
        ..remoteAudioReady = false;
      final voice = SocialCallVoiceController(factory: () => audio);
      await voice.connect(_access);
      expect(voice.connected, isTrue);
      expect(voice.mediaReady, isFalse);
      audio.peerPresent = true;
      expect(voice.mediaReady, isFalse);
      audio.remoteAudioReady = true;
      expect(voice.mediaReady, isTrue);
      voice.dispose();
    },
  );
  test(
    'microphone denial leaves listening connected and supports a retry',
    () async {
      final audio = _Audio()..rejectMicrophone = true;
      final voice = SocialCallVoiceController(factory: () => audio);
      await voice.connect(_access);
      expect(voice.connected, isTrue);
      expect(voice.needsMicrophoneRetry, isTrue);
      expect(voice.mediaReady, isFalse);
      audio.rejectMicrophone = false;
      await voice.setMuted(false);
      expect(voice.needsMicrophoneRetry, isFalse);
      expect(voice.mediaReady, isTrue);
      expect(audio.closes, 0);
      voice.dispose();
    },
  );
  test('unsupported speaker route does not break call capture', () async {
    final audio = _Audio()..rejectSpeaker = true;
    final voice = SocialCallVoiceController(factory: () => audio);
    await voice.connect(_access);
    expect(audio.micCalls, [true]);
    expect(voice.mediaReady, isTrue);
    voice.dispose();
  });
  test('missing access credentials do not create an audio session', () async {
    var created = 0;
    final voice = SocialCallVoiceController(
      factory: () {
        created++;
        return _Audio();
      },
    );
    await expectLater(voice.connect(() async => {}), throwsStateError);
    expect(created, 0);
    voice.dispose();
  });
  test(
    'mute intent during reconnect is restored and autoplay can be retried',
    () async {
      final audio = _Audio()..rejectAutoplay = true;
      final voice = SocialCallVoiceController(factory: () => audio);
      await voice.connect(_access);
      expect(voice.connected, isTrue);
      expect(voice.needsAudioStart, isTrue);
      audio.rejectAutoplay = false;
      await voice.startAudio();
      expect(voice.needsAudioStart, isFalse);
      audio.connected = false;
      audio.reconnecting = true;
      audio.changed?.call();
      await voice.setMuted(true);
      expect(audio.micCalls, [true]);
      audio.reconnecting = false;
      audio.connected = true;
      audio.changed?.call();
      await Future<void>.delayed(Duration.zero);
      expect(audio.micCalls, [true, false]);
      voice.dispose();
    },
  );
  test(
    'connection single flight and microphone publishes after connection',
    () async {
      final audio = _Audio()..joinGate = Completer<void>();
      final voice = SocialCallVoiceController(factory: () => audio);
      var tokens = 0;
      Future<Map<String, dynamic>> access() async {
        tokens++;
        return _access();
      }

      final first = voice.connect(access);
      final second = voice.connect(access);
      await Future<void>.delayed(Duration.zero);
      expect(tokens, 1);
      expect(audio.micCalls, isEmpty);
      audio.joinGate!.complete();
      await Future.wait([first, second]);
      expect(audio.micCalls, [true]);
      expect(voice.connected, isTrue);
      await voice.disconnect();
      voice.dispose();
    },
  );
  test('rapid mute commands serialize and latest intent wins', () async {
    final audio = _Audio();
    final voice = SocialCallVoiceController(factory: () => audio);
    await voice.connect(_access);
    audio.micCalls.clear();
    audio.micGate = Completer<void>();
    final mute = voice.setMuted(true);
    final unmute = voice.setMuted(false);
    audio.micGate!.complete();
    await Future.wait([mute, unmute]);
    expect(audio.micCalls, [false, true]);
    expect(audio.maximumInFlight, 1);
    expect(voice.muted, isFalse);
    voice.dispose();
  });
  test('dispose during token fetch never opens microphone or room', () async {
    final credentials = Completer<Map<String, dynamic>>();
    var created = 0;
    final voice = SocialCallVoiceController(
      factory: () {
        created++;
        return _Audio();
      },
    );
    final join = voice.connect(() => credentials.future);
    await Future<void>.delayed(Duration.zero);
    voice.dispose();
    credentials.complete(await _access());
    await join;
    expect(created, 0);
  });
  test(
    'dispose during native connect closes late connection without publishing',
    () async {
      final audio = _Audio()..joinGate = Completer<void>();
      final voice = SocialCallVoiceController(factory: () => audio);
      final join = voice.connect(_access);
      await Future<void>.delayed(Duration.zero);
      voice.dispose();
      audio.joinGate!.complete();
      await join;
      expect(audio.connected, isFalse);
      expect(audio.micCalls, isEmpty);
    },
  );
}
