import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api.dart';
import '../platform/app_flavor.dart';
import '../theme/theme_preset.dart';
import '../storage/secure_storage.dart';

/// حالة الإعدادات المحلية المشتركة: اللغة، الحركة، والمؤثرات البصرية.
class AppSettingsState {
  final Locale locale;
  final bool animationsEnabled;
  final bool weatherEffectsEnabled;
  final AppThemePreset themePreset;
  final bool loaded;

  const AppSettingsState({
    required this.locale,
    required this.animationsEnabled,
    required this.weatherEffectsEnabled,
    required this.themePreset,
    required this.loaded,
  });

  factory AppSettingsState.initial() => const AppSettingsState(
    locale: Locale('ar'),
    animationsEnabled: true,
    weatherEffectsEnabled: true,
    themePreset: AppThemePreset.midnightBlue,
    loaded: false,
  );

  AppSettingsState copyWith({
    Locale? locale,
    bool? animationsEnabled,
    bool? weatherEffectsEnabled,
    AppThemePreset? themePreset,
    bool? loaded,
  }) {
    return AppSettingsState(
      locale: locale ?? this.locale,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      weatherEffectsEnabled:
          weatherEffectsEnabled ?? this.weatherEffectsEnabled,
      themePreset: themePreset ?? this.themePreset,
      loaded: loaded ?? this.loaded,
    );
  }
}

final appSettingsControllerProvider =
    StateNotifierProvider<AppSettingsController, AppSettingsState>((ref) {
      final store = SecureStore(flavor: ref.watch(appFlavorProvider));
      return AppSettingsController(
        store,
        deviceLocale: PlatformDispatcher.instance.locale,
        storageScope: ref.read(appSettingsStorageScopeProvider),
        remoteSync: AppLocaleRemoteSync(store),
      )..bootstrap();
    });

/// Prefix used to isolate persisted settings per app runtime.
/// Example:
/// - user app => "user"
/// - store app => "store"
/// - delivery app => "delivery"
/// - captain app => "captain"
/// - company app => "company"
final appSettingsStorageScopeProvider = Provider<String>((ref) => 'root');

/// المتحكم المركزي لإعدادات الواجهة المخزنة محلياً.
///
/// Maintenance notes:
/// - إذا لم تُحفظ اللغة أو عادت الإعدادات للوضع الافتراضي بعد restart،
///   ابدأ من هذا الملف ثم `SecureStore`.
class AppSettingsController extends StateNotifier<AppSettingsState> {
  static const _keyLocaleBase = 'app_locale';
  static const _keyAnimationsBase = 'app_animations';
  static const _keyWeatherEffectsBase = 'app_weather_effects';
  static const _keyThemePresetBase = 'app_theme_preset';
  static const _legacyKeyLocale = _keyLocaleBase;
  static const _legacyKeyAnimations = _keyAnimationsBase;
  static const _legacyKeyWeatherEffects = _keyWeatherEffectsBase;
  static const _legacyKeyThemePreset = _keyThemePresetBase;

  final SecureStore store;
  final Locale? deviceLocale;
  final String storageScope;
  final AppLocaleRemoteSync remoteSync;

  AppSettingsController(
    this.store, {
    this.deviceLocale,
    String storageScope = 'root',
    AppLocaleRemoteSync? remoteSync,
  }) : storageScope = storageScope.trim().isEmpty
           ? 'root'
           : storageScope.trim().toLowerCase(),
       remoteSync = remoteSync ?? AppLocaleRemoteSync(store),
       super(AppSettingsState.initial());

  String get _keyLocale => '${storageScope}_$_keyLocaleBase';
  String get _keyAnimations => '${storageScope}_$_keyAnimationsBase';
  String get _keyWeatherEffects => '${storageScope}_$_keyWeatherEffectsBase';
  String get _keyThemePreset => '${storageScope}_$_keyThemePresetBase';

