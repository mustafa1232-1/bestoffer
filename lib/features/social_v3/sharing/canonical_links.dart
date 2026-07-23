import '../media/social_media_presentation.dart';

/// Builds canonical, shareable application URLs for social entities and
/// guarantees no internal/media URL is ever leaked (§9/§11 hard rule).
class SocialCanonicalLinks {
  const SocialCanonicalLinks({
    this.baseUrl = 'https://maslaki.app',
    this.reelOpenBaseUrl = 'https://bestoffer-production.up.railway.app',
  });

  final String baseUrl;
  final String reelOpenBaseUrl;

  String reel(int reelId) => '$reelOpenBaseUrl/r/$reelId';
  String post(int postId) => '$baseUrl/p/$postId';
  String story(int userId, int storyId) => '$baseUrl/s/$userId/$storyId';
  String profile(int userId) => '$baseUrl/u/$userId';
  String userReelDeepLink(int reelId) => 'maslaki-user://open/reel/$reelId';

  String externalReelShareText(int reelId) {
    final canonical = guardShareUrl(reel(reelId));
    return '$canonical\n${userReelDeepLink(reelId)}';
  }

  /// Asserts a URL about to be shared externally is a canonical app link, never
  /// an HLS manifest, R2 storage key, temporary upload URL, or internal API
  /// route. Returns the URL if safe; throws in debug and returns a safe empty
  /// string in release for anything unsafe.
  String guardShareUrl(String url) {
    assert(() {
      if (!isSafeShareUrl(url)) {
        throw AssertionError('Refusing to share a non-canonical URL: $url');
      }
      return true;
    }());
    return isSafeShareUrl(url) ? url : '';
  }
}

/// Pure predicate: true only for a canonical, externally-shareable URL.
bool isSafeShareUrl(String url) {
  final value = url.trim().toLowerCase();
  if (value.isEmpty) return false;
  if (isStreamingManifestUrl(value) || isVideoFileUrl(value)) return false;
  if (_isPublicRailwayReelOpenUrl(value)) return true;
  // Reject storage/provider/internal hosts and API routes.
  const forbidden = [
    'videodelivery.net',
    'cloudflarestream.com',
    '.r2.',
    'r2.cloudflarestorage.com',
    '/api/',
    'upload.videodelivery',
    'railway.app',
    'format=hls',
  ];
  if (forbidden.any(value.contains)) return false;
  return value.startsWith('http://') || value.startsWith('https://');
}

bool _isPublicRailwayReelOpenUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https') return false;
  if (uri.host != 'bestoffer-production.up.railway.app') return false;
  final segments = uri.pathSegments;
  if (segments.length != 2 || segments.first != 'r') return false;
  final id = int.tryParse(segments.last);
  return id != null && id > 0 && uri.query.isEmpty && uri.fragment.isEmpty;
}
