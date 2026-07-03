import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/auth_session_token_cache.dart';
import '../network/request_signing.dart';
import '../platform/app_flavor.dart';

class SecureStore {
  static const _storage = FlutterSecureStorage();

  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _guestModeKey = 'guest_mode_active';
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
    _guestModeKey,
    ..._requestSigningKeys,
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

    final scopedKey = storageKey(_tokenKey);
    _volatileValues[scopedKey] = token;
    _volatileTokens[flavor] = token;
    AuthSessionTokenCache.setToken(token, flavor: flavor);

    try {
      await _storage.write(key: scopedKey, value: token);
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
    final scopedKey = storageKey(key);
    _volatileValues[scopedKey] = value;
    try {
      await _storage.write(key: scopedKey, value: value);
    } catch (_) {
      // Fallback to volatile storage only.
    }
  }

  Future<String?> readString(String key) async {
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

