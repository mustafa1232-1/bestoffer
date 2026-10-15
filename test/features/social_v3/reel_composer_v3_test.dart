import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/l10n/app_localizations.dart';
import 'package:maslaki/features/social_v3/composer/reel_composer_state.dart';
import 'package:maslaki/features/social_v3/composer/reel_composer_v3.dart';
import 'package:maslaki/features/social_v3/pickers/social_media_picker_v3.dart';
import 'package:maslaki/features/social_v3/upload/reel_map_normalizer.dart';
import 'package:maslaki/features/social/ui/widgets/social_story_canvas.dart';
import 'package:maslaki/features/social/ui/widgets/social_story_tool_panels.dart';
import 'package:maslaki/features/social_v3/composer/reel_publish_screen.dart';

import 'reels_v3_fixtures.dart';

class _NoopApi implements ReelUploadApi {
  @override
  Future<({String uploadUrl, int assetId})> createUploadSession({
    required int sizeBytes,
    required String mimeType,
    required String fileName,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<String> pollStatus(int assetId) async {
    throw UnimplementedError();
  }

  @override
  Future<int> publishReel({
    required int assetId,
    required String caption,
    required String audience,
    required bool commentsEnabled,
    required bool sharingEnabled,
    Object? reelStyle,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }
}

class _SpyController extends ReelComposerController {
  _SpyController()
    : super(
        api: _NoopApi(),
        tusFactory:
            ({
              required uploadUrl,
              required totalBytes,
              required assetId,
              required video,
            }) => throw UnimplementedError(),
        idempotencyKey: 'spy-reel',
      );

  Map<String, dynamic>? capturedStyle;
  String? capturedCaption;

  @override
  Future<void> publish({
    required PickedSocialMedia video,
    required String caption,
    required String audience,
    bool commentsEnabled = true,
    bool sharingEnabled = true,
    Object? reelStyle,
    ReelVideoPreparer? prepareVideo,
  }) async {
    capturedCaption = caption;
    capturedStyle = normalizeOptionalMap(reelStyle);
    notifyListeners();
  }
}

class _PublishedSpyController extends _SpyController {
  ReelComposerStage simulatedStage = ReelComposerStage.draft;
  int? simulatedPublishedReelId;

  @override
  ReelComposerStage get stage => simulatedStage;

  @override
  int? get publishedReelId => simulatedPublishedReelId;

  void markPublished(int reelId) {
    simulatedPublishedReelId = reelId;
    simulatedStage = ReelComposerStage.published;
    notifyListeners();
  }
}

const _video = PickedSocialMedia(
  path: '/tmp/reel.mp4',
  name: 'reel.mp4',
  mimeType: 'video/mp4',
  sizeBytes: 8 * 1024 * 1024,
  type: PickedMediaType.video,
);

Future<_SpyController> _pumpComposer(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  String locale = 'ar',
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final controller = _SpyController();
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(locale),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ReelComposerV3(
          video: _video,
          controller: controller,
          videoControllerFactory: FakeVideoPlayerController.new,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return controller;
}

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(390, 844),
    const Size(412, 915),
    const Size(430, 932),
    const Size(768, 1024),
  ]) {
    for (final locale in ['ar', 'en']) {
      testWidgets(
        'editor and publishing fit $size $locale with enlarged text',
        (tester) async {
          final controller = await _pumpComposer(
            tester,
            size: size,
            locale: locale,
            textScale: 1.4,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final tooltip
              in locale == 'ar'
                  ? ['قص', 'السرعة', 'الصوت', 'الفلاتر']
                  : ['Trim', 'Speed', 'Audio', 'Filters']) {
            await tester.tap(find.byTooltip(tooltip));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: tooltip);
          }
          await tester.tap(find.byIcon(Icons.text_fields));
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Keyboard');
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip(locale == 'ar' ? 'تم' : 'Done'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(
              locale == 'ar' ? 'معاينة ومتابعة' : 'Preview and continue',
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Preview');
          await tester.tap(find.text(locale == 'ar' ? 'التالي' : 'Next'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Publish');
          expect(
            find
                .text(locale == 'ar' ? 'نشر الآن' : 'Publish now')
                .hitTestable(),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        },
      );
    }
  }
  testWidgets('reel composer renders preview canvas and tool rail', (
    tester,
  ) async {
    final controller = await _pumpComposer(tester);
    expect(find.byType(SocialStoryCanvas), findsOneWidget);
    expect(find.byIcon(Icons.text_fields), findsOneWidget);
    expect(find.byIcon(Icons.alternate_email), findsOneWidget);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
    expect(find.byIcon(Icons.draw_outlined), findsOneWidget);
    controller.dispose();
  });

  testWidgets('text tool opens, edits the draft, and publish forwards style', (
    tester,
  ) async {
    final controller = await _pumpComposer(tester);

    await tester.tap(find.byIcon(Icons.text_fields));
    await tester.pump();

    expect(find.byType(SocialStoryToolPanels), findsOneWidget);

    final textFields = find.byType(TextField);
    expect(textFields, findsOneWidget);
    await tester.enterText(textFields.first, 'Hello reel overlay');
    await tester.pump();

    await tester.tap(find.byTooltip('تم'));
    await tester.pump();
    await tester.tap(find.text('معاينة ومتابعة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(find.byType(ReelPublishScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'A separate caption');
    await tester.tap(find.text('نشر الآن'));
    await tester.pump();

    expect(controller.capturedCaption, 'A separate caption');
    expect(controller.capturedStyle, isNotNull);
    expect(controller.capturedStyle?['layers'], isA<List<dynamic>>());
    expect((controller.capturedStyle?['layers'] as List).isNotEmpty, isTrue);
    expect(
      (controller.capturedStyle?['layers'] as List).first['text'],
      'Hello reel overlay',
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('successful publish closes the composer once', (tester) async {
    var published = 0;
    final controller = _PublishedSpyController();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ar'),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MediaQuery(
                        data: const MediaQueryData(size: Size(393, 852)),
                        child: ReelComposerV3(
                          video: _video,
                          controller: controller,
                          videoControllerFactory: FakeVideoPlayerController.new,
                          onPublished: (_) => published++,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ReelComposerV3), findsOneWidget);

    await tester.pumpAndSettle();
    await tester.tap(find.text('معاينة ومتابعة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    controller.markPublished(77);
    await tester.pump();
    expect(published, 0);
    await tester.tap(find.text('تم'));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(published, 1);
    expect(find.byType(ReelComposerV3), findsNothing);
    controller.dispose();
  });
}
