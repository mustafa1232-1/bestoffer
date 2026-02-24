import 'package:dio/dio.dart';

class DeliveryApi {
  final Dio dio;

  DeliveryApi(this.dio);

  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    final response = await dio.post('/api/delivery/register', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> currentOrders() async {
    final response = await dio.get('/api/delivery/orders/current');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> history({String? date}) async {
    final response = await dio.get(
      '/api/delivery/orders/history',
      queryParameters: date == null ? null : {'date': date},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<void> claimOrder(int orderId) async {
    await dio.patch('/api/delivery/orders/$orderId/claim');
  }

  Future<void> startOrder(int orderId, {int? estimatedDeliveryMinutes}) async {
    await dio.patch(
      '/api/delivery/orders/$orderId/start',
      data: {'estimatedDeliveryMinutes': estimatedDeliveryMinutes},
    );
  }

  Future<void> markDelivered(int orderId) async {
    await dio.patch('/api/delivery/orders/$orderId/delivered');
  }

  Future<Map<String, dynamic>> endDay({String? date}) async {
    final response = await dio.post(
      '/api/delivery/end-day',
      data: {'date': date},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> analytics() async {
    final response = await dio.get('/api/delivery/analytics');
    return Map<String, dynamic>.from(response.data as Map);
  }
}
