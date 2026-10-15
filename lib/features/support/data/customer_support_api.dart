import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';

/// عميل واجهة الدعم لجانب المستخدم النهائي: إنشاء تذكرة + قائمة تذاكري.
/// يستدعي نفس نقاط الباك اند العامة (`/api/support/tickets`).
class CustomerSupportApi {
  final Dio dio;
  CustomerSupportApi(this.dio);

  Future<Map<String, dynamic>> createTicket({
    required String domain,
    required String type,
    required String subject,
    String? description,
    String priority = 'normal',
    String? entityType,
    int? entityId,
    String? entityLabel,
  }) async {
    // الربط بكيان يتطلب النوع والمعرّف معاً — وإلا لا نرسل نوعاً معلّقاً.
    final hasEntity =
        entityType != null &&
        entityType.trim().isNotEmpty &&
        entityId != null &&
        entityId > 0;
    final body = <String, dynamic>{
      'domain': domain,
      'type': type,
      'subject': subject.trim(),
      'priority': priority,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (hasEntity) 'entityType': entityType.trim(),
      if (hasEntity) 'entityId': entityId,
      if (entityLabel != null && entityLabel.trim().isNotEmpty)
        'entityLabel': entityLabel.trim(),
    };
    final response = await dio.post('/api/support/tickets', data: body);
    final data = response.data;
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    return map['ticket'] is Map
        ? Map<String, dynamic>.from(map['ticket'] as Map)
        : Map<String, dynamic>.from(map);
  }

  Future<List<Map<String, dynamic>>> myTickets({
    String? status,
    int limit = 25,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/support/tickets/mine',
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    final data = response.data;
    final list = data is Map ? (data['items'] as List?) : (data as List?);
    return (list ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> ticketDetails(int ticketId) async {
    final response = await dio.get('/api/support/tickets/$ticketId');
    final data = response.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> addMessage(
    int ticketId, {
    required String body,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final response = await dio.post(
      '/api/support/tickets/$ticketId/messages',
      data: {
        'body': body.trim(),
        if (attachments.isNotEmpty) 'attachments': attachments,
      },
    );
    final data = response.data;
    final Map<String, dynamic> map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    return map['message'] is Map
        ? Map<String, dynamic>.from(map['message'] as Map)
        : map;
  }

  Future<Map<String, dynamic>> reopenTicket(
    int ticketId, {
    String? reason,
  }) async {
    final response = await dio.post(
      '/api/support/tickets/$ticketId/reopen',
      data: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    final data = response.data;
    final Map<String, dynamic> map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    return map['ticket'] is Map
        ? Map<String, dynamic>.from(map['ticket'] as Map)
        : map;
  }
}

final customerSupportApiProvider = Provider<CustomerSupportApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return CustomerSupportApi(dio);
});
