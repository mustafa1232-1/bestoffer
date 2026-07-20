import 'dart:math';

import 'package:dio/dio.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:maslaki/core/network/auth_session_token_cache.dart';
import 'package:maslaki/core/network/request_signing.dart';
import 'package:maslaki/core/network/secure_networking_config.dart';
import 'package:maslaki/core/platform/app_flavor.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api.dart';
import '../utils/parsers.dart';
import 'secure_http_adapter_stub.dart'
    if (dart.library.io) 'secure_http_adapter_io.dart';
import 'session_invalidation.dart';

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
            final sessionGateExempt =
                skipAuth || isSessionInvalidationExemptRequest(options);
            final token = skipAuth ? null : await _readUsableAccessToken();
            if (!skipAuth) {
              if (token != null && token.isNotEmpty) {
                // A usable token is back (e.g. after re-login) - clear the gate.
                _sessionInvalidated = false;
                SessionRecoveryCoordinator.instance.reset();
              } else if (_sessionInvalidated && !sessionGateExempt) {
                // Session was terminally invalidated and there is no token.
                // Fail fast locally so background pollers stop spamming the
                // server with guaranteed-401 requests. Public (skipAuth) calls
                // are unaffected.
                return handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 401,
                      data: const {'message': 'INVALID_TOKEN'},
                    ),
                    type: DioExceptionType.badResponse,
                  ),
                );
              }
            }
            if (!skipAuth && token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            final deviceId = await _ensureDeviceId(store);
            options.headers['X-Device-Id'] = deviceId;
            options.headers['X-Client-Platform'] =
                store.flavor.clientPlatformTag;
            options.headers['X-App-Flavor'] = store.flavor.key;
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
          try {
            final refreshed = await _tryResolveUnauthorizedWithRefresh(error);
            if (refreshed != null) {
              return handler.resolve(refreshed);
            }
          } on DioException catch (refreshError) {
            return handler.next(refreshError);
          }

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
  Future<String?>? _accessRefreshFuture;
  Future<String?>? _sessionRecoveryFuture;

  /// Set once a confirmed terminal auth failure (INVALID_TOKEN) is observed and
  /// the session is cleared. While true (and no token exists) protected requests
  /// fail fast locally instead of hitting the server. Cleared when a usable
  /// token reappears (re-login).
  bool _sessionInvalidated = false;

  Future<String?> _readUsableAccessToken() async {
    final token =
        await store.readToken() ??
        AuthSessionTokenCache.currentToken(flavor: store.flavor);
    if (token == null || token.isEmpty) return null;
    if (!_shouldRefreshAccessToken(token)) return token;
    try {
      final refreshed = await _refreshAccessToken(token, allowExpired: true);
      if (refreshed != null && refreshed.isNotEmpty) return refreshed;
      return _isAccessTokenExpired(token) ? null : token;
    } on DioException {
      if (_isAccessTokenExpired(token)) rethrow;
      return token;
    }
  }

  bool _shouldRefreshAccessToken(String token) {
    try {
      final expiry = JwtDecoder.getExpirationDate(token);
      final remaining = expiry.difference(DateTime.now());
      return remaining <= const Duration(minutes: 5);
    } catch (_) {
      return false;
    }
  }

  bool _isAccessTokenExpired(String token) {
    try {
      return JwtDecoder.isExpired(token);
    } catch (_) {
      return false;
    }
  }

  Future<String?> _refreshAccessToken(
    String currentAccessToken, {
    bool allowExpired = false,
  }) async {
    if (_accessRefreshFuture != null) return _accessRefreshFuture;
    _accessRefreshFuture = _refreshAccessTokenOnce(
      currentAccessToken,
      allowExpired: allowExpired,
    );
    try {
      return await _accessRefreshFuture;
    } finally {
      _accessRefreshFuture = null;
    }
  }

  Future<String?> _refreshAccessTokenOnce(
    String currentAccessToken, {
    bool allowExpired = false,
  }) async {
    final refreshToken = await store.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return await _recoverAccessToken(currentAccessToken) ??
          (allowExpired ? null : currentAccessToken);
    }

    try {
      final deviceId = await _ensureDeviceId(store);
      final response = await dio.fetch<dynamic>(
        RequestOptions(
          path: '/api/auth/refresh',
          method: 'POST',
          baseUrl: dio.options.baseUrl,
          data: {'refreshToken': refreshToken},
          headers: {
            'Accept': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $currentAccessToken',
            'X-Device-Id': deviceId,
            'X-Client-Platform': store.flavor.clientPlatformTag,
            'X-App-Flavor': store.flavor.key,
          },
          extra: const {
            'skipSigning': true,
            'skipAuthRefresh': true,
            'skipTerminalSessionInvalidation': true,
          },
        ),
      );
      final raw = response.data;
      if (raw is! Map) return null;
      final accessToken =
          '${raw['token'] ?? raw['accessToken'] ?? raw['access_token'] ?? ''}'
              .trim();
      final nextRefreshToken =
          '${raw['refreshToken'] ?? raw['refresh_token'] ?? ''}'.trim();
      if (accessToken.isEmpty) return null;
      await store.saveAuthTokens(
        accessToken: accessToken,
        refreshToken: nextRefreshToken.isEmpty
            ? refreshToken
            : nextRefreshToken,
      );
      return accessToken;
    } on DioException catch (error) {
      if (_isInvalidRefreshFailure(error)) {
        final currentRefreshToken = await store.readRefreshToken();
        final decision = SessionRecoveryCoordinator.instance.classify(
          error,
          expectedRefreshToken: refreshToken,
          currentRefreshToken: currentRefreshToken,
        );
        if (decision == SessionRecoveryDecision.staleFailure) {
          error.requestOptions.extra['skipTerminalSessionInvalidation'] = true;
          final storedAccessToken = await store.readToken();
          if (storedAccessToken != null &&
              storedAccessToken.isNotEmpty &&
              storedAccessToken != currentAccessToken) {
            return storedAccessToken;
          }
          return null;
        }
        return await _recoverAccessToken(currentAccessToken);
      }
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _recoverAccessToken(String? currentAccessToken) async {
    if (_sessionRecoveryFuture != null) return _sessionRecoveryFuture;
    _sessionRecoveryFuture = _recoverAccessTokenOnce(currentAccessToken);
    try {
      return await _sessionRecoveryFuture;
    } finally {
      _sessionRecoveryFuture = null;
    }
  }

  Future<String?> _recoverAccessTokenOnce(String? currentAccessToken) async {
    final deviceSessionId = await store.readDeviceSessionId();
    final recoverySecret = await store.readDeviceRecoverySecret();
    if (deviceSessionId == null ||
        deviceSessionId.isEmpty ||
        recoverySecret == null ||
        recoverySecret.isEmpty) {
      return null;
    }

    try {
      final deviceId = await _ensureDeviceId(store);
      final response = await dio.fetch<dynamic>(
        RequestOptions(
          path: '/api/auth/session/recover',
          method: 'POST',
          baseUrl: dio.options.baseUrl,
          data: {
            'deviceSessionId': deviceSessionId,
            'deviceRecoverySecret': recoverySecret,
            'deviceId': deviceId,
            'appFlavor': store.flavor.key,
          },
          headers: {
            'Accept': 'application/json; charset=utf-8',
            if (currentAccessToken != null && currentAccessToken.isNotEmpty)
              'Authorization': 'Bearer $currentAccessToken',
            'X-Device-Id': deviceId,
            'X-Client-Platform': store.flavor.clientPlatformTag,
            'X-App-Flavor': store.flavor.key,
          },
          extra: const {
            'skipSigning': true,
            'skipAuthRefresh': true,
            'skipTerminalSessionInvalidation': true,
          },
        ),
      );
      final raw = response.data;
      if (raw is! Map) return null;
      final accessToken =
          '${raw['token'] ?? raw['accessToken'] ?? raw['access_token'] ?? ''}'
              .trim();
      final refreshToken =
          '${raw['refreshToken'] ?? raw['refresh_token'] ?? ''}'.trim();
      final nextDeviceSessionId =
          '${raw['deviceSessionId'] ?? raw['device_session_id'] ?? ''}'.trim();
      final nextRecoverySecret =
          '${raw['deviceRecoverySecret'] ?? raw['device_recovery_secret'] ?? ''}'
              .trim();
      if (accessToken.isEmpty) return null;
      await store.saveAuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken.isEmpty ? null : refreshToken,
        deviceSessionId: nextDeviceSessionId.isEmpty
            ? null
            : nextDeviceSessionId,
        deviceRecoverySecret: nextRecoverySecret.isEmpty
            ? null
            : nextRecoverySecret,
      );
      _sessionInvalidated = false;
      SessionRecoveryCoordinator.instance.reset();
      return accessToken;
    } catch (_) {
      return null;
    }
  }

  Future<Response<dynamic>?> _tryResolveUnauthorizedWithRefresh(
    DioException error,
  ) async {
    final request = error.requestOptions;
    if (error.response?.statusCode != 401) return null;
    if (request.extra['skipAuth'] == true ||
        request.extra['skipAuthRefresh'] == true ||
        request.extra['skipTerminalSessionInvalidation'] == true ||
        request.extra['_authRefreshRetried'] == true) {
      return null;
    }

    final responseCode = _extractAuthCode(error.response?.data);
    if (!isSessionAuthFailureCode(responseCode)) {
      return null;
    }

    final currentToken =
        await store.readToken() ??
        AuthSessionTokenCache.currentToken(flavor: store.flavor);
    if (currentToken == null || currentToken.isEmpty) return null;

    final requestToken = _readBearerHeader(request.headers['Authorization']);
    final nextToken = requestToken != null && requestToken != currentToken
        ? currentToken
        : await _refreshAccessToken(currentToken);
    if (nextToken == null || nextToken.isEmpty || nextToken == requestToken) {
      return null;
    }

    final retryOptions = request.copyWith(
      headers: Map<String, dynamic>.from(request.headers),
      extra: {...request.extra, '_authRefreshRetried': true},
    );
    retryOptions.headers['Authorization'] = 'Bearer $nextToken';
    retryOptions.headers['X-Device-Id'] = await _ensureDeviceId(store);
    retryOptions.headers['X-Client-Platform'] = store.flavor.clientPlatformTag;
    retryOptions.headers['X-App-Flavor'] = store.flavor.key;
    for (final header in const [
      'X-Request-Key-Id',
      'X-Request-Timestamp',
      'X-Request-Nonce',
      'X-Request-Signature',
    ]) {
      retryOptions.headers.remove(header);
    }
    if (retryOptions.extra['skipSigning'] != true) {
      await _attachRequestSignature(retryOptions, nextToken);
    }

    try {
      final response = await dio.fetch<dynamic>(retryOptions);
      response.data = _normalizePayload(response.data);
      return response;
    } on DioException {
      return null;
    }
  }

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
          extra: const {'skipSigning': true},
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
      if (_isRetryableConnectionError(error) ||
          (error.response?.statusCode ?? 0) >= 500 ||
          isRecoverableSessionAuthCode(messageCode)) {
        return null;
      }
      rethrow;
    }
  }

  String? _cachedBindingKey;

  Future<RequestSigningMaterial?> _readStoredSigningMaterial() async {
    final token =
        await store.readToken() ??
        AuthSessionTokenCache.currentToken(flavor: store.flavor);
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
      requestSigningKeyIdStorageKey: await store.readString(
        requestSigningKeyIdStorageKey,
      ),
      requestSigningSecretStorageKey: await store.readString(
        requestSigningSecretStorageKey,
      ),
      requestSigningIssuedAtStorageKey: await store.readString(
        requestSigningIssuedAtStorageKey,
      ),
      requestSigningExpiresAtStorageKey: await store.readString(
        requestSigningExpiresAtStorageKey,
      ),
      requestSigningAlgorithmStorageKey: await store.readString(
        requestSigningAlgorithmStorageKey,
      ),
      requestSigningRefreshWindowStorageKey: await store.readString(
        requestSigningRefreshWindowStorageKey,
      ),
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
  final key = store.storageKey(DioClient._deviceIdKey);
  final existing = await store.readString(DioClient._deviceIdKey);
  if (existing != null && existing.trim().isNotEmpty) {
    final normalized = existing.trim();
    await _persistDeviceIdFallback(key, normalized);
    return normalized;
  }
  final prefs = await SharedPreferences.getInstance();
  final fallback = prefs.getString(key);
  if (fallback != null && fallback.trim().isNotEmpty) {
    final normalized = fallback.trim();
    await store.writeString(DioClient._deviceIdKey, normalized);
    return normalized;
  }
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await store.writeString(DioClient._deviceIdKey, value);
  await _persistDeviceIdFallback(key, value);
  return value;
}

