import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api.dart';
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
  final Duration serverAttemptTimeout;
  final List<Duration> serverRetryBackoff;
  Future<void>? _bootstrapInFlight;
  Future<void>? _serverCheckInFlight;

  AppStartupController({
    required this.store,
    required this.dio,
    required bool? initialFirstLaunchDone,
    this.serverAttemptTimeout = const Duration(seconds: 10),
    this.serverRetryBackoff = const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
    ],
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

  // First-launch storage lives in the Keychain / SharedPreferences. On a fresh
  // iOS install those first reads can stall; an unbounded await here used to
  // strand the app on the "preparing" screen forever (phase never left idle, so
  // the server check never ran and no retry was offered). Time-box the read and
  // always fall through to the server check so the gate can never hang.
  static const _firstLaunchReadBudget = Duration(seconds: 4);
  static const _maxServerAttempts = 3;

  Future<void> bootstrap() async {
    final existing = _bootstrapInFlight;
    if (existing != null) return existing;
    if (state.initialized && state.isReady) return;
    state = state.copyWith(initialized: true);
    final future = _bootstrap();
    _bootstrapInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_bootstrapInFlight, future)) {
        _bootstrapInFlight = null;
      }
    }
  }

  Future<void> _bootstrap() async {
    final startupWatch = Stopwatch()..start();
    _logStartup(
      'startup_begin',
      status: state.phase.name,
      duration: Duration.zero,
    );
    _logStartup(
      'config_resolved',
      status: 'ok',
      duration: Duration.zero,
      detail: 'baseUrl=${Api.baseUrl}',
    );

    var done = false;
    try {
      done = await _readFirstLaunchDone().timeout(
        _firstLaunchReadBudget,
        onTimeout: () => false,
      );
      _logStartup(
        'session_restore_result',
        status: done ? 'first_launch_done' : 'first_launch_pending',
        duration: startupWatch.elapsed,
      );
    } catch (_) {
      // Storage unreadable (e.g. Keychain error on a fresh install) — treat as a
      // first launch and continue rather than stranding the user.
      done = false;
      _logStartup(
        'session_restore_result',
        status: 'storage_error_ignored',
        duration: startupWatch.elapsed,
      );
    }

    if (done) {
      state = state.copyWith(phase: AppStartupPhase.ready, clearError: true);
      _logStartup(
        'startup_ready',
        status: state.phase.name,
        duration: startupWatch.elapsed,
      );
      return;
    }

    _logStartup(
      'session_restore_begin',
      status: 'server_gate_required',
      duration: startupWatch.elapsed,
    );
    await checkServerReadiness();
    if (state.phase == AppStartupPhase.ready) {
      _logStartup(
        'startup_ready',
        status: state.phase.name,
        duration: startupWatch.elapsed,
      );
    } else {
      _logStartup(
        'startup_error',
        status: state.phase.name,
        duration: startupWatch.elapsed,
        errorType: state.error,
      );
    }
  }

  Future<void> checkServerReadiness() async {
    final existing = _serverCheckInFlight;
    if (existing != null) return existing;
    final future = _checkServerReadiness();
    _serverCheckInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_serverCheckInFlight, future)) {
        _serverCheckInFlight = null;
      }
    }
  }

  Future<void> _checkServerReadiness() async {
    for (var attempt = 1; attempt <= _maxServerAttempts; attempt++) {
      await _checkServerReadinessAttempt(attempt);
      if (state.phase == AppStartupPhase.ready) return;

      final delayIndex = attempt - 1;
      if (attempt < _maxServerAttempts &&
          delayIndex < serverRetryBackoff.length) {
        await Future<void>.delayed(serverRetryBackoff[delayIndex]);
      }
    }
  }

  Future<void> _checkServerReadinessAttempt(int attempt) async {
    state = state.copyWith(
      phase: AppStartupPhase.checkingServer,
      clearError: true,
      attempts: state.attempts + 1,
    );

    final attemptWatch = Stopwatch()..start();
    _logStartup(
      'server_check_begin',
      status: 'attempt_$attempt',
      duration: Duration.zero,
    );

    try {
      final response = await dio
          .get<dynamic>(
            '/health',
            options: Options(
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              // /health is public and runs before login — skip the auth/token/
              // signing interceptor path so a slow Keychain read cannot stall the
              // readiness probe.
              extra: const {'skipAuth': true},
            ),
          )
          .timeout(serverAttemptTimeout);
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 500) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        );
      }

      _logStartup(
        'server_check_success',
        status: 'ok',
        statusCode: response.statusCode,
        duration: attemptWatch.elapsed,
      );
      state = state.copyWith(phase: AppStartupPhase.ready, clearError: true);
    } on DioException catch (error) {
      _logStartup(
        'server_check_failure',
        status: 'retryable',
        statusCode: error.response?.statusCode,
        errorType: error.type.name,
        duration: attemptWatch.elapsed,
      );
      state = state.copyWith(
        phase: AppStartupPhase.serverCheckFailed,
        error: _readServerError(error),
      );
    } on TimeoutException {
      _logStartup(
        'server_check_failure',
        status: 'timeout',
        errorType: 'TimeoutException',
        duration: attemptWatch.elapsed,
      );
      state = state.copyWith(
        phase: AppStartupPhase.serverCheckFailed,
        error: 'Connection timeout while contacting server.',
      );
    } catch (error) {
      _logStartup(
        'server_check_failure',
        status: 'unknown',
        errorType: error.runtimeType.toString(),
        duration: attemptWatch.elapsed,
      );
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

    bool? secureValue;
    try {
      secureValue = await store
          .readBool(firstLaunchDoneStorageKey)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {
      secureValue = null;
    }
    if (secureValue != null) {
      // Best-effort mirror back; never let a slow write block startup.
      unawaited(_writeFirstLaunchDone(secureValue));
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
      return await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('prefs'),
      );
    } catch (_) {
      return null;
    }
  }

  void _logStartup(
    String event, {
    required String status,
    required Duration duration,
    int? statusCode,
    String? errorType,
    String? detail,
  }) {
    final fields = <String>[
      'platform=${defaultTargetPlatform.name}',
      'status=$status',
      'durationMs=${duration.inMilliseconds}',
      if (statusCode != null) 'statusCode=$statusCode',
      if (errorType != null && errorType.trim().isNotEmpty)
        'errorType=${_sanitizeLogValue(errorType)}',
      if (detail != null && detail.trim().isNotEmpty)
        'detail=${_sanitizeLogValue(detail)}',
    ];
    debugPrint('[startup][$event] ${fields.join(' ')}');
  }

  String _sanitizeLogValue(String value) {
    final text = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (text.length <= 160) return text;
    return '${text.substring(0, 160)}...';
  }

  String _readServerError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return 'Connection timeout while contacting server.';
    }
    return 'Unable to reach server right now.';
  }
}
