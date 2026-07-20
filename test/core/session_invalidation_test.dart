// ignore_for_file: deprecated_member_use_from_same_package

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
    SessionRecoveryCoordinator.instance.reset();
  });

  group('SessionRecoveryCoordinator.classify', () {
    test('treats access-token failures as needing recovery', () {
      expect(
        SessionRecoveryCoordinator.instance.classify(
          _err(
            401,
            {'message': 'INVALID_TOKEN'},
            headers: const {'Authorization': 'Bearer access-token'},
          ),
        ),
        SessionRecoveryDecision.needsRecovery,
      );
      expect(
        SessionRecoveryCoordinator.instance.classify(
          _err(
            401,
            {'message': 'TOKEN_EXPIRED'},
            headers: const {'Authorization': 'Bearer access-token'},
          ),
        ),
        SessionRecoveryDecision.needsRecovery,
      );
      expect(
        SessionRecoveryCoordinator.instance.classify(
          _err(
            401,
            {'message': 'ACCESS_TOKEN_EXPIRED'},
            headers: const {'Authorization': 'Bearer access-token'},
          ),
        ),
        SessionRecoveryDecision.needsRecovery,
      );
    });

    test('treats old terminal session codes as needing recovery', () {
      final recoverableCodes = <String>[
        'REFRESH_TOKEN_EXPIRED',
        'REFRESH_TOKEN_REUSED',
        'SESSION_REVOKED',
        'DEVICE_BINDING_MISMATCH',
        'APP_SURFACE_MISMATCH',
        'JWT_SIGNATURE_INVALID',
        'ACCOUNT_DISABLED',
      ];

      for (final code in recoverableCodes) {
        expect(
          SessionRecoveryCoordinator.instance.classify(
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
          SessionRecoveryDecision.needsRecovery,
          reason: code,
        );
      }
    });

    test('treats generic invalid refresh as needing recovery', () {
      expect(
        SessionRecoveryCoordinator.instance.classify(
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
        SessionRecoveryDecision.needsRecovery,
      );
    });

    test(
      'returns staleFailure when an older refresh token fails after rotation',
      () {
        expect(
          SessionRecoveryCoordinator.instance.classify(
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
          SessionRecoveryDecision.staleFailure,
        );
      },
    );

    test(
      'returns staleFailure before clearing when stored refresh token is missing',
      () {
        expect(
          SessionRecoveryCoordinator.instance.classify(
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
          SessionRecoveryDecision.staleFailure,
        );
      },
    );

    test('skips terminal invalidation when explicitly opted out', () {
      expect(
        SessionRecoveryCoordinator.instance.classify(
          _err(
            401,
            {'message': 'INVALID_REFRESH_TOKEN'},
            path: '/api/auth/refresh',
            headers: const {'Authorization': 'Bearer access-token'},
            extra: const {'skipTerminalSessionInvalidation': true},
            data: const <String, dynamic>{'refreshToken': 'refresh-token'},
          ),
        ),
        SessionRecoveryDecision.recoverable,
      );
    });

    test('ignores non-terminal 401s and other statuses', () {
      expect(
        SessionRecoveryCoordinator.instance.classify(
          _err(401, {'message': 'UNAUTHORIZED'}),
        ),
        SessionRecoveryDecision.recoverable,
      );
      expect(
        SessionRecoveryCoordinator.instance.classify(
          _err(403, {'message': 'FORBIDDEN_CUSTOMER_ONLY'}),
        ),
        SessionRecoveryDecision.recoverable,
      );
      expect(
        SessionRecoveryCoordinator.instance.classify(
          _err(500, {'message': 'INVALID_TOKEN'}),
        ),
        SessionRecoveryDecision.recoverable,
      );
      expect(
        SessionRecoveryCoordinator.instance.classify(
          DioException(
            requestOptions: RequestOptions(path: '/api/feed/posts'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        SessionRecoveryDecision.recoverable,
      );
      expect(
        SessionRecoveryCoordinator.instance.classify(
          DioException(
            requestOptions: RequestOptions(path: '/api/feed/posts'),
            type: DioExceptionType.connectionError,
          ),
        ),
        SessionRecoveryDecision.recoverable,
      );
    });
  });

  group('SessionRecoveryBus', () {
    test(
      'requestRecovery() bumps the tick without notifying legacy listeners',
      () {
        final bus = SessionRecoveryBus.instance;
        final startTick = bus.tick;
        var notified = 0;
        void listener() => notified++;
        bus.addListener(listener);
        addTearDown(() => bus.removeListener(listener));

        bus.requestRecovery();
        expect(bus.tick, startTick + 1);
        expect(notified, 0);

        bus.requestRecovery();
        expect(bus.tick, startTick + 2);
        expect(notified, 0);
      },
    );
  });

  group('invalidateTerminalSession compatibility shim', () {
    test('never runs cleanup or marks a terminal invalidation', () async {
      final coordinator = SessionRecoveryCoordinator.instance;
      var cleanupCount = 0;

      await coordinator.invalidateTerminalSession(
        cleanup: () async {
          cleanupCount++;
        },
      );
      await coordinator.invalidateTerminalSession(
        cleanup: () async {
          cleanupCount++;
        },
      );

      expect(cleanupCount, 0);
      expect(coordinator.terminalInvalidated, isFalse);
      expect(coordinator.recoveryPending, isTrue);
    });
  });
}
