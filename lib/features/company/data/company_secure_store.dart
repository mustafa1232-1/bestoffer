import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CompanySecureStore {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'company_access_token';
  static const _deviceIdKey = 'company_device_id';
  static const _activeCompanyIdKey = 'company_active_company_id';
  static final Map<String, String> _volatileValues = {};

  Future<void> saveToken(String token) async {
    _volatileValues[_tokenKey] = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {}
  }

  Future<String?> readToken() async {
    try {
      final value = await _storage.read(key: _tokenKey);
      if (value != null && value.isNotEmpty) {
        _volatileValues[_tokenKey] = value;
        return value;
      }
    } catch (_) {}
    return _volatileValues[_tokenKey];
  }

  Future<void> saveActiveCompanyId(int companyId) async {
    await writeString(_activeCompanyIdKey, '$companyId');
  }

  Future<int?> readActiveCompanyId() async {
    final raw = await readString(_activeCompanyIdKey);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<void> clear() async {
    _volatileValues.remove(_tokenKey);
    _volatileValues.remove(_activeCompanyIdKey);
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _activeCompanyIdKey);
    } catch (_) {}
  }

  Future<void> writeString(String key, String value) async {
    _volatileValues[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  Future<String?> readString(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) {
        _volatileValues[key] = value;
        return value;
      }
    } catch (_) {}
    return _volatileValues[key];
  }

  Future<String?> readDeviceId() => readString(_deviceIdKey);

  Future<void> writeDeviceId(String value) => writeString(_deviceIdKey, value);
}
