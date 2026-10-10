import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/games/ui/mafia_interactions.dart';

Map<String, dynamic> event(
  int id, {
  String kind = 'egg',
  int? target = 2,
  DateTime? at,
}) => {
  'id': id,
  'type': 'player_interaction',
  if (at != null) 'createdAt': at.toIso8601String(),
  'payload': {
    'kind': kind,
    'senderPlayerId': 1,
    'targetPlayerId': target,
    'senderName': 'علي',
    'targetName': 'نور',
  },
};

Future<void> mount(
  WidgetTester tester,
  MafiaInteractionController controller, {
  bool reduced = false,
  Map<int, Rect>? seats,
  VoidCallback? onTap,
}) => tester.pumpWidget(
  MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 360,
          height: 300,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                ),
              ),
              Positioned.fill(
                child: MafiaInteractionLayer(
                  controller: controller,
                  seats:
                      seats ??
                      {
                        1: const Rect.fromLTWH(10, 20, 100, 120),
                        2: const Rect.fromLTWH(230, 160, 100, 120),
                      },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'server clock determines freshness, not a misconfigured device clock',
    (tester) async {
      final controller = MafiaInteractionController();
      final serverTime = DateTime.utc(2020, 1, 1);
      controller.ingest([event(1, at: serverTime)], serverTime: serverTime);
      expect(controller.active, hasLength(1));
      controller.dispose();
    },
  );

  testWidgets('long first-row flights remain inside the arena', (tester) async {
    final controller = MafiaInteractionController();
    await mount(
      tester,
      controller,
      seats: {
        1: const Rect.fromLTWH(0, 0, 80, 114),
        2: const Rect.fromLTWH(280, 0, 80, 114),
      },
    );
    controller.ingest([event(1, kind: 'rose')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 490));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('mafia-projectile-1'))).dy,
      greaterThanOrEqualTo(0),
    );
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'all batched events play once; out-of-order receipt does not hide peers',
    (tester) async {
      final controller = MafiaInteractionController();
      controller.ingest([event(1)], silent: true);
      controller.ingest([event(4)]);
      controller.ingest([event(1), event(2), event(3), event(4)]);
      expect(controller.active.map((e) => e.id), [4, 2, 3]);
      await tester.pump(const Duration(seconds: 3));
      expect(controller.active, isEmpty);
      controller.ingest([event(2), event(3)]);
      expect(controller.active, isEmpty);
      controller.dispose();
    },
  );

  testWidgets(
    'old events, paused events and duplicate snapshots do not replay',
    (tester) async {
      final controller = MafiaInteractionController();
      controller.ingest([
        event(1, at: DateTime.now().subtract(const Duration(minutes: 1))),
      ], serverTime: DateTime.now());
      expect(controller.active, isEmpty);
      controller.ingest([event(2)]);
      controller.clear();
      controller.ingest([event(3)], silent: true);
      controller.ingest([event(2), event(3)]);
      expect(controller.active, isEmpty);
      controller.dispose();
      controller.ingest([event(4)]);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  test('geometry uses the same RTL seat bounds on phone and desktop', () {
    for (final width in [304.0, 350.0, 1160.0]) {
      final ltr = MafiaSeatGeometry(width: width, count: 14, rtl: false);
      final rtl = MafiaSeatGeometry(width: width, count: 14, rtl: true);
      for (var i = 0; i < 14; i++) {
        expect(rtl.seat(i).left, closeTo(width - ltr.seat(i).right, .001));
        expect(rtl.seat(i).bottom, lessThanOrEqualTo(rtl.height));
        expect(rtl.seat(i).left, greaterThanOrEqualTo(-.001));
      }
    }
  });

  test('gift curve starts and finishes at player cards', () {
    const start = Offset(50, 80), end = Offset(250, 200);
    expect(mafiaGiftPosition(start, end, 0), start);
    expect((mafiaGiftPosition(start, end, 1) - end).distance, lessThan(.001));
    expect(mafiaGiftPosition(start, end, .5).dy, lessThan(140));
  });

  testWidgets('egg travels from sender to recipient then becomes a splat', (
    tester,
  ) async {
    final controller = MafiaInteractionController();
    await mount(tester, controller);
    controller.ingest([event(1)]);
    await tester.pump();
    final projectile = find.byKey(const ValueKey('mafia-projectile-1'));
    expect(tester.getCenter(projectile), const Offset(60, 70));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getCenter(projectile).dx, greaterThan(100));
    await tester.pump(const Duration(milliseconds: 600));
    final impact = find.byKey(const ValueKey('mafia-impact-1'));
    expect(tester.getCenter(impact), const Offset(280, 210));
    expect(
      tester.widget<MafiaGiftSprite>(find.byType(MafiaGiftSprite)).kind,
      'splat',
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('mafia-effect-1')), findsNothing);
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('emotions stay on their sender; overlays never intercept a tap', (
    tester,
  ) async {
    var tapped = false;
    final controller = MafiaInteractionController();
    await mount(tester, controller, onTap: () => tapped = true);
    controller.ingest([event(2, kind: 'laugh', target: null)]);
    await tester.pump();
    expect(
      tester.getCenter(find.byKey(const ValueKey('mafia-projectile-2'))),
      const Offset(60, 70),
    );
    await tester.tapAt(const Offset(60, 70));
    expect(tapped, isTrue);
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reduced motion lands instantly without movement; missing targets are safe',
    (tester) async {
      final controller = MafiaInteractionController();
      await mount(tester, controller, reduced: true);
      controller.ingest([
        event(1, kind: 'tea'),
        event(2, kind: 'rose', target: 99),
      ]);
      await tester.pump();
      final impact = find.byKey(const ValueKey('mafia-impact-1'));
      expect(tester.getCenter(impact), const Offset(280, 210));
      expect(find.byKey(const ValueKey('mafia-effect-2')), findsNothing);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.getCenter(impact), const Offset(280, 210));
      controller.dispose();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resizing updates landing coordinates and disposal cancels motion',
    (tester) async {
      final controller = MafiaInteractionController();
      await mount(tester, controller);
      controller.ingest([event(1, kind: 'rose')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await mount(
        tester,
        controller,
        seats: {
          1: const Rect.fromLTWH(220, 20, 100, 120),
          2: const Rect.fromLTWH(10, 160, 100, 120),
        },
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(
        tester.getCenter(find.byKey(const ValueKey('mafia-impact-1'))),
        const Offset(60, 210),
      );
      controller.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );
}
