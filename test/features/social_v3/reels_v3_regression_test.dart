import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:maslaki/features/social/data/social_api.dart';
import 'package:maslaki/features/social/state/social_controller.dart';
import 'package:maslaki/features/social_v3/reels/reel_page_v3.dart';
import 'package:maslaki/features/social_v3/reels/reel_video_surface_v3.dart';
import 'package:maslaki/features/social_v3/reels/social_reels_screen_v3.dart';

import 'reels_v3_fixtures.dart';

class _FakeSocialApi extends SocialApi {
  _FakeSocialApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> getUserRelation(int userId) async {
    return <String, dynamic>{
      'relation': <String, dynamic>{'state': 'none'},
    };
  }
}

Future<void> _pumpReels(WidgetTester tester, {bool rtl = false}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [socialApiProvider.overrideWithValue(_FakeSocialApi())],
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(393, 852)),
          child: MaterialApp(
            home: SocialReelsScreenV3(
              reels: fakeReels(3),
              coordinatorFactory: fakeCoordinator,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Reels V3 hard-acceptance regression (§18)', () {
    testWidgets('Scaffold has NO AppBar and a black background', (
      tester,
    ) async {
      await _pumpReels(tester);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.appBar,
        isNull,
        reason: 'a full-screen reel must not have an AppBar',
      );
      expect(scaffold.backgroundColor, Colors.black);
      expect(scaffold.extendBody, isTrue);
      expect(scaffold.extendBodyBehindAppBar, isTrue);
    });

    testWidgets('reel is rendered by ReelPageV3, not an old feed card', (
      tester,
    ) async {
      await _pumpReels(tester);
      expect(find.byType(ReelPageV3), findsWidgets);
      // No Material Card anywhere around the reel content.
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('video surface is never circular-clipped', (tester) async {
      await _pumpReels(tester);
      final surface = find.byType(ReelVideoSurfaceV3).first;
      // No ClipOval between the surface and the root (the media must be
      // rectangular, never a circle).
      expect(
        find.ancestor(of: surface, matching: find.byType(ClipOval)),
        findsNothing,
      );
      // And the surface subtree itself uses no ClipOval.
      expect(
        find.descendant(of: surface, matching: find.byType(ClipOval)),
        findsNothing,
      );
    });

    testWidgets('the reels pager scrolls vertically', (tester) async {
      await _pumpReels(tester);
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.scrollDirection, Axis.vertical);
    });

    testWidgets('the video surface has no decorative border/card container', (
      tester,
    ) async {
      await _pumpReels(tester);
      // The immediate wrapper of the video surface is a plain black ColoredBox,
      // not a Container with a gold Border or a rounded card.
      final surface = tester.widget<ReelVideoSurfaceV3>(
        find.byType(ReelVideoSurfaceV3).first,
      );
      expect(surface.fit, BoxFit.cover);
    });

    testWidgets('renders in Arabic RTL without overflow', (tester) async {
      await _pumpReels(tester, rtl: true);
      expect(tester.takeException(), isNull);
      expect(find.text('ريلز'), findsWidgets);
    });

    testWidgets('single tap pauses and double tap likes the reel', (
      tester,
    ) async {
      var likes = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [socialApiProvider.overrideWithValue(_FakeSocialApi())],
          child: MediaQuery(
            data: const MediaQueryData(size: Size(393, 852)),
            child: MaterialApp(
              home: SocialReelsScreenV3(
                reels: [fakeReel()],
                coordinatorFactory: fakeCoordinator,
                onLike: (_, desiredLiked) async {
                  if (desiredLiked) likes++;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final page = find.byType(ReelPageV3).first;
      await tester.tap(page);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      await tester.tap(page);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

      final center = tester.getCenter(page);
      await tester.tapAt(center);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 120));
      expect(likes, 1);
      expect(find.byIcon(Icons.favorite), findsWidgets);
    });

    testWidgets('long press holds the active reel at 2x then restores 1x', (
      tester,
    ) async {
      final coordinator = fakeCoordinator();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [socialApiProvider.overrideWithValue(_FakeSocialApi())],
          child: MediaQuery(
            data: const MediaQueryData(size: Size(393, 852)),
            child: MaterialApp(
              home: SocialReelsScreenV3(
                reels: [fakeReel(withVideo: true)],
                coordinatorFactory: () => coordinator,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final active = coordinator.controllerFor(0) as FakeVideoPlayerController;
      expect(active.playbackSpeed, 1);

      final page = find.byType(ReelPageV3).first;
      final gesture = await tester.startGesture(tester.getCenter(page));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      expect(active.playbackSpeed, 2);
      expect(find.text('2x'), findsOneWidget);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 80));
      expect(active.playbackSpeed, 1);
      expect(find.text('2x'), findsNothing);
    });
  });
}
