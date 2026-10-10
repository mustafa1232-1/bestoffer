import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/games_api.dart';

enum TeamCodeVoiceState {
  idle,
  disabled,
  requestingPermission,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Owns the single cooperative voice channel used by a Team Code room.
/// Microphone intent survives reconnects, while web sessions begin in
/// listen-only mode until the player explicitly taps the microphone button.
class TeamCodeVoiceController extends ChangeNotifier {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  GamesApi? _api;
  Future<Map<String, dynamic>> Function()? _accessProvider;
  int? _roomId;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _connecting = false;
  bool _tearingDown = false;
  bool _manualDisconnect = false;
  bool _microphoneRequested = !kIsWeb;
  bool _canPublish = false;
  int _reconnectAttempt = 0;

  TeamCodeVoiceState state = TeamCodeVoiceState.idle;
  String? error;
  bool microphoneEnabled = false;
  bool speakerEnabled = true;
  bool needsAudioStart = false;
  Set<int> activeSpeakerUserIds = const {};

  bool get microphoneRequested => _microphoneRequested;
  bool get canPublish => _canPublish;
  bool get isConnected => state == TeamCodeVoiceState.connected;

  Future<void> connect(
    GamesApi api,
    int roomId, {
    bool force = false,
    bool startMuted = false,
    Future<Map<String, dynamic>> Function()? accessProvider,
  }) async {
    if (_disposed || _connecting) return;
    if (!force &&
        _roomId == roomId &&
        _room != null &&
        (state == TeamCodeVoiceState.connected ||
            state == TeamCodeVoiceState.reconnecting)) {
      return;
    }
    _api = api;
    if (accessProvider != null) _accessProvider = accessProvider;
    if (startMuted) _microphoneRequested = false;
    _roomId = roomId;
    _manualDisconnect = false;
    _connecting = true;
    _setState(
      _room == null
          ? TeamCodeVoiceState.connecting
          : TeamCodeVoiceState.reconnecting,
    );
    try {
      final access = await _requestAccess(api, roomId);
      if (access['enabled'] != true) {
        await _disposeRoom();
        error = '${access['reason'] ?? ''}'.trim();
        _setState(TeamCodeVoiceState.disabled);
        return;
      }
      await _replaceConnection(access);
      _reconnectAttempt = 0;
      error = null;
      _setState(TeamCodeVoiceState.connected);
    } catch (exception) {
      error = '$exception';
      if (_room == null) {
        await _disposeRoom();
        _setState(TeamCodeVoiceState.error);
      } else {
        _setState(TeamCodeVoiceState.reconnecting);
      }
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  Future<Map<String, dynamic>> _requestAccess(GamesApi api, int roomId) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await (_accessProvider?.call() ??
            api.teamCodeVoiceToken(roomId));
      } catch (exception) {
        lastError = exception;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: attempt == 0 ? 400 : 1200),
          );
        }
      }
    }
    throw lastError ?? StateError('TEAM_CODE_VOICE_ACCESS_FAILED');
  }

  Future<void> _replaceConnection(Map<String, dynamic> access) async {
    final url = '${access['url'] ?? ''}'.trim();
    final token = '${access['token'] ?? ''}'.trim();
    if (url.isEmpty || token.isEmpty) {
      throw StateError('TEAM_CODE_VOICE_ACCESS_INVALID');
    }
    await _disposeRoom();
    _canPublish = _map(access['permissions'])['canPublish'] == true;
    final room = Room(
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
    final listener = room.createListener();
    _bindEvents(listener, room);
    try {
      await room.connect(
        url,
        token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );
      _room = room;
      _listener = listener;
      await _applyMicrophonePreference();
      await _preferSpeakerOutput();
      _updatePlaybackStatus();
    } catch (_) {
      await listener.dispose();
      await room.dispose();
      rethrow;
    }
  }

  void _bindEvents(EventsListener<RoomEvent> listener, Room room) {
    listener
      ..on<RoomConnectedEvent>((_) {
        _reconnectAttempt = 0;
        if (!_disposed) _setState(TeamCodeVoiceState.connected);
      })
      ..on<RoomReconnectingEvent>((_) {
        if (!_disposed) _setState(TeamCodeVoiceState.reconnecting);
      })
      ..on<RoomReconnectedEvent>((_) {
        _reconnectAttempt = 0;
        if (!_disposed) _setState(TeamCodeVoiceState.connected);
      })
      ..on<RoomDisconnectedEvent>((_) {
        activeSpeakerUserIds = const {};
        microphoneEnabled = false;
        if (!_disposed && !_tearingDown && !_manualDisconnect) {
          _setState(TeamCodeVoiceState.reconnecting);
          _scheduleReconnect();
        }
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        activeSpeakerUserIds = event.speakers
            .map((participant) => _userIdFromIdentity(participant.identity))
            .whereType<int>()
            .toSet();
        _notify();
      })
      ..on<ParticipantPermissionsUpdatedEvent>((event) {
        if (event.participant != room.localParticipant) return;
        _canPublish = event.permissions.canPublish;
        unawaited(_applyMicrophonePreference());
      })
      ..on<AudioPlaybackStatusChanged>((_) => _updatePlaybackStatus());
  }

  Future<void> toggleMicrophone() async {
    _microphoneRequested = !_microphoneRequested;
    await _applyMicrophonePreference();
  }

  Future<void> _applyMicrophonePreference() async {
    final participant = _room?.localParticipant;
    if (participant == null) {
      microphoneEnabled = false;
      _notify();
      return;
    }
    if (_microphoneRequested &&
        _canPublish &&
        !await _ensureMicrophonePermission()) {
      return;
    }
    try {
      await participant.setMicrophoneEnabled(
        _microphoneRequested && _canPublish,
      );
      microphoneEnabled = participant.isMicrophoneEnabled();
      error = null;
    } catch (exception) {
      error = '$exception';
      microphoneEnabled = false;
    }
    _notify();
  }

  Future<void> toggleSpeaker() async {
    speakerEnabled = !speakerEnabled;
    try {
      await _preferSpeakerOutput();
      error = null;
    } catch (exception) {
      error = '$exception';
    }
    _notify();
  }

  Future<void> _preferSpeakerOutput() async {
    if (!kIsWeb) {
      await AudioManager.instance.setSpeakerOutputPreferred(speakerEnabled);
    }
  }

  Future<void> startAudio() async {
    try {
      await _room?.startAudio();
      error = null;
      _updatePlaybackStatus();
    } catch (exception) {
      error = '$exception';
      _notify();
    }
  }

  Future<void> retry() async {
    final api = _api;
    final roomId = _roomId;
    if (api == null || roomId == null) return;
    _reconnectTimer?.cancel();
    await connect(api, roomId, force: true);
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    await _disposeRoom();
    if (!_disposed) _setState(TeamCodeVoiceState.idle);
  }

  void _scheduleReconnect() {
    if (_disposed || _manualDisconnect || _reconnectTimer?.isActive == true) {
      return;
    }
    const delays = [1, 2, 4, 8, 15];
    final seconds = delays[_min(_reconnectAttempt, delays.length - 1)];
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      final api = _api;
      final roomId = _roomId;
      if (api != null && roomId != null && !_manualDisconnect) {
        unawaited(connect(api, roomId, force: true));
      }
    });
  }

  Future<bool> _ensureMicrophonePermission() async {
    final current = await Permission.microphone.status;
    if (current.isGranted || current.isLimited) return true;
    _setState(TeamCodeVoiceState.requestingPermission);
    final requested = await Permission.microphone.request();
    if (requested.isGranted || requested.isLimited) {
      if (_room != null) _setState(TeamCodeVoiceState.connected);
      return true;
    }
    error = 'MICROPHONE_PERMISSION_DENIED';
    microphoneEnabled = false;
    _setState(TeamCodeVoiceState.error);
    return false;
  }

  void _updatePlaybackStatus() {
    needsAudioStart = _room != null && !_room!.canPlaybackAudio;
    _notify();
  }

  Future<void> _disposeRoom() async {
    _tearingDown = true;
    try {
      final listener = _listener;
      final room = _room;
      _listener = null;
      _room = null;
      if (listener != null) await listener.dispose();
      if (room != null) {
        await room.disconnect();
        await room.dispose();
      }
      _canPublish = false;
      microphoneEnabled = false;
      needsAudioStart = false;
      activeSpeakerUserIds = const {};
    } finally {
      _tearingDown = false;
    }
  }

  void _setState(TeamCodeVoiceState value) {
    state = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    unawaited(_disposeRoom());
    super.dispose();
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

int? _userIdFromIdentity(String identity) {
  final match = RegExp(r'^team-code:\d+:user:(\d+)$').firstMatch(identity);
  return int.tryParse(match?.group(1) ?? '');
}

int _min(int a, int b) => a < b ? a : b;
