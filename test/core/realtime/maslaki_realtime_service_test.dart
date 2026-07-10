import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/realtime/maslaki_realtime_service.dart';
import 'package:maslaki/core/storage/secure_storage.dart';

class _NoTokenStore extends SecureStore {
  _NoTokenStore() : super();

  @override
  Future<String?> readToken() async => null;
}

class _CountingAdapter implements HttpClientAdapter {
  int fetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    return ResponseBody.fromString(
      '{"message":"NO_TOKEN"}',
      401,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'bindAuthenticatedSession returns false without an access token and does not request /api/realtime/token',
    () async {
      final adapter = _CountingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = MaslakiRealtimeService(dio, store: _NoTokenStore());

      final ready = await service.bindAuthenticatedSession();

      expect(ready, isFalse);
      expect(adapter.fetchCount, 0);
    },
  );
}
