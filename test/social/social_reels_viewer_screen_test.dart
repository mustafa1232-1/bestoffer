import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/data/social_api.dart';
import 'package:maslaki/features/social/models/social_models.dart';
import 'package:maslaki/features/social/state/social_controller.dart';
import 'package:maslaki/features/social/state/social_reels_controller.dart';
import 'package:maslaki/features/social/ui/social_reels_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

void main() {
  group('Social reels release readiness', () {
    test('reels controller times out instead of staying loading forever', () async {
      final api = _FakeSocialApi(
        exploreReels: Completer<Map<String, dynamic>>().future,
      );
      final container = ProviderContainer(
        overrides: [socialApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        socialReelsControllerProvider,
        (previous, next) {},
      );
      addTearDown(subscription.close);

      final controller = container.read(socialReelsControllerProvider.notifier);
      await controller.load(timeout: const Duration(milliseconds: 1));

      final state = container.read(socialReelsControllerProvider);
      expect(state.loading, isFalse);
      expect(state.loadingMore, isFalse);
      expect(state.error, kSocialReelsLoadTimeoutCode);
    });

    testWidgets('reels viewer shows empty/error state with retry and create CTA', (
      tester,
    ) async {
      late _FakeReelsController controller;
      final api = _FakeSocialApi();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            socialApiProvider.overrideWithValue(api),
            socialReelsControllerProvider.overrideWith((ref) {
              controller = _FakeReelsController(
                ref,
                const SocialReelsState(
                  loading: false,
                  loadingMore: false,
                  items: <SocialReelItem>[],
                  nextCursor: null,
                  error: 'Backend unavailable',
                ),
              );
              return controller;
            }),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('ar'), Locale('en')],
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: SocialReelsScreen(),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Backend unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Create reel'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(controller.loadCalls, greaterThanOrEqualTo(2));
    });
  });
}

class _FakeSocialApi extends SocialApi {
  _FakeSocialApi({this.exploreReels}) : super(Dio());

  final Future<Map<String, dynamic>>? exploreReels;

  @override
  Future<Map<String, dynamic>> listExploreReels({
    int limit = 14,
    int? beforeId,
  }) async {
    if (exploreReels != null) return exploreReels!;
    return <String, dynamic>{'reels': const [], 'nextCursor': null};
  }

  @override
  Future<Map<String, dynamic>> getReelById(int reelId) async {
    return <String, dynamic>{
      'reel': <String, dynamic>{
        'post': <String, dynamic>{
          'id': reelId,
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> recordReelView({
    required int reelId,
    int? watchDurationMs,
    double? completionRate,
    bool? completed,
    int? replayCount,
    String? context,
  }) async {
    return <String, dynamic>{'ok': true};
  }
}

class _FakeReelsController extends SocialReelsController {
  _FakeReelsController(super.ref, SocialReelsState initialState) {
    state = initialState;
  }

  int loadCalls = 0;

  @override
  Future<void> load({
    bool refresh = true,
    Duration timeout = kSocialReelsLoadTimeout,
  }) async {
    loadCalls += 1;
  }
}
