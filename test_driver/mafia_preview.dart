import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maslaki/core/realtime/maslaki_realtime_service.dart';
import 'package:maslaki/features/games/data/games_api.dart';
import 'package:maslaki/features/games/ui/mafia_room_screen.dart';

// Manual browser harness using the real screen, HTTP commands and SSE delivery.
class _PreviewRealtime extends MaslakiRealtimeService {
  _PreviewRealtime() : super(Dio());
  @override
  Future<Stream<MaslakiRealtimeEvent>?> subscribeDefaultUserChannel() async {
    final source = _EventSource('http://127.0.0.1:4880/events');
    final stream = StreamController<MaslakiRealtimeEvent>();
    source.onmessage = ((_MessageEvent event) {
      final value = jsonDecode(event.data.toDart) as Map<String, dynamic>;
      stream.add(
        MaslakiRealtimeEvent(
          topic: 'qa',
          event: value['event'] as String,
          data: Map<String, dynamic>.from(value['data'] as Map),
          envelope: const {},
        ),
      );
    }).toJS;
    stream.onCancel = () => source.close();
    return stream.stream;
  }
}

@JS('EventSource')
extension type _EventSource._(JSObject _) implements JSObject {
  external factory _EventSource(String url);
  external set onmessage(JSFunction callback);
  external void close();
}
extension type _MessageEvent(JSObject _) implements JSObject {
  external JSString get data;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4880'));
  final fixture = (await dio.get<Map<String, dynamic>>('/fixture')).data!;
  dio.options.headers['Authorization'] = 'Bearer ${fixture['token']}';
  runApp(
    ProviderScope(
      overrides: [
        gamesApiProvider.overrideWithValue(GamesApi(dio)),
        maslakiRealtimeServiceProvider.overrideWithValue(_PreviewRealtime()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'TajawalLocal'),
        home: MafiaRoomScreen(roomId: (fixture['roomId'] as num).toInt()),
      ),
    ),
  );
}
