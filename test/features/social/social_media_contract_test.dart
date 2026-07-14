import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maslaki/core/files/media_picker_service.dart';
import 'package:social_core/social_core.dart';

void main() {
  test('SocialMediaAsset parses stream playback contract fields', () {
    final asset = SocialMediaAsset.fromJson({
      'id': 42,
      'provider': 'stream',
      'streamUid': 'stream-uid-42',
      'normalizedUrl': 'https://customer-test.cloudflarestream.com/stream-uid-42/manifest/video.m3u8',
      'posterUrl': 'https://customer-test.cloudflarestream.com/stream-uid-42/thumbnails/thumbnail.jpg?time=1s',
      'playbackUrl': 'https://customer-test.cloudflarestream.com/stream-uid-42/manifest/video.m3u8',
      'thumbnailUrl': 'https://customer-test.cloudflarestream.com/stream-uid-42/thumbnails/thumbnail.jpg?time=1s',
      'durationMs': 42000,
      'processingStatus': 'ready',
    });

    expect(asset.id, 42);
    expect(asset.provider, 'stream');
    expect(asset.streamUid, 'stream-uid-42');
    expect(asset.playbackUrl, contains('/manifest/video.m3u8'));
    expect(asset.thumbnailUrl, contains('/thumbnails/thumbnail.jpg'));
  });

  test('SocialPost resolves stream-backed playback and poster urls', () {
    final post = SocialPost.fromJson({
      'id': 7,
      'userId': 3,
      'postKind': 'reel',
      'audienceScopeType': 'global',
      'caption': 'stream reel',
      'mediaKind': 'video',
      'asset': {
        'id': 77,
        'provider': 'stream',
        'streamUid': 'stream-uid-77',
        'normalizedUrl': 'https://customer-test.cloudflarestream.com/stream-uid-77/manifest/video.m3u8',
        'posterUrl': 'https://customer-test.cloudflarestream.com/stream-uid-77/thumbnails/thumbnail.jpg?time=1s',
        'playbackUrl': 'https://customer-test.cloudflarestream.com/stream-uid-77/manifest/video.m3u8',
        'thumbnailUrl': 'https://customer-test.cloudflarestream.com/stream-uid-77/thumbnails/thumbnail.jpg?time=1s',
        'durationMs': 31500,
        'processingStatus': 'ready',
      },
      'author': {'id': 3, 'fullName': 'Tester', 'role': 'user'},
      'likesCount': 0,
      'commentsCount': 0,
      'savesCount': 0,
      'impressionsCount': 0,
      'reelViewsCount': 0,
      'isLiked': false,
      'isSaved': false,
      'reportCount': 0,
    });

    expect(resolveSocialPostPosterUrl(post), contains('/thumbnails/thumbnail.jpg'));
    expect(resolveSocialPostVideoUrl(post), contains('/manifest/video.m3u8'));
  });

  test('gallery picker helper keeps order and max limit', () {
    final picked = buildLocalMediaFilesFromPickedMedia(
      [
        XFile('/tmp/first.jpg', name: 'first.jpg', mimeType: 'image/jpeg'),
        XFile('/tmp/second.mp4', name: 'second.mp4', mimeType: 'video/mp4'),
        XFile('/tmp/third.webp', name: 'third.webp', mimeType: 'image/webp'),
      ],
      maxFiles: 2,
    );

    expect(picked, hasLength(2));
    expect(picked.first.name, isNotEmpty);
    expect(picked.first.path, '/tmp/first.jpg');
    expect(picked.first.mimeType, 'image/jpeg');
    expect(picked.last.name, isNotEmpty);
    expect(picked.last.path, '/tmp/second.mp4');
    expect(picked.last.mimeType, 'video/mp4');
  });
}
