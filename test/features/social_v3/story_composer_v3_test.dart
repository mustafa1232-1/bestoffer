import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/composer/story_composer_source.dart';
import 'package:maslaki/features/social_v3/composer/story_composer_v3.dart';
import 'package:maslaki/features/social_v3/media/social_media_presentation.dart';

SharedReelSource _reel({required bool vertical}) => SharedReelSource(
      reelId: 99,
      originalOwnerId: 7,
      playbackUrl: 'https://videodelivery.net/uid/manifest/video.m3u8',
      thumbnailUrl: 'https://x/thumb.jpg',
      posterUrl: null,
      width: vertical ? 1080 : 1920,
      height: vertical ? 1920 : 1080,
      caption: 'shared',
      available: true,
    );

Future<void> _pump(WidgetTester tester, StoryComposerSource source) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: StoryComposerV3(source: source),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Story Composer V3 — shared reel is the base media (§6)', () {
    testWidgets('shared reel presentation never uses the playback URL as poster',
        (tester) async {
      final p = _reel(vertical: true).toPresentation();
      expect(p.posterImageUrl, 'https://x/thumb.jpg');
      expect(p.videoPlaybackUrl, 'https://videodelivery.net/uid/manifest/video.m3u8');
    });

    testWidgets('composer is full-screen (black Scaffold, no AppBar)',
        (tester) async {
      await _pump(tester, StoryComposerSource.sharedReel(_reel(vertical: true)));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.appBar, isNull);
      expect(scaffold.backgroundColor, Colors.black);
    });

    testWidgets('vertical shared reel fills the canvas (no fixed 278-wide card)',
        (tester) async {
      await _pump(tester, StoryComposerSource.sharedReel(_reel(vertical: true)));
      // The base canvas fills the 393-wide screen; there is no 278-wide box.
      final sizedBoxes = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((b) => b.width == 278);
      expect(sizedBoxes, isEmpty, reason: 'no width-278 attachment card allowed');
      expect(find.byType(ClipOval), findsNothing);
    });

    testWidgets('horizontal shared reel uses a blurred backdrop', (tester) async {
      await _pump(tester, StoryComposerSource.sharedReel(_reel(vertical: false)));
      expect(find.byType(ImageFiltered), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('deleted reel presentation is not public-eligible',
        (tester) async {
      final gone = SharedReelSource(
        reelId: 1,
        originalOwnerId: 7,
        playbackUrl: null,
        thumbnailUrl: null,
        posterUrl: null,
        width: 1080,
        height: 1920,
        caption: '',
        available: false,
      );
      expect(gone.toPresentation().processingStatus.isPublicEligible, isFalse);
    });

    testWidgets('publish fires the callback with caption + scope',
        (tester) async {
      String? cap;
      StoryComposerScope? scope;
      await tester.pumpWidget(
        MaterialApp(
          home: StoryComposerV3(
            source: StoryComposerSource.sharedReel(_reel(vertical: true)),
            onPublish: (c, s) async {
              cap = c;
              scope = s;
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.text('نشر'));
      await tester.pump();
      expect(cap, '');
      expect(scope?.scope, StoryAudienceScope.global);
    });

    testWidgets(
        'SAFETY: building-scoped story is NOT published globally when backend '
        'scope is unsupported (§1)', (tester) async {
      var published = false;
      var draftSaved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StoryComposerV3(
            source: StoryComposerSource.sharedReel(_reel(vertical: true)),
            scope: const StoryComposerScope(
              scope: StoryAudienceScope.building,
              scopeCode: 'B12',
              label: 'المبنى B12',
              locked: true,
            ),
            onSaveDraft: (_) => draftSaved = true,
            onPublish: (c, s) async {
              published = true; // must NOT happen — would be a global publish
              return true;
            },
          ),
        ),
      );
      expect(find.text('المبنى B12'), findsOneWidget);
      await tester.tap(find.text('نشر'));
      await tester.pump();
      // The scoped story was NOT published (no silent global downgrade)...
      expect(published, isFalse);
      // ...the draft is preserved and the user is told.
      expect(draftSaved, isTrue);
      expect(
        find.text('نشر القصص المخصصة للبناية غير متاح حالياً. تم حفظ المسودة.'),
        findsOneWidget,
      );
    });
  });
}
