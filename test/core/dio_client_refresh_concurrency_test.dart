import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/network/dio_client.dart';
import 'package:maslaki/core/platform/app_flavor.dart';
import 'package:maslaki/core/storage/secure_storage.dart';

class _MemorySecureStore extends SecureStore {
  _MemorySecureStore({
    String? accessToken,
    String? refreshToken,
    String? deviceId,
  })  : _accessToken = accessToken,
        _refreshToken = refreshToken,
        _deviceId = deviceId,
        super(flavor: AppFlavor.user);

  String? _accessToken;
  String? _refreshToken;
  String? _deviceId;

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _deviceId = null;
  }

  @override
  Future<String?> readString(String key) async {
    if (key == 'device_id') return _deviceId;
    if (key == 'refresh_token') return _refreshToken;
    return null;
  }

  @override
  Future<String?> readToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> saveToken(String token) async {
    _accessToken = token;
  }

  @override
  Future<void> saveAuthTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    _accessToken = accessToken;
    if (refreshToken != null && refreshToken.trim().isNotEmpty) {
      _refreshToken = refreshToken.trim();
    }
  }

  @override
  Future<void> writeString(String key, String value) async {
    if (key == 'device_id') {
      _deviceId = value;
    } else if (key == 'refresh_token') {
      _refreshToken = value;
    }
  }
}

abstract class _BaseRefreshAdapter implements HttpClientAdapter {
  int refreshCalls = 0;
  int protectedCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path == '/api/auth/refresh') {
      return handleRefresh();
    }

    if (path == '/protected') {
      protectedCalls += 1;
      final auth = '${options.headers['Authorization'] ?? ''}';
      final ok = auth.trim() == 'Bearer rotated-access-token';
      return ResponseBody.fromString(
        jsonEncode(<String, dynamic>{
          'message': ok ? 'OK' : 'INVALID_TOKEN',
          'ok': ok,
          'authorization': auth,
        }),
        ok ? 200 : 401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'ok': true}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  Future<ResponseBody> handleRefresh();
}

class _SingleRefreshAdapter extends _BaseRefreshAdapter {
  @override
  Future<ResponseBody> handleRefresh() async {
    refreshCalls += 1;
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{
        'token': 'rotated-access-token',
        'refreshToken': 'rotated-refresh-token',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _StaleRefreshAdapter extends _BaseRefreshAdapter {
  final Completer<void> _secondRefreshCompleted = Completer<void>();

  @override
  Future<ResponseBody> handleRefresh() async {
    refreshCalls += 1;
    if (refreshCalls == 1) {
      await _secondRefreshCompleted.future.timeout(
        const Duration(seconds: 5),
      );
      return ResponseBody.fromString(
        jsonEncode(<String, dynamic>{'message': 'INVALID_REFRESH_TOKEN'}),
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (!_secondRefreshCompleted.isCompleted) {
      _secondRefreshCompleted.complete();
    }
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{
        'token': 'rotated-access-token',
        'refreshToken': 'rotated-refresh-token',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('50 concurrent requests reuse a single refresh flight', () async {
    final store = _MemorySecureStore(
      accessToken: 'legacy-access-token',
      refreshToken: 'legacy-refresh-token',
      deviceId: 'device-a',
    );
    final adapter = _SingleRefreshAdapter();
    final client = DioClient(store);
    client.dio.httpClientAdapter = adapter;
    client.dio.options.baseUrl = 'http://127.0.0.1';

    final results = await Future.wait(
      List.generate(50, (_) => client.dio.get<dynamic>('/protected')),
    );

    expect(adapter.refreshCalls, 1);
    expect(adapter.protectedCalls, 100);
    expect(results.every((response) => response.statusCode == 200), isTrue);
    expect(store.readToken(), completion('rotated-access-token'));
    expect(store.readRefreshToken(), completion('rotated-refresh-token'));
  });

  test(
    'stale refresh failure from one DioClient does not clear a later success',
    () async {
      final store = _MemorySecureStore(
        accessToken: 'legacy-access-token',
        refreshToken: 'legacy-refresh-token',
        deviceId: 'device-b',
      );
      final adapter = _StaleRefreshAdapter();
      final clientA = DioClient(store);
      final clientB = DioClient(store);
      clientA.dio.httpClientAdapter = adapter;
      clientB.dio.httpClientAdapter = adapter;
      clientA.dio.options.baseUrl = 'http://127.0.0.1';
      clientB.dio.options.baseUrl = 'http://127.0.0.1';

      final first = clientA.dio.get<dynamic>('/protected');
      final second = clientB.dio.get<dynamic>('/protected');

      final settled = await Future.wait<Object>([
        first.then<Object>((response) => response).catchError((error) => error),
        second.then<Object>((response) => response).catchError((error) => error),
      ]);
      expect(adapter.refreshCalls, 2);
      expect(
        settled.whereType<Response<dynamic>>().any((response) {
          return response.statusCode == 200;
        }),
        isTrue,
      );
      expect(await store.readToken(), 'rotated-access-token');
      expect(await store.readRefreshToken(), 'rotated-refresh-token');
      expect(await store.readGuestMode(), isFalse);
    },
  );
}
