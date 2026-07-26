import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:maslaki/features/auth/domain/login_error_mapper.dart';

void main() {
  group('login error mapper', () {
    DioException error({
      int? statusCode,
      Object? data,
      DioExceptionType type = DioExceptionType.badResponse,
    }) {
      final request = RequestOptions(path: '/api/auth/login');
      return DioException(
        requestOptions: request,
        type: type,
        response: statusCode == null
            ? null
            : Response(
                requestOptions: request,
                statusCode: statusCode,
                data: data,
              ),
      );
    }

    test('maps invalid credentials without request id leakage', () {
      final message = Intl.withLocale(
        'en',
        () => mapLoginDioErrorForUser(
          error(
            statusCode: 401,
            data: {
              'message': 'INVALID_CREDENTIALS',
              'requestId': '4c754a8e-24fe-4028-9d37-771a8c8d1f2e',
            },
          ),
        ),
      );

      expect(
        message,
        'Unable to sign in. Check your phone number and PIN, then try again.',
      );
      expect(message, isNot(contains('4c754a8e')));
    });

    test('maps network failures differently from bad credentials', () {
      final message = Intl.withLocale(
        'en',
        () => mapLoginDioErrorForUser(
          error(type: DioExceptionType.connectionTimeout),
        ),
      );

      expect(message, contains('Unable to connect to the server'));
      expect(message, isNot(contains('Check your phone number and PIN')));
    });

    test('maps server failures differently from bad credentials', () {
      final message = Intl.withLocale(
        'en',
        () => mapLoginDioErrorForUser(
          error(statusCode: 500, data: {'message': 'SERVER_ERROR'}),
        ),
      );

      expect(message, contains('server error'));
      expect(message, isNot(contains('Check your phone number and PIN')));
    });
  });
}
