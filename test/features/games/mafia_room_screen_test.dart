import 'dart:async';

import 'package:core_design_system/core_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/games/data/games_api.dart';
import 'package:maslaki/features/games/ui/mafia_room_screen.dart';
import 'package:maslaki/features/games/state/mafia_voice_controller.dart';
import 'package:maslaki/core/realtime/maslaki_realtime_service.dart';

class _NoopRealtime extends MaslakiRealtimeService {
  _NoopRealtime() : super(Dio());

  @override
  Future<bool> bindAuthenticatedSession({bool force = false}) async => false;

  @override
  Future<void> clearSession() async {}

  @override
  Future<void> setAppActive(bool active) async {}

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeDefaultUserChannel() async =>
      null;

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeTopic(String topic) async =>
      null;

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeUserChannel(
    String namespace,
  ) async => null;
}

class _FakeMafiaApi extends GamesApi {
  _FakeMafiaApi(this.value) : super(Dio());

  Map<String, dynamic> value;
  bool? readyValue;
  bool roleAcknowledged = false;
  String? actionType;
  int? actionTargetPlayerId;
  int? kickedPlayerId;
  bool roomClosed = false;
  String? interactionKind;
  int? interactionTargetPlayerId;
  Map<String, dynamic>? interactionResponse;
  int? reportedPlayerId;
  String? reportReason;
  int snapshotReads = 0;
  Completer<Map<String, dynamic>>? delayedSnapshot;
  Completer<Map<String, dynamic>>? delayedVoice;
  bool failMessage = false;
  final messageKeys = <String?>[];

  @override
  Future<Map<String, dynamic>> mafiaSnapshot(int roomId) async {
    snapshotReads++;
    final delayed = delayedSnapshot;
    delayedSnapshot = null;
    return delayed == null ? value : delayed.future;
  }

  @override
  Future<Map<String, dynamic>> mafiaVoiceToken(int roomId) async =>
      delayedVoice != null
      ? delayedVoice!.future
      : {'enabled': false, 'reason': 'LIVEKIT_NOT_CONFIGURED'};

  @override
  Future<void> mafiaHeartbeat(int roomId) async {}

