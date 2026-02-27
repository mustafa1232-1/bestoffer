import 'package:bestoffer/core/storage/secure_storage.dart';
import 'package:dio/dio.dart';

import '../constants/api.dart';
import '../utils/parsers.dart';

class DioClient {
  final Dio dio;
  final SecureStore store;

  DioClient(this.store)
    : dio = Dio(
        BaseOptions(
          baseUrl: Api.baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          responseType: ResponseType.json,
          headers: const {'Accept': 'application/json; charset=utf-8'},
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await store.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
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

              final token = await store.readToken();
              if (token != null && token.isNotEmpty) {
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
