import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/domain/story_view_data.dart';
import 'package:maslaki/features/social_v3/media/social_media_presentation.dart';
import 'package:maslaki/features/social_v3/state/social_story_v3_connector.dart';
import 'package:maslaki/features/social_v3/stories/social_story_viewer_v3.dart';
import 'package:maslaki/features/social_v3/stories/story_progress_bar_v3.dart';
import 'package:social_core/social_models.dart';

const _media = SocialMediaPresentation(
  mediaAssetId: null,
  provider: null,
  mediaKind: SocialMediaKind.image,
  playbackType: SocialPlaybackType.none,
  videoPlaybackUrl: null,
  posterImageUrl: null,
  width: 1080,
  height: 1920,
  durationMs: null,
  processingStatus: SocialProcessingStatus.ready,
);

StoryV3Item _item({
  required int id,
  bool allowLikes = true,
  bool allowPrivateReplies = true,
  bool allowComments = true,
  bool allowSharing = true,
  bool allowReshare = true,
  bool isLiked = false,
  int likesCount = 0,
  int commentsCount = 0,
  Duration imageDuration = const Duration(seconds: 10),
}) {
  return StoryV3Item(
    storyId: id,
    caption: 'story $id',
    media: _media,
    backgroundColor: const Color(0xFF1E3A8A),
    imageDuration: imageDuration,
    clipStart: null,
    clipDuration: null,
    isLiked: isLiked,
    likesCount: likesCount,
    commentsCount: commentsCount,
    allowLikes: allowLikes,
    allowPrivateReplies: allowPrivateReplies,
    allowComments: allowComments,
    allowSharing: allowSharing,
    allowReshare: allowReshare,
    sharedReel: null,
  );
}

StoryV3Group _v3Group(int userId, List<StoryV3Item> items) {
  return StoryV3Group(
    userId: userId,
    authorName: 'User $userId',
    authorHandle: '@user$userId',
    authorAvatarUrl: null,
    items: items,
  );
}

const _author = SocialAuthor(
  id: 7,
  username: 'story-author',
  fullName: 'Story Author',
  imageUrl: null,
  phone: null,
  role: 'user',
);

SocialStory _sourceStory(
  int id, {
  bool allowLikes = true,
  bool allowPrivateReplies = true,
  bool allowComments = true,
  bool allowSharing = true,
  bool allowReshare = true,
  bool isLiked = false,
  int likesCount = 0,
  int commentsCount = 0,
}) {
  return SocialStory(
    id: id,
    userId: _author.id,
    caption: 'story $id',
    mediaUrl: null,
    mediaKind: 'image',
    asset: null,
    style: SocialStoryStyle.fromJson(const <String, dynamic>{}),
    allowLikes: allowLikes,
    allowPrivateReplies: allowPrivateReplies,
    allowComments: allowComments,
    allowSharing: allowSharing,
    allowReshare: allowReshare,
    isViewed: false,
    isMine: false,
    likesCount: likesCount,
    commentsCount: commentsCount,
    isLiked: isLiked,
    archivedAt: null,
    createdAt: null,
    expiresAt: null,
  );
}

SocialStoryGroup _sourceGroup(int userId, List<SocialStory> stories) {
  return SocialStoryGroup(
    userId: userId,
    author: SocialAuthor(
      id: userId,
      username: 'user$userId',
      fullName: 'User $userId',
      imageUrl: null,
      phone: null,
      role: 'user',
    ),
    latestAt: null,
    hasUnviewed: true,
    stories: stories,
  );
}

