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
    String? sessionId,
    String? deviceSessionId,
    String? deviceRecoverySecret,
  }) : super(flavor: AppFlavor.user) {
    if (accessToken != null) {
      _values['access_token'] = accessToken;
    }
    if (refreshToken != null) {
      _values['refresh_token'] = refreshToken;
    }
    if (sessionId != null) {
      _values['session_id'] = sessionId;
    }
    if (deviceSessionId != null) {
      _values['device_session_id'] = deviceSessionId;
    }
    if (deviceRecoverySecret != null) {
      _values['device_recovery_secret'] = deviceRecoverySecret;
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
    String? sessionId,
    String? deviceSessionId,
    String? deviceRecoverySecret,
  }) async {
    _values['access_token'] = accessToken;
    if (refreshToken != null && refreshToken.trim().isNotEmpty) {
      _values['refresh_token'] = refreshToken.trim();
    }
    if (sessionId != null && sessionId.trim().isNotEmpty) {
      _values['session_id'] = sessionId.trim();
    }
    if (deviceSessionId != null && deviceSessionId.trim().isNotEmpty) {
      _values['device_session_id'] = deviceSessionId.trim();
    }
    if (deviceRecoverySecret != null &&
        deviceRecoverySecret.trim().isNotEmpty) {
      _values['device_recovery_secret'] = deviceRecoverySecret.trim();
    }
  }

  @override
  Future<String?> readToken() async => _values['access_token'];

  @override
  Future<String?> readRefreshToken() async => _values['refresh_token'];

  @override
  Future<String?> readSessionId() async => _values['session_id'];

  @override
  Future<String?> readDeviceSessionId() async => _values['device_session_id'];

  @override
  Future<String?> readDeviceRecoverySecret() async =>
      _values['device_recovery_secret'];

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
    this.recoverResponder,
    this.refreshStarted,
  });

  String validAccessToken;
  final Future<ResponseBody> Function(RequestOptions options)? refreshResponder;
  final Future<ResponseBody> Function(RequestOptions options)? recoverResponder;
  final Completer<void>? refreshStarted;

  int protectedFetchCount = 0;
  int refreshFetchCount = 0;
  int recoverFetchCount = 0;

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
      return _json(200, <String, dynamic>{
        'token': validAccessToken,
        'refreshToken': 'refresh-new',
      });
    }

    if (options.path == '/api/auth/session/recover') {
      recoverFetchCount++;
      if (recoverResponder != null) {
        return recoverResponder!(options);
      }
      return _json(200, <String, dynamic>{
        'token': validAccessToken,
        'accessToken': validAccessToken,
        'refreshToken': 'refresh-recovered',
        'sessionId': 'session-recovered',
        'deviceSessionId': 'device-session-1',
        'deviceRecoverySecret': 'secret-1-012345678901234',
      });
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
    SessionRecoveryCoordinator.instance.reset();
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

  test('multiple DioClient instances share one process-wide refresh', () async {
    final store = _MemorySecureStore(
      accessToken: 'access-old',
      refreshToken: 'refresh-old',
      deviceId: 'device-1',
    );
    await store.writeString('session_id', 'session-1');
    final adapter = _RefreshConcurrencyAdapter(validAccessToken: 'access-new');
    final clients = List.generate(3, (_) {
      final client = DioClient(store);
      client.dio.httpClientAdapter = adapter;
      client.dio.options.baseUrl = 'http://127.0.0.1';
      return client;
    });

    final results = await Future.wait(
      List.generate(
        50,
        (index) => clients[index % clients.length].dio.get('/api/feed/posts'),
      ),
    );

    expect(results, hasLength(50));
    expect(adapter.refreshFetchCount, 1);
    expect(store.value('access_token'), 'access-new');
    expect(store.value('refresh_token'), 'refresh-new');
    expect(store.clearCount, 0);
  });

  test(
    'courier requests with terminal invalidation skipped still retry through one refresh',
    () async {
      final store = _MemorySecureStore(
        accessToken: 'access-old',
        refreshToken: 'refresh-old',
        sessionId: 'session-1',
        deviceId: 'device-1',
      );
      final adapter = _RefreshConcurrencyAdapter(
        validAccessToken: 'access-new',
      );
      final client = DioClient(store);
      client.dio.httpClientAdapter = adapter;
      client.dio.options.baseUrl = 'http://127.0.0.1';

      final results = await Future.wait(
        List.generate(
          10,
          (_) => client.dio.get(
            '/api/courier/requests',
            options: Options(
              extra: const <String, dynamic>{
                'skipTerminalSessionInvalidation': true,
              },
            ),
          ),
        ),
      );

      expect(results, hasLength(10));
      expect(adapter.refreshFetchCount, 1);
      expect(adapter.recoverFetchCount, 0);
      expect(store.value('access_token'), 'access-new');
      expect(store.clearCount, 0);
      expect(SessionRecoveryCoordinator.instance.terminalInvalidated, isFalse);
    },
  );

  test(
    'admin services endpoints share one refresh after initial 401',
    () async {
      final store = _MemorySecureStore(
        accessToken: 'access-old',
        refreshToken: 'refresh-old',
        sessionId: 'session-1',
        deviceId: 'device-1',
      );
      final adapter = _RefreshConcurrencyAdapter(
        validAccessToken: 'access-new',
      );
      final client = DioClient(store);
      client.dio.httpClientAdapter = adapter;
      client.dio.options.baseUrl = 'http://127.0.0.1';
      final endpoints = const <String>[
        '/api/admin/services/stats',
        '/api/admin/services/providers/pending',
        '/api/admin/services/offerings/pending',
        '/api/admin/services/categories/suggestions',
        '/api/admin/services/reports',
        '/api/admin/services/requests',
        '/api/admin/services/settings',
      ];

      final results = await Future.wait(
        List.generate(
          10,
          (index) => client.dio.get(endpoints[index % endpoints.length]),
        ),
      );

      expect(results, hasLength(10));
      expect(adapter.refreshFetchCount, 1);
      expect(adapter.recoverFetchCount, 0);
      expect(store.value('access_token'), 'access-new');
      expect(store.clearCount, 0);
    },
  );

  test(
    'missing access token recovers once from stored device session',
    () async {
      final store = _MemorySecureStore(
        deviceId: 'device-1',
        deviceSessionId: 'device-session-1',
        deviceRecoverySecret: 'secret-1-012345678901234',
      );
      final adapter = _RefreshConcurrencyAdapter(
        validAccessToken: 'access-new',
      );
      final client = DioClient(store);
      client.dio.httpClientAdapter = adapter;
      client.dio.options.baseUrl = 'http://127.0.0.1';

      final results = await Future.wait(
        List.generate(20, (_) => client.dio.get('/api/courier/requests')),
      );

      expect(results, hasLength(20));
      expect(adapter.refreshFetchCount, 0);
      expect(adapter.recoverFetchCount, 1);
      expect(adapter.protectedFetchCount, 20);
      expect(store.value('access_token'), 'access-new');
      expect(store.value('refresh_token'), 'refresh-recovered');
      expect(store.clearCount, 0);
    },
  );

  test(
    'network failure during recovery preserves stored session bundle',
    () async {
      final store = _MemorySecureStore(
        deviceId: 'device-1',
        deviceSessionId: 'device-session-1',
        deviceRecoverySecret: 'secret-1-012345678901234',
      );
      final adapter = _RefreshConcurrencyAdapter(
        validAccessToken: 'access-new',
        recoverResponder: (options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'offline',
          );
        },
      );
      final client = DioClient(store);
      client.dio.httpClientAdapter = adapter;
      client.dio.options.baseUrl = 'http://127.0.0.1';

      await expectLater(
        client.dio.get('/api/admin/services/stats'),
        throwsA(isA<DioException>()),
      );

      expect(adapter.recoverFetchCount, 1);
      expect(store.value('device_session_id'), 'device-session-1');
      expect(store.value('device_recovery_secret'), 'secret-1-012345678901234');
      expect(store.clearCount, 0);
    },
  );

  test('5xx during recovery preserves stored session bundle', () async {
    final store = _MemorySecureStore(
      deviceId: 'device-1',
      deviceSessionId: 'device-session-1',
      deviceRecoverySecret: 'secret-1-012345678901234',
    );
    final adapter = _RefreshConcurrencyAdapter(
      validAccessToken: 'access-new',
      recoverResponder: (_) async =>
          _json(503, <String, dynamic>{'message': 'SERVER_ERROR'}),
    );
    final client = DioClient(store);
    client.dio.httpClientAdapter = adapter;
    client.dio.options.baseUrl = 'http://127.0.0.1';

    await expectLater(
      client.dio.get('/api/admin/services/stats'),
      throwsA(isA<DioException>()),
    );

    expect(adapter.recoverFetchCount, 1);
    expect(store.value('device_session_id'), 'device-session-1');
    expect(store.value('device_recovery_secret'), 'secret-1-012345678901234');
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

    await expectLater(request, throwsA(isA<DioException>()));

    expect(store.value('access_token'), 'access-new');
    expect(store.value('refresh_token'), 'refresh-new');
    expect(store.clearCount, 0);
    expect(store.guestMode, isFalse);
    expect(SessionRecoveryCoordinator.instance.terminalInvalidated, isFalse);
  });
}