Future<void> _persistDeviceIdFallback(String key, String value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  } catch (_) {
    // The in-memory SecureStore fallback still covers the current process.
  }
}

bool _isRetryableConnectionError(DioException error) {
  return error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout;
}

bool _isInvalidRefreshFailure(DioException error) {
  final status = error.response?.statusCode;
  if (status != 400 && status != 401) return false;
  final data = error.response?.data;
  final rawMessage = data is Map ? (data['message'] ?? data['code']) : data;
  final message = '$rawMessage'.trim().toUpperCase();
  return isSessionAuthFailureCode(message);
}

String? _readBearerHeader(Object? value) {
  final raw = '$value'.trim();
  if (raw.isEmpty) return null;
  const prefix = 'Bearer ';
  if (!raw.toLowerCase().startsWith(prefix.toLowerCase())) return null;
  final token = raw.substring(prefix.length).trim();
  return token.isEmpty ? null : token;
}

String? _extractAuthCode(dynamic data) {
  if (data is Map) {
    final raw = data['message'] ?? data['code'];
    final normalized = '$raw'.trim().toUpperCase();
    return normalized.isEmpty ? null : normalized;
  }
  if (data is String) {
    final normalized = data.trim().toUpperCase();
    return normalized.isEmpty ? null : normalized;
  }
  return null;
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
