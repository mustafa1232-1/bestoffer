import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/network/dio_client.dart';
import 'package:maslaki/core/network/session_invalidation.dart';
import 'package:maslaki/core/platform/app_flavor.dart';
import 'package:maslaki/core/storage/secure_storage.dart';

class _MemorySecureStore extends SecureStore {
  _MemorySecureStore({
    String? accessToken,
    String? refreshToken,
    String? deviceId,
  }) : super(flavor: AppFlavor.user) {
    if (accessToken != null) {
      _values['access_token'] = accessToken;
    }
    if (refreshToken != null) {
      _values['refresh_token'] = refreshToken;
    }
    _values['device_id'] = deviceId ?? 'device-1';
  }

  final Map<String, String> _values = <String, String>{};
  int clearCount = 0;
  bool guestMode = false;

  @override
  Future<void> clear() async {
    clearCount++;
    _values.clear();
  }

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> saveToken(String token) async {
    _values['access_token'] = token;
  }

  @override
  Future<void> saveAuthTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    _values['access_token'] = accessToken;
    if (refreshToken != null && refreshToken.trim().isNotEmpty) {
      _values['refresh_token'] = refreshToken.trim();
    }
  }

  @override
  Future<String?> readToken() async => _values['access_token'];

  @override
  Future<String?> readRefreshToken() async => _values['refresh_token'];

  @override
  Future<void> saveGuestMode(bool enabled) async {
    guestMode = enabled;
    if (enabled) {
      _values['guest_mode_active'] = '1';
    } else {
      _values.remove('guest_mode_active');
    }
  }

  @override
  Future<bool> readGuestMode() async => guestMode;

  String? value(String key) => _values[key];
}

class _RefreshConcurrencyAdapter implements HttpClientAdapter {
  _RefreshConcurrencyAdapter({
    required this.validAccessToken,
    this.refreshResponder,
    this.refreshStarted,
  });

  String validAccessToken;
  final Future<ResponseBody> Function(RequestOptions options)? refreshResponder;
  final Completer<void>? refreshStarted;

  int protectedFetchCount = 0;
  int refreshFetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/api/auth/refresh') {
      refreshFetchCount++;
      refreshStarted?.complete();
      if (refreshResponder != null) {
        return refreshResponder!(options);
      }
      return _json(
        200,
        <String, dynamic>{
          'token': validAccessToken,
          'refreshToken': 'refresh-new',
        },
      );
    }

    protectedFetchCount++;
    final auth = options.headers['Authorization'];
    if (auth == 'Bearer $validAccessToken') {
      return _json(200, <String, dynamic>{'ok': true});
    }
    return _json(401, <String, dynamic>{'message': 'INVALID_TOKEN'});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json; charset=utf-8'],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SessionInvalidationCoordinator.instance.reset();
  });

  test('50 concurrent protected requests share one refresh only', () async {
    final store = _MemorySecureStore(
      accessToken: 'access-old',
      refreshToken: 'refresh-old',
      deviceId: 'device-1',
    );
    final adapter = _RefreshConcurrencyAdapter(validAccessToken: 'access-new');
    final client = DioClient(store);
    client.dio.httpClientAdapter = adapter;
    client.dio.options.baseUrl = 'http://127.0.0.1';

    final results = await Future.wait(
      List.generate(50, (_) => client.dio.get('/api/feed/posts')),
    );

    expect(results, hasLength(50));
    expect(adapter.refreshFetchCount, 1);
    expect(store.value('access_token'), 'access-new');
    expect(store.value('refresh_token'), 'refresh-new');
    expect(store.clearCount, 0);
  });

  test('stale refresh failure keeps the newer session intact', () async {
    final store = _MemorySecureStore(
      accessToken: 'access-old',
      refreshToken: 'refresh-old',
      deviceId: 'device-1',
    );
    final refreshStarted = Completer<void>();
    final refreshResponse = Completer<ResponseBody>();
    final adapter = _RefreshConcurrencyAdapter(
      validAccessToken: 'access-new',
      refreshStarted: refreshStarted,
      refreshResponder: (_) => refreshResponse.future,
    );
    final client = DioClient(store);
    client.dio.httpClientAdapter = adapter;
    client.dio.options.baseUrl = 'http://127.0.0.1';

    final request = client.dio.get('/api/feed/posts');
    await refreshStarted.future;

    await store.saveAuthTokens(
      accessToken: 'access-new',
      refreshToken: 'refresh-new',
    );

    refreshResponse.complete(
      _json(401, <String, dynamic>{'message': 'INVALID_REFRESH_TOKEN'}),
    );

    await expectLater(
      request,
      throwsA(isA<DioException>()),
    );

    expect(store.value('access_token'), 'access-new');
    expect(store.value('refresh_token'), 'refresh-new');
    expect(store.clearCount, 0);
    expect(store.guestMode, isFalse);
    expect(SessionInvalidationCoordinator.instance.terminalInvalidated, isFalse);
  });
}
