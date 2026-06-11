class AuthSessionTokenCache {
  static String? _token;

  static String? get currentToken => _token;

  static void setToken(String? token) {
    final normalized = token?.trim();
    _token = (normalized == null || normalized.isEmpty) ? null : normalized;
  }

  static void clear() {
    _token = null;
  }
}
