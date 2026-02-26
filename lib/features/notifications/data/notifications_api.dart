import 'dart:convert';

import 'package:dio/dio.dart';

class NotificationLiveEvent {
  final String event;
  final Map<String, dynamic> data;

  const NotificationLiveEvent({required this.event, required this.data});
}

class NotificationsApi {
  final Dio dio;

  NotificationsApi(this.dio);

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
  }) async {
    await dio.post(
      '/api/notifications/push-token',
      data: {
        'token': token,
        'platform': platform,
        'appVersion': appVersion,
        'deviceModel': deviceModel,
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

  Stream<NotificationLiveEvent> streamEvents() async* {
    final response = await dio.get<ResponseBody>(
      '/api/notifications/stream',
      options: Options(
        responseType: ResponseType.stream,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(hours: 1),
        headers: const {'Accept': 'text/event-stream'},
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

    await for (final line in lines) {
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
      yield NotificationLiveEvent(event: eventName, data: data);
      eventName = 'message';
      dataBuffer = '';
    }
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
