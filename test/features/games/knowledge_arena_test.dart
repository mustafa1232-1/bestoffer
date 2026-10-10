import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/games/state/knowledge_match_controller.dart';
import 'package:maslaki/features/games/ui/knowledge_match_board.dart';
import 'package:maslaki/features/games/ui/knowledge_landmark_art.dart';
import 'knowledge_match_controller_test.dart';

// Keep the golden's clock arc independent of wall-clock test runner load.
class _GoldenController extends KnowledgeMatchController {
  _GoldenController({required super.api, required super.matchId, super.store})
    : super(polling: false);

  @override
  DateTime get serverNow => DateTime.parse('${snapshot['serverTime']}');
}

void main() {
  setUpAll(() async {
    final font = FontLoader('TajawalLocal')
      ..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await KnowledgeLandmarkArt.preload();
  });
  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(900, 700),
  ]) {
    testWidgets('arena layout RTL ${size.width}, selection and receipt', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = KnowledgeFakeApi();
      final c = _GoldenController(
        api: api,
        matchId: 1,
        store: MemoryKnowledgeStore(),
      );
      addTearDown(c.dispose);
      await c.start();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'TajawalLocal'),
          home: ListenableBuilder(
            listenable: c,
            builder: (_, _) => RepaintBoundary(
              key: const ValueKey('arena-capture'),
              child: KnowledgeArena(
                controller: c,
                social: const SizedBox(),
                reducedMotion: true,
                onSettings: () {},
                onRematch: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('150 نقطة للإجابة الصحيحة'), findsOneWidget);
      expect(
        find.text('أي مدينة عراقية تُعرف بمدينة العلم والعلماء؟'),
        findsOneWidget,
      );
      expect(
        Directionality.of(tester.element(find.text('خريطة المعرفة'))),
        TextDirection.rtl,
      );
      if (size.width == 390) {
        await expectLater(
          find.byKey(const ValueKey('arena-capture')),
          matchesGoldenFile('goldens/knowledge-question.png'),
        );
      }
      await tester.tap(find.byKey(const ValueKey('knowledge-answer-1')));
      await tester.drag(
        find.byKey(const ValueKey('knowledge-content')),
        const Offset(0, -230),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.ensureVisible(find.byKey(const ValueKey('district-souk')));
      await tester.tap(find.byKey(const ValueKey('district-souk')));
      await tester.pump();
      expect(c.selectedAnswer, 1);
      expect(c.selectedDistrict, 'souk');
      expect(api.answers, 0);
      await tester.tap(find.byKey(const ValueKey('knowledge-submit')));
      await tester.pump();
      await tester.pump();
      expect(c.submission, KnowledgeSubmission.confirmed);
      expect(api.answers, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'long Arabic, large text, keyboard and reduced motion do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = KnowledgeFakeApi();
      (api.value['question'] as Map)['text'] =
          'سؤال عربي طويل للتحقق من وضوح الخط وترتيب الخيارات أثناء اللعب الجماعي دون إخفاء أي جزء من النص أو التداخل مع الخريطة والعداد في شاشة صغيرة.';
      (api.value['question'] as Map)['options'] = [
        'إجابة عربية طويلة تمتد على أكثر من سطر في هذا الاختبار',
        'الخيار الثاني',
        'الخيار الثالث',
        'الخيار الرابع',
      ];
      final c = KnowledgeMatchController(
        api: api,
        matchId: 1,
        store: MemoryKnowledgeStore(),
        polling: false,
      );
      addTearDown(c.dispose);
      await c.start();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'TajawalLocal'),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.6),
              disableAnimations: true,
              viewInsets: EdgeInsets.only(bottom: 200),
            ),
            child: KnowledgeArena(
              controller: c,
              social: const TextField(),
              reducedMotion: true,
              onSettings: () {},
              onRematch: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -800));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('illustrated map keeps rewards, ownership and real hit targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final match = knowledgeMap(knowledgeFixture()['match']);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'TajawalLocal'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('map-capture'),
              child: ColoredBox(
                color: const Color(0xFFF5F8F8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: KnowledgeMapSection(
                    match: match,
                    reducedMotion: true,
                    selected: 'souk',
                    onSelect: (id) => selected = id,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(KnowledgeLandmarkArt), findsNWidgets(11));
    expect(find.text('+1 منطقة'), findsOneWidget);
    expect(find.text('منطقة محتلة'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('district-river')));
    expect(selected, isNull);
    await tester.tap(find.byKey(const ValueKey('district-souk')));
    expect(selected, 'souk');
    await expectLater(
      find.byKey(const ValueKey('map-capture')),
      matchesGoldenFile('goldens/knowledge-map-illustrated.png'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'series wins and game result remain distinct from question points',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = KnowledgeFakeApi();
      (api.value['match'] as Map)['series'] = {
        'bestOf': 9,
        'winsRequired': 5,
        'game': 2,
        'winsA': 1,
        'winsB': 1,
      };
      api.value['phase'] = 'round_result';
      api.value['result'] = {
        'gameCompleted': true,
        'gameNumber': 2,
        'outcomes': [],
      };
      final c = KnowledgeMatchController(
        api: api,
        matchId: 1,
        store: MemoryKnowledgeStore(),
        polling: false,
      );
      addTearDown(c.dispose);
      await c.start();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'TajawalLocal'),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: KnowledgeArena(
              controller: c,
              social: const SizedBox(),
              reducedMotion: true,
              onSettings: () {},
              onRematch: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('الجولة 2 من 9 · الحسم بـ 5 انتصارات'), findsOneWidget);
      expect(find.text('انتصارات · نقاط الجولة 150'), findsOneWidget);
      expect(find.text('حُسمت الجولة 2 · 1 مقابل 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'result only paints server-owned territory, countdown hides answers',
    (tester) async {
      final api = KnowledgeFakeApi();
      final c = KnowledgeMatchController(
        api: api,
        matchId: 1,
        store: MemoryKnowledgeStore(),
        polling: false,
      );
      addTearDown(c.dispose);
      await c.start();
      c.snapshot['phase'] = 'countdown';
      await tester.pumpWidget(
        MaterialApp(
          home: KnowledgeArena(
            controller: c,
            social: const SizedBox(),
            reducedMotion: true,
            onSettings: () {},
            onRematch: () {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('knowledge-answer-1')), findsNothing);
      expect(find.text('استعد لفريقك'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('landmark paints bitmap pixels inside a loose-width column', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 140,
            height: 120,
            child: Column(
              children: [
                Expanded(
                  child: RepaintBoundary(
                    key: ValueKey('art-pixels'),
                    child: KnowledgeLandmarkArt(index: 0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('art-pixels')),
    );
    await tester.runAsync(() async {
      final bitmap = await boundary.toImage();
      final data = (await bitmap.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var painted = 0;
      final colors = <int>{};
      for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
        if (data.getUint8(offset + 3) > 100) {
          painted++;
          colors.add(data.getUint32(offset));
        }
      }
      expect(painted, greaterThan(1000));
      expect(colors.length, greaterThan(100));
      bitmap.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('selection animates the landmark without moving its hit target', (
    tester,
  ) async {
    String? selected;
    final match = knowledgeMap(knowledgeFixture()['match']);
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) => Center(
            child: SizedBox(
              width: 360,
              height: 550,
              child: KnowledgeTerritoryMap(
                match: match,
                selected: selected,
                onSelect: (value) => update(() => selected = value),
              ),
            ),
          ),
        ),
      ),
    );
    final target = find.byKey(const ValueKey('district-souk'));
    final bounds = tester.getRect(target);
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getRect(target), bounds);
    expect(
      tester
          .widgetList<Transform>(
            find.descendant(of: target, matching: find.byType(Transform)),
          )
          .any((widget) => widget.transform.entry(0, 0) > 1.01),
      true,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(target), bounds);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
