import 'package:flutter/foundation.dart';

class Api {
  static const String _baseUrlFromEnv = String.fromEnvironment('API_BASE_URL');
  static const String _defaultProductionUrl = String.fromEnvironment(
    'API_DEFAULT_PROD_URL',
    defaultValue: 'https://bestoffer-production-549e.up.railway.app',
  );

  static List<String> get fallbackBaseUrls {
    final envUrl = _baseUrlFromEnv.trim();
    if (envUrl.isNotEmpty) {
      return [envUrl];
    }

    final prodUrl = _defaultProductionUrl.trim();
    final urls = <String>{};
    if (prodUrl.isNotEmpty) {
      // Always keep production first so emulator and physical devices share
      // one stable backend by default.
      urls.add(prodUrl);
    }

    if (kReleaseMode) {
      return urls.isNotEmpty
          ? urls.toList()
          : const ['https://bestoffer-production-549e.up.railway.app'];
    }

    if (kIsWeb) {
      urls.add('http://localhost:3000');
      return urls.toList();
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        urls.add('http://10.0.2.2:3000'); // Android emulator
        urls.add('http://10.0.3.2:3000'); // Genymotion emulator
        urls.add('http://127.0.0.1:3000'); // adb reverse
        return urls.toList();
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        urls.add('http://127.0.0.1:3000');
        urls.add('http://localhost:3000');
        return urls.toList();
      case TargetPlatform.fuchsia:
        urls.add('http://localhost:3000');
        return urls.toList();
    }
  }

  static String get baseUrl {
    return fallbackBaseUrls.first;
  }
}
