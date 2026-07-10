import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/network/session_invalidation.dart';

DioException _err(int status, dynamic body) {
  final req = RequestOptions(path: '/api/hr/dashboard');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: req, statusCode: status, data: body),
  );
}

void main() {
  group('isTerminalAuthError', () {
    test('true for 401 INVALID_TOKEN / NO_TOKEN / INVALID_REFRESH_TOKEN', () {
      expect(isTerminalAuthError(_err(401, {'message': 'INVALID_TOKEN'})), isTrue);
      expect(isTerminalAuthError(_err(401, {'message': 'NO_TOKEN'})), isTrue);
      expect(isTerminalAuthError(_err(401, {'code': 'INVALID_REFRESH_TOKEN'})), isTrue);
      expect(isTerminalAuthError(_err(401, 'invalid_token')), isTrue); // case-insensitive
    });

    test('false for non-terminal 401s and other statuses', () {
      // A 401 that is not a terminal token failure (e.g. a one-off permission
      // check) must NOT nuke the session.
      expect(isTerminalAuthError(_err(401, {'message': 'SOME_OTHER_401'})), isFalse);
      expect(isTerminalAuthError(_err(403, {'message': 'FORBIDDEN_CUSTOMER_ONLY'})), isFalse);
      expect(isTerminalAuthError(_err(500, {'message': 'INVALID_TOKEN'})), isFalse);
      expect(isTerminalAuthError(_err(400, {'message': 'INVALID_PERIOD'})), isFalse);
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
