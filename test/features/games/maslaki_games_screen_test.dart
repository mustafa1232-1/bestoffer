import 'package:core_design_system/core_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/games/data/games_api.dart';
import 'package:maslaki/features/games/ui/maslaki_games_screen.dart';

class _FakeGamesApi extends GamesApi {
  _FakeGamesApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> status() async => {
    'game': {'enabled': true, 'puzzleCount': 30, 'activeRoom': null},
    'campaign': {'isMock': true},
  };

  @override
  Future<List<Map<String, dynamic>>> history() async => const [];
}

class _FailingGamesApi extends GamesApi {
  _FailingGamesApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> status() =>
      Future<Map<String, dynamic>>.error(Exception('network unavailable'));

  @override
  Future<List<Map<String, dynamic>>> history() =>
      Future<List<Map<String, dynamic>>>.error(
        Exception('network unavailable'),
      );
}

class _LeftRoomGamesApi extends _FakeGamesApi {
  @override
  Future<List<Map<String, dynamic>>> history() async => [
    {
      'sessionId': 10,
      'roomId': 20,
      'mode': 'solo',
      'status': 'active',
      'score': 40,
      'rewardEligible': false,
      'rewardClaimed': false,
      'canOpen': false,
    },
  ];
}

class _MafiaHistoryGamesApi extends _FakeGamesApi {
  @override
  Future<List<Map<String, dynamic>>> mafiaHistory() async => [
    {
      'roomId': 31,
      'inviteCode': 'M3SLK9',
      'status': 'completed',
      'ruleset': 'standard',
      'isHost': true,
      'maxPlayers': 14,
      'playerCount': 7,
    },
  ];
}

class _GuideSeenStore extends SecureStore {
  @override
  Future<bool?> readBool(String key) async => true;

  @override
  Future<void> writeBool(String key, bool value) async {}
}

Future<void> _pumpGames(WidgetTester tester, {GamesApi? api}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gamesApiProvider.overrideWithValue(api ?? _FakeGamesApi()),
        secureStoreProvider.overrideWithValue(_GuideSeenStore()),
      ],
      child: MaterialApp(
        theme: AppTheme.themed(MaslakiTheme.original),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.35)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: const MaslakiGamesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('games entry remains usable at 360px with enlarged Arabic text', (
    tester,
  ) async {
    await _pumpGames(tester);

    expect(find.byKey(const ValueKey('game-choice-team-code')), findsOneWidget);
    expect(find.byKey(const ValueKey('game-choice-mafia')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('game-choice-knowledge-map')),
      findsOneWidget,
    );
    expect(find.text('شفرة الفريق'), findsOneWidget);
    expect(find.text('ليلة مسلكي'), findsOneWidget);
    expect(find.text('فردي'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('game-choice-team-code')));
    await tester.pumpAndSettle();

    expect(find.text('فردي'), findsOneWidget);
    expect(find.text('إنشاء فريق'), findsOneWidget);
    expect(find.text('إنشاء غرفة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mafia opens separately and returns to the games picker', (
    tester,
  ) async {
    await _pumpGames(tester);

    await tester.tap(find.byKey(const ValueKey('game-choice-mafia')));
    await tester.pumpAndSettle();

    expect(find.text('إنشاء غرفة'), findsOneWidget);
    expect(find.text('فردي'), findsNothing);
    expect(find.text('إنشاء فريق'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('games-back-to-picker')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('game-choice-team-code')), findsOneWidget);
    expect(find.byKey(const ValueKey('game-choice-mafia')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mafia room setup exposes pace rules seats and reveal policy', (
    tester,
  ) async {
    await _pumpGames(tester);
    await tester.tap(find.byKey(const ValueKey('game-choice-mafia')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء غرفة'));
    await tester.pumpAndSettle();

    expect(find.text('جهّز ليلتك'), findsOneWidget);
    expect(find.text('قياسي'), findsOneWidget);
    expect(find.text('متقدم'), findsOneWidget);
    expect(find.text('كلاسيكي'), findsOneWidget);
    expect(find.text('سريع'), findsOneWidget);
    expect(find.byKey(const ValueKey('mafia-theme-emerald')), findsOneWidget);
    expect(find.byKey(const ValueKey('mafia-theme-royal')), findsOneWidget);
    expect(find.byKey(const ValueKey('mafia-theme-cinema')), findsOneWidget);
    expect(find.text('كشف دور المستبعد'), findsOneWidget);
    expect(find.byKey(const ValueKey('mafia-create-confirm')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tutorial puzzle accepts the documented code without a reward', (
    tester,
  ) async {
    await _pumpGames(tester);
    await tester.tap(find.byKey(const ValueKey('game-choice-team-code')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.help_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('لغز تعليمي بلا مكافأة'), findsOneWidget);
    for (final digit in ['2', '7', '4']) {
      await tester.tap(find.widgetWithText(IconButton, digit));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'تحقق'));
    await tester.pump();

    expect(find.text('صحيح. هكذا تُجمع الأدلة لفتح الخزنة.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('network failure is not presented as an admin shutdown', (
    tester,
  ) async {
    await _pumpGames(tester, api: _FailingGamesApi());

    expect(
      find.byKey(const ValueKey('game-choice-knowledge-map')),
      findsOneWidget,
    );
    expect(
      find.text('اللعبة متوقفة مؤقتًا من الإدارة. سيبقى سجلك محفوظًا.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a room left by the user remains archived but cannot reopen', (
    tester,
  ) async {
    await _pumpGames(tester, api: _LeftRoomGamesApi());
    await tester.tap(find.byKey(const ValueKey('game-choice-team-code')));
    await tester.pumpAndSettle();

    final historyTile = tester.widget<ListTile>(find.byType(ListTile));
    expect(historyTile.onTap, isNull);
    expect(find.textContaining('غادرت هذه الجولة'), findsOneWidget);
    expect((historyTile.trailing! as Icon).icon, Icons.lock_outline_rounded);
  });

  testWidgets('my mafia rooms can be reactivated with chosen rules', (
    tester,
  ) async {
    await _pumpGames(tester, api: _MafiaHistoryGamesApi());
    await tester.tap(find.byKey(const ValueKey('game-choice-mafia')));
    await tester.pumpAndSettle();

    expect(find.text('غرفي'), findsOneWidget);
    expect(find.text('الغرفة M3SLK9'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mafia-reactivate-31')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mafia-reactivate-same-rules')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mafia-reactivate-other-rules')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
