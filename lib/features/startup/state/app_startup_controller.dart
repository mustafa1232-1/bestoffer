import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/secure_storage.dart';
import '../../auth/state/auth_controller.dart';

enum AppStartupPhase {
  idle,
  checkingServer,
  serverCheckFailed,
  onboarding,
  ready,
}

class AppStartupState {
  final AppStartupPhase phase;
  final bool initialized;
  final String? error;
  final int attempts;

  const AppStartupState({
    required this.phase,
    required this.initialized,
    required this.error,
    required this.attempts,
  });

  const AppStartupState.initial()
    : phase = AppStartupPhase.idle,
      initialized = false,
      error = null,
      attempts = 0;

  bool get isReady => phase == AppStartupPhase.ready;

  AppStartupState copyWith({
    AppStartupPhase? phase,
    bool? initialized,
    String? error,
    bool clearError = false,
    int? attempts,
  }) {
    return AppStartupState(
      phase: phase ?? this.phase,
      initialized: initialized ?? this.initialized,
      error: clearError ? null : (error ?? this.error),
      attempts: attempts ?? this.attempts,
    );
  }
}

final appStartupControllerProvider =
    StateNotifierProvider<AppStartupController, AppStartupState>(
      (ref) => AppStartupController(
        store: ref.read(secureStoreProvider),
        dio: ref.read(dioClientProvider).dio,
        initialFirstLaunchDone: ref.read(appStartupInitialDoneProvider),
      ),
    );

final appStartupInitialDoneProvider = Provider<bool?>((ref) => null);

class AppStartupController extends StateNotifier<AppStartupState> {
  static const firstLaunchDoneStorageKey = 'app_first_launch_done_v2';
  static const legacyFirstLaunchDoneStorageKeys = <String>[
    'app_first_launch_done',
    'firstLaunchDone',
    'hasSeenOnboarding',
    'onboarding_done',
    'bestoffer_first_launch_done',
    'bestoffer_has_seen_onboarding',
    'shakaky_first_launch_done',
    'shakaky_has_seen_onboarding',
  ];

  final SecureStore store;
  final Dio dio;

  AppStartupController({
    required this.store,
    required this.dio,
    required bool? initialFirstLaunchDone,
  }) : super(
         initialFirstLaunchDone == true
             ? const AppStartupState(
                 phase: AppStartupPhase.ready,
                 initialized: true,
                 error: null,
                 attempts: 0,
               )
             : const AppStartupState.initial(),
       );

  Future<void> bootstrap() async {
    if (state.initialized) return;
    state = state.copyWith(initialized: true);

    final done = await _readFirstLaunchDone();
    if (done) {
      state = state.copyWith(phase: AppStartupPhase.ready, clearError: true);
      return;
    }

    await checkServerReadiness();
  }

  Future<void> checkServerReadiness() async {
    state = state.copyWith(
      phase: AppStartupPhase.checkingServer,
      clearError: true,
      attempts: state.attempts + 1,
    );

    try {
      final response = await dio.get<dynamic>(
        '/health',
        options: Options(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      if (response.statusCode == null || response.statusCode! >= 500) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        );
      }

      state = state.copyWith(phase: AppStartupPhase.ready, clearError: true);
    } on DioException catch (error) {
      state = state.copyWith(
        phase: AppStartupPhase.serverCheckFailed,
        error: _readServerError(error),
      );
    } catch (_) {
      state = state.copyWith(
        phase: AppStartupPhase.serverCheckFailed,
        error: 'Unable to connect to server.',
      );
    }
  }

  Future<void> completeFirstLaunch() async {
    await _writeFirstLaunchDone(true);
    state = state.copyWith(phase: AppStartupPhase.ready, clearError: true);
  }

  Future<bool> _readFirstLaunchDone() async {
    final prefs = await _prefsOrNull();
    if (prefs != null) {
      final scopedKey = firstLaunchDoneStorageKey;
      final value = prefs.getBool(scopedKey);
      if (value != null) return value;
      for (final legacyKey in legacyFirstLaunchDoneStorageKeys) {
        final legacyValue = prefs.getBool(legacyKey);
        if (legacyValue != null) {
          await prefs.setBool(scopedKey, legacyValue);
          return legacyValue;
        }
      }
    }

    final secureValue = await store.readBool(firstLaunchDoneStorageKey);
    if (secureValue != null) {
      await _writeFirstLaunchDone(secureValue);
      return secureValue;
    }
    return false;
  }

  Future<void> _writeFirstLaunchDone(bool value) async {
    final prefs = await _prefsOrNull();
    if (prefs != null) {
      await prefs.setBool(firstLaunchDoneStorageKey, value);
      for (final legacyKey in legacyFirstLaunchDoneStorageKeys) {
        await prefs.setBool(legacyKey, value);
      }
    }
    await store.writeBool(firstLaunchDoneStorageKey, value);
  }

  Future<SharedPreferences?> _prefsOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  String _readServerError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return 'Connection timeout while contacting server.';
    }
    return 'Unable to reach server right now.';
  }
}
