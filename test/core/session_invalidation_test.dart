import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/network/session_invalidation.dart';

DioException _err(
  int status,
  dynamic body, {
  String path = '/api/hr/dashboard',
  Map<String, dynamic>? headers,
  Map<String, dynamic>? extra,
  dynamic data,
}) {
  final req = RequestOptions(
    path: path,
    headers: headers ?? const <String, dynamic>{},
    extra: extra ?? const <String, dynamic>{},
    data: data,
  );
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: req, statusCode: status, data: body),
  );
}

void main() {
  setUp(() {
    SessionInvalidationCoordinator.instance.reset();
  });

  group('SessionInvalidationCoordinator.classify', () {
    test('treats access-token failures as recoverable', () {
      expect(
        SessionInvalidationCoordinator.instance.classify(
          _err(
            401,
            {'message': 'INVALID_TOKEN'},
            headers: const {'Authorization': 'Bearer access-token'},
          ),
        ),
        SessionInvalidationDecision.recoverable,
      );
      expect(
        SessionInvalidationCoordinator.instance.classify(
          _err(
            401,
            {'message': 'TOKEN_EXPIRED'},
            headers: const {'Authorization': 'Bearer access-token'},
          ),
        ),
        SessionInvalidationDecision.recoverable,
      );
      expect(
        SessionInvalidationCoordinator.instance.classify(
          _err(
            401,
            {'message': 'ACCESS_TOKEN_EXPIRED'},
            headers: const {'Authorization': 'Bearer access-token'},
          ),
        ),
        SessionInvalidationDecision.recoverable,
      );
    });

    test('treats confirmed terminal session codes as terminal', () {
      final terminalCodes = <String>[
        'REFRESH_TOKEN_EXPIRED',
        'REFRESH_TOKEN_REUSED',
        'SESSION_REVOKED',
        'DEVICE_BINDING_MISMATCH',
        'APP_SURFACE_MISMATCH',
        'JWT_SIGNATURE_INVALID',
        'ACCOUNT_DISABLED',
      ];

      for (final code in terminalCodes) {
        expect(
          SessionInvalidationCoordinator.instance.classify(
            _err(
              401,
              {'message': code},
              path: '/api/auth/refresh',
              headers: const {'Authorization': 'Bearer access-token'},
              data: const <String, dynamic>{'refreshToken': 'refresh-token'},
            ),
            expectedRefreshToken: 'refresh-token',
            currentRefreshToken: 'refresh-token',
          ),
          SessionInvalidationDecision.terminal,
          reason: code,
        );
      }
    });

    test('treats generic invalid refresh as recoverable', () {
      expect(
        SessionInvalidationCoordinator.instance.classify(
          _err(
            401,
            {'message': 'INVALID_REFRESH_TOKEN'},
            path: '/api/auth/refresh',
            headers: const {'Authorization': 'Bearer access-token'},
            data: const <String, dynamic>{'refreshToken': 'refresh-token'},
          ),
          expectedRefreshToken: 'refresh-token',
          currentRefreshToken: 'refresh-token',
        ),
        SessionInvalidationDecision.recoverable,
      );
    });

    test(
      'returns staleFailure when an older refresh token fails after rotation',
      () {
        expect(
          SessionInvalidationCoordinator.instance.classify(
            _err(
              401,
              {'message': 'INVALID_REFRESH_TOKEN'},
              path: '/api/auth/refresh',
              headers: const {'Authorization': 'Bearer access-token'},
              data: const <String, dynamic>{'refreshToken': 'refresh-token'},
            ),
            expectedRefreshToken: 'refresh-token',
            currentRefreshToken: 'new-refresh-token',
          ),
          SessionInvalidationDecision.staleFailure,
        );
      },
    );

    test(
      'returns staleFailure before clearing when stored refresh token is missing',
      () {
        expect(
          SessionInvalidationCoordinator.instance.classify(
            _err(
              401,
              {'message': 'REFRESH_TOKEN_EXPIRED'},
              path: '/api/auth/refresh',
              headers: const {'Authorization': 'Bearer access-token'},
              data: const <String, dynamic>{'refreshToken': 'refresh-token'},
            ),
            expectedRefreshToken: 'refresh-token',
            currentRefreshToken: null,
          ),
          SessionInvalidationDecision.staleFailure,
        );
      },
    );

    test('skips terminal invalidation when explicitly opted out', () {
      expect(
        SessionInvalidationCoordinator.instance.classify(
          _err(
            401,
            {'message': 'INVALID_REFRESH_TOKEN'},
            path: '/api/auth/refresh',
            headers: const {'Authorization': 'Bearer access-token'},
            extra: const {'skipTerminalSessionInvalidation': true},
            data: const <String, dynamic>{'refreshToken': 'refresh-token'},
          ),
        ),
        SessionInvalidationDecision.recoverable,
      );
    });

    test('ignores non-terminal 401s and other statuses', () {
      expect(
        SessionInvalidationCoordinator.instance.classify(
          _err(401, {'message': 'UNAUTHORIZED'}),
        ),
        SessionInvalidationDecision.recoverable,
      );
      expect(
        SessionInvalidationCoordinator.instance.classify(
          _err(403, {'message': 'FORBIDDEN_CUSTOMER_ONLY'}),
        ),
        SessionInvalidationDecision.recoverable,
      );
      expect(
        SessionInvalidationCoordinator.instance.classify(
          _err(500, {'message': 'INVALID_TOKEN'}),
        ),
        SessionInvalidationDecision.recoverable,
      );
      expect(
        SessionInvalidationCoordinator.instance.classify(
          DioException(
            requestOptions: RequestOptions(path: '/api/feed/posts'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        SessionInvalidationDecision.recoverable,
      );
      expect(
        SessionInvalidationCoordinator.instance.classify(
          DioException(
            requestOptions: RequestOptions(path: '/api/feed/posts'),
            type: DioExceptionType.connectionError,
          ),
        ),
        SessionInvalidationDecision.recoverable,
      );
    });
  });

  group('SessionInvalidationBus', () {
    test('invalidate() bumps the tick and notifies listeners', () {
      final bus = SessionInvalidationBus.instance;
      final startTick = bus.tick;
      var notified = 0;
      void listener() => notified++;
      bus.addListener(listener);
      addTearDown(() => bus.removeListener(listener));

      bus.invalidate();
      expect(bus.tick, startTick + 1);
      expect(notified, 1);

      bus.invalidate();
      expect(bus.tick, startTick + 2);
      expect(notified, 2);
    });
  });

  group('invalidateTerminalSession', () {
    test(
      'runs cleanup once for concurrent callers and stays idempotent',
      () async {
        final coordinator = SessionInvalidationCoordinator.instance;
        var cleanupCount = 0;
        final gate = Completer<void>();

        final first = coordinator.invalidateTerminalSession(
          cleanup: () async {
            cleanupCount++;
            await gate.future;
          },
        );
        final second = coordinator.invalidateTerminalSession(
          cleanup: () async {
            cleanupCount++;
          },
        );

        await Future<void>.delayed(Duration.zero);
        expect(cleanupCount, 1);

        gate.complete();
        await Future.wait([first, second]);

        await coordinator.invalidateTerminalSession(
          cleanup: () async {
            cleanupCount++;
          },
        );
        expect(cleanupCount, 1);

        coordinator.reset();
        await coordinator.invalidateTerminalSession(
          cleanup: () async {
            cleanupCount++;
          },
        );
        expect(cleanupCount, 2);
      },
    );
  });
}
