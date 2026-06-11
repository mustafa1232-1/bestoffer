import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/auth_controller.dart';

final sectionAvailabilityApiProvider = Provider<SectionAvailabilityApi>(
  (ref) => SectionAvailabilityApi(ref.read(dioClientProvider).dio),
);

class SectionAvailabilityApi {
  final Dio dio;

  SectionAvailabilityApi(this.dio);

  Future<List<Map<String, dynamic>>> listAvailability({
    String surfaceScope = 'user',
  }) async {
    final response = await dio.get(
      '/api/sections/availability',
      queryParameters: {'surfaceScope': surfaceScope},
    );
    final raw = response.data;
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }
    if (raw is Map && raw['items'] is List) {
      return List<dynamic>.from(raw['items'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }
}
