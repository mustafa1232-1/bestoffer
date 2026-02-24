import 'package:flutter/foundation.dart';

class Api {
  static const String _baseUrlFromEnv = String.fromEnvironment('API_BASE_URL');

  static List<String> get fallbackBaseUrls {
    final envUrl = _baseUrlFromEnv.trim();
    if (envUrl.isNotEmpty) {
      return [envUrl];
    }

    if (kIsWeb) {
      return const ['http://localhost:3000'];
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Android emulator -> 10.0.2.2
        // Physical Android via adb reverse -> 127.0.0.1
        // Genymotion emulator -> 10.0.3.2
        return const [
          'http://10.0.2.2:3000',
          'http://127.0.0.1:3000',
          'http://10.0.3.2:3000',
        ];
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return const ['http://127.0.0.1:3000', 'http://localhost:3000'];
      case TargetPlatform.fuchsia:
        return const ['http://localhost:3000'];
    }
  }

  static String get baseUrl {
    return fallbackBaseUrls.first;
  }
}
