// ignore_for_file: use_null_aware_elements

import 'package:dio/dio.dart';
import '../../../core/files/local_image_file.dart';

class HrApi {
  final Dio dio;

  HrApi(this.dio);

  Future<Map<String, dynamic>> getDashboard({int? merchantId}) async {
    final response = await dio.get(
      '/api/hr/dashboard',
      queryParameters: merchantId == null ? null : {'merchantId': merchantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listEmployees({
    int? merchantId,
    String search = '',
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/hr/employees',
      queryParameters: {
        if (merchantId != null) 'merchantId': merchantId,
        'search': search,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> upsertEmployee(Map<String, dynamic> body) async {
    final response = await dio.post('/api/hr/employees/upsert', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listAttendance({
    int? merchantId,
    int? employeeUserId,
    String? dateFrom,
    String? dateTo,
    int limit = 200,
  }) async {
    final response = await dio.get(
      '/api/hr/attendance',
      queryParameters: {
        if (merchantId != null) 'merchantId': merchantId,
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (dateFrom != null) 'dateFrom': dateFrom,
        if (dateTo != null) 'dateTo': dateTo,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> upsertAttendance(
    Map<String, dynamic> body,
  ) async {
    final response = await dio.post('/api/hr/attendance/upsert', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> buildPayroll(Map<String, dynamic> body) async {
    final response = await dio.post(
      '/api/hr/payroll/batches/build',
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listPayrollBatches({
    int? merchantId,
    String? status,
    int limit = 40,
  }) async {
    final response = await dio.get(
      '/api/hr/payroll/batches',
      queryParameters: {
        if (merchantId != null) 'merchantId': merchantId,
        if (status != null) 'status': status,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getPayrollBatch({
    required int batchId,
    int? merchantId,
  }) async {
    final response = await dio.get(
      '/api/hr/payroll/batches/$batchId',
      queryParameters: merchantId == null ? null : {'merchantId': merchantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> submitPayrollBatch({
    required int batchId,
    int? merchantId,
  }) async {
    final response = await dio.post(
      '/api/hr/payroll/batches/$batchId/submit',
      data: merchantId == null ? {} : {'merchantId': merchantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> closePayrollBatch({
    required int batchId,
    int? merchantId,
  }) async {
    final response = await dio.post(
      '/api/hr/payroll/batches/$batchId/close',
      data: merchantId == null ? {} : {'merchantId': merchantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listLeaveRequests({
    int? merchantId,
    int? employeeUserId,
    String? dateFrom,
    String? dateTo,
    String? status,
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/hr/leave-requests',
      queryParameters: {
        if (merchantId != null) 'merchantId': merchantId,
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (dateFrom != null) 'dateFrom': dateFrom,
        if (dateTo != null) 'dateTo': dateTo,
        if (status != null) 'status': status,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createLeaveRequest(
    Map<String, dynamic> body,
  ) async {
    final response = await dio.post('/api/hr/leave-requests', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> decideLeaveRequest({
    required int leaveId,
    required String status,
    int? merchantId,
    String? decisionNote,
  }) async {
    final response = await dio.post(
      '/api/hr/leave-requests/$leaveId/decide',
      data: {
        'status': status,
        if (merchantId != null) 'merchantId': merchantId,
        if (decisionNote != null && decisionNote.trim().isNotEmpty)
          'decisionNote': decisionNote.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listSalaryActions({
    int? merchantId,
    int? employeeUserId,
    int? periodYear,
    int? periodMonth,
    String? status,
    int limit = 200,
  }) async {
    final response = await dio.get(
      '/api/hr/salary-actions',
      queryParameters: {
        if (merchantId != null) 'merchantId': merchantId,
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (periodYear != null) 'periodYear': periodYear,
        if (periodMonth != null) 'periodMonth': periodMonth,
        if (status != null) 'status': status,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createSalaryAction(
    Map<String, dynamic> body,
  ) async {
    final response = await dio.post('/api/hr/salary-actions', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateSalaryActionStatus({
    required int actionId,
    required String status,
    int? merchantId,
  }) async {
    final response = await dio.post(
      '/api/hr/salary-actions/$actionId/status',
      data: {
        'status': status,
        if (merchantId != null) 'merchantId': merchantId,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getAttendanceArchive({
    int? merchantId,
    required int periodYear,
    required int periodMonth,
  }) async {
    final response = await dio.get(
      '/api/hr/archive/attendance',
      queryParameters: {
        if (merchantId != null) 'merchantId': merchantId,
        'periodYear': periodYear,
        'periodMonth': periodMonth,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> selfCheckIn({
    int? merchantId,
    String? note,
    LocalImageFile? imageFile,
  }) async {
    final data = FormData.fromMap({
      if (merchantId != null) 'merchantId': merchantId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (imageFile != null) 'imageFile': await imageFile.toMultipartFile(),
    });
    final response = await dio.post('/api/hr/attendance/check-in', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> selfCheckOut({
    int? merchantId,
    String? note,
    LocalImageFile? imageFile,
  }) async {
    final data = FormData.fromMap({
      if (merchantId != null) 'merchantId': merchantId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (imageFile != null) 'imageFile': await imageFile.toMultipartFile(),
    });
    final response = await dio.post('/api/hr/attendance/check-out', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> myProfiles({int? merchantId}) async {
    final response = await dio.get(
      '/api/hr/my/profiles',
      queryParameters: merchantId == null ? null : {'merchantId': merchantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listMyAttendance({
    int? merchantId,
    String? dateFrom,
    String? dateTo,
    int limit = 200,
  }) async {
    final response = await dio.get(
      '/api/hr/my/attendance',
      queryParameters: {
        if (merchantId != null) 'merchantId': merchantId,
        if (dateFrom != null) 'dateFrom': dateFrom,
        if (dateTo != null) 'dateTo': dateTo,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listMyLeaveRequests({
    int? merchantId,
    String? status,
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/hr/my/leave-requests',
      queryParameters: {
        if (merchantId != null) 'merchantId': merchantId,
        if (status != null) 'status': status,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createMyLeaveRequest(
    Map<String, dynamic> body,
  ) async {
    final response = await dio.post('/api/hr/my/leave-requests', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listMyAdvanceRequests({
    int? merchantId,
    String? status,
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/hr/my/advance-requests',
      queryParameters: {
        if (merchantId != null) 'merchantId': merchantId,
        if (status != null) 'status': status,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createMyAdvanceRequest(
    Map<String, dynamic> body,
  ) async {
    final response = await dio.post('/api/hr/my/advance-requests', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> listAdvanceRequests({
    int? merchantId,
    int? employeeUserId,
    String? status,
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/hr/advance-requests',
      queryParameters: {
        if (merchantId != null) 'merchantId': merchantId,
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (status != null) 'status': status,
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> decideAdvanceRequest({
    required int requestId,
    required String status,
    int? merchantId,
    String? decisionNote,
    int? effectiveYear,
    int? effectiveMonth,
  }) async {
    final response = await dio.post(
      '/api/hr/advance-requests/$requestId/decide',
      data: {
        'status': status,
        if (merchantId != null) 'merchantId': merchantId,
        if (decisionNote != null && decisionNote.trim().isNotEmpty)
          'decisionNote': decisionNote.trim(),
        if (effectiveYear != null) 'effectiveYear': effectiveYear,
        if (effectiveMonth != null) 'effectiveMonth': effectiveMonth,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
