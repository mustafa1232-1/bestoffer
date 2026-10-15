import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/notifications/attention_alert_service.dart';
import 'package:maslaki/features/notifications/data/notifications_api.dart';
import 'package:maslaki/features/social/data/social_api.dart';
import 'package:maslaki/features/social/state/social_call_voice_controller.dart';
import 'package:maslaki/features/social/ui/social_call_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _Alert implements AttentionAlertService {
  @override
  Future<void> play() async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

class _Audio implements SocialCallAudioSession {
  @override
  bool connected = false;
  @override
  bool reconnecting = false;
  @override
  bool canPlaybackAudio = true;
  @override
  bool peerPresent = true;
  @override
  bool remoteAudioReady = true;
  VoidCallback? changed;
  int joins = 0;
  final captures = <bool>[];
  @override
  void onChanged(VoidCallback callback) => changed = callback;
  @override
  Future<void> connect(String url, String token) async {
    joins++;
    connected = true;
    changed?.call();
  }

  @override
  Future<void> microphone(bool enabled) async {
    captures.add(enabled);
  }

  @override
  Future<void> speaker(bool enabled) async {}
  @override
  Future<void> startAudio() async {}
  @override
  Future<void> close() async {
    connected = false;
  }
}

class _Api extends SocialApi {
  _Api() : super(Dio());
  Map<String, dynamic>? session;
  final signals = <String>[];
  List<Map<String, dynamic>> pending = [];
  Completer<Map<String, dynamic>>? tokenGate;
  bool rejectAccept = false;
  int starts = 0;
  int tokens = 0;
  @override
  Future<Map<String, dynamic>> getThreadCallState({
    required int threadId,
    int signalLimit = 160,
  }) async => {
    'session': session == null ? null : Map.of(session!),
    'signals': pending,
  };
  @override
  Future<Map<String, dynamic>> startThreadCall({
    required int threadId,
    bool preferLiveKit = false,
  }) async {
    expect(preferLiveKit, isTrue);
    starts++;
    session = {'id': 7, 'status': 'ringing', 'voiceTransport': 'auto'};
    return {'session': Map.of(session!)};
  }

  @override
  Future<Map<String, dynamic>> sendThreadCallSignal({
    required int threadId,
    int? sessionId,
    required String signalType,
    Map<String, dynamic>? signalPayload,
  }) async {
    signals.add(signalType);
    if (signalType == 'accept') {
      if (rejectAccept) throw StateError('network unavailable');
      expect(signalPayload?['transport'], 'livekit');
      session = {'id': 7, 'status': 'active', 'voiceTransport': 'livekit'};
    }
    return {'session': session == null ? null : Map.of(session!)};
  }

  @override
  Future<Map<String, dynamic>> getThreadCallVoiceToken({
    required int threadId,
    required int sessionId,
  }) async {
    tokens++;
    return tokenGate?.future ??
        Future.value({'url': 'wss://test', 'token': 'test'});
  }
}

class _Events extends NotificationsApi {
  _Events() : super(Dio());
  final events = StreamController<NotificationLiveEvent>.broadcast();
  @override
  Stream<NotificationLiveEvent> streamEvents({
    int? lastEventId,
    String? channel,
  }) => events.stream;
  void send(Map<String, dynamic> data) => events.add(
    NotificationLiveEvent(
      event: 'social_call_update',
      data: {'threadId': 1, ...data},
    ),
  );
}

