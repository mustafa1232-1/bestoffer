import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';

final paidUpgradesApiProvider = Provider<PaidUpgradesApi>((ref) {
  return PaidUpgradesApi(ref.read(dioClientProvider).dio);
});

class PaidUpgradesApi {
  final Dio dio;

  PaidUpgradesApi(this.dio);

  Future<List<Map<String, dynamic>>> listPlans() async {
    final response = await dio.get('/api/paid-upgrades/plans');
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> me() async {
    final response = await dio.get('/api/paid-upgrades/me');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listMyRequests({
    String status = 'all',
    int limit = 30,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/paid-upgrades/requests',
      queryParameters: {
        'status': status,
        'limit': limit,
        'offset': offset,
      },
    );
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createRequests(Map<String, dynamic> body) async {
    final response = await dio.post('/api/paid-upgrades/requests', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> cancelRequest(int requestId) async {
    await dio.post('/api/paid-upgrades/requests/$requestId/cancel');
  }

  Future<List<Map<String, dynamic>>> listAdminRequests({
    String status = 'pending_admin_review',
    String? planCode,
    int limit = 30,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/admin/paid-upgrades/requests',
      queryParameters: {
        'status': status,
        if (planCode != null && planCode.trim().isNotEmpty) 'planCode': planCode.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    final raw = response.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<void> approveRequest(int requestId, {String? reviewNote}) async {
    await dio.patch(
      '/api/admin/paid-upgrades/requests/$requestId/approve',
      data: {
        if ((reviewNote ?? '').trim().isNotEmpty) 'reviewNote': reviewNote!.trim(),
      },
    );
  }

  Future<void> rejectRequest(int requestId, {String? reviewNote}) async {
    await dio.patch(
      '/api/admin/paid-upgrades/requests/$requestId/reject',
      data: {
        if ((reviewNote ?? '').trim().isNotEmpty) 'reviewNote': reviewNote!.trim(),
      },
    );
  }

  Future<void> activateRequest(int requestId) async {
    await dio.patch('/api/admin/paid-upgrades/requests/$requestId/activate');
  }
}
