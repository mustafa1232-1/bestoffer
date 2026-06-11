import 'package:dio/dio.dart';

class AccountantApi {
  final Dio dio;

  AccountantApi(this.dio);

  Future<Map<String, dynamic>> getSummary() async {
    final response = await dio.get('/api/accountant/summary');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> listPendingSettlements({int limit = 100}) async {
    final response = await dio.get(
      '/api/accountant/pending-delivery-settlements',
      queryParameters: {'limit': limit},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> confirmSettlement({
    required int settlementId,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/accountant/pending-delivery-settlements/$settlementId/confirm',
      data: {'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> addOpeningBalance({
    required num amount,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/accountant/opening-balance',
      data: {'amount': amount, 'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> addExpense({
    required num amount,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/accountant/expenses',
      data: {'amount': amount, 'note': note},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> listLedger({int limit = 100}) async {
    final response = await dio.get(
      '/api/accountant/ledger',
      queryParameters: {'limit': limit},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> listPendingPayrollBatches({
    int limit = 60,
  }) async {
    final response = await dio.get(
      '/api/accountant/payroll/pending-batches',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getPayrollBatch(int batchId) async {
    final response = await dio.get('/api/accountant/payroll/batches/$batchId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> acknowledgePayrollBatch(int batchId) async {
    final response = await dio.post(
      '/api/accountant/payroll/batches/$batchId/acknowledge',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> markPayrollItemPaid({
    required int itemId,
    String? payoutNote,
  }) async {
    final response = await dio.post(
      '/api/accountant/payroll/items/$itemId/pay',
      data: {'payoutNote': payoutNote},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
