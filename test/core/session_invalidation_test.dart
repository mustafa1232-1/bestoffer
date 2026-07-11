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
  group('isTerminalAuthError', () {
    test('false for 401 auth codes without bearer on guest requests', () {
      expect(
        isTerminalAuthError(_err(401, {'message': 'INVALID_TOKEN'})),
        isFalse,
      );
      expect(isTerminalAuthError(_err(401, {'message': 'NO_TOKEN'})), isFalse);
      expect(
        isTerminalAuthError(_err(401, {'code': 'INVALID_REFRESH_TOKEN'})),
        isFalse,
      );
      expect(
        isTerminalAuthError(_err(401, 'invalid_token')),
        isFalse,
      ); // case-insensitive
    });

    test(
      'false for guest and auth bootstrap flows without a stored session',
      () {
        expect(
          isTerminalAuthError(
            _err(401, {'message': 'NO_TOKEN'}, path: '/api/realtime/token'),
          ),
          isFalse,
        );
        expect(
          isTerminalAuthError(
            _err(401, {'message': 'NO_TOKEN'}, path: '/api/notifications/push-token'),
          ),
          isFalse,
        );
        expect(
          isTerminalAuthError(
            _err(401, {
              'message': 'INVALID_CREDENTIALS',
            }, path: '/api/auth/login'),
          ),
          isFalse,
        );
        expect(
          isTerminalAuthError(
            _err(401, {'message': 'NO_TOKEN'}, path: '/api/auth/register'),
          ),
          isFalse,
        );
        expect(
          isTerminalAuthError(
            _err(401, {
              'message': 'NO_TOKEN',
            }, path: '/api/services/provider/register'),
          ),
          isFalse,
        );
        expect(
          isTerminalAuthError(
            _err(401, {
              'message': 'NO_TOKEN',
            }, path: '/api/services/provider/subscription/status'),
          ),
          isFalse,
        );
        expect(
          isTerminalAuthError(
            _err(
              401,
              {'message': 'NO_TOKEN'},
              path: '/api/auth/refresh',
              data: const <String, dynamic>{},
            ),
          ),
          isFalse,
        );
        expect(
          isTerminalAuthError(
            _err(401, {
              'message': 'INVALID_TOKEN',
            }, path: '/api/services/public/categories'),
          ),
          isFalse,
        );
      },
    );

    test('true for authenticated requests with bearer tokens', () {
      expect(
        isTerminalAuthError(
          _err(
            401,
            {'message': 'NO_TOKEN'},
            path: '/api/realtime/token',
            headers: const {'Authorization': 'Bearer access-token'},
          ),
        ),
        isTrue,
      );
      expect(
        isTerminalAuthError(
          _err(
            401,
            {'message': 'TOKEN_EXPIRED'},
            path: '/api/hr/dashboard',
            headers: const {'Authorization': 'Bearer access-token'},
          ),
        ),
        isTrue,
      );
      expect(
        isTerminalAuthError(
          _err(
            401,
            {'code': 'INVALID_REFRESH_TOKEN'},
            path: '/api/auth/refresh',
            headers: const {'Authorization': 'Bearer access-token'},
            data: const <String, dynamic>{'refreshToken': 'refresh-token'},
          ),
        ),
        isTrue,
      );
    });

    test('false for non-terminal 401s and other statuses', () {
      // A 401 that is not a terminal token failure (e.g. a one-off permission
      // check) must NOT nuke the session.
      expect(
        isTerminalAuthError(_err(401, {'message': 'SOME_OTHER_401'})),
        isFalse,
      );
      expect(
        isTerminalAuthError(_err(403, {'message': 'FORBIDDEN_CUSTOMER_ONLY'})),
        isFalse,
      );
      expect(
        isTerminalAuthError(_err(500, {'message': 'INVALID_TOKEN'})),
        isFalse,
      );
      expect(
        isTerminalAuthError(_err(400, {'message': 'INVALID_PERIOD'})),
        isFalse,
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
}