  /// يحمّل التفضيلات من التخزين، مع أولوية للقيمة المحفوظة ثم لغة الجهاز
  /// ثم fallback عربي.
  Future<void> bootstrap() async {
    final localeRaw = await _readScopedStringWithLegacyFallback(
      _keyLocale,
      _legacyKeyLocale,
    );
    final animationsRaw = await _readScopedBoolWithLegacyFallback(
      _keyAnimations,
      _legacyKeyAnimations,
    );
    final weatherRaw = await _readScopedBoolWithLegacyFallback(
      _keyWeatherEffects,
      _legacyKeyWeatherEffects,
    );
    final themePresetRaw = await _readScopedStringWithLegacyFallback(
      _keyThemePreset,
      _legacyKeyThemePreset,
    );

    final locale =
        _normalizeLocale(localeRaw) ??
        _normalizeLocale(deviceLocale?.languageCode) ??
        const Locale('ar');
    state = state.copyWith(
      locale: locale,
      animationsEnabled: animationsRaw ?? true,
      weatherEffectsEnabled: weatherRaw ?? true,
      themePreset: AppThemePreset.fromStorageValue(themePresetRaw),
      loaded: true,
    );
  }

  /// يثبت اللغة المختارة محلياً ويحدث Directionality على مستوى التطبيق.
  Future<void> setLocale(Locale locale, {bool syncRemote = true}) async {
    final normalized =
        _normalizeLocale(locale.languageCode) ?? const Locale('ar');
    await _persistLocale(normalized);
    if (!syncRemote) return;
    await remoteSync.savePreferredLocale(normalized.languageCode);
  }

  Future<void> applyRemoteLocale(Locale locale) async {
    final normalized =
        _normalizeLocale(locale.languageCode) ?? const Locale('ar');
    await _persistLocale(normalized);
  }

  Future<void> setAnimationsEnabled(bool value) async {
    state = state.copyWith(animationsEnabled: value);
    await store.writeBool(_keyAnimations, value);
  }

  Future<void> setWeatherEffectsEnabled(bool value) async {
    state = state.copyWith(weatherEffectsEnabled: value);
    await store.writeBool(_keyWeatherEffects, value);
  }

  Future<void> setThemePreset(AppThemePreset preset) async {
    state = state.copyWith(themePreset: AppThemePreset.midnightBlue);
    await store.writeString(
      _keyThemePreset,
      AppThemePreset.midnightBlue.storageValue,
    );
  }

  Future<void> resetVisualDefaults() async {
    state = state.copyWith(
      animationsEnabled: true,
      weatherEffectsEnabled: true,
      themePreset: AppThemePreset.midnightBlue,
    );
    await store.writeBool(_keyAnimations, true);
    await store.writeBool(_keyWeatherEffects, true);
    await store.writeString(
      _keyThemePreset,
      AppThemePreset.midnightBlue.storageValue,
    );
  }

  Locale? _normalizeLocale(String? code) {
    if (code == null) return null;
    final normalized = code.toLowerCase().trim();
    if (normalized == 'en') return const Locale('en');
    if (normalized == 'ar') return const Locale('ar');
    return null;
  }

  Future<String?> _readScopedStringWithLegacyFallback(
    String scopedKey,
    String legacyKey,
  ) async {
    final scoped = await store.readString(scopedKey);
    if (scoped != null && scoped.trim().isNotEmpty) {
      return scoped;
    }
    return store.readString(legacyKey);
  }

  Future<bool?> _readScopedBoolWithLegacyFallback(
    String scopedKey,
    String legacyKey,
  ) async {
    final scoped = await store.readBool(scopedKey);
    if (scoped != null) return scoped;
    return store.readBool(legacyKey);
  }

  Future<void> _persistLocale(Locale locale) async {
    state = state.copyWith(locale: locale);
    await store.writeString(_keyLocale, locale.languageCode);
  }
}

class AppLocaleRemoteSync {
  final SecureStore store;
  final Dio _dio;

  AppLocaleRemoteSync(this.store)
    : _dio = Dio(
        BaseOptions(
          baseUrl: Api.baseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: const {'Accept': 'application/json; charset=utf-8'},
        ),
      );

  Future<void> savePreferredLocale(String languageCode) async {
    final normalized = languageCode.trim().toLowerCase();
    if (normalized != 'ar' && normalized != 'en') return;

    final token = await store.readToken();
    if (token == null || token.isEmpty) return;

    try {
      await _dio.patch<void>(
        '/api/users/me',
        data: {'preferredLocale': normalized},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'X-Client-Platform': store.flavor.clientPlatformTag,
            'X-App-Flavor': store.flavor.key,
          },
        ),
      );
    } catch (_) {
      // Keep the local language change even if remote sync is unavailable.
    }
  }
}
