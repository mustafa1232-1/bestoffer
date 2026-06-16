import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/realtime/maslaki_realtime_service.dart';

class NotificationLiveEvent {
  final String event;
  final Map<String, dynamic> data;
  final int? eventId;

  const NotificationLiveEvent({
    required this.event,
    required this.data,
    this.eventId,
  });
}

class NotificationsApi {
  final Dio dio;
  final MaslakiRealtimeClient? realtime;

  NotificationsApi(this.dio, {this.realtime});

  Future<List<dynamic>> list({bool unreadOnly = false, int limit = 50}) async {
    final response = await dio.get(
      '/api/notifications',
      queryParameters: {'unreadOnly': unreadOnly ? 1 : 0, 'limit': limit},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<int> unreadCount() async {
    final response = await dio.get('/api/notifications/unread-count');
    final map = Map<String, dynamic>.from(response.data as Map);
    return int.tryParse('${map['unreadCount']}') ?? 0;
  }

  Future<void> markRead(int notificationId) async {
    await dio.patch('/api/notifications/$notificationId/read');
  }

  Future<void> markAllRead() async {
    await dio.patch('/api/notifications/read-all');
  }

  Future<void> registerPushToken({
    required String token,
    String? platform,
    String? appVersion,
    String? deviceModel,
    String? localeCode,
  }) async {
    await dio.post(
      '/api/notifications/push-token',
      data: {
        'token': token,
        'platform': platform,
        'appVersion': appVersion,
        'deviceModel': deviceModel,
        'locale': localeCode,
      },
    );
  }

  Future<void> unregisterPushToken({required String token}) async {
    await dio.delete('/api/notifications/push-token', data: {'token': token});
  }

  Future<Map<String, dynamic>> pushStatus() async {
    final response = await dio.get('/api/notifications/push-status');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> trackAction({
    required String actionId,
    int? notificationId,
    String? target,
    String? entityType,
    int? entityId,
    String requestState = 'opened',
    Map<String, dynamic> payload = const {},
  }) async {
    final response = await dio.post(
      '/api/notifications/actions/track',
      data: {
        'actionId': actionId,
        'notificationId': notificationId,
        'target': target,
        'entityType': entityType,
        'entityId': entityId,
        'requestState': requestState,
        'payload': payload,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Stream<NotificationLiveEvent> streamEvents({
    int? lastEventId,
    String channel = 'notifications',
  }) {
    final normalizedChannel = switch (channel.trim().toLowerCase()) {
      'social' => 'social',
      _ => 'notifications',
    };
    return _streamSupabaseFirst(
      openRealtime: () async =>
          await realtime?.subscribeUserChannel(normalizedChannel),
      fallback: () => _streamEventsViaSse(
        lastEventId: lastEventId,
        channel: normalizedChannel,
      ),
    );
  }

  Stream<NotificationLiveEvent> streamThreadEvents({
    required int threadId,
    int? lastEventId,
  }) {
    return _streamSupabaseFirst(
      openRealtime: () async => await realtime?.subscribeUserChannel('social'),
      fallback: () =>
          _streamEventsViaSse(
            lastEventId: lastEventId,
            channel: 'social',
          ).where(
            (event) =>
                event.event == 'resync_required' ||
                _matchesThreadEvent(event.data, threadId),
          ),
    ).where(
      (event) =>
          event.event == 'connected' ||
          event.event == 'resync_required' ||
          _matchesThreadEvent(event.data, threadId),
    );
  }

  Stream<NotificationLiveEvent> _streamSupabaseFirst({
    required Future<Stream<MaslakiRealtimeEvent>?> Function() openRealtime,
    required Stream<NotificationLiveEvent> Function() fallback,
  }) {
    late final StreamController<NotificationLiveEvent> controller;
    StreamSubscription<dynamic>? activeSubscription;
    var usingFallback = false;

    Future<void> attachFallback() async {
      if (usingFallback || controller.isClosed) return;
      usingFallback = true;
      await activeSubscription?.cancel();
      activeSubscription = fallback().listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
      );
    }

    Future<void> bootstrap() async {
      try {
        final realtimeStream = await openRealtime();
        if (realtimeStream == null) {
          await attachFallback();
          return;
        }
        controller.add(
          const NotificationLiveEvent(
            event: 'connected',
            data: <String, dynamic>{},
          ),
        );
        activeSubscription = realtimeStream.listen(
          (event) {
            controller.add(
              NotificationLiveEvent(
                event: event.event,
                data: event.data,
                eventId: event.eventId,
              ),
            );
          },
          onError: (_) => unawaited(attachFallback()),
          onDone: () => unawaited(attachFallback()),
          cancelOnError: false,
        );
      } catch (_) {
        await attachFallback();
      }
    }

    controller = StreamController<NotificationLiveEvent>(
      onListen: () {
        unawaited(bootstrap());
      },
      onCancel: () async {
        await activeSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<NotificationLiveEvent> _streamEventsViaSse({
    int? lastEventId,
    required String channel,
  }) async* {
    final response = await dio.get<ResponseBody>(
      '/api/notifications/stream',
      queryParameters: {
        'channel': channel,
        if (lastEventId != null && lastEventId > 0) 'lastEventId': lastEventId,
      },
      options: Options(
        responseType: ResponseType.stream,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(hours: 1),
        headers: {
          'Accept': 'text/event-stream',
          'X-Realtime-Channel': channel,
          if (lastEventId != null && lastEventId > 0)
            'Last-Event-ID': '$lastEventId',
        },
      ),
    );

    final body = response.data;
    if (body == null) return;

    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    String eventName = 'message';
    var dataBuffer = '';
    int? parsedEventId;

    await for (final line in lines) {
      if (line.startsWith('retry:')) {
        continue;
      }

      if (line.startsWith('id:')) {
        parsedEventId = int.tryParse(line.substring(3).trim());
        continue;
      }

      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
        continue;
      }

      if (line.startsWith('data:')) {
        final chunk = line.substring(5).trimLeft();
        dataBuffer = dataBuffer.isEmpty ? chunk : '$dataBuffer\n$chunk';
        continue;
      }

      if (line.isNotEmpty) continue;
      if (dataBuffer.isEmpty) {
        eventName = 'message';
        continue;
      }

      final data = _parseSsePayload(dataBuffer);
      yield NotificationLiveEvent(
        event: eventName,
        data: data,
        eventId: parsedEventId,
      );
      eventName = 'message';
      dataBuffer = '';
      parsedEventId = null;
    }
  }

  bool _matchesThreadEvent(Map<String, dynamic> data, int threadId) {
    final rawThreadId =
        data['threadId'] ??
        data['thread_id'] ??
        (data['message'] is Map
            ? (data['message'] as Map)['threadId']
            : null) ??
        (data['message'] is Map ? (data['message'] as Map)['thread_id'] : null);
    return int.tryParse('$rawThreadId') == threadId;
  }

  Map<String, dynamic> _parseSsePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {'value': decoded};
    } catch (_) {
      return {'raw': raw};
    }
  }
}
