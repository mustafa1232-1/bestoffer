import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
    test(
      'reels controller times out instead of staying loading forever',
      () async {
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

        final controller = container.read(
          socialReelsControllerProvider.notifier,
        );
        await controller.load(timeout: const Duration(milliseconds: 1));

        final state = container.read(socialReelsControllerProvider);
        expect(state.loading, isFalse);
        expect(state.loadingMore, isFalse);
        expect(state.error, kSocialReelsLoadTimeoutCode);
      },
    );

    testWidgets(
      'reels viewer shows empty/error state with retry and create CTA',
      (tester) async {
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
                    error:
                        'DioException [bad response]: status code of 401 and RequestOptions',
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

        expect(find.textContaining('DioException'), findsNothing);
        expect(find.textContaining('RequestOptions'), findsNothing);
        expect(
          find.text('Unable to load reels right now. Try again.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Create reel'), findsNothing);

        await tester.tap(find.text('Retry'));
        await tester.pump();

        expect(controller.loadCalls, greaterThanOrEqualTo(2));
      },
    );

    test(
      'reels controller maps 401 to a safe user-facing state code',
      () async {
        final api = _FakeSocialApi(
          exploreReels: Future<Map<String, dynamic>>.error(
            DioException(
              requestOptions: RequestOptions(path: '/api/feed/reels/explore'),
              response: Response<Map<String, dynamic>>(
                requestOptions: RequestOptions(path: '/api/feed/reels/explore'),
                statusCode: 401,
                data: const <String, dynamic>{'message': 'NO_TOKEN'},
              ),
              type: DioExceptionType.badResponse,
            ),
          ),
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

        await container.read(socialReelsControllerProvider.notifier).load();

        final state = container.read(socialReelsControllerProvider);
        expect(state.loading, isFalse);
        expect(state.error, kSocialReelsLoadAuthCode);
        expect(state.error, isNot(contains('DioException')));
        expect(state.error, isNot(contains('RequestOptions')));
      },
    );

    test('public reel reads are sent without auth or refresh', () async {
      final dio = Dio();
      final adapter = _CaptureAdapter();
      dio.httpClientAdapter = adapter;
      final api = SocialApi(dio);

      await api.listExploreReels();
      await api.getReelById(123);
      await api.recordReelView(reelId: 123, context: 'reels_v3');

      expect(adapter.requests, hasLength(3));
      for (final request in adapter.requests) {
        expect(request.extra['skipAuth'], isTrue);
        expect(request.extra['skipAuthRefresh'], isTrue);
        expect(request.extra['skipTerminalSessionInvalidation'], isTrue);
      }
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
        'post': <String, dynamic>{'id': reelId},
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

class _CaptureAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = options.path.endsWith('/explore')
        ? <String, dynamic>{'reels': const [], 'nextCursor': null}
        : <String, dynamic>{'reel': const <String, dynamic>{}};
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
