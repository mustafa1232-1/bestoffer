import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/games/data/games_api.dart';
import 'package:maslaki/features/games/ui/knowledge_game_screen.dart';
import 'package:maslaki/features/games/ui/knowledge_tournament_bracket.dart';
import 'package:maslaki/features/games/state/knowledge_match_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _KnowledgeGamesApi extends GamesApi {
  _KnowledgeGamesApi() : super(Dio());
  int matchListCalls = 0;
  int roomCalls = 0;
  int seatJoinCalls = 0;
  bool matchReady = false;
  String? seatedSide;
  int roomTeamSize = 1;
  int roomOccupiedSeats = 0;
  int createdBestOf = 0;
  int bracketCalls = 0;
  bool tournamentFinished = false;

  @override
  Future<Map<String, dynamic>> knowledgeBracket(int eventId) async {
    bracketCalls++;
    return {
      'event': {'id': eventId, 'title': 'بطولة مسلكي', 'bestOf': 3},
      'teams': [],
      'rounds': [
        {
          'number': 1,
          'matches': [
            {
              'id': 91,
              'round': 1,
              'matchNumber': 1,
              'status': 'completed',
              'teamA': {'id': 1, 'name': 'فريق دجلة'},
              'teamB': {'id': 2, 'name': 'فريق النخيل'},
              'winsA': 2,
              'winsB': 1,
              'canPlay': true,
              'winnerTeamId': 1,
            },
          ],
        },
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> knowledgeEvents() async => [
    {
      'id': 42,
      'type': 'tournament',
      'title': 'بطولة مسلكي التجريبية',
      'status': 'registration',
      'teamSize': 2,
      'maxTeams': 12,
      'registeredTeams': 5,
      'prize': {'title': 'شارة الأبطال', 'mock': true},
    },
    {
      'id': 13,
      'type': 'duel',
      'title': 'Public room',
      'status': 'registration',
      'teamSize': 1,
      'isMine': false,
      'isPrivate': false,
      'occupiedSeats': 0,
      'totalSeats': 2,
    },
  ];

  @override
  Future<Map<String, dynamic>> createKnowledgeDuel({
    int teamSize = 1,
    bool isPrivate = false,
    int bestOf = 3,
  }) async {
    createdBestOf = bestOf;
    return {'eventId': 7, 'joinCode': 'M7SLK42'};
  }

  @override
  Future<Map<String, dynamic>> lookupKnowledgeRoom(String code) async => {
    'id': 7,
    'eventType': 'duel',
    'title': 'تحدي خريطة المعرفة',
    'teamSize': 1,
    'isPrivate': false,
  };

  @override
  Future<Map<String, dynamic>> knowledgeRoom(
    int eventId, {
    String? code,
  }) async {
    roomCalls++;
    List<Map<String, dynamic>> players(String side) {
      return seatedSide == side
          ? [
              {'name': 'لاعب'},
            ]
          : <Map<String, dynamic>>[];
    }

    return {
      'id': eventId,
      'status': 'registration',
      'teamSize': roomTeamSize,
      'isPrivate': false,
      'isMine': false,
      'isMember': seatedSide != null,
      'occupiedSeats': roomOccupiedSeats,
      'totalSeats': roomTeamSize * 2,
      'teams': [
        {'side': 'a', 'occupied': players('a').length, 'players': players('a')},
        {'side': 'b', 'occupied': players('b').length, 'players': players('b')},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> joinKnowledgeRoomSeat(
    int eventId, {
    required String side,
    String? code,
  }) async {
    seatJoinCalls++;
    seatedSide = side;
    roomOccupiedSeats = 1;
    return knowledgeRoom(eventId);
  }

  @override
  Future<Map<String, dynamic>> closeKnowledgeRoom(int eventId) async => {
    'id': eventId,
    'status': 'closed',
  };

  @override
  Future<Map<String, dynamic>> reactivateKnowledgeRoom(int eventId) async => {
    'id': eventId,
    'status': 'registration',
  };

  @override
  Future<Map<String, dynamic>> joinKnowledgeTeam(String code) async => {
    'eventId': 7,
    'eventTitle': 'تحدي خريطة المعرفة',
    'eventType': 'duel',
    'teamSize': 1,
    'joinCode': code,
  };

  @override
  Future<List<Map<String, dynamic>>> knowledgeMatches(int eventId) async {
    matchListCalls++;
    if (!matchReady) return [];
    return [
      {
        'id': 91,
        'status': 'active',
        'round': 1,
        'matchNumber': 1,
        'scoreA': 0,
        'scoreB': 0,
        'teamA': 'الفريق الأول',
        'teamB': 'الفريق الثاني',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> knowledgeMatch(int matchId) async => {
    if (tournamentFinished) 'phase': 'finished',
    'match': {
      'id': matchId,
      'status': tournamentFinished ? 'completed' : 'active',
      if (tournamentFinished) ...{
        'eventType': 'tournament',
        'eventId': 42,
        'winnerTeamId': 1,
        'series': {
          'bestOf': 3,
          'game': 3,
          'winsA': 2,
          'winsB': 1,
          'winsRequired': 2,
        },
      },
      'questionNumber': 0,
      'mySide': 'a',
      'teamSize': 1,
      'teams': {
        'a': {'id': 1, 'name': 'الفريق الأول', 'score': 0, 'members': []},
        'b': {'id': 2, 'name': 'الفريق الثاني', 'score': 0, 'members': []},
      },
      'territories': {'a': [], 'b': []},
      'availableDistricts': [],
      'districts': [],
    },
    'question': null,
    'answered': false,
    'lastAnswer': null,
    'chat': {
      'messages': [
        {'id': 1, 'channel': 'team', 'name': 'عضو الفريق', 'body': 'جاهز؟'},
      ],
      'publicEnabled': false,
      'consent': {
        'enabled': false,
        'ownTeam': {'optedIn': 0, 'total': 1, 'required': 1},
        'opponentTeam': {'optedIn': 0, 'total': 1, 'required': 1},
      },
      'reactions': [],
    },
  };
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'tournament polling pauses in match and return reuses the same bracket',
    (tester) async {
      final api = _KnowledgeGamesApi()..tournamentFinished = true;
      tester.view.physicalSize = const Size(390, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gamesApiProvider.overrideWithValue(api),
            knowledgeRealtimeProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: KnowledgeEventScreen(
              event: {'id': 42, 'title': 'بطولة مسلكي'},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final initial = api.bracketCalls;
      await tester.pump(const Duration(seconds: 5));
      expect(api.bracketCalls, initial + 1);
      final card = find.byType(KnowledgeBracketMatch).last;
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final hidden = api.bracketCalls;
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(api.bracketCalls, hidden);
      final back = find.text('مخطط البطولة والمواجهة التالية');
      await tester.ensureVisible(back);
      await tester.tap(back);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byType(KnowledgeEventScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(api.bracketCalls, hidden + 1);
      await tester.pump(const Duration(seconds: 5));
      expect(api.bracketCalls, hidden + 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('knowledge game creates a duel with a shareable waiting room', (
    tester,
  ) async {
    final api = _KnowledgeGamesApi();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesApiProvider.overrideWithValue(api),
          knowledgeRealtimeProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: KnowledgeGameScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('بطولة مسلكي التجريبية'), findsOneWidget);
    expect(find.text('سجّل فريقاً'), findsOneWidget);
    await tester.tap(find.text('إنشاء غرفة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 جولات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فرد ضد فرد'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.ensureVisible(find.text('غرفة عامة'));
    await tester.tap(find.text('غرفة عامة'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('غرفتك جاهزة للتحدي'), findsOneWidget);
    expect(find.text('M7SLK42'), findsOneWidget);
    expect(api.createdBestOf, 5);
    await tester.pump(const Duration(seconds: 2));
    expect(api.roomCalls, greaterThan(0));
    expect(find.text('مقعد شاغر'), findsWidgets);
    await tester.tap(find.text('اجلس').first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.seatJoinCalls, 1);
    expect(api.matchListCalls, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('joining by code opens a visible waiting room', (tester) async {
    final api = _KnowledgeGamesApi();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesApiProvider.overrideWithValue(api),
          knowledgeRealtimeProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: KnowledgeGameScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('دخول برمز'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'M7SLK42');
    await tester.tap(find.text('انضمام'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('غرفتك جاهزة للتحدي'), findsOneWidget);
    expect(find.text('M7SLK42'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public room opens its lobby and lets the player take a seat', (
    tester,
  ) async {
    final api = _KnowledgeGamesApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesApiProvider.overrideWithValue(api),
          knowledgeRealtimeProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: KnowledgeGameScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Public room'), findsOneWidget);
    await tester.tap(find.text('Public room'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('اجلس'), findsWidgets);
    await tester.tap(find.text('اجلس').first);
    await tester.pump(const Duration(milliseconds: 200));

    expect(api.seatJoinCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('even players on one team are prompted to fill the opponent', (
    tester,
  ) async {
    final api = _KnowledgeGamesApi()
      ..roomTeamSize = 2
      ..seatedSide = 'a'
      ..roomOccupiedSeats = 2;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesApiProvider.overrideWithValue(api),
          knowledgeRealtimeProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: KnowledgeWaitingRoomScreen(
              eventId: 13,
              joinCode: '',
              title: 'Test room',
              teamSize: 2,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text(
        'الغرفة تنتظر اكتمال الفريقين؛ شارك الرمز وادعُ لاعبين للمقاعد المتبقية.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('waiting room opens a match as soon as one is ready', (
    tester,
  ) async {
    final api = _KnowledgeGamesApi();
    api.matchReady = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesApiProvider.overrideWithValue(api),
          knowledgeRealtimeProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: KnowledgeWaitingRoomScreen(
              eventId: 7,
              joinCode: 'M7SLK42',
              title: 'تحدي خريطة المعرفة',
              teamSize: 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.matchListCalls, greaterThan(0));
    expect(find.text('خريطة المعرفة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'knowledge match shows team chat and requires consent for public chat',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gamesApiProvider.overrideWithValue(_KnowledgeGamesApi()),
            knowledgeRealtimeProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: KnowledgeMatchScreen(matchId: 91),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.scrollUntilVisible(
        find.text('دردشة الفريق والصوت'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('knowledge-content')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('دردشة الفريق والصوت'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('تواصل الفريقين'), findsOneWidget);
      expect(find.text('صوت الفريق'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('جاهز؟'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
