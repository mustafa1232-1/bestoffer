import 'package:dio/dio.dart';

import '../../../core/files/local_image_file.dart';

class AdminApi {
  final Dio dio;

  AdminApi(this.dio);

  Future<Map<String, dynamic>> analytics() async {
    final response = await dio.get('/api/admin/analytics');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> ordersPrintReport({required String period}) async {
    final response = await dio.get(
      '/api/admin/orders/print-report',
      queryParameters: {'period': period},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> pendingMerchants() async {
    final response = await dio.get('/api/admin/merchants/pending');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> merchants() async {
    final response = await dio.get('/api/admin/merchants');
    return List<dynamic>.from(response.data as List);
  }

  Future<void> approveMerchant(int merchantId) async {
    await dio.patch('/api/admin/merchants/$merchantId/approve');
  }

  Future<void> toggleMerchantDisabled({
    required int merchantId,
    required bool isDisabled,
  }) async {
    await dio.patch(
      '/api/admin/merchants/$merchantId/disabled',
      data: {'isDisabled': isDisabled},
    );
  }

  Future<List<dynamic>> pendingSettlements() async {
    final response = await dio.get('/api/admin/settlements/pending');
    return List<dynamic>.from(response.data as List);
  }

  Future<void> approveSettlement(int settlementId, {String? adminNote}) async {
    await dio.patch(
      '/api/admin/settlements/$settlementId/approve',
      data: {'adminNote': adminNote},
    );
  }

  Future<Map<String, dynamic>> createUser(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final data = imageFile == null
        ? body
        : FormData.fromMap({
            ...body,
            'imageFile': await imageFile.toMultipartFile(),
          });
    final response = await dio.post('/api/admin/users', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> availableOwners() async {
    final response = await dio.get('/api/admin/owners/available');
    return List<dynamic>.from(response.data as List);
  }
}
