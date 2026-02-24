import 'package:dio/dio.dart';

import '../../../core/files/local_image_file.dart';

class OwnerApi {
  final Dio dio;

  OwnerApi(this.dio);

  Future<Map<String, dynamic>> getMerchant() async {
    final response = await dio.get('/api/owner/merchant');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateMerchant(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final requestData = await _withOptionalImage(body, imageFile: imageFile);
    final response = await dio.put('/api/owner/merchant', data: requestData);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> listCategories() async {
    final response = await dio.get('/api/owner/categories');
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createCategory(Map<String, dynamic> body) async {
    final response = await dio.post('/api/owner/categories', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateCategory(
    int categoryId,
    Map<String, dynamic> body,
  ) async {
    final response = await dio.put(
      '/api/owner/categories/$categoryId',
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteCategory(int categoryId) async {
    await dio.delete('/api/owner/categories/$categoryId');
  }

  Future<List<dynamic>> listProducts() async {
    final response = await dio.get('/api/owner/products');
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final requestData = await _withOptionalImage(body, imageFile: imageFile);
    final response = await dio.post('/api/owner/products', data: requestData);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateProduct(
    int productId,
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final requestData = await _withOptionalImage(body, imageFile: imageFile);
    final response = await dio.put(
      '/api/owner/products/$productId',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteProduct(int productId) async {
    await dio.delete('/api/owner/products/$productId');
  }

  Future<List<dynamic>> listDeliveryAgents() async {
    final response = await dio.get('/api/owner/delivery-agents');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> listCurrentOrders() async {
    final response = await dio.get('/api/owner/orders/current');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> listOrderHistory({String? date}) async {
    final response = await dio.get(
      '/api/owner/orders/history',
      queryParameters: date == null ? null : {'date': date},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<void> updateOrderStatus({
    required int orderId,
    required String status,
    int? estimatedPrepMinutes,
    int? estimatedDeliveryMinutes,
  }) async {
    await dio.patch(
      '/api/owner/orders/$orderId/status',
      data: {
        'status': status,
        'estimatedPrepMinutes': estimatedPrepMinutes,
        'estimatedDeliveryMinutes': estimatedDeliveryMinutes,
      },
    );
  }

  Future<void> assignDelivery({
    required int orderId,
    required int deliveryUserId,
  }) async {
    await dio.patch(
      '/api/owner/orders/$orderId/assign-delivery',
      data: {'deliveryUserId': deliveryUserId},
    );
  }

  Future<Map<String, dynamic>> analytics() async {
    final response = await dio.get('/api/owner/analytics');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> ordersPrintReport({required String period}) async {
    final response = await dio.get(
      '/api/owner/orders/print-report',
      queryParameters: {'period': period},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> settlementSummary() async {
    final response = await dio.get('/api/owner/settlements/summary');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> requestSettlement({String? note}) async {
    final response = await dio.post(
      '/api/owner/settlements/request',
      data: {'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}

Future<Object> _withOptionalImage(
  Map<String, dynamic> body, {
  required LocalImageFile? imageFile,
}) async {
  if (imageFile == null) return body;
  final map = <String, dynamic>{
    ...body,
    'imageFile': await imageFile.toMultipartFile(),
  };
  return FormData.fromMap(map);
}
