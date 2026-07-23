import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/composer/story_composer_source.dart';
import 'package:maslaki/features/social_v3/domain/story_view_data.dart';
import 'package:social_core/social_models.dart';

void main() {
  test('shared reel story keeps poster and playback metadata', () {
    final story = SocialStory.fromJson({
      'id': 11,
      'userId': 7,
      'caption': 'Shared reel',
      'mediaUrl': 'https://example.com/playback.m3u8',
      'mediaKind': 'reel',
      'asset': {
        'provider': 'cloudflare_stream',
        'streamUid': 'stream-uid-77',
        'playbackUrl': 'https://example.com/playback.m3u8',
        'thumbnailUrl': 'https://example.com/thumb.jpg',
        'posterUrl': 'https://example.com/poster.jpg',
        'aspectRatio': 0.5625,
        'processingStatus': 'ready',
      },
      'storyStyle': {
        'version': 2,
        'mode': 'reelShare',
        'background': {
          'type': 'posterBlur',
          'primaryColor': '#0F172A',
          'secondaryColor': '#1D4ED8',
          'imageUrl': 'https://example.com/poster.jpg',
        },
        'attachment': {
          'type': 'reel_share',
          'reelId': 42,
          'mediaAssetId': 77,
          'streamUid': 'stream-uid-77',
          'authorId': 7,
          'authorName': 'Ali',
          'posterUrl': 'https://example.com/poster.jpg',
          'caption': 'Nice reel',
          'mediaUrl': 'https://example.com/playback.m3u8',
          'playbackUrl': 'https://example.com/playback.m3u8',
          'thumbnailUrl': 'https://example.com/thumb.jpg',
          'mediaKind': 'video',
          'aspectRatio': 0.5625,
          'label': 'Watch reel',
        },
        'layers': [
          {
            'id': 'text-1',
            'type': 'text',
            'x': 0.5,
            'y': 0.2,
            'scale': 1.0,
            'rotation': 0.0,
            'zIndex': 10,
            'text': 'My edit',
            'color': '#FFFFFF',
            'fontWeight': 'bold',
            'textAlign': 'center',
          },
          {
            'id': 'reel-card',
            'type': 'reelShare',
            'x': 0.5,
            'y': 0.56,
            'scale': 1.0,
            'rotation': 0.0,
            'zIndex': 20,
            'locked': true,
          },
        ],
      },
      'likesCount': 0,
      'commentsCount': 0,
      'isLiked': false,
      'isViewed': false,
      'isMine': false,
      'createdAt': '2026-03-28T08:00:00.000Z',
      'expiresAt': '2026-03-29T08:00:00.000Z',
    });

    final item = StoryV3Item.fromStory(story);
    expect(item.sharedReel, isNotNull);
    expect(item.isVideo, isTrue);
    expect(item.media.videoPlaybackUrl, 'https://example.com/playback.m3u8');
    expect(item.media.posterImageUrl, 'https://example.com/thumb.jpg');
    expect(item.draft?.layers.any((layer) => layer.text == 'My edit'), isTrue);
    expect(item.sharedReel!.reelId, 42);
    expect(item.sharedReel!.playbackUrl, 'https://example.com/playback.m3u8');
    expect(item.sharedReel!.thumbnailUrl, 'https://example.com/thumb.jpg');
    expect(item.sharedReel!.posterUrl, 'https://example.com/poster.jpg');
    expect(item.sharedReel!.aspectRatio, 0.5625);
    expect(item.sharedReel!.available, isTrue);
    expect(item.sharedReel!.author, 'Ali');

    final source = SharedReelSource.fromReelRef(item.sharedReel!);
    final presentation = source.toPresentation();
    expect(presentation.posterImageUrl, 'https://example.com/thumb.jpg');
    expect(presentation.videoPlaybackUrl, 'https://example.com/playback.m3u8');
    expect(presentation.isReady, isTrue);
  });
}
