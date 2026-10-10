import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/games_api.dart';

enum MafiaVoiceState {
  idle,
  disabled,
  requestingPermission,
  connecting,
  connected,
  reconnecting,
  error,
}

enum _VoiceChannel { main, afterlife }

/// Maintains the live game room and, for eliminated players, an additional
/// afterlife room. User mute intent survives server-enforced silent phases.
class MafiaVoiceController extends ChangeNotifier {
  Room? _mainRoom;
  Room? _afterlifeRoom;
  EventsListener<RoomEvent>? _mainListener;
  EventsListener<RoomEvent>? _afterlifeListener;
  GamesApi? _api;
  int? _roomId;
  Timer? _reconnectTimer;
  Timer? _permissionRetryTimer;
  bool _disposed = false;
  bool _connecting = false;
  bool _refreshingPermissions = false;
  bool _permissionsQueued = false;
  int _generation = 0;
  Future<void>? _microphoneWork;
  bool _microphoneDirty = false;
  bool _tearingDown = false;
  bool _manualDisconnect = false;
  // Browsers only allow microphone capture after a direct user gesture.
  // Start web/PWA sessions listen-only; the microphone button then performs
  // the permission request without destabilising the LiveKit connection.
  bool _microphoneRequested = !kIsWeb;
  bool _mainCanPublish = false;
  bool _afterlifeCanPublish = false;
  int _reconnectAttempt = 0;
  Set<int> _mainSpeakers = const {};
  Set<int> _afterlifeSpeakers = const {};
  final Set<int> _mutedUserIds = <int>{};

  MafiaVoiceState state = MafiaVoiceState.idle;
  String? error;
  bool canPublish = false;
  bool microphoneEnabled = false;
  bool speakerEnabled = true;
  bool needsAudioStart = false;
  Set<int> activeSpeakerUserIds = const {};

  bool get isConnected => state == MafiaVoiceState.connected;
  bool get microphoneRequested => _microphoneRequested;
  bool get isInAfterlife => _afterlifeRoom != null;
  Set<int> get mutedUserIds => Set<int>.unmodifiable(_mutedUserIds);

  bool isUserMuted(int userId) => _mutedUserIds.contains(userId);

  Future<void> connect(GamesApi api, int roomId, {bool force = false}) async {
    if (_disposed || _connecting) return;
    if (_refreshingPermissions) {
      _permissionsQueued = true;
      return;
    }
    if (!force &&
        _roomId == roomId &&
        _mainRoom != null &&
        (state == MafiaVoiceState.connected ||
            state == MafiaVoiceState.reconnecting)) {
      return;
    }
    _api = api;
    _roomId = roomId;
    _manualDisconnect = false;
    _connecting = true;
    final generation = _generation;
    _setState(
      _mainRoom == null
          ? MafiaVoiceState.connecting
          : MafiaVoiceState.reconnecting,
    );
    try {
      final access = await _requestAccess(api, roomId);
      if (!_current(generation)) return;
      if (access['enabled'] != true) {
        await _disposeRooms();
        _setState(MafiaVoiceState.disabled);
        return;
      }
      await _replaceConnections(access);
      if (!_current(generation)) return;
      _reconnectAttempt = 0;
      error = null;
      _setState(MafiaVoiceState.connected);
      // Reconcile once after joining, when the server can update this actual
      // participant rather than only issuing a token for a not-yet-joined room.
      _permissionsQueued = true;
    } catch (exception) {
      if (!_current(generation)) return;
      if (_isForbidden(exception)) {
        await disconnect();
        error = 'MAFIA_ROOM_FORBIDDEN';
        return;
      }
      error = '$exception';
      if (_mainRoom == null) {
        await _disposeRooms();
        _setState(MafiaVoiceState.error);
      } else {
        _setState(MafiaVoiceState.reconnecting);
      }
      _scheduleReconnect();
    } finally {
      _connecting = false;
      if (!_current(generation)) await _disposeRooms();
      if (_permissionsQueued && _current(generation)) {
        _permissionsQueued = false;
        unawaited(refreshPermissions());
      }
    }
  }