  @override
  Future<Map<String, dynamic>> sendMafiaMessage(
    int roomId, {
    required String body,
    required String channel,
    String? clientMessageId,
  }) async {
    messageKeys.add(clientMessageId);
    if (failMessage) throw StateError('network offline');
    return {
      'ok': true,
      'message': {
        'id': 99,
        'body': body,
        'channel': channel,
        'senderName': 'لاعب 1',
        'seatNumber': 1,
        'clientMessageId': clientMessageId,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> setMafiaReady(int roomId, bool ready) async {
    readyValue = ready;
    value = Map<String, dynamic>.from(value)
      ..['me'] = {
        ...Map<String, dynamic>.from(value['me'] as Map),
        'isReady': ready,
      };
    return value;
  }

  @override
  Future<Map<String, dynamic>> acknowledgeMafiaRole(int roomId) async {
    roleAcknowledged = true;
    value = Map<String, dynamic>.from(value)
      ..['me'] = {
        ...Map<String, dynamic>.from(value['me'] as Map),
        'roleAcknowledged': true,
      };
    return value;
  }

  @override
  Future<Map<String, dynamic>> mafiaAction(
    int roomId, {
    required String type,
    int? targetPlayerId,
    required String commandId,
    int? phaseVersion,
  }) async {
    actionType = type;
    actionTargetPlayerId = targetPlayerId;
    return value;
  }

  @override
  Future<Map<String, dynamic>> kickMafiaPlayer(int roomId, int playerId) async {
    kickedPlayerId = playerId;
    final players = List<Map<String, dynamic>>.from(
      (value['players'] as List).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    )..removeWhere((player) => player['playerId'] == playerId);
    value = Map<String, dynamic>.from(value)..['players'] = players;
    return value;
  }

  @override
  Future<Map<String, dynamic>> closeMafiaRoom(int roomId) async {
    roomClosed = true;
    value = Map<String, dynamic>.from(value)
      ..['room'] = {
        ...Map<String, dynamic>.from(value['room'] as Map),
        'status': 'cancelled',
      };
    return value;
  }

  @override
  Future<Map<String, dynamic>> sendMafiaInteraction(
    int roomId, {
    required String kind,
    int? targetPlayerId,
    required String commandId,
  }) async {
    interactionKind = kind;
    interactionTargetPlayerId = targetPlayerId;
    return interactionResponse ?? {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> reportMafiaPlayer(
    int roomId, {
    required int targetPlayerId,
    required String reason,
    String? details,
    required String commandId,
  }) async {
    reportedPlayerId = targetPlayerId;
    reportReason = reason;
    return {'ok': true, 'reportId': 88};
  }
}

Map<String, dynamic> _snapshot({
  String status = 'lobby',
  String? role,
  bool acknowledged = true,
  int dayNumber = 0,
}) {
  final players = List.generate(
    7,
    (index) => {
      'playerId': index + 1,
      'userId': index + 100,
      'seatNumber': index + 1,
      'name': 'لاعب ${index + 1}',
      'lifeStatus': 'alive',
      'isReady': index != 0,
      'isConnected': true,
      'role': index == 0 ? role : null,
      'isMafiaTeammate': false,
    },
  );
  return {
    'room': {
      'id': 10,
      'inviteCode': 'M7K9Q2',
      'hostUserId': 100,
      'ruleset': 'standard',
      'status': status,
      'maxPlayers': 14,
      'dayNumber': dayNumber,
      'phaseVersion': status == 'lobby' ? 1 : 2,
      'winner': null,
    },
    'phase': {
      'status': status,
      'remainingSeconds': status == 'lobby' ? null : 25,
      'candidateIds': <int>[],
    },
    'me': {
      'playerId': 1,
      'userId': 100,
      'seatNumber': 1,
      'role': role,
      'team': role == 'mafia' ? 'mafia' : 'town',
      'lifeStatus': 'alive',
      'isReady': false,
      'roleAcknowledged': acknowledged,
      'mafiaTeammateIds': <int>[],
    },
    'players': players,
    'events': <Map<String, dynamic>>[],
    'messages': <Map<String, dynamic>>[],
    'voice': {'enabled': false, 'canRequestToken': false},
  };
}

Future<void> _pumpRoom(
  WidgetTester tester,
  _FakeMafiaApi api, {
  Size size = const Size(390, 844),
  MaslakiRealtimeService? realtime,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gamesApiProvider.overrideWithValue(api),
        maslakiRealtimeServiceProvider.overrideWithValue(
          realtime ?? _NoopRealtime(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.themed(MaslakiTheme.original),
        home: const MafiaRoomScreen(roomId: 10),
      ),
    ),
  );
  await _pumpAnimatedRoom(tester);
}

Future<void> _pumpAnimatedRoom(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
}

void main() {
  testWidgets(
    'confirmed reaction renders from its card without another snapshot',
    (tester) async {
      final api = _FakeMafiaApi(_snapshot());
      api.interactionResponse = {
        'ok': true,
        'event': {
          'id': 87,
          'type': 'player_interaction',
          'payload': {
            'kind': 'laugh',
            'senderPlayerId': 1,
            'senderName': 'لاعب 1',
          },
        },
      };
      await _pumpRoom(tester, api);
      final reads = api.snapshotReads;
      await tester.tap(find.byKey(const ValueKey('mafia-reaction-laugh')));
      await tester.pump();
      expect(api.snapshotReads, reads);
      expect(find.byKey(const ValueKey('mafia-effect-87')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('an old in-flight snapshot cannot undo a confirmed command', (
    tester,
  ) async {
    final realtime = _LiveRealtime();
    final before = {..._snapshot(), 'stateVersion': 1};
    final api = _FakeMafiaApi(before);
    await _pumpRoom(tester, api, realtime: realtime);
    final delayed = Completer<Map<String, dynamic>>();
    api.delayedSnapshot = delayed;
    realtime.changed();
    await tester.pump();
    api.value = {...before, 'stateVersion': 2};
    await tester.ensureVisible(find.text('تأكيد الجاهزية'));
    await tester.tap(find.text('تأكيد الجاهزية'));
    await _pumpAnimatedRoom(tester);
    delayed.complete(before);
    await _pumpAnimatedRoom(tester);
    expect(find.text('أنا جاهز'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await realtime.events.close();
  });
  testWidgets('private draft cannot leak into public chat on a phase change', (
    tester,
  ) async {
    final realtime = _LiveRealtime();
    final api = _FakeMafiaApi(
      _snapshot(status: 'night', role: 'mafia', dayNumber: 1),
    );
    await _pumpRoom(tester, api, realtime: realtime);
    await tester.tap(find.byTooltip('المحادثة'));
    await _pumpAnimatedRoom(tester);
    await tester.enterText(
      find.byKey(const ValueKey('mafia-chat-input')),
      'خطة سرية',
    );
    api.value = _snapshot(
      status: 'day_discussion',
      role: 'mafia',
      dayNumber: 1,
    );
    realtime.changed();
    await _pumpAnimatedRoom(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('mafia-chat-input')))
          .controller!
          .text,
      isEmpty,
    );
    api.value = _snapshot(status: 'night', role: 'mafia', dayNumber: 1);
    realtime.changed();
    await _pumpAnimatedRoom(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('mafia-chat-input')))
          .controller!
          .text,
      'خطة سرية',
    );
    await tester.pumpWidget(const SizedBox());
    await realtime.events.close();
  });
  test('disposing while a voice token is loading cannot open a room', () async {
    final api = _FakeMafiaApi(_snapshot())..delayedVoice = Completer();
    final voice = MafiaVoiceController();
    final connection = voice.connect(api, 10);
    voice.dispose();
    api.delayedVoice!.complete({
      'enabled': true,
      'url': 'wss://invalid.test',
      'token': 'unused',
    });
    await connection;
    expect(voice.isConnected, false);
  });

  testWidgets('confirmed commands do not fetch an extra snapshot', (
    tester,
  ) async {
    final api = _FakeMafiaApi(_snapshot());
    await _pumpRoom(tester, api);
    expect(api.snapshotReads, 1);
    await tester.ensureVisible(find.text('تأكيد الجاهزية'));
    await tester.tap(find.text('تأكيد الجاهزية'));
    await _pumpAnimatedRoom(tester);
    expect(api.snapshotReads, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('open chat receives updates and preserves retry draft and key', (
    tester,
  ) async {
    final realtime = _LiveRealtime();
    final api = _FakeMafiaApi(_snapshot());
    await _pumpRoom(tester, api, realtime: realtime);
    await tester.tap(find.byTooltip('المحادثة'));
    await _pumpAnimatedRoom(tester);
    api.value = {
      ...api.value,
      'stateVersion': 2,
      'messages': [
        {
          'id': 1,
          'body': 'وصلت الرسالة مباشرة',
          'channel': 'public',
          'senderName': 'صديق',
          'seatNumber': 2,
        },
      ],
    };
    realtime.changed();
    await _pumpAnimatedRoom(tester);
    expect(find.text('وصلت الرسالة مباشرة'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('mafia-chat-input')),
      'رسالة تجريبية',
    );
    api.failMessage = true;
    await tester.tap(find.byKey(const ValueKey('mafia-chat-send')));
    await _pumpAnimatedRoom(tester);
    expect(find.text('رسالة تجريبية'), findsOneWidget);
    api.failMessage = false;
    await tester.tap(find.byKey(const ValueKey('mafia-chat-send')));
    await _pumpAnimatedRoom(tester);
    expect(api.messageKeys.length, 2);
    expect(api.messageKeys.first, api.messageKeys.last);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('mafia-chat-input')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('رسالة تجريبية'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await realtime.events.close();
  });

  testWidgets('realtime during a fetch queues exactly one follow-up', (
    tester,
  ) async {
    final realtime = _LiveRealtime();
    final api = _FakeMafiaApi(_snapshot());
    await _pumpRoom(tester, api, realtime: realtime);
    final delayed = Completer<Map<String, dynamic>>();
    api.delayedSnapshot = delayed;
    realtime.changed();
    await tester.pump();
    realtime.changed();
    realtime.changed();
    await tester.pump();
    expect(api.snapshotReads, 2);
    delayed.complete(api.value);
    await _pumpAnimatedRoom(tester);
    expect(api.snapshotReads, 3);
    await tester.pumpWidget(const SizedBox());
    await realtime.events.close();
  });
  test(
    'local player mute preference toggles without an active voice room',
    () async {
      final controller = MafiaVoiceController();
      await controller.toggleUserMute(42);
      expect(controller.isUserMuted(42), true);
      expect(controller.mutedUserIds, {42});
      await controller.toggleUserMute(42);
      expect(controller.isUserMuted(42), false);
      controller.dispose();
    },
  );

  testWidgets(
    'animated arena remains clear with fourteen players on a narrow phone',
    (tester) async {
      final data = _snapshot(status: 'day_vote', role: 'citizen', dayNumber: 2);
      data['players'] = List.generate(
        14,
        (index) => {
          'playerId': index + 1,
          'userId': index + 100,
          'seatNumber': index + 1,
          'name': 'لاعب ${index + 1}',
          'lifeStatus': index == 13 ? 'eliminated' : 'alive',
          'isReady': true,
          'isConnected': index != 12,
          'role': index == 0 ? 'citizen' : null,
        },
      );
      final api = _FakeMafiaApi(data);

      await _pumpRoom(tester, api, size: const Size(320, 700));

      expect(find.byKey(const ValueKey('mafia-room-stage')), findsOneWidget);
      expect(find.byKey(const ValueKey('mafia-player-arena')), findsOneWidget);
      expect(find.byKey(const ValueKey('mafia-player-14')), findsOneWidget);
      expect(find.text('13'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lobby shows seven players and lets the host become ready', (
    tester,
  ) async {
    final api = _FakeMafiaApi(_snapshot());
    await _pumpRoom(tester, api);

    expect(find.text('قاعة الانتظار'), findsOneWidget);
    expect(find.text('7 من 14 لاعبين'), findsOneWidget);
    expect(find.text('الصوت الحي غير مهيأ على الخادم'), findsOneWidget);

    await tester.tap(find.text('تأكيد الجاهزية'));
    await _pumpAnimatedRoom(tester);
    expect(api.readyValue, true);
    expect(find.text('أنا جاهز'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role reveal is private and must be acknowledged', (
    tester,
  ) async {
    final api = _FakeMafiaApi(
      _snapshot(status: 'role_reveal', role: 'detective', acknowledged: false),
    );
    await _pumpRoom(tester, api);

    expect(find.text('دورك: المحقق'), findsOneWidget);
    expect(find.textContaining('افحص لاعباً كل ليلة'), findsOneWidget);
    await tester.tap(find.text('حفظت دوري'));
    await _pumpAnimatedRoom(tester);
    expect(api.roleAcknowledged, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('doctor can select and protect their own seat', (tester) async {
    final api = _FakeMafiaApi(
      _snapshot(status: 'night', role: 'doctor', dayNumber: 1),
    );
    await _pumpRoom(tester, api);

    await tester.tap(find.byKey(const ValueKey('mafia-player-1')));
    await tester.pump();
    final submit = find.byKey(const ValueKey('mafia-submit-action'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await _pumpAnimatedRoom(tester);

    expect(api.actionType, 'doctor_protect');
    expect(api.actionTargetPlayerId, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host can kick a player during a live round and close the room', (
    tester,
  ) async {
    final api = _FakeMafiaApi(
      _snapshot(status: 'day_discussion', dayNumber: 1),
    );
    await _pumpRoom(tester, api);

    await tester.tap(find.byKey(const ValueKey('mafia-host-controls')));
    await _pumpAnimatedRoom(tester);
    expect(find.text('إدارة الغرفة'), findsOneWidget);
    expect(find.byKey(const ValueKey('mafia-close-room')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mafia-kick-player-2')));
    await _pumpAnimatedRoom(tester);
    await tester.tap(find.byKey(const ValueKey('mafia-confirm-kick')));
    await _pumpAnimatedRoom(tester);
    expect(api.kickedPlayerId, 2);
    expect(find.text('لاعب 2'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mafia-host-controls')));
    await _pumpAnimatedRoom(tester);
    await tester.tap(find.byKey(const ValueKey('mafia-close-room')));
    await _pumpAnimatedRoom(tester);
    await tester.tap(find.byKey(const ValueKey('mafia-confirm-close')));
    await _pumpAnimatedRoom(tester);

    expect(api.roomClosed, true);
    expect(find.text('أُغلقت الليلة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room controls are hidden from non-host players', (tester) async {
    final snapshot = _snapshot();
    snapshot['room'] = {
      ...Map<String, dynamic>.from(snapshot['room'] as Map),
      'hostUserId': 999,
    };
    await _pumpRoom(tester, _FakeMafiaApi(snapshot));

    expect(find.byKey(const ValueKey('mafia-host-controls')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mafia teammates are visible to each other', (tester) async {
    final snapshot = _snapshot(status: 'night', role: 'mafia', dayNumber: 1);
    snapshot['me'] = {
      ...Map<String, dynamic>.from(snapshot['me'] as Map),
      'mafiaTeammateIds': [1, 2],
    };
    await _pumpRoom(tester, _FakeMafiaApi(snapshot));

    expect(find.text('من فريقك'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('players can send reactions and targeted gifts', (tester) async {
    final api = _FakeMafiaApi(_snapshot());
    await _pumpRoom(tester, api);

    await tester.tap(find.byKey(const ValueKey('mafia-reaction-laugh')));
    await _pumpAnimatedRoom(tester);
    expect(api.interactionKind, 'laugh');
    expect(api.interactionTargetPlayerId, isNull);

    await tester.tap(find.byKey(const ValueKey('mafia-gift-player-2')));
    await _pumpAnimatedRoom(tester);
    await tester.tap(find.byKey(const ValueKey('mafia-gift-rose')));
    await _pumpAnimatedRoom(tester);
    expect(api.interactionKind, 'rose');
    expect(api.interactionTargetPlayerId, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'player actions support persistent local mute and private report',
    (tester) async {
      final api = _FakeMafiaApi(_snapshot());
      await _pumpRoom(tester, api);

      await tester.tap(find.byKey(const ValueKey('mafia-gift-player-2')));
      await _pumpAnimatedRoom(tester);
      await tester.tap(find.byKey(const ValueKey('mafia-local-mute-2')));
      await _pumpAnimatedRoom(tester);
      expect(find.text('تم كتم اللاعب لديك فقط.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mafia-gift-player-2')));
      await _pumpAnimatedRoom(tester);
      expect(find.text('إلغاء الكتم لدي'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mafia-report-2')));
      await _pumpAnimatedRoom(tester);
      expect(find.text('الإبلاغ عن لاعب 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mafia-submit-report')));
      await _pumpAnimatedRoom(tester);
      await tester.pump();

      expect(api.reportedPlayerId, 2);
      expect(api.reportReason, 'harassment');
      expect(find.textContaining('وصل البلاغ إلى الإدارة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrator mission and seasonal profile are shown together', (
    tester,
  ) async {
    final snapshot = _snapshot(
      status: 'day_discussion',
      role: 'citizen',
      dayNumber: 1,
    );
    snapshot['narrator'] = {
      'tone': 'guide',
      'title': 'استيقظت المدينة',
      'body': 'راقبوا التناقضات قبل التصويت.',
    };
    snapshot['mission'] = {
      'type': 'cast_vote',
      'title': 'صوت المدينة',
      'description': 'شارك في تصويت نهاري واحد.',
      'completed': false,
    };
    snapshot['profile'] = {
      'level': 3,
      'points': 175,
      'wins': 2,
      'gamesPlayed': 5,
      'achievements': [
        {'id': 'first_night', 'title': 'أول ليلة'},
      ],
    };
    await _pumpRoom(tester, _FakeMafiaApi(snapshot));

    expect(find.byKey(const ValueKey('mafia-narrator')), findsOneWidget);
    expect(find.text('استيقظت المدينة'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('mafia-secret-mission')),
      250,
    );
    expect(find.byKey(const ValueKey('mafia-secret-mission')), findsOneWidget);
    expect(find.text('صوت المدينة'), findsOneWidget);
    expect(find.byKey(const ValueKey('mafia-player-profile')), findsOneWidget);
    expect(find.textContaining('175 نقطة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed game reveals roles and records one MVP choice', (
    tester,
  ) async {
    final snapshot = _snapshot(
      status: 'completed',
      role: 'detective',
      dayNumber: 3,
    );
    snapshot['room'] = {
      ...Map<String, dynamic>.from(snapshot['room'] as Map),
      'winner': 'town',
    };
    snapshot['summary'] = {
      'winner': 'town',
      'days': 3,
      'eliminations': [
        {'eventId': 20, 'dayNumber': 2, 'seatNumber': 4, 'role': 'mafia'},
      ],
      'honors': <Map<String, dynamic>>[],
      'myHonorPlayerId': null,
    };
    final players = (snapshot['players'] as List).cast<Map<String, dynamic>>();
    players[0]['role'] = 'detective';
    players[1]['role'] = 'mafia';
    final api = _FakeMafiaApi(snapshot);
    await _pumpRoom(tester, api);

    expect(find.byKey(const ValueKey('mafia-game-summary')), findsOneWidget);
    expect(find.text('أشرقت شمس المدينة'), findsOneWidget);
    final honor = find.byKey(const ValueKey('mafia-honor-2'));
    tester.widget<ActionChip>(honor).onPressed!.call();
    await _pumpAnimatedRoom(tester);
    expect(api.interactionKind, 'mvp');
    expect(api.interactionTargetPlayerId, 2);
    expect(tester.takeException(), isNull);
  });
}

class _LiveRealtime extends _NoopRealtime {
  final events = StreamController<MaslakiRealtimeEvent>.broadcast();
  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeDefaultUserChannel() async =>
      events.stream;
  void changed() => events.add(
    const MaslakiRealtimeEvent(
      topic: 'qa',
      event: 'mafia_room_updated',
      data: {'roomId': 10},
      envelope: {},
    ),
  );
}
