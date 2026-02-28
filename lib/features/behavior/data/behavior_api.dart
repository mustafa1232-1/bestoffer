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
}
