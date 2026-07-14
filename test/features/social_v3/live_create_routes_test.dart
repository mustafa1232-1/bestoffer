import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/composer/post_composer_v3.dart';
import 'package:maslaki/features/social_v3/composer/reel_composer_v3.dart';
import 'package:maslaki/features/social_v3/composer/reel_gallery_entry_v3.dart';
import 'package:maslaki/features/social_v3/composer/social_create_selector_v3.dart';
import 'package:maslaki/features/social_v3/composer/story_composer_source.dart';
import 'package:maslaki/features/social_v3/composer/story_composer_v3.dart';
import 'package:maslaki/features/social_v3/pickers/social_media_picker_v3.dart';
import 'package:maslaki/features/social_v3/reels/social_reels_screen_v3.dart';

import 'reels_v3_fixtures.dart';

const _video = PickedSocialMedia(
  path: '/tmp/r.mp4', name: 'r.mp4', mimeType: 'video/mp4',
  sizeBytes: 1024, type: PickedMediaType.video,
);
const _image = PickedSocialMedia(
  path: '/tmp/p.jpg', name: 'p.jpg', mimeType: 'image/jpeg',
  sizeBytes: 512, type: PickedMediaType.image,
);

/// Fake native picker (overrides the platform methods).
class _FakePicker extends SocialMediaPickerV3 {
  _FakePicker({this.video, this.single, this.multi = const []});
  final PickedSocialMedia? video;
  final PickedSocialMedia? single;
  final List<PickedSocialMedia> multi;
  @override
  Future<PickedSocialMedia?> pickReelVideo() async => video;
  @override
  Future<PickedSocialMedia?> pickStoryImageOrVideo() async => single;
  @override
  Future<List<PickedSocialMedia>> pickMultiplePostMedia() async => multi;
}

Future<void> _pumpButton(
  WidgetTester tester,
  Future<void> Function(BuildContext) onTap,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => onTap(ctx),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  // Fixed pumps (not pumpAndSettle) — image placeholders spin indefinitely on
  // fake file paths; we only need the pushed route to be present.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('Create Reel entry → ReelComposerV3', (tester) async {
    await _pumpButton(
      tester,
      (ctx) => openReelComposerV3(ctx, picker: _FakePicker(video: _video)),
    );
    expect(find.byType(ReelComposerV3), findsOneWidget);
  });

  testWidgets('Create Story entry → StoryComposerV3', (tester) async {
    await _pumpButton(
      tester,
      (ctx) =>
          openStoryComposerV3FromGallery(ctx, picker: _FakePicker(single: _image)),
    );
    expect(find.byType(StoryComposerV3), findsOneWidget);
  });

  testWidgets('Create Post entry → PostComposerV3', (tester) async {
    await _pumpButton(
      tester,
      (ctx) => openPostComposerV3(ctx, picker: _FakePicker(multi: [_image, _image])),
    );
    expect(find.byType(PostComposerV3), findsOneWidget);
  });

  testWidgets('Add Reel to Story → StoryComposerV3 with SharedReelSource',
      (tester) async {
    await _pumpButton(
      tester,
      (ctx) => openStoryComposerV3WithReel(
        ctx,
        reel: const SharedReelSource(
          reelId: 1, originalOwnerId: 2, playbackUrl: null,
          thumbnailUrl: 'https://x/t.jpg', posterUrl: null,
          width: 1080, height: 1920, caption: '', available: true,
        ),
      ),
    );
    final composer = tester.widget<StoryComposerV3>(find.byType(StoryComposerV3));
    expect(composer.source.kind, StorySourceKind.sharedReel);
  });

  testWidgets('create selector lists Post / Story / Reel', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        }),
      ),
    );
    // ignore: unawaited_futures
    showSocialCreateSelectorV3(ctx);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('منشور'), findsOneWidget);
    expect(find.text('قصة'), findsOneWidget);
    expect(find.text('ريل'), findsOneWidget);
  });

  testWidgets('full-screen Reels route renders NO floating Create button',
      (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: MaterialApp(
          home: SocialReelsScreenV3(
            reels: fakeReels(1),
            coordinatorFactory: fakeCoordinator,
            onCreate: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.floatingActionButton, isNull);
  });
}
