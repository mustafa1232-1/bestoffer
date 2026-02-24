import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage.dart';

class AppSettingsState {
  final Locale locale;
  final bool animationsEnabled;
  final bool weatherEffectsEnabled;
  final bool loaded;

  const AppSettingsState({
    required this.locale,
    required this.animationsEnabled,
    required this.weatherEffectsEnabled,
    required this.loaded,
  });

  factory AppSettingsState.initial() => const AppSettingsState(
    locale: Locale('ar'),
    animationsEnabled: true,
    weatherEffectsEnabled: true,
    loaded: false,
  );

  AppSettingsState copyWith({
    Locale? locale,
    bool? animationsEnabled,
    bool? weatherEffectsEnabled,
    bool? loaded,
  }) {
    return AppSettingsState(
      locale: locale ?? this.locale,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      weatherEffectsEnabled:
          weatherEffectsEnabled ?? this.weatherEffectsEnabled,
      loaded: loaded ?? this.loaded,
    );
  }
}

final appSettingsControllerProvider =
    StateNotifierProvider<AppSettingsController, AppSettingsState>(
      (ref) => AppSettingsController(SecureStore())..bootstrap(),
    );

class AppSettingsController extends StateNotifier<AppSettingsState> {
  static const _keyLocale = 'app_locale';
  static const _keyAnimations = 'app_animations';
  static const _keyWeatherEffects = 'app_weather_effects';

  final SecureStore store;

  AppSettingsController(this.store) : super(AppSettingsState.initial());

  Future<void> bootstrap() async {
    final localeRaw = await store.readString(_keyLocale);
    final animationsRaw = await store.readBool(_keyAnimations);
    final weatherRaw = await store.readBool(_keyWeatherEffects);

    final locale = _normalizeLocale(localeRaw);
    state = state.copyWith(
      locale: locale,
      animationsEnabled: animationsRaw ?? true,
      weatherEffectsEnabled: weatherRaw ?? true,
      loaded: true,
    );
  }

  Future<void> setLocale(Locale locale) async {
    final normalized = _normalizeLocale(locale.languageCode);
    state = state.copyWith(locale: normalized);
    await store.writeString(_keyLocale, normalized.languageCode);
  }

  Future<void> setAnimationsEnabled(bool value) async {
    state = state.copyWith(animationsEnabled: value);
    await store.writeBool(_keyAnimations, value);
  }

  Future<void> setWeatherEffectsEnabled(bool value) async {
    state = state.copyWith(weatherEffectsEnabled: value);
    await store.writeBool(_keyWeatherEffects, value);
  }

  Future<void> resetVisualDefaults() async {
    state = state.copyWith(
      animationsEnabled: true,
      weatherEffectsEnabled: true,
    );
    await store.writeBool(_keyAnimations, true);
    await store.writeBool(_keyWeatherEffects, true);
  }

  Locale _normalizeLocale(String? code) {
    if (code == null) return const Locale('ar');
    final normalized = code.toLowerCase().trim();
    if (normalized == 'en') return const Locale('en');
    return const Locale('ar');
  }
}
