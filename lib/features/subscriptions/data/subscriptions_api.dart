import 'package:dio/dio.dart';

/// Thin HTTP layer for the merchant monthly subscription debt lifecycle.
/// Admin/backoffice endpoints live under /api/admin/merchant-subscriptions;
/// the store-owner read view is served by the owner module.
class SubscriptionsApi {
  final Dio dio;

  SubscriptionsApi(this.dio);

  Future<List<dynamic>> adminListInvoices({
    String? status,
    String? month,
    int limit = 200,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (month != null && month.isNotEmpty) query['month'] = month;
    final response = await dio.get(
      '/api/admin/merchant-subscriptions/invoices',
      queryParameters: query,
    );
    final data = response.data;
    if (data is Map && data['invoices'] is List) {
      return List<dynamic>.from(data['invoices'] as List);
    }
    if (data is List) return List<dynamic>.from(data);
    return const <dynamic>[];
  }

  Future<Map<String, dynamic>> adminGenerate({String? month}) async {
    final response = await dio.post(
      '/api/admin/merchant-subscriptions/generate',
      data: {if (month != null && month.isNotEmpty) 'month': month},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> adminRecordPayment({
    required int invoiceId,
    required num amount,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final response = await dio.post(
      '/api/admin/merchant-subscriptions/invoices/$invoiceId/payments',
      data: {
        'amount': amount,
        'paymentMethod': paymentMethod,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> adminWaive({
    required int invoiceId,
    required String reason,
  }) async {
    final response = await dio.post(
      '/api/admin/merchant-subscriptions/invoices/$invoiceId/waive',
      data: {'reason': reason.trim()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
