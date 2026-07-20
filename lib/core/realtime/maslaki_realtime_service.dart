import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/state/auth_controller.dart';
import '../network/session_invalidation.dart';
import '../storage/secure_storage.dart';

final maslakiRealtimeServiceProvider = Provider<MaslakiRealtimeService>((ref) {
  final service = MaslakiRealtimeService(
    ref.read(dioClientProvider).dio,
    store: ref.read(secureStoreProvider),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

abstract class MaslakiRealtimeClient {
  Future<bool> bindAuthenticatedSession({bool force = false});
  Future<void> clearSession();
  Future<void> setAppActive(bool active);
  Future<Stream<MaslakiRealtimeEvent>?> subscribeDefaultUserChannel();
  Future<Stream<MaslakiRealtimeEvent>?> subscribeUserChannel(String namespace);
  Future<Stream<MaslakiRealtimeEvent>?> subscribeTopic(String topic);
}

class MaslakiRealtimeEvent {
  final String topic;
  final String event;
  final Map<String, dynamic> data;
  final int? eventId;
  final Map<String, dynamic> envelope;

  const MaslakiRealtimeEvent({
    required this.topic,
    required this.event,
    required this.data,
    required this.envelope,
    this.eventId,
  });
}

class MaslakiRealtimeService implements MaslakiRealtimeClient {
  MaslakiRealtimeService(this._dio, {SecureStore? store})
    : _store = store ?? SecureStore() {
    _sessionRecoveryListener = () {
      unawaited(_resyncAfterSessionRecovery());
    };
    SessionRecoveryBus.instance.addListener(_sessionRecoveryListener);
  }

  /// Re-binds realtime after a silent session recovery.
  ///
  /// Recovery is not a logout. `clearSession` closes every topic controller and
  /// disposes the client, which permanently killed realtime for subscribers
  /// that had already been handed a stream. Instead we re-mint the realtime
  /// token and re-attach the existing topics, exactly like resuming the app.
  Future<void> _resyncAfterSessionRecovery() async {
    if (_disposed) return;
    // Duplicate recovery ticks must not run overlapping rebinds.
    if (_recoveryResyncInFlight) return;
    _recoveryResyncInFlight = true;
    try {
      final ready = await bindAuthenticatedSession(force: true);
      if (!ready || _disposed) return;
      await _restoreLiveTopics();
    } finally {
      _recoveryResyncInFlight = false;
    }
  }

  final Dio _dio;
  final SecureStore _store;
  final Map<String, _TopicSubscriptionEntry> _topics =
      <String, _TopicSubscriptionEntry>{};
  late final VoidCallback _sessionRecoveryListener;
  bool _recoveryResyncInFlight = false;

  SupabaseClient? _client;
  String? _supabaseUrl;
  String? _supabaseAnonKey;
  int? _boundUserId;
  DateTime? _tokenExpiresAt;
  Timer? _tokenRefreshTimer;
  Future<bool>? _bindInFlight;
  bool _appActive = true;
  bool _disposed = false;

  @override
  Future<bool> bindAuthenticatedSession({bool force = false}) async {
    if (_disposed) return false;
    final inFlight = _bindInFlight;
    if (inFlight != null) return inFlight;

    final future = _bindAuthenticatedSessionInternal(force: force);
    _bindInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_bindInFlight, future)) {
        _bindInFlight = null;
      }
    }
  }

  @override
  Future<void> clearSession() async {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _boundUserId = null;
    _tokenExpiresAt = null;
    await _disposeAllTopics(closeControllers: true);
    await _disposeClient();
  }

  @override
  Future<void> setAppActive(bool active) async {
    if (_disposed || _appActive == active) return;
    _appActive = active;
    if (!active) {
      await _detachAllTopicChannels();
      return;
    }
    final ready = await bindAuthenticatedSession();
    if (!ready) return;
    await _restoreLiveTopics();
  }

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeUserChannel(
    String namespace,
  ) async {
    final normalized = namespace.trim().toLowerCase();
    final ready = await bindAuthenticatedSession();
    final userId = _boundUserId;
    if (!ready || userId == null || userId <= 0) return null;
    if (normalized.isEmpty) {
      return subscribeTopic('user:$userId');
    }
    return subscribeTopic('$normalized:user:$userId');
  }

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeDefaultUserChannel() async {
    return subscribeUserChannel('');
  }

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeTopic(String topic) async {
    if (_disposed) return null;
    final normalizedTopic = topic.trim();
    if (normalizedTopic.isEmpty) return null;
    final ready = await bindAuthenticatedSession();
    if (!ready) return null;

    final entry = _topics.putIfAbsent(
      normalizedTopic,
      () => _TopicSubscriptionEntry(
        topic: normalizedTopic,
        onListen: () => _handleTopicListen(normalizedTopic),
        onCancel: () => _handleTopicCancel(normalizedTopic),
      ),
    );

    if (_appActive) {
      final connected = await _ensureTopicConnected(entry);
      if (!connected) {
        _topics.remove(normalizedTopic);
        await entry.close();
        return null;
      }
    }

    return entry.stream;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    SessionRecoveryBus.instance.removeListener(_sessionRecoveryListener);
    await clearSession();
  }

  Future<bool> _bindAuthenticatedSessionInternal({required bool force}) async {
    if (!_appActive && !force) {
      return _client != null &&
          _boundUserId != null &&
          _tokenStillUsable(minBuffer: const Duration(seconds: 45));
    }

    if (!force &&
        _client != null &&
        _boundUserId != null &&
        _tokenStillUsable(minBuffer: const Duration(seconds: 75))) {
      return true;
    }

    final tokenResponse = await _fetchRealtimeToken();
    if (tokenResponse == null) return false;

    await _ensureSupabaseClient(
      supabaseUrl: tokenResponse.supabaseUrl,
      supabaseAnonKey: tokenResponse.supabaseAnonKey,
    );

    try {
      await _client!.realtime.setAuth(tokenResponse.realtimeToken);
    } catch (error) {
      debugPrint('[realtime] failed to set Supabase auth: $error');
      return false;
    }

    _boundUserId = tokenResponse.userId;
    _tokenExpiresAt = DateTime.now().add(
      Duration(seconds: max(tokenResponse.expiresIn, 60)),
    );
    _scheduleTokenRefresh();
    return true;
  }

  Future<_RealtimeTokenResponse?> _fetchRealtimeToken() async {
    try {
      final accessToken = await _store.readToken();
      if (accessToken == null || accessToken.trim().isEmpty) {
        return null;
      }
      final response = await _dio.post('/api/realtime/token');
      final map = Map<String, dynamic>.from(response.data as Map);
      return _RealtimeTokenResponse.fromMap(map);
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      final data = error.response?.data;
      final code = data is Map ? '${data['message'] ?? ''}'.trim() : '';
      if (statusCode == 503 &&
          (code == 'REALTIME_DISABLED' || code == 'REALTIME_NOT_CONFIGURED')) {
        debugPrint('[realtime] fallback to SSE: $code');
        return null;
      }
      if (statusCode == 401) {
        debugPrint('[realtime] auth unavailable for token fetch');
        return null;
      }
      debugPrint('[realtime] token fetch failed: $error');
      return null;
    } catch (error) {
      debugPrint('[realtime] unexpected token fetch failure: $error');
      return null;
    }
  }

  Future<void> _ensureSupabaseClient({
    required String supabaseUrl,
    required String supabaseAnonKey,
  }) async {
    final needsRebuild =
        _client == null ||
        _supabaseUrl != supabaseUrl ||
        _supabaseAnonKey != supabaseAnonKey;
    if (!needsRebuild) return;

    await _disposeAllTopics(closeControllers: false);
    await _disposeClient();

    _supabaseUrl = supabaseUrl;
    _supabaseAnonKey = supabaseAnonKey;
    _client = SupabaseClient(
      supabaseUrl,
      supabaseAnonKey,
      realtimeClientOptions: const RealtimeClientOptions(
        timeout: Duration(seconds: 12),
      ),
    );
  }

  bool _tokenStillUsable({required Duration minBuffer}) {
    final expiresAt = _tokenExpiresAt;
    if (expiresAt == null) return false;
    return expiresAt.isAfter(DateTime.now().add(minBuffer));
  }

  void _scheduleTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    final expiresAt = _tokenExpiresAt;
    if (expiresAt == null) return;
    final now = DateTime.now();
    final refreshAt = expiresAt.subtract(const Duration(minutes: 2));
    final delay = refreshAt.isAfter(now)
        ? refreshAt.difference(now)
        : const Duration(seconds: 30);
    _tokenRefreshTimer = Timer(delay, () async {
      if (_disposed) return;
      final ready = await bindAuthenticatedSession(force: true);
      if (!ready) {
        await _failAllTopics(StateError('supabase_realtime_refresh_failed'));
        return;
      }
      if (_appActive) {
        await _restoreLiveTopics();
      }
    });
  }

  Future<void> _handleTopicListen(String topic) async {
    final entry = _topics[topic];
    if (entry == null) return;
    entry.listeners += 1;
    entry.idleDisposeTimer?.cancel();
    entry.idleDisposeTimer = null;
    if (_appActive) {
      final connected = await _ensureTopicConnected(entry);
      if (!connected) {
        await _failTopic(
          topic,
          StateError('supabase_realtime_topic_unavailable'),
        );
      }
    }
  }

  Future<void> _handleTopicCancel(String topic) async {
    final entry = _topics[topic];
    if (entry == null) return;
    entry.listeners = max(0, entry.listeners - 1);
    if (entry.listeners > 0) return;
    entry.idleDisposeTimer?.cancel();
    entry.idleDisposeTimer = Timer(const Duration(seconds: 5), () async {
      final current = _topics[topic];
      if (current == null || current.listeners > 0) return;
      _topics.remove(topic);
      await current.close();
    });
  }

  Future<bool> _ensureTopicConnected(_TopicSubscriptionEntry entry) async {
    if (_disposed || !_appActive) return true;
    final client = _client;
    if (client == null) return false;
    if (entry.channel != null && entry.isSubscribed) return true;
    if (entry.connectionInFlight != null) {
      return entry.connectionInFlight!;
    }

    final future = _connectTopicEntry(entry, client);
    entry.connectionInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(entry.connectionInFlight, future)) {
        entry.connectionInFlight = null;
      }
    }
  }

  Future<bool> _connectTopicEntry(
    _TopicSubscriptionEntry entry,
    SupabaseClient client,
  ) async {
    final completer = Completer<bool>();
    entry.statusCompleter = completer;
    entry.manualClose = false;
    entry.isSubscribed = false;

    final channel = client.channel(
      entry.topic,
      opts: const RealtimeChannelConfig(private: true),
    );
    entry.channel = channel;

    channel.onBroadcast(
      event: '*',
      callback: (payload) => _handleChannelBroadcast(entry.topic, payload),
    );

    channel.subscribe((status, [error]) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          entry.failureCount = 0;
          entry.isSubscribed = true;
          if (!completer.isCompleted) {
            completer.complete(true);
          }
          break;
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          entry.isSubscribed = false;
          if (!completer.isCompleted) {
            completer.complete(false);
          } else {
            _handleRuntimeTopicFailure(entry.topic, error);
          }
          break;
        case RealtimeSubscribeStatus.closed:
          entry.isSubscribed = false;
          if (!completer.isCompleted) {
            completer.complete(false);
          } else if (!entry.manualClose) {
            _handleRuntimeTopicFailure(entry.topic, error);
          }
          break;
      }
    });

    try {
      return await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return false;
    }
  }

  void _handleChannelBroadcast(String topic, Map<String, dynamic> payload) {
    final entry = _topics[topic];
    if (entry == null || entry.controller.isClosed) return;
    final event = _normalizeRealtimeEvent(topic, payload);
    if (event == null) return;
    entry.controller.add(event);
  }

  MaslakiRealtimeEvent? _normalizeRealtimeEvent(
    String topic,
    Map<String, dynamic> payload,
  ) {
    final direct = payload;
    final envelope = _extractEnvelope(direct) ?? direct;
    final eventName =
        _safeText(envelope['event']) ?? _safeText(direct['event']) ?? 'message';
    final data =
        _asMap(envelope['data']) ??
        _asMap(direct['payload']) ??
        _asMap(direct['data']) ??
        const <String, dynamic>{};
    return MaslakiRealtimeEvent(
      topic: topic,
      event: eventName,
      data: data,
      eventId: _toPositiveInt(envelope['id']) ?? _toPositiveInt(direct['id']),
      envelope: envelope,
    );
  }

  Map<String, dynamic>? _extractEnvelope(Map<String, dynamic> raw) {
    if (_looksLikeEnvelope(raw)) return raw;
    final payload = _asMap(raw['payload']);
    if (_looksLikeEnvelope(payload)) return payload;
    final data = _asMap(raw['data']);
    if (_looksLikeEnvelope(data)) return data;
    final nestedPayload = data == null ? null : _asMap(data['payload']);
    if (_looksLikeEnvelope(nestedPayload)) return nestedPayload;
    if (payload != null) {
      return <String, dynamic>{
        'event':
            _safeText(raw['event']) ?? _safeText(payload['event']) ?? 'message',
        'data': payload,
        'channel': _safeText(raw['topic']) ?? _safeText(raw['channel']),
      };
    }
    return null;
  }

  bool _looksLikeEnvelope(Map<String, dynamic>? value) {
    if (value == null || value.isEmpty) return false;
    return value.containsKey('data') && value.containsKey('event');
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, mapValue) => MapEntry('$key', mapValue));
    }
    return null;
  }

  String? _safeText(dynamic value) {
    final text = '$value'.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  int? _toPositiveInt(dynamic value) {
    final parsed = int.tryParse('${value ?? ''}');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  Future<void> _handleRuntimeTopicFailure(String topic, Object? error) async {
    final entry = _topics[topic];
    if (entry == null) return;
    entry.failureCount += 1;
    if (entry.failureCount < 3) return;
    await _failTopic(
      topic,
      StateError(
        'supabase_realtime_topic_failure:${entry.topic}:${error ?? 'unknown'}',
      ),
    );
  }

  Future<void> _failTopic(String topic, Object error) async {
    final entry = _topics.remove(topic);
    if (entry == null) return;
    try {
      if (!entry.controller.isClosed) {
        entry.controller.addError(error);
      }
    } catch (_) {
      // Ignore addError when listeners have already gone away.
    }
    await entry.close();
  }

  Future<void> _failAllTopics(Object error) async {
    final topics = _topics.keys.toList(growable: false);
    for (final topic in topics) {
      await _failTopic(topic, error);
    }
  }

  Future<void> _restoreLiveTopics() async {
    for (final entry in _topics.values) {
      if (entry.listeners <= 0) continue;
      final connected = await _ensureTopicConnected(entry);
      if (!connected) {
        await _failTopic(
          entry.topic,
          StateError('supabase_realtime_restore_failed'),
        );
      }
    }
  }

  Future<void> _detachAllTopicChannels() async {
    for (final entry in _topics.values) {
      await entry.detachChannel(_client);
    }
  }

  Future<void> _disposeAllTopics({required bool closeControllers}) async {
    final values = _topics.values.toList(growable: false);
    _topics.clear();
    for (final entry in values) {
      if (closeControllers) {
        await entry.close(client: _client);
      } else {
        await entry.detachChannel(_client);
      }
    }
  }

  Future<void> _disposeClient() async {
    final client = _client;
    _client = null;
    if (client == null) return;
    try {
      await client.removeAllChannels();
    } catch (_) {
      // Best-effort cleanup.
    }
    try {
      await client.dispose();
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}

class _RealtimeTokenResponse {
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String realtimeToken;
  final int userId;
  final int expiresIn;

  const _RealtimeTokenResponse({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.realtimeToken,
    required this.userId,
    required this.expiresIn,
  });

  factory _RealtimeTokenResponse.fromMap(Map<String, dynamic> map) {
    return _RealtimeTokenResponse(
      supabaseUrl: '${map['supabaseUrl'] ?? ''}'.trim(),
      supabaseAnonKey: '${map['supabaseAnonKey'] ?? ''}'.trim(),
      realtimeToken: '${map['realtimeToken'] ?? ''}'.trim(),
      userId: int.tryParse('${map['userId'] ?? ''}') ?? 0,
      expiresIn: int.tryParse('${map['expiresIn'] ?? ''}') ?? 900,
    );
  }
}

class _TopicSubscriptionEntry {
  _TopicSubscriptionEntry({
    required this.topic,
    required VoidCallback onListen,
    required Future<void> Function() onCancel,
  }) : controller = StreamController<MaslakiRealtimeEvent>.broadcast(
         sync: true,
         onListen: onListen,
         onCancel: onCancel,
       );

  final String topic;
  final StreamController<MaslakiRealtimeEvent> controller;
  RealtimeChannel? channel;
  Completer<bool>? statusCompleter;
  Future<bool>? connectionInFlight;
  Timer? idleDisposeTimer;
  int listeners = 0;
  int failureCount = 0;
  bool isSubscribed = false;
  bool manualClose = false;

  Stream<MaslakiRealtimeEvent> get stream => controller.stream;

  Future<void> detachChannel(SupabaseClient? client) async {
    idleDisposeTimer?.cancel();
    idleDisposeTimer = null;
    final currentChannel = channel;
    channel = null;
    statusCompleter = null;
    connectionInFlight = null;
    isSubscribed = false;
    if (currentChannel == null || client == null) return;
    manualClose = true;
    try {
      await client.removeChannel(currentChannel);
    } catch (_) {
      // Best-effort detach.
    } finally {
      manualClose = false;
    }
  }

  Future<void> close({SupabaseClient? client}) async {
    await detachChannel(client);
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}
