import 'package:maslaki/features/social/models/social_models.dart';
import 'package:maslaki/features/social/models/social_story_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SocialStoryDraft restores reel-share documents from story style', () {
    final story = SocialStory.fromJson({
      'id': 11,
      'userId': 7,
      'caption': 'Shared reel',
      'mediaUrl': null,
      'mediaKind': null,
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

    final draft = SocialStoryDraft.fromStoryStyle(story: story);
    expect(draft.mode, SocialStoryComposerMode.reelShare);
    expect(draft.attachment?.isReelShare, isTrue);
    expect(draft.attachment?.reelId, 42);
    expect(draft.attachment?.mediaAssetId, 77);
    expect(draft.attachment?.streamUid, 'stream-uid-77');
    expect(draft.attachment?.authorId, 7);
    expect(draft.attachment?.playbackUrl, 'https://example.com/playback.m3u8');
    expect(draft.attachment?.thumbnailUrl, 'https://example.com/thumb.jpg');
    expect(draft.background.type, SocialStoryBackgroundType.posterBlur);
    expect(draft.layers.single.type, SocialStoryLayerType.reelShare);

    final json = draft.toStoryStyleJson();
    expect(json['mode'], 'reelShare');
    expect((json['attachment'] as Map<String, dynamic>)['reelId'], 42);
    expect((json['attachment'] as Map<String, dynamic>)['mediaAssetId'], 77);
    expect(
      (json['attachment'] as Map<String, dynamic>)['streamUid'],
      'stream-uid-77',
    );
    expect((json['attachment'] as Map<String, dynamic>)['type'], 'reel_share');
    expect((json['layers'] as List).single['type'], 'reelShare');
  });

  test('buildReelShareDraft uses username-first author label', () {
    final draft = buildReelShareDraft(
      SocialReelItem(
        post: SocialPost.fromJson({
          'id': 14,
          'userId': 8,
          'postKind': 'reel',
          'caption': 'Watch this',
          'likesCount': 0,
          'commentsCount': 0,
          'savesCount': 0,
          'impressionsCount': 0,
          'reelViewsCount': 0,
          'isLiked': false,
          'isSaved': false,
          'reportCount': 0,
          'author': {
            'id': 8,
            'username': 'basmaya.creator',
            'fullName': 'Basmaya Creator',
            'role': 'user',
          },
        }),
        metrics: const SocialReelMetrics(
          impressionsCount: 0,
          viewsCount: 0,
          averageWatchDurationMs: 0,
          averageCompletionRate: 0,
          replayCount: 0,
        ),
      ),
    );

    expect(draft.attachment?.authorName, '@basmaya.creator');
    expect(draft.layers.single.type, SocialStoryLayerType.reelShare);
  });

  test(
    'SocialStory parses authoritative interaction settings with safe defaults',
    () {
      final defaultStory = SocialStory.fromJson({
        'id': 19,
        'userId': 7,
        'caption': 'Default flags',
        'isViewed': false,
        'isMine': false,
        'likesCount': 0,
        'commentsCount': 0,
        'isLiked': false,
        'createdAt': '2026-03-28T08:00:00.000Z',
        'expiresAt': '2026-03-29T08:00:00.000Z',
      });
      expect(defaultStory.allowLikes, isTrue);
      expect(defaultStory.allowPrivateReplies, isTrue);
      expect(defaultStory.allowComments, isTrue);
      expect(defaultStory.allowSharing, isTrue);
      expect(defaultStory.allowReshare, isTrue);

      final lockedStory = SocialStory.fromJson({
        'id': 20,
        'userId': 7,
        'caption': 'Locked flags',
        'storyInteractionSettings': {
          'allowLikes': false,
          'allowPrivateReplies': false,
          'allowComments': false,
          'allowSharing': false,
          'allowReshare': false,
        },
        'isViewed': false,
        'isMine': false,
        'likesCount': 0,
        'commentsCount': 0,
        'isLiked': false,
        'createdAt': '2026-03-28T08:00:00.000Z',
        'expiresAt': '2026-03-29T08:00:00.000Z',
      });

      expect(lockedStory.allowLikes, isFalse);
      expect(lockedStory.allowPrivateReplies, isFalse);
      expect(lockedStory.allowComments, isFalse);
      expect(lockedStory.allowSharing, isFalse);
      expect(lockedStory.allowReshare, isFalse);
    },
  );
}
