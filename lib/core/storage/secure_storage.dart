import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/auth_session_token_cache.dart';
import '../network/request_signing.dart';
import '../platform/app_flavor.dart';

class SecureStore {
  static const _storage = FlutterSecureStorage();

  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _sessionIdKey = 'session_id';
  static const _guestModeKey = 'guest_mode_active';
  static const _deviceSessionIdKey = 'device_session_id';
  static const _deviceRecoverySecretKey = 'device_recovery_secret';
  static const _authBundleKey = 'auth_bundle';
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
    _sessionIdKey,
    _guestModeKey,
    _deviceSessionIdKey,
    _deviceRecoverySecretKey,
    _authBundleKey,
    ..._requestSigningKeys,
  };

  static const _authBundleFields = <String, String>{
    _tokenKey: 'accessToken',
    _refreshTokenKey: 'refreshToken',
    _sessionIdKey: 'sessionId',
    _deviceSessionIdKey: 'deviceSessionId',
    _deviceRecoverySecretKey: 'deviceRecoverySecret',
  };

  static final Map<String, String> _volatileValues = {};
  static final Map<AppFlavor, String?> _volatileTokens = {};

  final AppFlavor flavor;

  SecureStore({AppFlavor? flavor})
    : flavor = flavor ?? AppFlavorContext.current;

  String storageKey(String key) => _storageKeyFor(flavor, key);

  String _storageKeyFor(AppFlavor flavor, String key) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return normalizedKey;
    return '${flavor.key}_$normalizedKey';
  }

  List<String> _fallbackStorageKeys(String key) {
    if (flavor == AppFlavor.user) {
      final legacy = key.trim();
      if (legacy.isNotEmpty) return [legacy];
    }
    return const [];
  }

  List<String> _allStorageKeys(String key) {
    final scoped = storageKey(key);
    final fallbacks = _fallbackStorageKeys(key);
    return [scoped, ...fallbacks.where((value) => value != scoped)];
  }

  Future<void> saveToken(String token) async {
    final previousToken =
        _volatileTokens[flavor] ??
        _volatileValues[storageKey(_tokenKey)] ??
        AuthSessionTokenCache.currentToken(flavor: flavor);
    if (previousToken != null && previousToken != token) {
      for (final key in _requestSigningKeys) {
        await delete(key);
      }
    }

    _volatileTokens[flavor] = token;
    AuthSessionTokenCache.setToken(token, flavor: flavor);
    await _saveAuthBundle(accessToken: token);
    await _writeStoredString(_tokenKey, token);
  }

  Future<void> saveAuthTokens({
    required String accessToken,
    String? refreshToken,
    String? sessionId,
    String? deviceSessionId,
    String? deviceRecoverySecret,
  }) async {
    await _saveAuthBundle(
      accessToken: accessToken,
      refreshToken: refreshToken,
      sessionId: sessionId,
      deviceSessionId: deviceSessionId,
      deviceRecoverySecret: deviceRecoverySecret,
    );
  }

  Future<void> _saveAuthBundle({
    required String accessToken,
    String? refreshToken,
    String? sessionId,
    String? deviceSessionId,
    String? deviceRecoverySecret,
  }) async {
    final previous = await _readAuthBundle();
    final previousToken = _readBundleString(previous, 'accessToken');
    if (previousToken != null && previousToken != accessToken) {
      for (final key in _requestSigningKeys) {
        await delete(key);
      }
    }

    final bundle = <String, dynamic>{
      'accessToken': accessToken.trim(),
      'refreshToken':
          _normalizeOptional(refreshToken) ??
          _readBundleString(previous, 'refreshToken') ??
          await _readStoredString(_refreshTokenKey),
      'sessionId':
          _normalizeOptional(sessionId) ??
          _readBundleString(previous, 'sessionId') ??
          await _readStoredString(_sessionIdKey),
      'deviceSessionId':
          _normalizeOptional(deviceSessionId) ??
          _readBundleString(previous, 'deviceSessionId') ??
          await _readStoredString(_deviceSessionIdKey),
      'deviceRecoverySecret':
          _normalizeOptional(deviceRecoverySecret) ??
          _readBundleString(previous, 'deviceRecoverySecret') ??
          await _readStoredString(_deviceRecoverySecretKey),
      'bundleVersion': 1,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    bundle.removeWhere((_, value) => value == null || '$value'.trim().isEmpty);

    final encoded = jsonEncode(bundle);
    await _writeStoredString(_authBundleKey, encoded);
    _volatileTokens[flavor] = bundle['accessToken'] as String?;
    AuthSessionTokenCache.setToken(
      bundle['accessToken'] as String?,
      flavor: flavor,
    );

    await _writeStoredString(_tokenKey, bundle['accessToken'] as String);
    for (final entry in _authBundleFields.entries) {
      if (entry.key == _tokenKey) continue;
      final value = _readBundleString(bundle, entry.value);
      if (value != null) {
        await _writeStoredString(entry.key, value);
      }
    }
  }

  Future<void> saveGuestMode(bool enabled) async {
    if (enabled) {
      await writeBool(_guestModeKey, true);
    } else {
      await delete(_guestModeKey);
    }
  }

  Future<bool> readGuestMode() async {
    return await readBool(_guestModeKey) ?? false;
  }

  Future<String?> readToken() async {
    final guestMode = await readBool(_guestModeKey) ?? false;
    if (guestMode) {
      _volatileTokens[flavor] = null;
      AuthSessionTokenCache.clear(flavor: flavor);
      return null;
    }

    final value = await readString(_tokenKey);
    if (value != null && value.isNotEmpty) {
      _volatileTokens[flavor] = value;
      AuthSessionTokenCache.setToken(value, flavor: flavor);
      return value;
    }

    final fallback =
        _volatileTokens[flavor] ??
        _volatileValues[storageKey(_tokenKey)] ??
        AuthSessionTokenCache.currentToken(flavor: flavor);
    AuthSessionTokenCache.setToken(fallback, flavor: flavor);
    return fallback;
  }

  Future<String?> readRefreshToken() async {
    final value = await readString(_refreshTokenKey);
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<String?> readSessionId() async {
    final value = await readString(_sessionIdKey);
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<String?> readDeviceSessionId() async {
    final value = await readString(_deviceSessionIdKey);
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<String?> readDeviceRecoverySecret() async {
    final value = await readString(_deviceRecoverySecretKey);
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<void> clear() async {
    for (final key in _authScopedKeys) {
      _volatileValues.remove(storageKey(key));
      for (final fallback in _fallbackStorageKeys(key)) {
        _volatileValues.remove(fallback);
      }
    }
    _volatileTokens[flavor] = null;
    AuthSessionTokenCache.clear(flavor: flavor);
    for (final key in _authScopedKeys) {
      for (final storageName in _allStorageKeys(key)) {
        try {
          await _storage.delete(key: storageName);
        } catch (_) {
          // Ignore clear failures in secure storage.
        }
      }
    }
  }

  Future<void> writeString(String key, String value) async {
    if (_authBundleFields.containsKey(key)) {
      final existing = await _readAuthBundle();
      final next = Map<String, dynamic>.from(existing ?? const {});
      next[_authBundleFields[key]!] = value;
      next['bundleVersion'] = 1;
      next['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      await _writeStoredString(_authBundleKey, jsonEncode(next));
      if (key == _tokenKey) {
        _volatileTokens[flavor] = value;
        AuthSessionTokenCache.setToken(value, flavor: flavor);
      }
    }
    await _writeStoredString(key, value);
  }

  Future<void> _writeStoredString(String key, String value) async {
    final scopedKey = storageKey(key);
    _volatileValues[scopedKey] = value;
    try {
      await _storage.write(key: scopedKey, value: value);
    } catch (_) {
      // Fallback to volatile storage only.
    }
  }

  Future<String?> readString(String key) async {
    final bundleField = _authBundleFields[key];
    if (bundleField != null) {
      final bundle = await _readAuthBundle();
      final value = _readBundleString(bundle, bundleField);
      if (value != null && value.isNotEmpty) return value;
    }
    return _readStoredString(key);
  }

  Future<String?> _readStoredString(String key) async {
    for (final storageName in _allStorageKeys(key)) {
      try {
        final value = await _storage.read(key: storageName);
        if (value != null) {
          _volatileValues[storageName] = value;
          return value;
        }
      } catch (_) {
        // Fallback to volatile storage only.
      }
      final cached = _volatileValues[storageName];
      if (cached != null) {
        return cached;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _readAuthBundle() async {
    final raw = await _readStoredString(_authBundleKey);
    final text = raw?.trim();
    if (text != null && text.isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Fall through to legacy migration.
      }
    }

    final legacyAccessToken = await _readStoredString(_tokenKey);
    if (legacyAccessToken == null || legacyAccessToken.trim().isEmpty) {
      return null;
    }
    final migrated = <String, dynamic>{
      'accessToken': legacyAccessToken.trim(),
      'refreshToken': await _readStoredString(_refreshTokenKey),
      'sessionId': await _readStoredString(_sessionIdKey),
      'deviceSessionId': await _readStoredString(_deviceSessionIdKey),
      'deviceRecoverySecret': await _readStoredString(_deviceRecoverySecretKey),
      'bundleVersion': 1,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    migrated.removeWhere(
      (_, value) => value == null || '$value'.trim().isEmpty,
    );
    await _writeStoredString(_authBundleKey, jsonEncode(migrated));
    return migrated;
  }

  String? _readBundleString(Map<String, dynamic>? bundle, String key) {
    final raw = bundle?[key];
    final text = raw == null ? null : '$raw'.trim();
    return text == null || text.isEmpty ? null : text;
  }

  String? _normalizeOptional(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  Future<void> delete(String key) async {
    for (final storageName in _allStorageKeys(key)) {
      _volatileValues.remove(storageName);
      try {
        await _storage.delete(key: storageName);
      } catch (_) {
        // Ignore clear failures in secure storage.
      }
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
