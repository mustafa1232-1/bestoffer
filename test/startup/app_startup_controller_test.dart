import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/features/startup/state/app_startup_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A store whose reads never complete — reproduces the fresh-iOS-install case
/// where the Keychain / SharedPreferences first read stalls. The old gate
/// awaited this with no timeout and stranded the app on the "preparing" screen
/// forever (phase never left idle, attempts stayed 0, no retry).
class _HangingStore extends SecureStore {
  @override
  Future<bool?> readBool(String key) => Completer<bool?>().future; // never resolves

  @override
  Future<void> writeBool(String key, bool value) async {}
}

class _FalseStore extends SecureStore {
  @override
  Future<bool?> readBool(String key) async => false;

  @override
  Future<void> writeBool(String key, bool value) async {}
}

/// A dio whose /health always fails, so we can assert the gate advanced to the
/// server-check phase (which surfaces a retry) rather than hanging at idle.
class _FailingHealthAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'bootstrap never strands when first-launch storage hangs; it advances to the server check',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..httpClientAdapter = _FailingHealthAdapter();

      final controller = AppStartupController(
        store: _HangingStore(),
        dio: dio,
        initialFirstLaunchDone: null,
      );

      // Must complete well within the read budget + health timeout, not hang.
      await controller.bootstrap().timeout(const Duration(seconds: 20));

      // The gate advanced past idle and offered a recoverable state instead of
      // stranding the user on the preparing screen with attempts: 0.
      expect(controller.state.phase, AppStartupPhase.serverCheckFailed);
      expect(controller.state.attempts, 3);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('a healthy server check reaches the ready phase', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final adapter = _OkHealthAdapter();
    dio.httpClientAdapter = adapter;

    final controller = AppStartupController(
      store: _HangingStore(),
      dio: dio,
      initialFirstLaunchDone: null,
    );

    await controller.bootstrap().timeout(const Duration(seconds: 20));

    expect(controller.state.phase, AppStartupPhase.ready);
    expect(adapter.lastOptions?.extra['skipAuth'], isTrue);
    expect(controller.state.attempts, 1);
  });

  test('server check timeout exits loading after bounded retries', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final adapter = _HangingHealthAdapter();
    dio.httpClientAdapter = adapter;

    final controller = AppStartupController(
      store: _FalseStore(),
      dio: dio,
      initialFirstLaunchDone: null,
      serverAttemptTimeout: const Duration(milliseconds: 10),
      serverRetryBackoff: const [Duration.zero, Duration.zero],
    );

    await controller.bootstrap().timeout(const Duration(seconds: 2));

    expect(controller.state.phase, AppStartupPhase.serverCheckFailed);
    expect(
      controller.state.error,
      'Connection timeout while contacting server.',
    );
    expect(controller.state.attempts, 3);
    expect(adapter.calls, 3);
  });

  test(
    '503 responses retry at most three times and expose retry state',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      final adapter = _StatusHealthAdapter(statusCode: 503);
      dio.httpClientAdapter = adapter;

      final controller = AppStartupController(
        store: _FalseStore(),
        dio: dio,
        initialFirstLaunchDone: null,
        serverAttemptTimeout: const Duration(milliseconds: 50),
        serverRetryBackoff: const [Duration.zero, Duration.zero],
      );

      await controller.bootstrap().timeout(const Duration(seconds: 2));

      expect(controller.state.phase, AppStartupPhase.serverCheckFailed);
      expect(controller.state.attempts, 3);
      expect(adapter.calls, 3);
    },
  );

  test('concurrent bootstrap calls share one server check', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final adapter = _CompletingHealthAdapter();
    dio.httpClientAdapter = adapter;

    final controller = AppStartupController(
      store: _FalseStore(),
      dio: dio,
      initialFirstLaunchDone: null,
      serverAttemptTimeout: const Duration(seconds: 1),
      serverRetryBackoff: const [Duration.zero, Duration.zero],
    );

    final first = controller.bootstrap();
    final second = controller.bootstrap();
    await _waitFor(() => adapter.calls == 1);

    expect(adapter.calls, 1);
    adapter.complete(200);
    await Future.wait([first, second]).timeout(const Duration(seconds: 2));

    expect(controller.state.phase, AppStartupPhase.ready);
    expect(adapter.calls, 1);
  });

  test(
    'an already completed first launch does not hit the server gate',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      final adapter = _StatusHealthAdapter(statusCode: 200);
      dio.httpClientAdapter = adapter;

      final controller = AppStartupController(
        store: _FalseStore(),
        dio: dio,
        initialFirstLaunchDone: true,
      );

      await controller.bootstrap();

      expect(controller.state.phase, AppStartupPhase.ready);
      expect(adapter.calls, 0);
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 50; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _OkHealthAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      '{"status":"ok"}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _StatusHealthAdapter implements HttpClientAdapter {
  _StatusHealthAdapter({required this.statusCode});

  final int statusCode;
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    return ResponseBody.fromString(
      '{"status":"error"}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _HangingHealthAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls += 1;
    return Completer<ResponseBody>().future;
  }
}

class _CompletingHealthAdapter implements HttpClientAdapter {
  int calls = 0;
  final Completer<ResponseBody> _completer = Completer<ResponseBody>();

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls += 1;
    return _completer.future;
  }

  void complete(int statusCode) {
    _completer.complete(
      ResponseBody.fromString(
        '{"status":"ok"}',
        statusCode,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
  }
}
