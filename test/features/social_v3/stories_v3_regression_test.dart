import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/stories/social_story_viewer_v3.dart';
import 'package:maslaki/features/social_v3/stories/story_progress_bar_v3.dart';

import 'stories_v3_fixtures.dart';

Future<void> _pumpViewer(
  WidgetTester tester, {
  bool rtl = false,
  List<int> itemCounts = const [3, 2],
}) async {
  final groups = [
    for (var g = 0; g < itemCounts.length; g++)
      storyGroup(userId: g + 1, name: 'user${g + 1}', itemCount: itemCounts[g]),
  ];
  await tester.pumpWidget(
    Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: MaterialApp(
          home: SocialStoryViewerV3(groups: groups),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Story Viewer V3 hard-acceptance regression (§18)', () {
    testWidgets('is a full-screen route, NOT a bottom sheet', (tester) async {
      await _pumpViewer(tester);
      expect(find.byType(BottomSheet), findsNothing);
      // No drag handle / no rounded 84%-height shell — it is a full Scaffold.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.black);
    });

    testWidgets('progress bar shows only the CURRENT group\'s items',
        (tester) async {
      await _pumpViewer(tester, itemCounts: const [3, 2]);
      // Active group has 3 items → 3 segments, not 5 (sum of all groups).
      final bars = tester
          .widgetList<StoryProgressBarV3>(find.byType(StoryProgressBarV3))
          .toList();
      expect(bars, isNotEmpty);
      expect(bars.first.itemCount, 3);
    });

    testWidgets('image item auto-advances and does not loop', (tester) async {
      await _pumpViewer(tester, itemCounts: const [2]);
      var bar = tester.widget<StoryProgressBarV3>(
        find.byType(StoryProgressBarV3).first,
      );
      expect(bar.currentIndex, 0);

      // Let the 5s image duration elapse.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 50));

      bar = tester.widget<StoryProgressBarV3>(
        find.byType(StoryProgressBarV3).first,
      );
      expect(bar.currentIndex, 1, reason: 'must advance to the next item, not loop');
    });

    testWidgets('renders in Arabic RTL without exceptions', (tester) async {
      await _pumpViewer(tester, rtl: true);
      expect(tester.takeException(), isNull);
    });
  });

  group('StoryProgressBarV3', () {
    testWidgets('fills prior=full, current=partial, later=empty',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StoryProgressBarV3(
              itemCount: 4,
              currentIndex: 1,
              currentProgress: 0.5,
            ),
          ),
        ),
      );
      final bars = tester
          .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator))
          .toList();
      expect(bars.length, 4);
      expect(bars[0].value, 1.0);
      expect(bars[1].value, 0.5);
      expect(bars[2].value, 0.0);
      expect(bars[3].value, 0.0);
    });
  });
}
