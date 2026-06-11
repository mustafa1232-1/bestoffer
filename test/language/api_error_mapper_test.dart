import 'package:maslaki/core/network/api_error_mapper.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  group('api error mapper', () {
    test('maps stable backend codes using current locale', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/auth/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/login'),
          statusCode: 409,
          data: {'message': 'PHONE_EXISTS'},
        ),
      );

      final english = Intl.withLocale(
        'en',
        () => mapDioError(error, fallback: 'fallback'),
      );
      final arabic = Intl.withLocale(
        'ar',
        () => mapDioError(error, fallback: 'fallback'),
      );

      expect(english, 'This phone number is already registered.');
      expect(arabic, 'رقم الهاتف مسجل مسبقًا.');
    });

    test('builds localized validation messages from field list', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/payments'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/payments'),
          statusCode: 422,
          data: {
            'message': 'VALIDATION_ERROR',
            'fields': ['amount', 'merchantId'],
          },
        ),
      );

      final message = Intl.withLocale(
        'en',
        () => mapDioError(error, fallback: 'fallback'),
      );

      expect(message, 'Enter a valid amount.\nSelect a merchant first.');
    });

    test('parses field map and form code from validation payload', () {
      final parsed = parseBackendFieldErrors({
        'message': 'VALIDATION_ERROR',
        'fields': {
          'phone': 'PHONE_EXISTS',
          'buildingNumber': 'REQUIRED',
          '_form': 'ADDRESS_INVALID',
        },
      });

      expect(parsed.messageCode, 'VALIDATION_ERROR');
      expect(parsed.codeFor('phone'), 'PHONE_EXISTS');
      expect(parsed.codeFor('buildingNumber'), 'REQUIRED');
      expect(parsed.formCode, 'ADDRESS_INVALID');
    });

    test('parses details.fields when top-level fields are absent', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/company/branch'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/company/branch'),
          statusCode: 400,
          data: {
            'message': 'VALIDATION_ERROR',
            'details': {
              'fields': {
                'apartment': 'REQUIRED',
                '_form': 'ADDRESS_INVALID',
              },
            },
          },
        ),
      );

      final parsed = parseBackendFieldErrors(error);

      expect(parsed.codeFor('apartment'), 'REQUIRED');
      expect(parsed.formCode, 'ADDRESS_INVALID');
    });
  });
}
