import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/composer/post_composer_v3.dart';
import 'package:maslaki/features/social_v3/composer/reel_composer_v3.dart';
import 'package:maslaki/features/social_v3/composer/reel_gallery_entry_v3.dart';
import 'package:maslaki/features/social_v3/composer/social_create_selector_v3.dart';
import 'package:maslaki/features/social_v3/composer/story_composer_source.dart';
import 'package:maslaki/features/social_v3/composer/story_composer_v3.dart';
import 'package:maslaki/features/social/data/social_api.dart';
import 'package:maslaki/features/social/state/social_controller.dart';
import 'package:maslaki/features/social_v3/pickers/social_media_picker_v3.dart';
import 'package:maslaki/features/social_v3/reels/social_reels_screen_v3.dart';

import 'package:dio/dio.dart';
import 'package:maslaki/features/social_v3/capabilities/social_capabilities.dart';
import 'package:maslaki/features/social_v3/capabilities/social_capabilities_api.dart';
import 'package:maslaki/features/social_v3/capabilities/social_capabilities_controller.dart';

import 'reels_v3_fixtures.dart';

class _FakeCapsApi extends SocialCapabilitiesApi {
  _FakeCapsApi(this.caps) : super(Dio());
  final SocialCapabilities caps;
  @override
  Future<SocialCapabilities> fetch() async => caps;
}

class _FakeSocialApi extends SocialApi {
  _FakeSocialApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> getUserRelation(int userId) async {
    return <String, dynamic>{
      'relation': <String, dynamic>{
        'state': 'none',
      },
    };
  }
}

Future<void> _pumpButtonWithCaps(
  WidgetTester tester, {
  required SocialCapabilities caps,
  required Future<void> Function(BuildContext) onTap,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        socialCapabilitiesApiProvider.overrideWithValue(_FakeCapsApi(caps)),
        socialApiProvider.overrideWithValue(_FakeSocialApi()),
      ],
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

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
  Future<PickedSocialMedia?> pickStoryImage() async => single;
  @override
  Future<PickedSocialMedia?> pickStoryVideo() async => video;
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
      overrides: [
        socialApiProvider.overrideWithValue(_FakeSocialApi()),
      ],
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
    await tester.tap(find.text('صورة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
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

  testWidgets(
      '§3 unsupported scoped: shows confirmation dialog, no composer yet',
      (tester) async {
    await _pumpButtonWithCaps(
      tester,
      caps: SocialCapabilities.failClosed,
      onTap: (ctx) => openStoryComposerV3Scoped(
        ctx,
        scopeType: 'building',
        scopeCode: 'B12',
        picker: _FakePicker(single: _image),
      ),
    );
    // The confirmation dialog appears; NO composer opens before confirmation.
    expect(find.text('القصص المخصصة غير متاحة حالياً'), findsOneWidget);
    expect(find.text('إنشاء قصة عامة'), findsOneWidget);
    expect(find.byType(StoryComposerV3), findsNothing);
  });

  testWidgets('§3 unsupported scoped: Cancel opens nothing', (tester) async {
    await _pumpButtonWithCaps(
      tester,
      caps: SocialCapabilities.failClosed,
      onTap: (ctx) => openStoryComposerV3Scoped(
        ctx,
        scopeType: 'building',
        scopeCode: 'B12',
        picker: _FakePicker(single: _image),
      ),
    );
    await tester.tap(find.text('إلغاء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(StoryComposerV3), findsNothing);
  });

  testWidgets(
      '§3 unsupported scoped: explicit "global" opens global composer with label',
      (tester) async {
    await _pumpButtonWithCaps(
      tester,
      caps: SocialCapabilities.failClosed,
      onTap: (ctx) => openStoryComposerV3Scoped(
        ctx,
        scopeType: 'building',
        scopeCode: 'B12',
        picker: _FakePicker(single: _image),
      ),
    );
    await tester.tap(find.text('إنشاء قصة عامة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('صورة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final composer = tester.widget<StoryComposerV3>(find.byType(StoryComposerV3));
    expect(composer.scope.scope, StoryAudienceScope.global);
    // The global audience label is visible.
    expect(find.text('الجمهور: جميع المستخدمين'), findsOneWidget);
  });

  testWidgets('Scoped community Story: capability supported → locked scope',
      (tester) async {
    await _pumpButtonWithCaps(
      tester,
      caps: const SocialCapabilities(
        storyAudienceScope: StoryAudienceScopeCapability(
          supported: true,
          supportedTypes: ['global', 'building'],
          officialStoriesSupported: false,
          version: 1,
          reason: 'ENABLED',
        ),
      ),
      onTap: (ctx) => openStoryComposerV3Scoped(
        ctx,
        scopeType: 'building',
        scopeCode: 'B12',
        label: 'المبنى B12',
        picker: _FakePicker(single: _image),
      ),
    );
    await tester.tap(find.text('صورة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final composer = tester.widget<StoryComposerV3>(find.byType(StoryComposerV3));
    expect(composer.scope.scope, StoryAudienceScope.building);
    expect(composer.scope.locked, isTrue);
  });

  testWidgets('Merchant review → PostComposerV3 in review mode', (tester) async {
    await _pumpButton(
      tester,
      (ctx) => openPostComposerV3Review(
        ctx,
        review: const MerchantReviewDraft(
          merchantId: 3, merchantName: 'سوبر ماركت',
        ),
      ),
    );
    final composer = tester.widget<PostComposerV3>(find.byType(PostComposerV3));
    expect(composer.mode, PostComposerMode.merchantReview);
    expect(composer.review?.merchantId, 3);
    expect(find.text('تقييم متجر'), findsOneWidget);
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
      ProviderScope(
        overrides: [
          socialApiProvider.overrideWithValue(_FakeSocialApi()),
        ],
        child: MediaQuery(
          data: const MediaQueryData(size: Size(393, 852)),
          child: MaterialApp(
            home: SocialReelsScreenV3(
              reels: fakeReels(1),
              coordinatorFactory: fakeCoordinator,
              onCreate: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.floatingActionButton, isNull);
  });
}
