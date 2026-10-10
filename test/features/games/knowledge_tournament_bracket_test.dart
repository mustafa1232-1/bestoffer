import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/games/ui/knowledge_landmark_art.dart';
import 'package:maslaki/features/games/ui/knowledge_tournament_bracket.dart';
import 'package:maslaki/features/games/ui/knowledge_series_picker.dart';

Map<String, dynamic> bracketFixture(int size) => {
  'event': {
    'id': 1,
    'title': 'كأس مسلكي',
    'bestOf': 3,
    'teamSize': 2,
    'status': 'active',
  },
  'teams': [],
  'rounds': [
    for (var count = size ~/ 2, round = 1; count >= 1; count ~/= 2, round++)
      {
        'number': round,
        'matches': [
          for (var i = 1; i <= count; i++)
            {
              'id': round * 100 + i,
              'round': round,
              'matchNumber': i,
              'status': round == 1 ? 'active' : 'waiting',
              'teamA': round == 1
                  ? {'id': i * 2 - 1, 'name': 'فريق دجلة $i'}
                  : null,
              'teamB': round == 1
                  ? {'id': i * 2, 'name': 'فريق النخيل $i'}
                  : null,
              'sourceA': round > 1
                  ? {'round': round - 1, 'matchNumber': i * 2 - 1}
                  : null,
              'sourceB': round > 1
                  ? {'round': round - 1, 'matchNumber': i * 2}
                  : null,
              'winsA': 1,
              'winsB': 0,
              'scoreA': 650,
              'scoreB': 510,
              'canPlay': round == 1 && i == 1,
            },
        ],
      },
  ],
};

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
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets(
      'complete bracket fits RTL viewport $width and zoom remains usable',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Map<String, dynamic>? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'TajawalLocal'),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: const ValueKey('bracket-golden'),
                    child: ColoredBox(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: KnowledgeTournamentBracket(
                          data: bracketFixture(16),
                          onOpenMatch: (m) => opened = m,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(KnowledgeLandmarkArt), findsOneWidget);
        expect(find.byType(KnowledgeBracketMatch), findsNWidgets(23));
        final view = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final before = view.transformationController!.value.getMaxScaleOnAxis();
        await tester.tap(find.byTooltip('تكبير المخطط'));
        await tester.pump();
        expect(
          view.transformationController!.value.getMaxScaleOnAxis(),
          greaterThan(before),
        );
        await tester.tap(find.byTooltip('عرض المخطط كاملاً'));
        await tester.pump();
        if (width == 1100) {
          await expectLater(
            find.byKey(const ValueKey('bracket-golden')),
            matchesGoldenFile('goldens/knowledge-tournament.png'),
          );
        }
        final card = find.byType(KnowledgeBracketMatch).at(15);
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pump();
        expect(opened?['id'], 101);
        opened = null;
        await tester.ensureVisible(find.byType(KnowledgeBracketMatch).at(16));
        await tester.tap(find.byType(KnowledgeBracketMatch).at(16));
        expect(opened, isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('64-team chart and enlarged Arabic text do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: KnowledgeTournamentBracket(
                  data: bracketFixture(64),
                  onOpenMatch: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('series picker sends selected best-of and required win count', (
    tester,
  ) async {
    var value = 3;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => KnowledgeSeriesPicker(
              value: value,
              onChanged: (n) => setState(() => value = n),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('9 جولات'));
    await tester.pumpAndSettle();
    expect(value, 9);
    expect(find.text('الحسم بـ 5 انتصارات · 5 أسئلة لكل جولة'), findsOneWidget);
  });
}
