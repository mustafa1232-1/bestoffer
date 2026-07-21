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
            ({required uploadUrl, required totalBytes, required assetId}) =>
                throw UnimplementedError(),
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

Future<_SpyController> _pumpComposer(WidgetTester tester) async {
  final controller = _SpyController();
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ar'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(393, 852)),
          child: ReelComposerV3(video: _video, controller: controller),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return controller;
}

void main() {
  testWidgets('reel composer renders preview canvas and tool rail', (
    tester,
  ) async {
    final controller = await _pumpComposer(tester);
    expect(find.byType(SocialStoryCanvas), findsOneWidget);
    expect(find.byIcon(Icons.text_fields_rounded), findsOneWidget);
    expect(find.byIcon(Icons.alternate_email_rounded), findsOneWidget);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
    expect(find.byIcon(Icons.brush_rounded), findsOneWidget);
    controller.dispose();
  });

  testWidgets('text tool opens, edits the draft, and publish forwards style', (
    tester,
  ) async {
    final controller = await _pumpComposer(tester);

    await tester.tap(find.byIcon(Icons.text_fields_rounded));
    await tester.pump();

    expect(find.byType(SocialStoryToolPanels), findsOneWidget);

    final textFields = find.byType(TextField);
    expect(textFields, findsAtLeastNWidgets(2));
    await tester.enterText(textFields.at(1), 'Hello reel');
    await tester.pump();

    await tester.tap(find.text('نشر'));
    await tester.pump();

    expect(controller.capturedCaption, 'Hello reel');
    expect(controller.capturedStyle, isNotNull);
    expect(controller.capturedStyle?['caption'], 'Hello reel');
    expect(controller.capturedStyle?['layers'], isA<List<dynamic>>());
    expect((controller.capturedStyle?['layers'] as List).isNotEmpty, isTrue);
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

    controller.markPublished(77);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(published, 1);
    expect(find.byType(ReelComposerV3), findsNothing);
    controller.dispose();
  });
}
