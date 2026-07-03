import '../platform/app_flavor.dart';

class AuthSessionTokenCache {
  static final Map<AppFlavor, String?> _tokens = <AppFlavor, String?>{};

  static String? currentToken({AppFlavor? flavor}) {
    final resolvedFlavor = flavor ?? AppFlavorContext.current;
    return _tokens[resolvedFlavor];
  }

  static void setToken(String? token, {AppFlavor? flavor}) {
    final normalized = token?.trim();
    final resolvedFlavor = flavor ?? AppFlavorContext.current;
    _tokens[resolvedFlavor] =
        (normalized == null || normalized.isEmpty) ? null : normalized;
  }

  static void clear({AppFlavor? flavor}) {
    final resolvedFlavor = flavor ?? AppFlavorContext.current;
    _tokens.remove(resolvedFlavor);
  }

  static void clearAll() {
    _tokens.clear();
  }
}

