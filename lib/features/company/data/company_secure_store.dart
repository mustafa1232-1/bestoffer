import '../../../core/platform/app_flavor.dart';
import '../../../core/storage/secure_storage.dart';

class CompanySecureStore {
  static const _activeCompanyIdKey = 'active_company_id';

  final SecureStore _store = SecureStore(flavor: AppFlavor.company);

  SecureStore get secureStore => _store;

  Future<void> saveToken(String token) async {
    await _store.saveToken(token);
  }

  Future<void> saveAuthTokens({
    required String accessToken,
    String? refreshToken,
    String? sessionId,
    String? deviceSessionId,
    String? deviceRecoverySecret,
  }) async {
    await _store.saveAuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      sessionId: sessionId,
      deviceSessionId: deviceSessionId,
      deviceRecoverySecret: deviceRecoverySecret,
    );
  }

  Future<String?> readToken() async {
    return _store.readToken();
  }

  Future<String?> readRefreshToken() async {
    return _store.readRefreshToken();
  }

  Future<void> saveActiveCompanyId(int companyId) async {
    await writeString(_activeCompanyIdKey, '$companyId');
  }

  Future<int?> readActiveCompanyId() async {
    final raw = await readString(_activeCompanyIdKey);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<void> clear() async {
    await _store.clear();
  }

  Future<void> writeString(String key, String value) async {
    await _store.writeString(key, value);
  }

  Future<String?> readString(String key) async {
    return _store.readString(key);
  }

  Future<String?> readDeviceId() => readString('device_id');

  Future<void> writeDeviceId(String value) => writeString('device_id', value);
}
