import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/files/local_image_file.dart';

class OrdersApi {
  final Dio dio;

  OrdersApi(this.dio);

  Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final data = await _withOptionalOrderImage(body, imageFile);
    final response = await dio.post('/api/orders', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> listMyOrders() async {
    final response = await dio.get('/api/orders/my');
    return List<dynamic>.from(response.data as List);
  }

  Future<void> confirmDelivered(int orderId) async {
    await dio.post('/api/orders/$orderId/confirm-delivered');
  }

  Future<void> rateDelivery({
    required int orderId,
    required int rating,
    String? review,
  }) async {
    await dio.post(
      '/api/orders/$orderId/rate-delivery',
      data: {'rating': rating, 'review': review},
    );
  }

  Future<void> rateMerchant({
    required int orderId,
    required int rating,
    String? review,
  }) async {
    await dio.post(
      '/api/orders/$orderId/rate-merchant',
      data: {'rating': rating, 'review': review},
    );
  }

  Future<void> reorder({required int orderId, String? note}) async {
    await dio.post('/api/orders/$orderId/reorder', data: {'note': note});
  }

  Future<List<int>> listFavoriteProductIds() async {
    final response = await dio.get('/api/orders/favorites/ids');
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = List<dynamic>.from(map['productIds'] as List? ?? const []);
    return raw.map((e) => int.tryParse('$e') ?? 0).where((e) => e > 0).toList();
  }

  Future<void> addFavoriteProduct(int productId) async {
    await dio.post('/api/orders/favorites/$productId');
  }

  Future<void> removeFavoriteProduct(int productId) async {
    await dio.delete('/api/orders/favorites/$productId');
  }

  Future<List<dynamic>> listDeliveryAddresses() async {
    final response = await dio.get('/api/auth/account/addresses');
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createDeliveryAddress(
    Map<String, dynamic> body,
  ) async {
    final response = await dio.post('/api/auth/account/addresses', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateDeliveryAddress(
    int addressId,
    Map<String, dynamic> body,
  ) async {
    final response = await dio.put(
      '/api/auth/account/addresses/$addressId',
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> setDefaultDeliveryAddress(int addressId) async {
    final response = await dio.patch(
      '/api/auth/account/addresses/$addressId/default',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteDeliveryAddress(int addressId) async {
    await dio.delete('/api/auth/account/addresses/$addressId');
  }
}

Future<Object> _withOptionalOrderImage(
  Map<String, dynamic> body,
  LocalImageFile? imageFile,
) async {
  if (imageFile == null) return body;

  final map = <String, dynamic>{
    ...body,
    'items': jsonEncode(body['items']),
    'imageFile': await imageFile.toMultipartFile(),
  };
  return FormData.fromMap(map);
}
