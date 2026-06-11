import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';

final behaviorApiProvider = Provider<BehaviorApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return BehaviorApi(dio);
});

class BehaviorApi {
  final Dio _dio;

  BehaviorApi(this._dio);

  Future<void> trackEvent({
    required String eventName,
    String? category,
    String? action,
    String source = 'app_ui',
    String? entityType,
    int? entityId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _dio.post(
        '/api/behavior/events',
        data: {
          'eventName': eventName,
          if (category != null && category.trim().isNotEmpty)
            'category': category.trim(),
          if (action != null && action.trim().isNotEmpty)
            'action': action.trim(),
          'source': source,
          if (entityType != null && entityType.trim().isNotEmpty)
            'entityType': entityType.trim(),
          if (entityId != null && entityId > 0) 'entityId': entityId,
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        },
      );
    } catch (_) {
      // Analytics tracking must never break user flow.
    }
  }

  Future<BehaviorEventsPage> myEvents({int limit = 80, int? beforeId}) async {
    final response = await _dio.get(
      '/api/behavior/events/me',
      queryParameters: {
        'limit': limit,
        if (beforeId != null && beforeId > 0) 'beforeId': beforeId,
      },
    );
    final data = response.data;
    if (data is List) {
      final items = List<dynamic>.from(data)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
      return BehaviorEventsPage(items: items, nextCursor: null);
    }
    final map = Map<String, dynamic>.from((data as Map?) ?? const {});
    final raw = List<dynamic>.from(map['items'] as List? ?? const []);
    final items = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final nextCursor = int.tryParse('${map['nextCursor'] ?? ''}');
    return BehaviorEventsPage(items: items, nextCursor: nextCursor);
  }

  Future<Map<String, dynamic>> myInsights() async {
    final response = await _dio.get('/api/behavior/insights/me');
    return Map<String, dynamic>.from((response.data as Map?) ?? const {});
  }
}

class BehaviorEventsPage {
  final List<Map<String, dynamic>> items;
  final int? nextCursor;

  const BehaviorEventsPage({required this.items, required this.nextCursor});
}
