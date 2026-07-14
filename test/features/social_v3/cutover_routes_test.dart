import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/ui/social_reels_screen.dart';
import 'package:maslaki/features/social/ui/social_story_quick_viewer.dart';
import 'package:maslaki/features/social_v3/feed/social_feed_reel_preview_v3.dart';
import 'package:maslaki/features/social_v3/media/social_media_presentation.dart';
import 'package:maslaki/features/social_v3/state/social_reels_v3_connector.dart';
import 'package:maslaki/features/social_v3/state/social_story_v3_connector.dart';
import 'package:maslaki/features/social_v3/stories/social_story_viewer_v3.dart';
import 'package:social_core/social_models.dart';

SocialAuthor _author() => const SocialAuthor(
      id: 7,
      username: 'jacki',
      fullName: 'Jacki',
      imageUrl: null,
      phone: null,
      role: 'user',
    );

SocialStory _imageStory(int id) => SocialStory(
      id: id,
      userId: 7,
      caption: 'hi',
      mediaUrl: null,
      mediaKind: 'image',
      asset: null,
      style: SocialStoryStyle.fromJson(const {}),
      isViewed: false,
      isMine: false,
      likesCount: 0,
      commentsCount: 0,
      isLiked: false,
      archivedAt: null,
      createdAt: null,
      expiresAt: null,
    );

SocialStoryGroup _group() => SocialStoryGroup(
      userId: 7,
      author: _author(),
      latestAt: null,
      hasUnviewed: true,
      stories: [_imageStory(1), _imageStory(2)],
    );

void main() {
  group('Reels tab cutover', () {
    testWidgets('SocialReelsScreen (the live tab) builds the V3 connector, '
        'never the old viewer', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                final built = const SocialReelsScreen(initialReelId: 42)
                    .build(context);
                expect(built, isA<SocialReelsV3Connector>());
                expect((built as SocialReelsV3Connector).initialReelId, 42);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });
  });

  group('Story cutover', () {
    testWidgets('showSocialStoryQuickViewer opens the full-screen V3 viewer, '
        'not a bottom sheet', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showSocialStoryQuickViewer(
                    context: context,
                    group: _group(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SocialStoryViewerV3), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('openSocialStoryViewerV3 preserves the initial group',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  openSocialStoryViewerV3(context: context, group: _group()),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final viewer = tester.widget<SocialStoryViewerV3>(
        find.byType(SocialStoryViewerV3),
      );
      expect(viewer.groups.first.userId, 7);
    });
  });

  group('Feed reel preview (§4) regression', () {
    testWidgets('is rectangular, bounded, and never circular', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // Approx. failure-screenshot phone width.
            body: SizedBox(
              width: 432,
              child: SocialFeedReelPreviewV3(
                media: const SocialMediaPresentation(
                  mediaAssetId: 1,
                  provider: 'cloudflare_stream',
                  mediaKind: SocialMediaKind.reel,
                  playbackType: SocialPlaybackType.hls,
                  // Deliberately only a playback URL + null poster: the failure
                  // case. It must NOT become circular or a giant blank.
                  videoPlaybackUrl: 'https://x/manifest/video.m3u8',
                  posterImageUrl: null,
                  width: 1080,
                  height: 1920,
                  durationMs: 15000,
                  processingStatus: SocialProcessingStatus.ready,
                ),
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      // Never circular.
      expect(find.byType(ClipOval), findsNothing);
      expect(find.byType(ClipRRect), findsWidgets);

      // Bounded aspect ratio (portrait, between 9:16 and 4:5).
      final aspect = tester.widget<AspectRatio>(find.byType(AspectRatio).first);
      expect(aspect.aspectRatio, greaterThanOrEqualTo(9 / 16 - 0.001));
      expect(aspect.aspectRatio, lessThanOrEqualTo(4 / 5 + 0.001));

      // Tap opens the viewer (callback fires).
      await tester.tap(find.byType(SocialFeedReelPreviewV3));
      expect(tapped, isTrue);
      // No exception from the manifest-only media (guard degrades gracefully).
      expect(tester.takeException(), isNull);
    });
  });
}