Future<void> _pumpCall(
  WidgetTester tester,
  _Api api,
  _Events events,
  _Audio audio, {
  bool caller = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        socialCallApiProvider.overrideWithValue(api),
        socialCallLiveApiProvider.overrideWithValue(events),
        attentionAlertServiceProvider.overrideWithValue(_Alert()),
        socialCallVoiceFactoryProvider.overrideWithValue(
          () => SocialCallVoiceController(factory: () => audio),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SocialCallScreen(
          threadId: 1,
          isCaller: caller,
          initialSessionId: caller ? null : 7,
          remoteDisplayName: 'Peer',
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late _Api api;
  late _Events events;
  late _Audio audio;
  late List<String> legacyCalls;
  setUp(() {
    api = _Api()
      ..session = {'id': 7, 'status': 'ringing', 'voiceTransport': 'auto'};
    events = _Events();
    audio = _Audio();
    legacyCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('FlutterWebRTC.Method'), (
          call,
        ) async {
          legacyCalls.add(call.method);
          throw PlatformException(code: 'legacy-must-not-be-used');
        });
  });
  tearDown(() async {
    await events.events.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Method'),
          null,
        );
  });

  testWidgets(
    'incoming call can answer without SDP or opening microphone first',
    (tester) async {
      await _pumpCall(tester, api, events, audio);
      expect(find.text('Answer'), findsOneWidget);
      expect(audio.joins, 0);
      expect(audio.captures, isEmpty);
      expect(legacyCalls, isEmpty);
      expect(api.signals, ['ringing']);
      await tester.tap(find.text('Answer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.signals, ['ringing', 'accept']);
      expect(api.tokens, 1);
      expect(audio.joins, 1);
      expect(audio.captures, [true]);
      expect(legacyCalls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(audio.connected, isFalse);
    },
  );

  testWidgets('server call role overrides a stale outgoing navigation intent', (
    tester,
  ) async {
    api.session!['isCaller'] = false;
    await _pumpCall(tester, api, events, audio, caller: true);
    expect(api.starts, 0);
    expect(find.text('Answer'), findsOneWidget);
    expect(audio.captures, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'caller negotiates LiveKit and stale ringing cannot undo acceptance',
    (tester) async {
      api.session = null;
      await _pumpCall(tester, api, events, audio, caller: true);
      expect(api.starts, 1);
      events.send({
        'session': api.session,
        'signal': {
          'id': 1,
          'signalType': 'ringing',
          'signalPayload': {'transport': 'livekit'},
        },
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(legacyCalls, isEmpty);
      expect(api.signals, isEmpty);
      api.session = {'id': 7, 'status': 'active', 'voiceTransport': 'livekit'};
      events.send({'session': api.session});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.connected, isTrue);
      events.send({
        'eventType': 'outgoing_call',
        'session': {'id': 7, 'status': 'ringing', 'voiceTransport': 'auto'},
      });
      await tester.pump();
      expect(api.tokens, 1);
      expect(find.text('Call connected'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('rejected acceptance keeps the Answer action available', (
    tester,
  ) async {
    api.rejectAccept = true;
    await _pumpCall(tester, api, events, audio);
    await tester.tap(find.text('Answer'));
    await tester.pump();
    expect(find.text('Answer'), findsOneWidget);
    expect(audio.joins, 0);
    api.rejectAccept = false;
    await tester.tap(find.text('Answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(audio.joins, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'disposing while fetching credentials never joins or captures later',
    (tester) async {
      api.tokenGate = Completer<Map<String, dynamic>>();
      await _pumpCall(tester, api, events, audio);
      await tester.tap(find.text('Answer'));
      await tester.pump();
      expect(api.tokens, 1);
      await tester.pumpWidget(const SizedBox());
      api.tokenGate!.complete({'url': 'wss://test', 'token': 'test'});
      await tester.pump();
      expect(audio.joins, 0);
      expect(audio.captures, isEmpty);
    },
  );

  testWidgets('room joined without peer audio is not labelled connected', (
    tester,
  ) async {
    audio.peerPresent = false;
    audio.remoteAudioReady = false;
    await _pumpCall(tester, api, events, audio);
    await tester.tap(find.text('Answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Call connected'), findsNothing);
    expect(
      find.text('Waiting for the other participant to join audio'),
      findsOneWidget,
    );
    audio.peerPresent = true;
    audio.remoteAudioReady = true;
    audio.changed?.call();
    await tester.pump();
    expect(find.text('Call connected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('terminal room disconnect obtains a fresh token and reconnects', (
    tester,
  ) async {
    await _pumpCall(tester, api, events, audio);
    await tester.tap(find.text('Answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(audio.joins, 1);
    audio.connected = false;
    audio.changed?.call();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.tokens, 2);
    expect(audio.joins, 2);
    expect(audio.connected, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('legacy offer arriving before Answer does not capture audio', (
    tester,
  ) async {
    api.session!['voiceTransport'] = 'webrtc';
    api.pending = [
      {
        'id': 1,
        'signalType': 'offer',
        'signalPayload': {'type': 'offer', 'sdp': 'legacy'},
      },
    ];
    await _pumpCall(tester, api, events, audio);
    expect(find.text('Answer'), findsOneWidget);
    expect(legacyCalls, isEmpty);
    expect(audio.captures, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
