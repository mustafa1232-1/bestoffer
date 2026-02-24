import 'package:dio/dio.dart';

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
}
