import 'dart:math';

import 'package:dio/dio.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:maslaki/core/network/auth_session_token_cache.dart';
import 'package:maslaki/core/network/request_signing.dart';
import 'package:maslaki/core/network/secure_networking_config.dart';
import 'package:maslaki/core/storage/secure_storage.dart';

import '../constants/api.dart';
import '../utils/parsers.dart';
import 'secure_http_adapter_stub.dart'
    if (dart.library.io) 'secure_http_adapter_io.dart';

class DioClient {
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
    configureSecureHttpAdapter(dio, SecureNetworkingConfig.current());
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final skipAuth = options.extra['skipAuth'] == true;
            final token = skipAuth
                ? null
                : await store.readToken() ?? AuthSessionTokenCache.currentToken;
            if (!skipAuth && token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            final deviceId = await _ensureDeviceId(store);
            options.headers['X-Device-Id'] = deviceId;
            options.headers['X-Client-Platform'] = 'flutter';
            if (!skipAuth &&
                token != null &&
                token.isNotEmpty &&
                options.extra['skipSigning'] != true) {
              await _attachRequestSignature(options, token);
            }
            return handler.next(options);
          } catch (error) {
            return handler.reject(
              error is DioException
                  ? error
                  : DioException(
                      requestOptions: options,
                      error: error,
                      type: DioExceptionType.unknown,
                    ),
            );
          }
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

              final response = await dio.fetch<dynamic>(retryOptions);
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

  final Dio dio;
  final SecureStore store;

  static const _deviceIdKey = 'device_id';

  RequestSigningMaterial? _cachedSigningMaterial;
  Future<RequestSigningMaterial?>? _signingRefreshFuture;

