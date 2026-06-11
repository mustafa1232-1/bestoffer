import 'dart:math';

import 'package:core_storage/core_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final runtimeApiBaseUrlProvider = Provider<String>((_) {
  return RuntimeApiConfig.baseUrl;
});

final runtimeDioProvider = Provider<Dio>((ref) {
  final secureStore = ref.watch(appScopedSecureStoreProvider);
  final preferencesStore = ref.watch(appScopedPreferencesStoreProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: ref.watch(runtimeApiBaseUrlProvider),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: 'application/json; charset=utf-8',
      responseType: ResponseType.json,
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await secureStore.readToken();
        if (token != null && token.trim().isNotEmpty) {
          options.headers['Authorization'] = 'Bearer ${token.trim()}';
        }
        options.headers['X-Device-Id'] = await _ensureRuntimeDeviceId(
          preferencesStore,
        );
        options.headers['X-Client-Platform'] = 'flutter_split_runtime';
        handler.next(options);
      },
    ),
  );
  return dio;
});

class RuntimeApiConfig {
  static const String _baseUrlFromEnv = String.fromEnvironment('API_BASE_URL');
  static const String _defaultProductionUrl = String.fromEnvironment(
    'API_DEFAULT_PROD_URL',
    defaultValue: 'https://bestoffer-production.up.railway.app',
  );

  static List<String> get fallbackBaseUrls {
    final envUrl = _baseUrlFromEnv.trim();
    if (envUrl.isNotEmpty) {
      return [envUrl];
    }

    final prodUrl = _defaultProductionUrl.trim();
    final urls = <String>{};
    if (prodUrl.isNotEmpty) {
      urls.add(prodUrl);
    }

    if (kReleaseMode) {
      return urls.isNotEmpty
          ? urls.toList()
          : const ['https://bestoffer-production.up.railway.app'];
    }

    if (kIsWeb) {
      urls.add('http://localhost:3000');
      return urls.toList();
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        urls.add('http://10.0.2.2:3000');
        urls.add('http://10.0.3.2:3000');
        urls.add('http://127.0.0.1:3000');
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

  static String get baseUrl => fallbackBaseUrls.first;
}

Future<String> _ensureRuntimeDeviceId(
  AppScopedPreferencesStore preferencesStore,
) async {
  const deviceIdKey = 'runtime.device_id';
  final existing = await preferencesStore.readString(deviceIdKey);
  if (existing != null && existing.trim().isNotEmpty) {
    return existing.trim();
  }
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await preferencesStore.writeString(deviceIdKey, value);
  return value;
}
