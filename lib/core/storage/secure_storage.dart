import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/auth_session_token_cache.dart';
import '../network/request_signing.dart';

class SecureStore {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _requestSigningKeys = <String>{
    requestSigningKeyIdStorageKey,
    requestSigningSecretStorageKey,
    requestSigningIssuedAtStorageKey,
    requestSigningExpiresAtStorageKey,
    requestSigningAlgorithmStorageKey,
    requestSigningRefreshWindowStorageKey,
  };
  static const _authScopedKeys = <String>{
    _tokenKey,
    _refreshTokenKey,
    ..._requestSigningKeys,
  };
  static final Map<String, String> _volatileValues = {};
  static String? _volatileToken;

  Future<void> saveToken(String token) async {
    final previousToken =
        _volatileToken ??
        _volatileValues[_tokenKey] ??
        AuthSessionTokenCache.currentToken;
    if (previousToken != null && previousToken != token) {
      for (final key in _requestSigningKeys) {
        _volatileValues.remove(key);
        try {
          await _storage.delete(key: key);
        } catch (_) {
          // Ignore secure storage cleanup failures.
        }
      }
    }
    _volatileValues[_tokenKey] = token;
    _volatileToken = token;
    AuthSessionTokenCache.setToken(token);
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {
      // Some Android emulators fail secure keystore init; keep volatile fallback.
    }
  }

  Future<void> saveAuthTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await saveToken(accessToken);
    final normalizedRefreshToken = refreshToken?.trim();
    if (normalizedRefreshToken != null && normalizedRefreshToken.isNotEmpty) {
      await writeString(_refreshTokenKey, normalizedRefreshToken);
    }
  }

  Future<String?> readToken() async {
    final value = await readString(_tokenKey);
    if (value != null && value.isNotEmpty) {
      _volatileToken = value;
      AuthSessionTokenCache.setToken(value);
      return value;
    }
    final fallback =
        _volatileToken ??
        _volatileValues[_tokenKey] ??
        AuthSessionTokenCache.currentToken;
    AuthSessionTokenCache.setToken(fallback);
    return fallback;
  }

  Future<String?> readRefreshToken() async {
    final value = await readString(_refreshTokenKey);
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<void> clear() async {
    for (final key in _authScopedKeys) {
      _volatileValues.remove(key);
    }
    _volatileToken = null;
    AuthSessionTokenCache.clear();
    for (final key in _authScopedKeys) {
      try {
        await _storage.delete(key: key);
      } catch (_) {
        // Ignore clear failures in secure storage.
      }
    }
  }

  Future<void> writeString(String key, String value) async {
    _volatileValues[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Fallback to volatile storage only.
    }
  }

  Future<String?> readString(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) {
        _volatileValues[key] = value;
        return value;
      }
    } catch (_) {
      // Fallback to volatile storage only.
    }
    return _volatileValues[key];
  }

  Future<void> delete(String key) async {
    _volatileValues.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Ignore clear failures in secure storage.
    }
  }

  Future<void> writeBool(String key, bool value) =>
      writeString(key, value ? '1' : '0');

  Future<bool?> readBool(String key) async {
    final raw = await readString(key);
    if (raw == null) return null;
    if (raw == '1' || raw.toLowerCase() == 'true') return true;
    if (raw == '0' || raw.toLowerCase() == 'false') return false;
    return null;
  }
}
