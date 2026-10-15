import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// The transport boundary also allows lifecycle/mute races to be tested without
/// a microphone or a production LiveKit room.
abstract class SocialCallAudioSession {
  bool get connected;
  bool get reconnecting;
  bool get canPlaybackAudio;
  bool get peerPresent;
  bool get remoteAudioReady;
  void onChanged(VoidCallback callback);
  Future<void> connect(String url, String token);
  Future<void> microphone(bool enabled);
  Future<void> speaker(bool enabled);
  Future<void> startAudio();
  Future<void> close();
}

class LiveKitSocialCallAudio implements SocialCallAudioSession {
  LiveKitSocialCallAudio({Room? room})
    : _room =
          room ??
          Room(
            roomOptions: const RoomOptions(
              adaptiveStream: false,
              dynacast: false,
              defaultAudioCaptureOptions: AudioCaptureOptions(
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
              ),
            ),
          );
  final Room _room;
  EventsListener<RoomEvent>? _events;
  Future<void>? _closing;
  @override
  bool get connected => _room.connectionState == ConnectionState.connected;
  @override
  bool get reconnecting =>
      _room.connectionState == ConnectionState.reconnecting;
  @override
  bool get canPlaybackAudio => _room.canPlaybackAudio;
  @override
  bool get peerPresent => _room.remoteParticipants.isNotEmpty;
  @override
  bool get remoteAudioReady => _room.remoteParticipants.values.any(
    (participant) => participant.audioTrackPublications.any(
      (publication) => publication.track != null,
    ),
  );
  @override
  void onChanged(VoidCallback callback) {
    _events = _room.createListener()
      ..on<RoomConnectedEvent>((_) => callback())
      ..on<RoomDisconnectedEvent>((_) => callback())
      ..on<RoomReconnectingEvent>((_) => callback())
      ..on<RoomReconnectedEvent>((_) => callback())
      ..on<ParticipantConnectedEvent>((_) => callback())
      ..on<ParticipantDisconnectedEvent>((_) => callback())
      ..on<TrackSubscribedEvent>((_) => callback())
      ..on<TrackUnsubscribedEvent>((_) => callback())
      ..on<AudioPlaybackStatusChanged>((_) => callback());
  }

  @override
  Future<void> connect(String url, String token) => _room.connect(
    url,
    token,
    connectOptions: const ConnectOptions(autoSubscribe: true),
  );
  @override
  Future<void> microphone(bool enabled) async {
    final participant = _room.localParticipant;
    if (participant == null) throw StateError('SOCIAL_VOICE_NOT_CONNECTED');
    await participant.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> speaker(bool enabled) =>
      AudioManager.instance.setSpeakerOutputPreferred(enabled);
  @override
  Future<void> startAudio() => _room.startAudio();
  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await _events?.dispose();
    await _room.dispose();
  }
}

class SocialCallVoiceController extends ChangeNotifier {
  SocialCallVoiceController({SocialCallAudioSession Function()? factory})
    : _factory = factory ?? LiveKitSocialCallAudio.new;
  final SocialCallAudioSession Function() _factory;
  SocialCallAudioSession? _session;
  Future<void>? _connecting;
  Future<void>? _microphoneWork;
  bool _disposed = false;
  bool _muted = false;
  bool _speaker = true;
  bool _microphoneReady = false;
  Object? lastError;
  int _generation = 0;
  bool get connected => _session?.connected == true;
  bool get reconnecting => _session?.reconnecting == true;
  bool get needsAudioStart => connected && _session?.canPlaybackAudio == false;
  bool get muted => _muted;
  bool get peerPresent => _session?.peerPresent == true;
  bool get mediaReady =>
      connected &&
      _microphoneReady &&
      _session?.remoteAudioReady == true &&
      !needsAudioStart;
  bool get needsMicrophoneRetry =>
      connected && !_microphoneReady && lastError != null;

  Future<void> connect(Future<Map<String, dynamic>> Function() access) {
    if (_disposed || connected || reconnecting) return Future.value();
    return _connecting ??= _connect(
      access,
    ).whenComplete(() => _connecting = null);
  }

  Future<void> _connect(Future<Map<String, dynamic>> Function() access) async {
    final generation = _generation;
    await _session?.close();
    _session = null;
    _microphoneReady = false;
    lastError = null;
    final credentials = await access().timeout(const Duration(seconds: 12));
    if (_disposed || generation != _generation) return;
    final url = '${credentials['url'] ?? ''}'.trim();
    final token = '${credentials['token'] ?? ''}'.trim();
    if (url.isEmpty || token.isEmpty) {
      throw StateError('SOCIAL_VOICE_ACCESS_INVALID');
    }
    final session = _factory();
    _session = session;
    var wasReconnecting = false;
    session.onChanged(() {
      if (_disposed || !identical(_session, session)) return;
      final restored = wasReconnecting && session.connected;
      wasReconnecting = session.reconnecting;
      if (restored) {
        // A mute change while the socket is reconnecting is still user intent.
        unawaited(
          setMuted(_muted).catchError((Object error) {
            lastError = error;
            if (!_disposed) notifyListeners();
          }),
        );
      }
      notifyListeners();
    });
    try {
      await session
          .connect(url, token)
          .then((_) async {
            if (_disposed ||
                !identical(_session, session) ||
                generation != _generation) {
              await session.close();
            }
          })
          .timeout(const Duration(seconds: 35));
      if (_disposed || generation != _generation) {
        await session.close();
        return;
      }
      // Routing is best effort; unsupported earpiece selection must not close
      // an otherwise working room (the game uses the same LiveKit manager).
      try {
        await session.speaker(_speaker);
      } catch (_) {}
      if (_disposed || generation != _generation) return;
      await _microphoneWork;
      if (_disposed || generation != _generation) return;
      // Keep receiving audio when capture is denied. A gesture can retry it.
      try {
        await setMuted(_muted);
      } catch (error) {
        lastError = error;
      }
      if (_disposed || generation != _generation) return;
      // Browser autoplay denial must leave the room connected. The screen
      // exposes startAudio on a user gesture when canPlaybackAudio is false.
      try {
        await session.startAudio();
      } catch (error) {
        lastError = error;
      }
      if (!_disposed) notifyListeners();
    } catch (error) {
      lastError = error;
      if (identical(_session, session)) _session = null;
      await session.close();
      if (!_disposed) notifyListeners();
      rethrow;
    }
  }

  Future<void> setMuted(bool muted) {
    _muted = muted;
    if (_disposed || !connected) return Future.value();
    return _microphoneWork ??= _syncMicrophone().whenComplete(
      () => _microphoneWork = null,
    );
  }

  Future<void> _syncMicrophone() async {
    final session = _session;
    try {
      bool applied;
      do {
        applied = _muted;
        await session?.microphone(!applied);
      } while (!_disposed && identical(session, _session) && applied != _muted);
      if (!_disposed && identical(session, _session)) {
        _microphoneReady = true;
        lastError = null;
      }
    } catch (error) {
      if (!_disposed && identical(session, _session)) {
        _microphoneReady = false;
        lastError = error;
        notifyListeners();
      }
      rethrow;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setSpeaker(bool enabled) async {
    _speaker = enabled;
    await _session?.speaker(enabled);
  }

  Future<void> startAudio() async {
    await _session?.startAudio();
    if (_microphoneReady) lastError = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> disconnect() async {
    _generation++;
    final session = _session;
    _session = null;
    _microphoneReady = false;
    await session?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}
