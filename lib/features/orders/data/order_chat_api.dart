import 'package:dio/dio.dart';

class OrderChatApi {
  final Dio dio;

  OrderChatApi(this.dio);

  Future<Map<String, dynamic>> listMessages(
    int orderId, {
    int limit = 120,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (beforeId != null) query['beforeId'] = beforeId;
    final response = await dio.get(
      '/api/orders/$orderId/chat/messages',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> sendMessage(
    int orderId,
    String message,
  ) async {
    final response = await dio.post(
      '/api/orders/$orderId/chat/messages',
      data: {'message': message},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
