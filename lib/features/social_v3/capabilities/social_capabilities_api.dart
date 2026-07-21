import 'package:dio/dio.dart';

import 'social_capabilities.dart';
import '../upload/reel_map_normalizer.dart';

/// Fetches authoritative social capabilities. Any failure returns the
/// fail-closed default — a network error must never enable scoped stories.
class SocialCapabilitiesApi {
  const SocialCapabilitiesApi(this._dio);

  final Dio _dio;

  Future<SocialCapabilities> fetch() async {
    try {
      final res = await _dio.get<dynamic>('/api/feed/capabilities');
      final data = res.data;
      if (data == null) return SocialCapabilities.failClosed;
      return SocialCapabilities.fromJson(
        normalizeReelMap(data, 'SOCIAL_CAPABILITIES_INVALID_RESPONSE'),
      );
    } catch (_) {
      return SocialCapabilities.failClosed;
    }
  }
}