  Future<Map<String, dynamic>> _requestAccess(GamesApi api, int roomId) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await api.mafiaVoiceToken(roomId);
      } catch (exception) {
        if (_disposed || _manualDisconnect || _isForbidden(exception)) rethrow;
        lastError = exception;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: attempt == 0 ? 400 : 1200),
          );
        }
      }
    }
    throw lastError ?? StateError('MAFIA_VOICE_ACCESS_FAILED');
  }

  Future<void> _replaceConnections(Map<String, dynamic> access) async {
    final url = '${access['url'] ?? ''}'.trim();
    final token = '${access['token'] ?? ''}'.trim();
    if (url.isEmpty || token.isEmpty) {
      throw StateError('MAFIA_VOICE_ACCESS_INVALID');
    }
    await _disposeRooms();
    if (_disposed || _manualDisconnect) return;
    _mainCanPublish = _map(access['permissions'])['canPublish'] == true;
    final main = await _connectRoom(
      url: url,
      token: token,
      channel: _VoiceChannel.main,
    );
    _mainRoom = main.$1;
    _mainListener = main.$2;

    final afterlife = _map(access['afterlife']);
    _afterlifeCanPublish = _map(afterlife['permissions'])['canPublish'] == true;
    if (afterlife.isNotEmpty) {
      final secondaryToken = '${afterlife['token'] ?? ''}'.trim();
      if (secondaryToken.isNotEmpty) {
        final secondary = await _connectRoom(
          url: url,
          token: secondaryToken,
          channel: _VoiceChannel.afterlife,
        );
        _afterlifeRoom = secondary.$1;
        _afterlifeListener = secondary.$2;
      }
    }
    await _applyMicrophonePreference();
    await _preferSpeakerOutput();
    await _restoreLocalMutes();
    _updatePlaybackStatus();
  }

  Future<(Room, EventsListener<RoomEvent>)> _connectRoom({
    required String url,
    required String token,
    required _VoiceChannel channel,
  }) async {
    final generation = _generation;
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
    _bindEvents(listener, room, channel);
    try {
      await room.connect(
        url,
        token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );
      if (!_current(generation)) throw StateError('VOICE_CONNECTION_CANCELLED');
      return (room, listener);
    } catch (_) {
      await listener.dispose();
      await room.dispose();
      rethrow;
    }
  }

  void _bindEvents(
    EventsListener<RoomEvent> listener,
    Room room,
    _VoiceChannel channel,
  ) {
    listener
      ..on<RoomConnectedEvent>((_) {
        _reconnectAttempt = 0;
        if (!_disposed) _setState(MafiaVoiceState.connected);
      })
      ..on<RoomReconnectingEvent>((_) {
        if (!_disposed) _setState(MafiaVoiceState.reconnecting);
      })
      ..on<RoomReconnectedEvent>((_) {
        _reconnectAttempt = 0;
        if (!_disposed) _setState(MafiaVoiceState.connected);
        unawaited(_restoreLocalMutes());
        unawaited(refreshPermissions());
      })
      ..on<RoomDisconnectedEvent>((_) {
        if (channel == _VoiceChannel.main) _mainSpeakers = const {};
        if (channel == _VoiceChannel.afterlife) {
          _afterlifeSpeakers = const {};
        }
        _mergeActiveSpeakers();
        if (!_disposed && !_tearingDown && !_manualDisconnect) {
          microphoneEnabled = false;
          _setState(MafiaVoiceState.reconnecting);
          _scheduleReconnect();
        }
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        final speakers = event.speakers
            .map((participant) => _userIdFromIdentity(participant.identity))
            .whereType<int>()
            .toSet();
        if (channel == _VoiceChannel.main) {
          _mainSpeakers = speakers;
        } else {
          _afterlifeSpeakers = speakers;
        }
        _mergeActiveSpeakers();
      })
      ..on<ParticipantConnectedEvent>((event) {
        final userId = _userIdFromIdentity(event.participant.identity);
        if (userId != null && _mutedUserIds.contains(userId)) {
          unawaited(_applyLocalMute(userId));
        }
      })
      ..on<TrackSubscribedEvent>((event) {
        final userId = _userIdFromIdentity(event.participant.identity);
        if (userId != null && _mutedUserIds.contains(userId)) {
          unawaited(_applyLocalMute(userId));
        }
      })
      ..on<ParticipantPermissionsUpdatedEvent>((event) {
        if (event.participant != room.localParticipant) return;
        if (channel == _VoiceChannel.main) {
          _mainCanPublish = event.permissions.canPublish;
        } else {
          _afterlifeCanPublish = event.permissions.canPublish;
        }
        unawaited(_applyMicrophonePreference());
      })
      ..on<AudioPlaybackStatusChanged>((_) => _updatePlaybackStatus());
  }

  Future<void> refreshPermissions() async {
    if (_disposed || _manualDisconnect) return;
    if (_connecting || _refreshingPermissions) {
      _permissionsQueued = true;
      return;
    }
    final api = _api;
    final roomId = _roomId;
    if (api == null || roomId == null || state == MafiaVoiceState.disabled) {
      return;
    }
    if (_mainRoom == null ||
        _mainRoom!.connectionState == ConnectionState.disconnected) {
      await connect(api, roomId, force: true);
      return;
    }
    final generation = _generation;
    _refreshingPermissions = true;
    try {
      final access = await _requestAccess(api, roomId);
      if (!_current(generation)) return;
      if (access['enabled'] != true) return;
      _mainCanPublish = _map(access['permissions'])['canPublish'] == true;
      final afterlife = _map(access['afterlife']);
      _afterlifeCanPublish =
          _map(afterlife['permissions'])['canPublish'] == true;
      if (afterlife.isNotEmpty && _afterlifeRoom == null) {
        final url = '${access['url'] ?? ''}'.trim();
        final token = '${afterlife['token'] ?? ''}'.trim();
        if (url.isNotEmpty && token.isNotEmpty) {
          _afterlifeCanPublish =
              _map(afterlife['permissions'])['canPublish'] == true;
          final secondary = await _connectRoom(
            url: url,
            token: token,
            channel: _VoiceChannel.afterlife,
          );
          _afterlifeRoom = secondary.$1;
          _afterlifeListener = secondary.$2;
        }
      } else if (afterlife.isEmpty && _afterlifeRoom != null) {
        await _disposeAfterlifeRoom();
      }
      await _applyMicrophonePreference();
      error = null;
      _permissionRetryTimer?.cancel();
      if (_mainRoom?.connectionState == ConnectionState.connected) {
        _setState(MafiaVoiceState.connected);
      }
    } catch (exception) {
      if (!_current(generation)) return;
      if (_isForbidden(exception)) {
        await disconnect();
        error = 'MAFIA_ROOM_FORBIDDEN';
        return;
      }
      error = '$exception';
      _notify();
      _permissionRetryTimer?.cancel();
      _permissionRetryTimer = Timer(
        const Duration(seconds: 2),
        () => unawaited(refreshPermissions()),
      );
    } finally {
      _refreshingPermissions = false;
      if (_permissionsQueued && _current(generation)) {
        _permissionsQueued = false;
        unawaited(refreshPermissions());
      }
    }
  }

  Future<void> toggleMicrophone() async {
    _microphoneRequested = !_microphoneRequested;
    await _applyMicrophonePreference();
  }

  Future<void> _applyMicrophonePreference() async {
    if (_disposed || _manualDisconnect) return;
    _microphoneDirty = true;
    final existing = _microphoneWork;
    if (existing != null) return existing;
    final done = Completer<void>();
    _microphoneWork = done.future;
    try {
      while (_microphoneDirty && !_disposed && !_manualDisconnect) {
        _microphoneDirty = false;
        await _syncMicrophone();
      }
    } catch (exception) {
      if (!_disposed) {
        error = '$exception';
        _notify();
      }
    } finally {
      _microphoneWork = null;
      done.complete();
    }
  }

  Future<void> _syncMicrophone() async {
    final generation = _generation;
    final useAfterlife = _afterlifeRoom != null;
    final mainAllowed =
        !useAfterlife &&
        _mainCanPublish &&
        (_mainRoom?.localParticipant?.permissions.canPublish ?? false);
    final deadAllowed =
        useAfterlife &&
        _afterlifeCanPublish &&
        (_afterlifeRoom?.localParticipant?.permissions.canPublish ?? false);
    canPublish = mainAllowed || deadAllowed;
    if (_microphoneRequested &&
        canPublish &&
        !await _ensureMicrophonePermission()) {
      return;
    }
    if (!_current(generation)) return;
    var enabled = false;
    // Disable the old channel before capture on the new one. One microphone
    // operation is in flight; later taps/permission events are coalesced.
    final entries = <(Room?, bool)>[
      (_mainRoom, mainAllowed),
      (_afterlifeRoom, deadAllowed),
    ]..sort((a, b) => (a.$2 ? 1 : 0).compareTo(b.$2 ? 1 : 0));
    for (final entry in entries) {
      if (!_current(generation)) return;
      final participant = entry.$1?.localParticipant;
      if (participant == null) continue;
      final shouldEnable = _microphoneRequested && entry.$2;
      try {
        if (participant.isMicrophoneEnabled() != shouldEnable) {
          await participant.setMicrophoneEnabled(shouldEnable);
        }
        enabled = enabled || participant.isMicrophoneEnabled();
      } catch (exception) {
        error = '$exception';
      }
    }
    microphoneEnabled = enabled;
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

  Future<void> toggleUserMute(int userId) async {
    if (userId <= 0) return;
    if (!_mutedUserIds.add(userId)) {
      _mutedUserIds.remove(userId);
    }
    await _applyLocalMute(userId);
    _mergeActiveSpeakers();
  }

  Future<void> _restoreLocalMutes() async {
    for (final userId in _mutedUserIds) {
      await _applyLocalMute(userId);
    }
  }

  Future<void> _applyLocalMute(int userId) async {
    final shouldMute = _mutedUserIds.contains(userId);
    for (final room in <Room?>[_mainRoom, _afterlifeRoom]) {
      if (room == null) continue;
      for (final participant in room.remoteParticipants.values) {
        if (_userIdFromIdentity(participant.identity) != userId) continue;
        for (final publication in participant.audioTrackPublications) {
          if (shouldMute) {
            await publication.disable();
          } else {
            await publication.enable();
          }
        }
      }
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
      if (_mainRoom != null) await _mainRoom!.startAudio();
      if (_afterlifeRoom != null) await _afterlifeRoom!.startAudio();
      _updatePlaybackStatus();
      error = null;
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
    if (_mainRoom != null && state == MafiaVoiceState.connected) {
      await refreshPermissions();
    } else {
      await connect(api, roomId, force: true);
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _generation++;
    _reconnectTimer?.cancel();
    _permissionRetryTimer?.cancel();
    await _disposeRooms();
    if (!_disposed) _setState(MafiaVoiceState.idle);
  }

  void _scheduleReconnect() {
    if (_disposed || _manualDisconnect || _reconnectTimer?.isActive == true) {
      return;
    }
    final delays = [1, 2, 4, 8, 15];
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
    if (kIsWeb) {
      return true; // Capture asks the browser from the microphone tap.
    }
    final current = await Permission.microphone.status;
    if (current.isGranted || current.isLimited) return true;
    _setState(MafiaVoiceState.requestingPermission);
    final requested = await Permission.microphone.request();
    if (requested.isGranted || requested.isLimited) {
      if (_mainRoom != null) _setState(MafiaVoiceState.connected);
      return true;
    }
    error = 'MICROPHONE_PERMISSION_DENIED';
    microphoneEnabled = false;
    _microphoneRequested = false;
    _setState(
      _mainRoom?.connectionState == ConnectionState.connected
          ? MafiaVoiceState.connected
          : MafiaVoiceState.idle,
    );
    return false;
  }

  void _mergeActiveSpeakers() {
    activeSpeakerUserIds = {..._mainSpeakers, ..._afterlifeSpeakers}
      ..removeAll(_mutedUserIds);
    _notify();
  }

  void _updatePlaybackStatus() {
    final mainBlocked = _mainRoom != null && !_mainRoom!.canPlaybackAudio;
    final afterlifeBlocked =
        _afterlifeRoom != null && !_afterlifeRoom!.canPlaybackAudio;
    needsAudioStart = mainBlocked || afterlifeBlocked;
    _notify();
  }

  Future<void> _disposeAfterlifeRoom() async {
    final listener = _afterlifeListener;
    final room = _afterlifeRoom;
    _afterlifeListener = null;
    _afterlifeRoom = null;
    _afterlifeCanPublish = false;
    _afterlifeSpeakers = const {};
    if (listener != null) await listener.dispose();
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
  }

  Future<void> _disposeRooms() async {
    _tearingDown = true;
    try {
      final mainListener = _mainListener;
      final mainRoom = _mainRoom;
      _mainListener = null;
      _mainRoom = null;
      await _disposeAfterlifeRoom();
      if (mainListener != null) await mainListener.dispose();
      if (mainRoom != null) {
        await mainRoom.disconnect();
        await mainRoom.dispose();
      }
      _mainCanPublish = false;
      _mainSpeakers = const {};
      activeSpeakerUserIds = const {};
      canPublish = false;
      microphoneEnabled = false;
      needsAudioStart = false;
    } finally {
      _tearingDown = false;
    }
  }

  void _setState(MafiaVoiceState value) {
    state = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed && !_manualDisconnect && generation == _generation;

  bool _isForbidden(Object exception) =>
      exception is DioException &&
      [401, 403, 404].contains(exception.response?.statusCode);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _permissionRetryTimer?.cancel();
    unawaited(_disposeRooms());
    super.dispose();
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

int? _userIdFromIdentity(String identity) {
  final match = RegExp(
    r'^mafia:\d+:(?:dead:)?user:(\d+)$',
  ).firstMatch(identity);
  return int.tryParse(match?.group(1) ?? '');
}

int _min(int a, int b) => a < b ? a : b;
