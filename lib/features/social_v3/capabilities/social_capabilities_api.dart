import 'package:dio/dio.dart';

import 'social_capabilities.dart';

/// Fetches authoritative social capabilities. Any failure returns the
/// fail-closed default — a network error must never enable scoped stories.
class SocialCapabilitiesApi {
  const SocialCapabilitiesApi(this._dio);

  final Dio _dio;

  Future<SocialCapabilities> fetch() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/feed/capabilities',
      );
      final data = res.data;
      if (data == null) return SocialCapabilities.failClosed;
      return SocialCapabilities.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return SocialCapabilities.failClosed;
    }
  }
}