Future<void> _pumpViewer(
  WidgetTester tester, {
  required StoryV3Item item,
  StoryV3LikeCallback? onToggleLike,
  StoryV3CommentsCallback? onOpenComments,
  StoryV3ShareCallback? onShare,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SocialStoryViewerV3(
        groups: <StoryV3Group>[
          _v3Group(7, <StoryV3Item>[item]),
        ],
        onToggleLike: onToggleLike,
        onOpenComments: onOpenComments,
        onShare: onShare,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('StoryV3Item interaction mapping', () {
    test('maps all flags plus like/comment state from SocialStory', () {
      final item = StoryV3Item.fromStory(
        _sourceStory(
          41,
          allowLikes: false,
          allowPrivateReplies: false,
          allowComments: true,
          allowSharing: false,
          allowReshare: true,
          isLiked: true,
          likesCount: 12,
          commentsCount: 7,
        ),
      );

      expect(item.allowLikes, isFalse);
      expect(item.allowPrivateReplies, isFalse);
      expect(item.allowComments, isTrue);
      expect(item.allowSharing, isFalse);
      expect(item.allowReshare, isTrue);
      expect(item.isLiked, isTrue);
      expect(item.likesCount, 12);
      expect(item.commentsCount, 7);
    });
  });

  group('SocialStoryViewerV3 live actions', () {
    testWidgets('only renders actions allowed by their story flags', (
      tester,
    ) async {
      final item = _item(
        id: 51,
        allowLikes: true,
        allowPrivateReplies: true,
        allowComments: false,
        allowSharing: true,
        allowReshare: true,
        likesCount: 12,
        commentsCount: 7,
      );

      await _pumpViewer(
        tester,
        item: item,
        onToggleLike: (_) async => const StoryV3LikeResult(),
        onOpenComments: (_) async => 0,
        onShare: (_) async {},
      );

      expect(
        find.byKey(const ValueKey<String>('story-v3-like-51')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('story-v3-comment-51')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('story-v3-share-51')),
        findsOneWidget,
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.byIcon(Icons.reply_rounded), findsNothing);
      expect(find.byIcon(Icons.repeat_rounded), findsNothing);
    });

    testWidgets('like callback updates optimistic state with server result', (
      tester,
    ) async {
      int? toggledStoryId;
      await _pumpViewer(
        tester,
        item: _item(id: 52, likesCount: 2),
        onToggleLike: (storyId) async {
          toggledStoryId = storyId;
          return const StoryV3LikeResult(isLiked: true, likesCount: 3);
        },
      );

      await tester.tap(find.byKey(const ValueKey<String>('story-v3-like-52')));
      await tester.pump();

      expect(toggledStoryId, 52);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets(
      'pauses image progress while comments overlay callback awaits',
      (tester) async {
        final commentsCompleter = Completer<int?>();
        await _pumpViewer(
          tester,
          item: _item(
            id: 53,
            allowLikes: false,
            allowComments: true,
            allowSharing: false,
          ),
          onOpenComments: (_) => commentsCompleter.future,
        );
        await tester.pump(const Duration(milliseconds: 500));

        await tester.tap(
          find.byKey(const ValueKey<String>('story-v3-comment-53')),
        );
        await tester.pump();
        final pausedAt = tester
            .widget<StoryProgressBarV3>(find.byType(StoryProgressBarV3).first)
            .currentProgress;

        await tester.pump(const Duration(seconds: 2));
        final stillPausedAt = tester
            .widget<StoryProgressBarV3>(find.byType(StoryProgressBarV3).first)
            .currentProgress;
        expect(stillPausedAt, closeTo(pausedAt, 0.001));

        commentsCompleter.complete(0);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final resumedAt = tester
            .widget<StoryProgressBarV3>(find.byType(StoryProgressBarV3).first)
            .currentProgress;
        expect(resumedAt, greaterThan(stillPausedAt));
      },
    );
  });

  group('SocialStory V3 connector initial selection', () {
    testWidgets('opens initialStoryId inside the selected group', (
      tester,
    ) async {
      final first = _sourceGroup(1, <SocialStory>[
        _sourceStory(11),
        _sourceStory(12),
      ]);
      final selected = _sourceGroup(2, <SocialStory>[
        _sourceStory(21),
        _sourceStory(22),
      ]);
      final viewed = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => openSocialStoryViewerV3(
                context: context,
                group: selected,
                storyGroups: <SocialStoryGroup>[first, selected],
                initialStoryId: 22,
                onStoryViewed: viewed.add,
              ),
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
      expect(viewer.initialGroupIndex, 1);
      expect(viewer.initialItemIndex, 1);
      expect(
        tester
            .widget<StoryProgressBarV3>(find.byType(StoryProgressBarV3).first)
            .currentIndex,
        1,
      );
      expect(viewed, <int>[22]);
    });

    testWidgets('does not resolve initialStoryId from another group', (
      tester,
    ) async {
      final first = _sourceGroup(1, <SocialStory>[
        _sourceStory(11),
        _sourceStory(12),
      ]);
      final selected = _sourceGroup(2, <SocialStory>[
        _sourceStory(21),
        _sourceStory(22),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => openSocialStoryViewerV3(
                context: context,
                group: selected,
                storyGroups: <SocialStoryGroup>[first, selected],
                initialStoryId: 12,
              ),
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
      expect(viewer.initialGroupIndex, 1);
      expect(viewer.initialItemIndex, 0);
    });
  });
}
