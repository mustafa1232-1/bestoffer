import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/realtime/maslaki_realtime_service.dart';
import 'package:maslaki/features/notifications/data/notifications_api.dart';
import 'package:maslaki/features/orders/data/orders_api.dart';
import 'package:maslaki/features/taxi/data/taxi_api.dart';

void main() {
  group('Supabase-first realtime wrappers', () {
    late List<StreamController<MaslakiRealtimeEvent>> realtimeControllers;

    setUp(() {
      realtimeControllers = <StreamController<MaslakiRealtimeEvent>>[];
    });

    tearDown(() async {
      for (final controller in realtimeControllers) {
        await controller.close();
      }
    });

    test(
      'NotificationsApi emits synthetic connected before realtime events',
      () async {
        final realtime = _FakeRealtimeClient()
          ..userChannels['notifications'] = _openController(
            realtimeControllers,
            const MaslakiRealtimeEvent(
              topic: 'notifications:user:77',
              event: 'notification',
              data: <String, dynamic>{
                'notification': {'id': 9},
              },
              eventId: 51,
              envelope: <String, dynamic>{},
            ),
          ).stream;

        final api = NotificationsApi(Dio(), realtime: realtime);
        final events = await api
            .streamEvents(channel: 'notifications')
            .take(2)
            .toList()
            .timeout(const Duration(seconds: 2));

        expect(events[0].event, 'connected');
        expect(events[1].event, 'notification');
        expect(events[1].eventId, 51);
        expect(
          (events[1].data['notification'] as Map<String, dynamic>)['id'],
          9,
        );
      },
    );

    test(
      'NotificationsApi thread stream falls back to SSE and keeps resync_required',
      () async {
        final dio = Dio()
          ..httpClientAdapter = _FakeStreamAdapter((options) {
            expect(options.path, '/api/notifications/stream');
            final sse = [
              'event: resync_required',
              'data: {"latestEventId": 90}',
              '',
              'event: social_chat_message',
              'data: {"threadId": 7, "body": "keep"}',
              '',
              'event: social_chat_message',
              'data: {"threadId": 8, "body": "drop"}',
              '',
            ].join('\n');
            return ResponseBody.fromString(
              sse,
              200,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>['text/event-stream'],
              },
            );
          });

        final api = NotificationsApi(dio, realtime: _FakeRealtimeClient());
        final events = await api
            .streamThreadEvents(threadId: 7)
            .take(2)
            .toList()
            .timeout(const Duration(seconds: 2));

        expect(events.map((event) => event.event), <String>[
          'resync_required',
          'social_chat_message',
        ]);
        expect(events.last.data['body'], 'keep');
      },
    );

    test(
      'TaxiApi ride stream falls back to SSE and filters by ride topic',
      () async {
        final dio = Dio()
          ..httpClientAdapter = _FakeStreamAdapter((options) {
            expect(options.path, '/api/taxi/stream');
            final sse = [
              'event: resync_required',
              'data: {"latestEventId": 101}',
              '',
              'event: taxi_ride_update',
              'data: {"rideId": 44, "status": "captain_arriving"}',
              '',
              'event: taxi_ride_update',
              'data: {"rideId": 99, "status": "drop"}',
              '',
            ].join('\n');
            return ResponseBody.fromString(
              sse,
              200,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>['text/event-stream'],
              },
            );
          });

        final api = TaxiApi(dio, realtime: _FakeRealtimeClient());
        final events = await api
            .streamRideEvents(rideId: 44)
            .take(2)
            .toList()
            .timeout(const Duration(seconds: 2));

        expect(events.map((event) => event.event), <String>[
          'resync_required',
          'taxi_ride_update',
        ]);
        expect(events.last.data['status'], 'captain_arriving');
      },
    );

    test('OrdersApi uses default user channel before fallback', () async {
      final realtime = _FakeRealtimeClient()
        ..defaultUserChannel = _openController(
          realtimeControllers,
          const MaslakiRealtimeEvent(
            topic: 'user:77',
            event: 'order_tracking_update',
            data: <String, dynamic>{
              'orderId': 12,
              'stage': 'heading_to_customer',
            },
            eventId: 19,
            envelope: <String, dynamic>{},
          ),
        ).stream;

      final api = OrdersApi(Dio(), realtime: realtime);
      final events = await api
          .streamTrackingEvents(orderId: 12)
          .take(2)
          .toList()
          .timeout(const Duration(seconds: 2));

      expect(events.first.event, 'connected');
      expect(events.last.event, 'order_tracking_update');
      expect(events.last.data['stage'], 'heading_to_customer');
      expect(events.last.eventId, 19);
    });
  });
}

StreamController<MaslakiRealtimeEvent> _openController(
  List<StreamController<MaslakiRealtimeEvent>> bucket,
  MaslakiRealtimeEvent event,
) {
  final controller = StreamController<MaslakiRealtimeEvent>();
  bucket.add(controller);
  scheduleMicrotask(() {
    controller.add(event);
  });
  return controller;
}

class _FakeRealtimeClient implements MaslakiRealtimeClient {
  final Map<String, Stream<MaslakiRealtimeEvent>?> userChannels =
      <String, Stream<MaslakiRealtimeEvent>?>{};
  final Map<String, Stream<MaslakiRealtimeEvent>?> topics =
      <String, Stream<MaslakiRealtimeEvent>?>{};
  Stream<MaslakiRealtimeEvent>? defaultUserChannel;

  @override
  Future<bool> bindAuthenticatedSession({bool force = false}) async {
    return true;
  }

  @override
  Future<void> clearSession() async {}

  @override
  Future<void> setAppActive(bool active) async {}

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeTopic(String topic) async {
    return topics[topic];
  }

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeDefaultUserChannel() async {
    return defaultUserChannel;
  }

  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeUserChannel(
    String namespace,
  ) async {
    return userChannels[namespace];
  }
}

class _FakeStreamAdapter implements HttpClientAdapter {
  _FakeStreamAdapter(this._responder);

  final ResponseBody Function(RequestOptions options) _responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _responder(options);
  }

  @override
  void close({bool force = false}) {}
}
