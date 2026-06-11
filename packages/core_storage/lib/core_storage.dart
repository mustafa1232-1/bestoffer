import 'dart:async';

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _memoryPreferences = <String, Object?>{};
final _memorySecureValues = <String, String?>{};

class AppScopedSecureStore {
  static const _tokenKey = 'auth.token';
  static const _secureStorage = FlutterSecureStorage();

  final AppScopedPreferencesStore _preferences;
  final bool inMemoryOnly;

  const AppScopedSecureStore(this._preferences, {this.inMemoryOnly = false});

  String _tokenStorageKey() => _preferences.scopedKey(_tokenKey);

  Future<void> saveToken(String token) async {
    final namespacedKey = _tokenStorageKey();
    if (inMemoryOnly) {
      _memorySecureValues[namespacedKey] = token;
      return;
    }
    await _secureStorage.write(key: namespacedKey, value: token);
  }

  Future<String?> readToken() async {
    final namespacedKey = _tokenStorageKey();
    if (inMemoryOnly) return _memorySecureValues[namespacedKey];
    return _secureStorage.read(key: namespacedKey);
  }

  Future<void> clearToken() async {
    final namespacedKey = _tokenStorageKey();
    if (inMemoryOnly) {
      _memorySecureValues.remove(namespacedKey);
      return;
    }
    await _secureStorage.delete(key: namespacedKey);
  }
}

class AppScopedPreferencesStore {
  final String scope;

  const AppScopedPreferencesStore({required this.scope});

  String scopedKey(String key) => '$scope.$key';

  Future<String?> readString(String key) async {
    final namespacedKey = scopedKey(key);
    final prefs = await _prefsOrNull();
    if (prefs != null) return prefs.getString(namespacedKey);
    return _memoryPreferences[namespacedKey] as String?;
  }

  Future<bool?> readBool(String key) async {
    final namespacedKey = scopedKey(key);
    final prefs = await _prefsOrNull();
    if (prefs != null) return prefs.getBool(namespacedKey);
    return _memoryPreferences[namespacedKey] as bool?;
  }

  Future<void> writeString(String key, String value) async {
    final namespacedKey = scopedKey(key);
    final prefs = await _prefsOrNull();
    if (prefs != null) {
      await prefs.setString(namespacedKey, value);
      return;
    }
    _memoryPreferences[namespacedKey] = value;
  }

  Future<void> writeBool(String key, bool value) async {
    final namespacedKey = scopedKey(key);
    final prefs = await _prefsOrNull();
    if (prefs != null) {
      await prefs.setBool(namespacedKey, value);
      return;
    }
    _memoryPreferences[namespacedKey] = value;
  }

  Future<void> remove(String key) async {
    final namespacedKey = scopedKey(key);
    final prefs = await _prefsOrNull();
    if (prefs != null) {
      await prefs.remove(namespacedKey);
      return;
    }
    _memoryPreferences.remove(namespacedKey);
  }

  Future<SharedPreferences?> _prefsOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }
}

class AppSettingsState {
  final Locale locale;
  final AppThemePreset themePreset;
  final bool animationsEnabled;
  final bool weatherEffectsEnabled;

  const AppSettingsState({
    required this.locale,
    required this.themePreset,
    required this.animationsEnabled,
    required this.weatherEffectsEnabled,
  });

  const AppSettingsState.initial()
    : this(
        locale: const Locale('ar'),
        themePreset: AppThemePreset.midnightBlue,
        animationsEnabled: true,
        weatherEffectsEnabled: true,
      );

  AppSettingsState copyWith({
    Locale? locale,
    AppThemePreset? themePreset,
    bool? animationsEnabled,
    bool? weatherEffectsEnabled,
  }) {
    return AppSettingsState(
      locale: locale ?? this.locale,
      themePreset: themePreset ?? this.themePreset,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      weatherEffectsEnabled:
          weatherEffectsEnabled ?? this.weatherEffectsEnabled,
    );
  }
}

class AppSettingsController extends StateNotifier<AppSettingsState> {
  static const _localeKey = 'settings.locale';
  static const _themePresetKey = 'settings.theme_preset';
  static const _animationsKey = 'settings.animations_enabled';
  static const _weatherEffectsKey = 'settings.weather_effects_enabled';

  final AppScopedPreferencesStore _store;

  AppSettingsController(this._store) : super(const AppSettingsState.initial()) {
    Future.microtask(_restore);
  }

  Future<void> _restore() async {
    final localeCode = await _store.readString(_localeKey);
    final themePreset = await _store.readString(_themePresetKey);
    final animationsEnabled = await _store.readBool(_animationsKey);
    final weatherEffectsEnabled = await _store.readBool(_weatherEffectsKey);

    state = state.copyWith(
      locale: localeCode == null || localeCode.isEmpty
          ? state.locale
          : Locale(localeCode),
      themePreset: AppThemePreset.fromStorageValue(themePreset),
      animationsEnabled: animationsEnabled ?? state.animationsEnabled,
      weatherEffectsEnabled:
          weatherEffectsEnabled ?? state.weatherEffectsEnabled,
    );
  }

  Future<void> setLocale(Locale locale) async {
    state = state.copyWith(locale: locale);
    await _store.writeString(_localeKey, locale.languageCode);
  }

  Future<void> setThemePreset(AppThemePreset preset) async {
    state = state.copyWith(themePreset: AppThemePreset.midnightBlue);
    await _store.writeString(
      _themePresetKey,
      AppThemePreset.midnightBlue.storageValue,
    );
  }

  Future<void> setAnimationsEnabled(bool enabled) async {
    state = state.copyWith(animationsEnabled: enabled);
    await _store.writeBool(_animationsKey, enabled);
  }

  Future<void> setWeatherEffectsEnabled(bool enabled) async {
    state = state.copyWith(weatherEffectsEnabled: enabled);
    await _store.writeBool(_weatherEffectsKey, enabled);
  }
}

final appSettingsStorageScopeProvider = Provider<String>((_) => 'global');

final appScopedPreferencesStoreProvider = Provider<AppScopedPreferencesStore>((
  ref,
) {
  return AppScopedPreferencesStore(
    scope: ref.watch(appSettingsStorageScopeProvider),
  );
});

final appScopedSecureStoreProvider = Provider<AppScopedSecureStore>((ref) {
  return AppScopedSecureStore(ref.watch(appScopedPreferencesStoreProvider));
});

final appSettingsControllerProvider =
    StateNotifierProvider<AppSettingsController, AppSettingsState>((ref) {
      return AppSettingsController(
        ref.watch(appScopedPreferencesStoreProvider),
      );
    });
