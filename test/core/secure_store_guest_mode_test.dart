import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/network/auth_session_token_cache.dart';
import 'package:maslaki/core/storage/secure_storage.dart';

class _MemorySecureStore extends SecureStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> readString(String key) async {
    return _values[key];
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

void main() {
  test('guest mode suppresses any cached token and returns null', () async {
    final store = _MemorySecureStore();
    await store.saveGuestMode(true);
    await store.writeString('access_token', 'stale-token');
    AuthSessionTokenCache.setToken('stale-token');

    final token = await store.readToken();

    expect(token, isNull);
    expect(AuthSessionTokenCache.currentToken(), isNull);
  });
}
