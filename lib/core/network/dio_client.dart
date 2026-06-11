import 'dart:math';

import 'package:maslaki/core/network/auth_session_token_cache.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:dio/dio.dart';

import '../constants/api.dart';
import '../utils/parsers.dart';

/// Purpose:
/// عميل HTTP المركزي للتطبيق. يضيف auth/device headers، يطبع payloads
/// النصية، ويطبق fallback بين base URLs عند أعطال الشبكة.
///
/// Used by:
/// - معظم `*Api` في طبقة البيانات
///
/// Critical notes:
/// - أي تغيير هنا ينعكس على كل طلبات التطبيق تقريباً.
/// - fallback بين الـ base URLs مقصود لتجاوز انقطاع مؤقت في بيئة واحدة،
///   وليس لإخفاء أخطاء business responses.
///
/// Maintenance notes:
/// - عند تكرار 401 أو فشل requests جماعي أو payloads مشوهة، ابدأ من هذا
///   الملف قبل الغوص في API module محدد.
class DioClient {
  final Dio dio;
  final SecureStore store;
  static const _deviceIdKey = 'device_id';

  DioClient(this.store)
    : dio = Dio(
        BaseOptions(
          baseUrl: Api.baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          responseType: ResponseType.json,
          headers: {'Accept': 'application/json; charset=utf-8'},
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final skipAuth = options.extra['skipAuth'] == true;
          final token =
              skipAuth
                  ? null
                  : await store.readToken() ?? AuthSessionTokenCache.currentToken;
          if (!skipAuth && token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          final deviceId = await _ensureDeviceId(store);
          options.headers['X-Device-Id'] = deviceId;
          options.headers['X-Client-Platform'] = 'flutter';
          return handler.next(options);
        },
        onResponse: (response, handler) {
          response.data = _normalizePayload(response.data);
          return handler.next(response);
        },
        onError: (error, handler) async {
          if (!_isRetryableConnectionError(error)) {
            return handler.next(error);
          }

          final request = error.requestOptions;
          final fallbackUrls = Api.fallbackBaseUrls;
          if (fallbackUrls.length <= 1) {
            return handler.next(error);
          }

          final tried = _readTriedBaseUrls(request);
          for (final url in fallbackUrls) {
            if (tried.contains(url)) continue;

            try {
              final retryOptions = request.copyWith(
                baseUrl: url,
                extra: {
                  ...request.extra,
                  '_triedBaseUrls': [...tried, url],
                },
              );

              final skipAuth = retryOptions.extra['skipAuth'] == true;
              final token =
                  skipAuth
                      ? null
                      : await store.readToken() ?? AuthSessionTokenCache.currentToken;
              if (!skipAuth && token != null && token.isNotEmpty) {
                retryOptions.headers['Authorization'] = 'Bearer $token';
              }

              final response = await dio.fetch<dynamic>(retryOptions);
              // Persist the first reachable base URL for all next requests.
              dio.options.baseUrl = url;
              response.data = _normalizePayload(response.data);
              return handler.resolve(response);
            } on DioException catch (retryError) {
              if (!_isRetryableConnectionError(retryError)) {
                return handler.next(retryError);
              }
            }
          }

          return handler.next(error);
        },
      ),
    );
  }
}

/// يضمن وجود device id ثابت لكل تثبيت تطبيق لاستخدامه في tracing والجلسات.
Future<String> _ensureDeviceId(SecureStore store) async {
  final existing = await store.readString(DioClient._deviceIdKey);
  if (existing != null && existing.trim().isNotEmpty) {
    return existing.trim();
  }
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await store.writeString(DioClient._deviceIdKey, value);
  return value;
}

/// يميز أخطاء النقل المؤقتة عن أخطاء الخادم أو business validation.
bool _isRetryableConnectionError(DioException error) {
  return error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout;
}

List<String> _readTriedBaseUrls(RequestOptions request) {
  final raw = request.extra['_triedBaseUrls'];
  if (raw is List) {
    return raw.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
  }

  final current = request.baseUrl.trim().isEmpty
      ? Api.baseUrl
      : request.baseUrl;
  return [current];
}

/// يمر على payload recursively لتوحيد النصوص المرسلة من الخادم قبل دخولها
/// إلى النماذج أو الواجهة.
dynamic _normalizePayload(dynamic value) {
  if (value is String) {
    return normalizeText(value);
  }

  if (value is List) {
    return value.map(_normalizePayload).toList();
  }

  if (value is Map) {
    return value.map((k, v) => MapEntry(k, _normalizePayload(v)));
  }

  return value;
}
