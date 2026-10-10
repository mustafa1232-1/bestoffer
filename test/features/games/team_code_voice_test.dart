import 'package:core_design_system/core_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/realtime/maslaki_realtime_service.dart';
import 'package:maslaki/features/games/data/games_api.dart';
import 'package:maslaki/features/games/state/team_code_voice_controller.dart';
import 'package:maslaki/features/games/ui/team_code_room_screen.dart';

class _NoopRealtime extends MaslakiRealtimeService {
  _NoopRealtime() : super(Dio());

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeDefaultUserChannel() async =>
      null;
}

class _FakeTeamCodeApi extends GamesApi {
  _FakeTeamCodeApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> teamCodeVoiceToken(int roomId) async => {
    'enabled': false,
    'reason': 'LIVEKIT_NOT_CONFIGURED',
  };

  @override
  Future<Map<String, dynamic>> snapshot(int roomId) async => {
    'room': {
      'id': roomId,
      'inviteCode': 'CODE42',
      'mode': 'cooperative',
      'status': 'lobby',
      'hostUserId': 7,
      'stateVersion': 1,
    },
    'me': {'membershipId': 1, 'userId': 7},
    'members': [
      {
        'membershipId': 1,
        'userId': 7,
        'seatNumber': 1,
        'name': 'مصطفى',
        'isReady': false,
        'isActive': true,
        'isConnected': true,
      },
      {
        'membershipId': 2,
        'userId': 8,
        'seatNumber': 2,
        'name': 'علي',
        'isReady': false,
        'isActive': true,
        'isConnected': true,
      },
    ],
    'session': null,
    'round': null,
    'proposal': null,
    'messages': <Map<String, dynamic>>[],
    'results': <Map<String, dynamic>>[],
    'voice': {'enabled': true, 'canRequestToken': true},
  };

  @override
  Future<void> heartbeat(int roomId) async {}
}

void main() {
  test(
    'team code microphone preference toggles before a room connects',
    () async {
      final controller = TeamCodeVoiceController();
      final initial = controller.microphoneRequested;
      await controller.toggleMicrophone();
      expect(controller.microphoneRequested, isNot(initial));
      controller.dispose();
    },
  );

  test(
    'disabled LiveKit access settles without reconnecting forever',
    () async {
      final controller = TeamCodeVoiceController();
      await controller.connect(_FakeTeamCodeApi(), 42);
      expect(controller.state, TeamCodeVoiceState.disabled);
      expect(controller.isConnected, isFalse);
      controller.dispose();
    },
  );

  testWidgets('cooperative room exposes a clear voice control bar', (
    tester,
  ) async {
    final api = _FakeTeamCodeApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesApiProvider.overrideWithValue(api),
          maslakiRealtimeServiceProvider.overrideWithValue(_NoopRealtime()),
        ],
        child: MaterialApp(
          theme: AppTheme.themed(MaslakiTheme.original),
          home: const TeamCodeRoomScreen(roomId: 42),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('الصوت غير متاح'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
  });
}