  Future<void> _attachRequestSignature(
    RequestOptions options,
    String accessToken,
  ) async {
    if (!requiresRequestSigning(
      method: options.method,
      path: resolveRequestPath(options),
    )) {
      return;
    }

    final sessionBinding = _readSessionBinding(accessToken);
    if (sessionBinding == null) return;

    final material = await _ensureSigningMaterial(
      accessToken,
      sessionBinding: sessionBinding,
    );
    if (material == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _generateNonce();
    final bodyHash = buildRequestBodyHash(options.data);
    final canonical = buildRequestSigningCanonical(
      method: options.method,
      path: resolveRequestPath(options),
      timestamp: timestamp,
      nonce: nonce,
      sessionId: sessionBinding.sessionId,
      deviceFingerprint: sessionBinding.deviceFingerprint,
      bodyHash: bodyHash,
    );
    final signature = buildRequestSignature(
      secret: material.secret,
      canonical: canonical,
    );

    options.headers['X-Request-Key-Id'] = material.keyId;
    options.headers['X-Request-Timestamp'] = timestamp;
    options.headers['X-Request-Nonce'] = nonce;
    options.headers['X-Request-Signature'] = signature;
  }

  Future<RequestSigningMaterial?> _ensureSigningMaterial(
    String accessToken, {
    required _RequestSessionBinding sessionBinding,
  }) async {
    final cached = await _readStoredSigningMaterial();
    if (cached != null && !cached.shouldRefreshSoon) {
      return cached;
    }
    if (_signingRefreshFuture != null) {
      return _signingRefreshFuture;
    }
    _signingRefreshFuture = _refreshSigningMaterial(
      accessToken,
      sessionBinding: sessionBinding,
    );
    try {
      return await _signingRefreshFuture;
    } finally {
      _signingRefreshFuture = null;
    }
  }

  Future<RequestSigningMaterial?> _refreshSigningMaterial(
    String accessToken, {
    required _RequestSessionBinding sessionBinding,
  }) async {
    try {
      final response = await dio.fetch<dynamic>(
        RequestOptions(
          path: '/api/security/signing-material',
          method: 'POST',
          baseUrl: dio.options.baseUrl,
          headers: {'Authorization': 'Bearer $accessToken'},
          extra: const {
            'skipSigning': true,
          },
        ),
      );
      final raw = response.data;
      if (raw is! Map) return null;
      final material = RequestSigningMaterial.fromResponse(
        Map<String, dynamic>.from(raw),
      );
      _cachedSigningMaterial = material;
      await _persistSigningMaterial(material);
      _cachedBindingKey = sessionBinding.bindingKey;
      return material;
    } on DioException catch (error) {
      final messageCode = _extractMessageCode(error.response?.data);
      if (error.response?.statusCode == 503 &&
          messageCode == 'REQUEST_SIGNING_DISABLED') {
        await _clearSigningMaterial();
        return null;
      }
      rethrow;
    }
  }

  String? _cachedBindingKey;

  Future<RequestSigningMaterial?> _readStoredSigningMaterial() async {
    final token = await store.readToken() ?? AuthSessionTokenCache.currentToken;
    if (token == null || token.isEmpty) {
      await _clearSigningMaterial();
      return null;
    }
    final binding = _readSessionBinding(token);
    if (binding == null) {
      await _clearSigningMaterial();
      return null;
    }
    if (_cachedSigningMaterial != null &&
        _cachedBindingKey == binding.bindingKey &&
        !_cachedSigningMaterial!.isExpired) {
      return _cachedSigningMaterial;
    }

    final material = RequestSigningMaterial.fromStorageMap({
      requestSigningKeyIdStorageKey:
          await store.readString(requestSigningKeyIdStorageKey),
      requestSigningSecretStorageKey:
          await store.readString(requestSigningSecretStorageKey),
      requestSigningIssuedAtStorageKey:
          await store.readString(requestSigningIssuedAtStorageKey),
      requestSigningExpiresAtStorageKey:
          await store.readString(requestSigningExpiresAtStorageKey),
      requestSigningAlgorithmStorageKey:
          await store.readString(requestSigningAlgorithmStorageKey),
      requestSigningRefreshWindowStorageKey:
          await store.readString(requestSigningRefreshWindowStorageKey),
    });

    if (material == null || material.isExpired) {
      await _clearSigningMaterial();
      return null;
    }

    _cachedBindingKey = binding.bindingKey;
    _cachedSigningMaterial = material;
    return material;
  }

  Future<void> _persistSigningMaterial(RequestSigningMaterial material) async {
    for (final entry in material.toStorageMap().entries) {
      await store.writeString(entry.key, entry.value);
    }
  }

  Future<void> _clearSigningMaterial() async {
    _cachedSigningMaterial = null;
    _cachedBindingKey = null;
    for (final key in <String>[
      requestSigningKeyIdStorageKey,
      requestSigningSecretStorageKey,
      requestSigningIssuedAtStorageKey,
      requestSigningExpiresAtStorageKey,
      requestSigningAlgorithmStorageKey,
      requestSigningRefreshWindowStorageKey,
    ]) {
      await store.delete(key);
    }
  }

  _RequestSessionBinding? _readSessionBinding(String token) {
    try {
      final claims = JwtDecoder.decode(token);
      final sessionId = '${claims['sid'] ?? ''}'.trim();
      final deviceFingerprint = '${claims['dvh'] ?? ''}'.trim();
      if (sessionId.isEmpty || deviceFingerprint.isEmpty) {
        return null;
      }
      return _RequestSessionBinding(
        sessionId: sessionId,
        deviceFingerprint: deviceFingerprint,
      );
    } catch (_) {
      return null;
    }
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _RequestSessionBinding {
  const _RequestSessionBinding({
    required this.sessionId,
    required this.deviceFingerprint,
  });

  final String sessionId;
  final String deviceFingerprint;

  String get bindingKey => '$sessionId:$deviceFingerprint';
}

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

String _extractMessageCode(dynamic responseData) {
  if (responseData is Map) {
    return '${responseData['message'] ?? ''}'.trim().toUpperCase();
  }
  return '';
}
