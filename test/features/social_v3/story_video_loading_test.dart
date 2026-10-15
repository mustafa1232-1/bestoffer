import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/domain/story_view_data.dart';
import 'package:maslaki/features/social_v3/stories/social_story_viewer_v3.dart';
import 'reels_v3_fixtures.dart';

class _DelayedStoryVideo extends FakeVideoPlayerController {
  _DelayedStoryVideo(super.url);
  final ready = Completer<void>();
  @override
  Future<void> initialize() async {
    await ready.future;
    if (!disposed) await super.initialize();
  }
}

StoryV3Group _group(int count) => StoryV3Group(
  userId: 1,
  authorName: 'Story author',
  authorHandle: '@story',
  authorAvatarUrl: null,
  items: List.generate(
    count,
    (i) => StoryV3Item(
      storyId: i + 1,
      caption: 'Video ${i + 1}',
      media: fakeReel(id: i + 1, withVideo: true).media,
      backgroundColor: Colors.black,
      imageDuration: const Duration(seconds: 5),
      clipStart: null,
      clipDuration: null,
      isLiked: false,
      sharedReel: null,
    ),
  ),
);

void main() {
  testWidgets(
    'stalled story initialization exposes retry and releases the player',
    (tester) async {
      final players = <_DelayedStoryVideo>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SocialStoryViewerV3(
            groups: [_group(1)],
            videoFactory: (url) {
              final player = _DelayedStoryVideo(url);
              players.add(player);
              return player;
            },
          ),
        ),
      );
      await tester.pump();
      expect(players, hasLength(1));
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
      expect(find.text('Video could not play'), findsOneWidget);
      expect(players.first.disposed, isTrue);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(players, hasLength(2));
      players.last.ready.complete();
      await tester.pump();
      expect(players.last.playCalls, greaterThan(0));
      expect(find.text('Video could not play'), findsNothing);
      players.first.ready.complete();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(players.every((p) => p.disposed), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a prefetched story starts when its initialization finishes after navigation',
    (tester) async {
      final players = <_DelayedStoryVideo>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SocialStoryViewerV3(
            groups: [_group(2)],
            videoFactory: (url) {
              final player = _DelayedStoryVideo(url);
              players.add(player);
              return player;
            },
          ),
        ),
      );
      await tester.pump();
      expect(players, hasLength(1));
      players.first.ready.complete();
      await tester.pump();
      expect(players, hasLength(2));
      await tester.tapAt(const Offset(700, 300));
      await tester.pump();
      expect(players.last.playCalls, 0);
      players.last.ready.complete();
      await tester.pump();
      expect(players.last.playCalls, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
