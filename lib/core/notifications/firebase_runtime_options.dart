import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseRuntimeOptions {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _genericAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _measurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
  );
  static const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
  static const _iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');
  static const _androidClientId = String.fromEnvironment(
    'FIREBASE_ANDROID_CLIENT_ID',
  );

  static FirebaseOptions? currentPlatform() {
    if (_apiKey.isEmpty || _projectId.isEmpty || _messagingSenderId.isEmpty) {
      return null;
    }

    if (kIsWeb) {
      final appId = _firstNonEmpty([_webAppId, _genericAppId]);
      if (appId == null) return null;
      return FirebaseOptions(
        apiKey: _apiKey,
        appId: appId,
        messagingSenderId: _messagingSenderId,
        projectId: _projectId,
        authDomain: _valueOrNull(_authDomain),
        storageBucket: _valueOrNull(_storageBucket),
        measurementId: _valueOrNull(_measurementId),
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final appId = _firstNonEmpty([_androidAppId, _genericAppId]);
        if (appId == null) return null;
        return FirebaseOptions(
          apiKey: _apiKey,
          appId: appId,
          messagingSenderId: _messagingSenderId,
          projectId: _projectId,
          storageBucket: _valueOrNull(_storageBucket),
          androidClientId: _valueOrNull(_androidClientId),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        final appId = _firstNonEmpty([_iosAppId, _genericAppId]);
        if (appId == null) return null;
        return FirebaseOptions(
          apiKey: _apiKey,
          appId: appId,
          messagingSenderId: _messagingSenderId,
          projectId: _projectId,
          storageBucket: _valueOrNull(_storageBucket),
          iosBundleId: _valueOrNull(_iosBundleId),
          iosClientId: _valueOrNull(_iosClientId),
        );
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return null;
    }
  }

  static String? _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static String? _valueOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
