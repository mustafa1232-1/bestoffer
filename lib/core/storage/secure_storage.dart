import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'access_token';
  static final Map<String, String> _volatileValues = {};
  static String? _volatileToken;

  Future<void> saveToken(String token) async {
    _volatileValues[_tokenKey] = token;
    _volatileToken = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {
      // Some Android emulators fail secure keystore init; keep volatile fallback.
    }
  }

  Future<String?> readToken() async {
    final value = await readString(_tokenKey);
    if (value != null && value.isNotEmpty) {
      _volatileToken = value;
      return value;
    }
    return _volatileToken ?? _volatileValues[_tokenKey];
  }

  Future<void> clear() async {
    _volatileValues.remove(_tokenKey);
    _volatileToken = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // Ignore clear failures in secure storage.
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
