import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:maslaki/l10n/app_localizations.dart';

import 'core/calls/in_app_call_overlay_coordinator.dart';
import 'core/constants/api.dart';
import 'core/errors/app_runtime_error_presentation.dart';
import 'core/i18n/app_localizations_context.dart';
import 'core/navigation/app_route_observer.dart';
import 'core/platform/app_flavor.dart';
import 'core/platform/app_platform_capabilities.dart';
import 'core/media/media_cache_service.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_navigation.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/auth/session_expiry_notice.dart';
import 'core/realtime/maslaki_realtime_service.dart';
import 'core/sections/section_availability_controller.dart';
import 'core/settings/app_settings_controller.dart';
import 'core/storage/secure_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/admin/ui/admin_dashboard_screen.dart';
import 'features/customer/ui/maslaki_user_shell.dart';
import 'features/notifications/data/notifications_api.dart';
import 'features/social/ui/social_call_screen.dart';
import 'features/startup/state/app_startup_controller.dart';
import 'features/startup/ui/app_first_launch_screen.dart';

const _sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
const _appEnvName = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'development',
);
const _appVersionName = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'dev',
);
final _crashReportGate = _CrashReportGate();

Future<void> _runAppWithOptionalSentry(Widget app) async {
  if (_sentryDsn.trim().isEmpty) {
    runApp(app);
    return;
  }

  await SentryFlutter.init((options) {
    options.dsn = _sentryDsn.trim();
    options.environment = _appEnvName.trim();
    options.release = _appVersionName.trim();
    options.sendDefaultPii = false;
    options.enableAppLifecycleBreadcrumbs = true;
    options.enableUserInteractionBreadcrumbs = false;
    options.enableAutoNativeBreadcrumbs = true;
    options.beforeBreadcrumb = (breadcrumb, hint) {
      if (breadcrumb == null) {
        return null;
      }
      final rawData = breadcrumb.data ?? const <String, dynamic>{};
      final scrubbed = Map<String, dynamic>.from(rawData);
      for (final key in scrubbed.keys.toList()) {
        final lower = key.toLowerCase();
        if (lower.contains('token') ||
            lower.contains('secret') ||
            lower.contains('password') ||
            lower.contains('authorization') ||
            lower.contains('phone') ||
            lower.contains('address') ||
            lower.contains('payment')) {
          scrubbed[key] = '[redacted]';
        }
      }
      return Breadcrumb(
        message: breadcrumb.message,
        category: breadcrumb.category,
        type: breadcrumb.type,
        level: breadcrumb.level,
        data: scrubbed,
        timestamp: breadcrumb.timestamp,
      );
    };
  }, appRunner: () => runApp(app));
}

/// Purpose:
/// Ù†Ù‚Ø·Ø© Ø§Ù„Ø¥Ù‚Ù„Ø§Ø¹ Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠØ© Ù„ØªØ·Ø¨ÙŠÙ‚ Ø§Ù„Ø¹Ù…ÙŠÙ„/Ø§Ù„Ø£Ø¯Ù…Ù†/Ø§Ù„Ù…ÙˆØ¸ÙÙŠÙ† Ø¯Ø§Ø®Ù„ Flutter.
///
/// Used by:
/// - Android/iOS/Desktop entrypoint Ø§Ù„Ø¹Ø§Ø¯ÙŠ
///
/// Depends on:
/// - Riverpod bootstrap
/// - auth/startup/settings controllers
/// - local/push notifications
/// - in-app call overlays
///
/// Critical notes:
/// - ØªØ±ØªÙŠØ¨ Ø§Ù„ØªÙ‡ÙŠØ¦Ø© Ù‡Ù†Ø§ Ø­Ø³Ø§Ø³: Flutter bindings -> error hooks -> notifications
///   -> startup bootstrap -> auth bootstrap -> routing.
/// - Ø£ÙŠ ÙƒØ³Ø± Ù‡Ù†Ø§ ÙŠØ¸Ù‡Ø± Ø¹Ø§Ø¯Ø©Ù‹ ÙƒØ´Ø§Ø´Ø© Ø¨ÙŠØ¶Ø§Ø¡ Ø£Ùˆ ØªØ¹Ù„ÙŠÙ‚ Ù…Ø¨ÙƒØ± Ù‚Ø¨Ù„ Ø¸Ù‡ÙˆØ± Ø£ÙˆÙ„ Ø´Ø§Ø´Ø©.
///
/// Maintenance notes:
/// - Ø¥Ø°Ø§ Ù„Ù… ÙŠÙØªØ­ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ Ø£Ùˆ ØªØ¹Ø·Ù„ Ù…Ø¨Ø§Ø´Ø±Ø© Ø¨Ø¹Ø¯ Ø§Ù„Ø¥Ù‚Ù„Ø§Ø¹ØŒ Ø§Ø¨Ø¯Ø£ Ù…Ù† Ù‡Ø°Ø§ Ø§Ù„Ù…Ù„Ù Ø«Ù…
///   Ø§ÙØ­Øµ `AppStartupController`, `AuthController` ÙˆØªÙ‡ÙŠØ¦Ø© Ø§Ù„Ø¥Ø´Ø¹Ø§Ø±Ø§Øª.
void runUserAppBootstrap() {
  AppFlavorContext.setCurrent(AppFlavor.user);
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    installAppRuntimeErrorPresentation();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      final stack = details.stack ?? StackTrace.current;
      Zone.current.handleUncaughtError(details.exception, stack);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _reportFatalError('platform', error, stack);
      return true;
    };

    if (appSupportsPushMessaging) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
    await _runAppWithOptionalSentry(
      ProviderScope(
        overrides: [
          appFlavorProvider.overrideWithValue(AppFlavor.user),
          appStartupInitialDoneProvider.overrideWithValue(false),
          appSettingsStorageScopeProvider.overrideWithValue(
            AppFlavor.user.storageScope,
          ),
        ],
        child: const MaslakiApp(),
      ),
    );
  }, (error, stack) => _reportFatalError('zone', error, stack));
}

/// ÙŠØ±Ø³Ù„ Ø§Ù„Ø£Ø®Ø·Ø§Ø¡ Ø§Ù„Ù‚Ø§ØªÙ„Ø© Ø¥Ù„Ù‰ `debugPrint` Ø¨Ø´ÙƒÙ„ Ø®ÙÙŠÙ ÙŠÙ…ÙƒÙ† Ø§Ù„Ø§Ø¹ØªÙ…Ø§Ø¯ Ø¹Ù„ÙŠÙ‡ Ø­ØªÙ‰
/// Ø¹Ù†Ø¯Ù…Ø§ Ù„Ø§ ØªÙƒÙˆÙ† Ø¨Ø§Ù‚ÙŠ Ø§Ù„Ø®Ø¯Ù…Ø§Øª Ø£Ùˆ Ø§Ù„Ù€ crash reporters Ø¬Ø§Ù‡Ø²Ø© Ø¨Ø¹Ø¯.
void _reportFatalError(String source, Object error, StackTrace stack) {
  final fingerprint = _crashReportGate.buildFingerprint(
    source: source,
    error: error,
    stack: stack,
  );
  if (!_crashReportGate.tryAcquire(fingerprint)) {
    debugPrint('[fatal][$source] duplicate crash suppressed');
    return;
  }
  // Keep this lightweight: survives both debug and release.
  debugPrint('[fatal][$source] $error');
  debugPrintStack(stackTrace: stack, label: '[fatal][$source] stack');
  unawaited(
    _reportCrashEvent(
      source: source,
      error: error,
      stack: stack,
      fingerprint: fingerprint,
    ).whenComplete(() => _crashReportGate.release(fingerprint)),
  );
}

Future<void> _reportCrashEvent({
  required String source,
  required Object error,
  required StackTrace stack,
  required String fingerprint,
}) async {
  try {
    final store = SecureStore();
    final token = await store.readToken();
    if (token == null || token.trim().isEmpty) return;

    final dio = Dio(
      BaseOptions(
        baseUrl: Api.baseUrl,
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
          'X-Client-Platform': appPlatformName,
        },
      ),
    );

    await dio.post(
      '/api/system/crash-events',
      data: {
        'source': source,
        'message': '$error',
        'stackTrace': '$stack',
        'platform': appPlatformName,
        'appVersion': _appVersionName,
        'extra': {'fingerprint': fingerprint, 'environment': _appEnvName},
      },
    );
  } catch (_) {
    // Do not throw from fatal reporter.
  }
}

class _CrashReportGate {
  _CrashReportGate({
    Duration duplicateWindow = const Duration(minutes: 2),
    Duration rateWindow = const Duration(minutes: 2),
    int maxEventsPerWindow = 8,
  }) : _duplicateWindow = duplicateWindow,
       _rateWindow = rateWindow,
       _maxEventsPerWindow = maxEventsPerWindow;

  final Duration _duplicateWindow;
  final Duration _rateWindow;
  final int _maxEventsPerWindow;
  final Map<String, DateTime> _recentFingerprints = <String, DateTime>{};
  final Set<String> _inFlightFingerprints = <String>{};
  final ListQueue<DateTime> _recentReports = ListQueue<DateTime>();

  String buildFingerprint({
    required String source,
    required Object error,
    required StackTrace stack,
  }) {
    final stackLines = stack
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(6)
        .join('|');
    return [
      source.trim().toLowerCase(),
      error.runtimeType.toString(),
      '$error'.trim(),
      stackLines,
    ].join('::');
  }

  bool tryAcquire(String fingerprint) {
    final now = DateTime.now();
    _prune(now);
    if (_inFlightFingerprints.contains(fingerprint)) {
      return false;
    }
    final previous = _recentFingerprints[fingerprint];
    if (previous != null && now.difference(previous) < _duplicateWindow) {
      return false;
    }
    if (_recentReports.length >= _maxEventsPerWindow) {
      return false;
    }
    _inFlightFingerprints.add(fingerprint);
    _recentFingerprints[fingerprint] = now;
    _recentReports.addLast(now);
    return true;
  }

  void release(String fingerprint) {
    _inFlightFingerprints.remove(fingerprint);
  }

  void _prune(DateTime now) {
    while (_recentReports.isNotEmpty &&
        now.difference(_recentReports.first) >= _rateWindow) {
      _recentReports.removeFirst();
    }
    final expired = _recentFingerprints.entries
        .where((entry) => now.difference(entry.value) >= _duplicateWindow)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expired) {
      _recentFingerprints.remove(key);
    }
  }
}

/// Ø§Ù„ØºÙ„Ø§Ù Ø§Ù„Ø£Ø¹Ù„Ù‰ Ù„Ù„ØªØ·Ø¨ÙŠÙ‚. Ù…Ø³Ø¤ÙˆÙ„ÙŠØªÙ‡ Ø§Ù„Ø£Ø³Ø§Ø³ÙŠØ© ØªÙ…Ø±ÙŠØ± locale/theme/routing
/// ÙˆØ±Ø¨Ø· Ø·Ø¨Ù‚Ø§Øª Ø§Ù„Ø¥Ø´Ø¹Ø§Ø±Ø§Øª ÙˆØ§Ù„ØªÙ†Ù‚Ù„ Ø¨Ø­Ø§Ù„Ø© Ø§Ù„Ù…ØµØ§Ø¯Ù‚Ø© Ø§Ù„Ø­Ø§Ù„ÙŠØ©.
class MaslakiApp extends ConsumerStatefulWidget {
  const MaslakiApp({super.key});

  @override
  ConsumerState<MaslakiApp> createState() => _MaslakiAppState();
}

class _MaslakiAppState extends ConsumerState<MaslakiApp>
    with WidgetsBindingObserver {
  static const Duration _authBootstrapTimeout = Duration(seconds: 20);
  static const Duration _startupStepTimeout = Duration(seconds: 12);
  static const Duration _bestEffortStepTimeout = Duration(seconds: 8);

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final SentryNavigatorObserver _sentryObserver = SentryNavigatorObserver();
  final _OpsBreadcrumbNavigatorObserver _opsBreadcrumbObserver =
      _OpsBreadcrumbNavigatorObserver();
  ProviderSubscription<AuthState>? _authStateSub;
  StreamSubscription<NotificationTapPayload>? _notificationTapSub;
  StreamSubscription<NotificationTapPayload>? _pushTapSub;
  StreamSubscription<NotificationLiveEvent>? _socialCallSub;
  Timer? _socialCallReconnectTimer;
  NotificationTapPayload? _pendingTapPayload;
  _PendingIncomingSocialCall? _pendingIncomingSocialCall;
  int? _pushSyncedUserId;
  int? _socialCallLastEventId;
  bool _pushSyncInFlight = false;
  bool _roleMismatchLogoutInFlight = false;
  int _socialCallReconnectAttempt = 0;

  /// ÙŠØ±Ø§Ù‚Ø¨ ØªØºÙŠÙ‘Ø± Ø¬Ù„Ø³Ø© Ø§Ù„Ù…ØµØ§Ø¯Ù‚Ø© ÙˆÙŠØ­ÙˆÙ‘Ù„ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ Ø¨ÙŠÙ† Ø´Ø§Ø´Ø© Ø§Ù„Ø¯Ø®ÙˆÙ„ ÙˆØ§Ù„ÙˆØ¬Ù‡Ø©
  /// Ø§Ù„Ù…Ù†Ø§Ø³Ø¨Ø© Ù„Ù„Ø¯ÙˆØ±ØŒ ÙƒÙ…Ø§ ÙŠØ±Ø¨Ø· listeners Ø§Ù„Ø®Ø§ØµØ© Ø¨Ø§Ù„Ù†Ù‚Ø± Ø¹Ù„Ù‰ Ø§Ù„Ø¥Ø´Ø¹Ø§Ø±Ø§Øª.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authStateSub = ref.listenManual<AuthState>(authControllerProvider, (
      previous,
      next,
    ) {
      _handleAuthStateChanged(previous, next);
    });
    Future.microtask(() async {
      if (!mounted) return;
      final authBootstrap = _guardedStartupStep(
        'auth_bootstrap',
        ref.read(authControllerProvider.notifier).bootstrap(),
        timeout: _authBootstrapTimeout,
      );
      await _guardedStartupStep(
        'media_cache_maintenance',
        ref.read(mediaCacheServiceProvider).scheduleMaintenance(),
        timeout: _bestEffortStepTimeout,
      );
      if (!mounted) return;
      await _guardedStartupStep(
        'app_startup_bootstrap',
        ref.read(appStartupControllerProvider.notifier).bootstrap(),
        timeout: _startupStepTimeout,
      );
      if (!mounted) return;
      await _guardedStartupStep(
        'section_availability_bootstrap',
        ref.read(sectionAvailabilityControllerProvider.notifier).bootstrap(),
        timeout: _bestEffortStepTimeout,
      );
      if (!mounted) return;
      final localNotifications = ref.read(localNotificationsProvider);
      await _guardedStartupStep(
        'local_notifications_initialize',
        localNotifications.initialize(),
        timeout: _bestEffortStepTimeout,
      );
      if (!mounted) return;
      _notificationTapSub = localNotifications.tapStream.listen(
        _handleNotificationTap,
      );
      await authBootstrap;
      if (!mounted) return;
      final auth = ref.read(authControllerProvider);
      if (_hasVerifiedSession(auth)) {
        await _guardedStartupStep(
          'realtime_bind',
          ref.read(maslakiRealtimeServiceProvider).bindAuthenticatedSession(),
          timeout: _bestEffortStepTimeout,
        );
        if (!mounted) return;
        await _ensurePushReadyAndSync(auth);
      }
    });
  }

  Future<void> _guardedStartupStep(
    String label,
    Future<void> future, {
    required Duration timeout,
  }) async {
    try {
      await future.timeout(timeout);
    } catch (error, stack) {
      debugPrint('[startup][$label] $error');
      debugPrintStack(stackTrace: stack, label: '[startup][$label] stack');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authStateSub?.close();
    _notificationTapSub?.cancel();
    _pushTapSub?.cancel();
    _socialCallSub?.cancel();
    _socialCallReconnectTimer?.cancel();
    super.dispose();
  }

  /// ÙŠØ¹ÙŠØ¯ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… Ø¥Ù„Ù‰ Ø´Ø§Ø´Ø© Ø§Ù„Ø¯Ø®ÙˆÙ„ Ø¨Ø¹Ø¯ logout Ø£Ùˆ Ø§Ù†ØªÙ‡Ø§Ø¡ Ø§Ù„Ø¬Ù„Ø³Ø©.
  ///
  /// Maintenance notes:
  /// - Ø¥Ø°Ø§ Ø¨Ù‚ÙŠØª Ø´Ø§Ø´Ø© Ù‚Ø¯ÙŠÙ…Ø© ÙÙŠ stack Ø¨Ø¹Ø¯ logout Ø§ÙØ­Øµ Ù‡Ø°Ø§ Ø§Ù„Ù…Ø³Ø§Ø± Ù…Ø¹
  ///   listeners Ø§Ù„Ø®Ø§ØµØ© Ø¨Ù€ `AuthController`.
  void _redirectToLogin() {
    final nav = _navigatorKey.currentState;
    if (nav == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _redirectToLogin();
      });
      return;
    }
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  /// ÙŠÙˆØ¬Ù‡ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… Ø¥Ù„Ù‰ home Ø§Ù„Ù…Ù†Ø§Ø³Ø¨Ø© Ù„Ø¯ÙˆØ±Ù‡ Ø¨Ø¹Ø¯ Ù†Ø¬Ø§Ø­ bootstrap Ø£Ùˆ login.
  void _redirectToHome(AuthState auth) {
    final nav = _navigatorKey.currentState;
    if (nav == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _redirectToHome(auth);
      });
      return;
    }
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => _homeForAuth(auth)),
      (route) => false,
    );
  }

  /// ÙŠØ®ØªØ§Ø± Ø´Ø§Ø´Ø© Ø§Ù„Ø¨Ø¯Ø§ÙŠØ© Ø§Ù„ØµØ­ÙŠØ­Ø© Ø­Ø³Ø¨ claims Ø§Ù„Ø¬Ù„Ø³Ø© Ø§Ù„Ø­Ø§Ù„ÙŠØ©.
  ///
  /// Critical notes:
  /// - Ù‡Ø°Ø§ Ù„ÙŠØ³ route guard ÙƒØ§Ù…Ù„Ø§Ù‹ØŒ Ù„ÙƒÙ†Ù‡ Ø£ÙˆÙ„ Ù†Ù‚Ø·Ø© ØªÙ‚Ø³ÙŠÙ… UX Ø­Ø³Ø¨ Ø§Ù„Ø¯ÙˆØ±.
  Widget _homeForAuth(AuthState auth) {
    if (auth.isSuperAdmin) {
      return const AdminDashboardScreen();
    }
    return const MaslakiUserShell();
  }

  bool _isUserAppRole(AuthState auth) {
    return auth.isCustomer || auth.isSuperAdmin;
  }

  bool _hasVerifiedSession(AuthState auth) =>
      auth.isAuthed && auth.user != null;

  void _addOpsBreadcrumb({
    required String message,
    required String category,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    if (_sentryDsn.trim().isEmpty) return;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        type: 'navigation',
        level: SentryLevel.info,
        data: data,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(ref.read(maslakiRealtimeServiceProvider).setAppActive(false));
      return;
    }
    unawaited(ref.read(maslakiRealtimeServiceProvider).setAppActive(true));
    unawaited(
      ref
          .read(sectionAvailabilityControllerProvider.notifier)
          .refresh(silent: true),
    );
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed || auth.user == null) return;
    unawaited(_ensurePushReadyAndSync(auth));
  }

  /// ÙŠØ¤Ø¬Ù„ ÙØªØ­ ÙˆØ¬Ù‡Ø© Ø§Ù„Ø¥Ø´Ø¹Ø§Ø± Ø­ØªÙ‰ ØªØªÙˆÙØ± Ø¬Ù„Ø³Ø© ÙˆÙ…Ù„Ø§Ø­Ù‚ navigator.
  void _handleNotificationTap(NotificationTapPayload payload) {
    _addOpsBreadcrumb(
      message: 'notification_received',
      category: 'notifications',
      data: {'target': payload.target ?? '', 'type': payload.type ?? ''},
    );
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed) {
      _pendingTapPayload = payload;
      return;
    }
    final quickAction = (payload.quickActionId ?? '').trim().toLowerCase();
    if (quickAction.isEmpty || quickAction == 'open') {
      unawaited(_trackNotificationAction(payload, requestState: 'opened'));
    }
    if (quickAction.isNotEmpty && quickAction != 'open') {
      unawaited(_trackNotificationAction(payload, requestState: 'ignored'));
    }
    _openFromNotificationPayload(payload);
  }

  void _handleAuthStateChanged(AuthState? previous, AuthState next) {
    final wasAuthed = previous == null ? false : _hasVerifiedSession(previous);
    final isAuthed = _hasVerifiedSession(next);
    final previousUserId = previous?.user?.id;
    final nextUserId = next.user?.id;
    final previousBindingKey = previous == null
        ? null
        : _buildCallLiveBindingKey(previous);
    final nextBindingKey = _buildCallLiveBindingKey(next);

    if (wasAuthed && !isAuthed) {
      _pushSyncedUserId = null;
      unawaited(ref.read(pushNotificationsProvider).unregisterCurrentToken());
      unawaited(ref.read(maslakiRealtimeServiceProvider).clearSession());
      unawaited(_syncCallLiveStreams(next));
      if (next.guestMode) {
        unawaited(SessionExpiryNoticeGate.instance.show(context));
      } else {
        _redirectToLogin();
      }
      return;
    }

    if (!wasAuthed && isAuthed) {
      _addOpsBreadcrumb(
        message: 'user_login_success',
        category: 'auth',
        data: {'role': next.user?.role ?? '', 'userId': next.user?.id ?? 0},
      );
      final startup = ref.read(appStartupControllerProvider);
      if (startup.isReady) {
        _redirectToHome(next);
      }
    }

    if (isAuthed) {
      unawaited(
        ref.read(maslakiRealtimeServiceProvider).bindAuthenticatedSession(),
      );
    }

    if (isAuthed && nextUserId != null && previousUserId != nextUserId) {
      unawaited(_ensurePushReadyAndSync(next));
    }

    if (previousBindingKey != nextBindingKey) {
      unawaited(_syncCallLiveStreams(next));
    }
  }

  Future<void> _ensurePushReadyAndSync(AuthState auth) async {
    if (!mounted || !auth.isAuthed || auth.user == null) return;
    final push = ref.read(pushNotificationsProvider);
    await push.initialize();
    if (!mounted) return;
    _pushTapSub ??= push.tapStream.listen(_handleNotificationTap);

    final userId = auth.user!.id;
    if (_pushSyncInFlight || _pushSyncedUserId == userId) return;
    _pushSyncInFlight = true;
    try {
      await push.syncToken(userId: userId);
      _pushSyncedUserId = userId;
    } catch (_) {
      // Keep sync best-effort; lifecycle resume will retry if needed.
    } finally {
      _pushSyncInFlight = false;
    }
  }

  Future<void> _trackNotificationAction(
    NotificationTapPayload payload, {
    required String requestState,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final api = NotificationsApi(ref.read(dioClientProvider).dio);
      await api.trackAction(
        actionId: (payload.quickActionId ?? 'open').trim().isEmpty
            ? 'open'
            : payload.quickActionId!.trim().toLowerCase(),
        notificationId: payload.notificationId,
        target: payload.target,
        entityType: payload.targetEntity,
        entityId: payload.entityId,
        requestState: requestState,
        payload: {
          if (payload.orderId != null) 'orderId': payload.orderId,
          if (payload.rideId != null) 'rideId': payload.rideId,
          if (payload.type != null) 'type': payload.type,
          if (extra.isNotEmpty) ...extra,
        },
      );
    } catch (_) {
      // Best-effort operational telemetry.
    }
  }

  /// ÙŠÙØªØ­ Ø§Ù„Ù…Ø³Ø§Ø± Ø§Ù„Ù†Ø§ØªØ¬ Ù…Ù† payload Ø§Ù„Ø¥Ø´Ø¹Ø§Ø± Ø¯Ø§Ø®Ù„ navigator Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠ.
  ///
  /// Maintenance notes:
  /// - Ø¹Ù†Ø¯ Ø§Ù„Ø´ÙƒÙˆÙ‰ Ù…Ù† "Ø§Ù„Ø¶ØºØ· Ø¹Ù„Ù‰ Ø§Ù„Ø¥Ø´Ø¹Ø§Ø± Ù„Ø§ ÙŠÙØªØ­ Ø´ÙŠØ¦Ø§Ù‹" Ø§ÙØ­Øµ:
  ///   payload -> `NotificationNavigation` -> navigator state -> auth state.
  void _openFromNotificationPayload(NotificationTapPayload payload) {
    final nav = _navigatorKey.currentState;
    if (nav == null) {
      _pendingTapPayload = payload;
      return;
    }

    unawaited(() async {
      await ref
          .read(sectionAvailabilityControllerProvider.notifier)
          .refresh(silent: true);
      if (!mounted) return;
      final auth = ref.read(authControllerProvider);
      await NotificationNavigation.open(
        navigator: nav,
        auth: auth,
        payload: payload,
      );
    }());
  }

  Future<void> _syncCallLiveStreams(AuthState auth) async {
    await _socialCallSub?.cancel();
    _socialCallSub = null;
    _socialCallReconnectTimer?.cancel();
    _socialCallReconnectAttempt = 0;
    _socialCallLastEventId = null;

    if (!auth.isAuthed || auth.user == null) return;

    if (_shouldListenSocialCalls(auth)) {
      _connectSocialCallStream();
    }
  }

  String _buildCallLiveBindingKey(AuthState auth) {
    if (!auth.isAuthed || auth.user == null) return 'guest';
    return [
      auth.user!.id,
      auth.isBackoffice,
      auth.isOwner,
      auth.isDelivery,
      auth.isAccountant,
      auth.isHr,
      auth.isTaxiCaptain,
    ].join(':');
  }

  bool _shouldListenSocialCalls(AuthState auth) =>
      appInAppCallsEnabled &&
      auth.isAuthed &&
      !auth.isBackoffice &&
      !auth.isOwner &&
      !auth.isDelivery &&
      !auth.isTaxiCaptain &&
      !auth.isHr &&
      !auth.isAccountant;

  void _connectSocialCallStream() {
    _socialCallSub?.cancel();
    _socialCallReconnectTimer?.cancel();
    final api = NotificationsApi(
      ref.read(dioClientProvider).dio,
      realtime: ref.read(maslakiRealtimeServiceProvider),
    );
    _socialCallSub = api
        .streamEvents(lastEventId: _socialCallLastEventId, channel: 'social')
        .listen(
          _onSocialCallLiveEvent,
          onError: (_) => _scheduleSocialCallReconnect(),
          onDone: _scheduleSocialCallReconnect,
          cancelOnError: true,
        );
  }

  void _scheduleSocialCallReconnect() {
    final auth = ref.read(authControllerProvider);
    if (!_shouldListenSocialCalls(auth)) return;
    if (_socialCallReconnectTimer?.isActive == true) return;
    _socialCallReconnectAttempt = (_socialCallReconnectAttempt + 1).clamp(1, 6);
    final delaySeconds = switch (_socialCallReconnectAttempt) {
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 12,
      5 => 20,
      _ => 30,
    };
    _socialCallReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted) return;
      _connectSocialCallStream();
    });
  }

  void _onSocialCallLiveEvent(NotificationLiveEvent event) {
    if (event.event == 'connected' || event.event == 'replayed') {
      _socialCallReconnectAttempt = 0;
      return;
    }
    if (event.event == 'resync_required') {
      _socialCallReconnectAttempt = 0;
      _socialCallLastEventId = _readPositiveInt(event.data['latestEventId']);
      return;
    }
    if (event.event != 'social_call_update') return;
    if (!_acceptLiveEventId(event.eventId)) return;

    final eventType = _readText(event.data['eventType']);
    if (eventType != 'incoming_call') return;

    final sessionMap = event.data['session'] is Map
        ? Map<String, dynamic>.from(event.data['session'] as Map)
        : const <String, dynamic>{};
    final callerMap = event.data['caller'] is Map
        ? Map<String, dynamic>.from(event.data['caller'] as Map)
        : const <String, dynamic>{};
    final threadId =
        _readPositiveInt(event.data['threadId'] ?? event.data['thread_id']) ??
        0;
    if (threadId <= 0) return;

    unawaited(
      _openIncomingSocialCall(
        threadId: threadId,
        sessionId: _readPositiveInt(
          sessionMap['id'] ??
              event.data['sessionId'] ??
              event.data['session_id'],
        ),
        remoteDisplayName:
            _readText(event.data['remoteDisplayName']) ??
            _readText(sessionMap['remoteDisplayName']) ??
            _readText(callerMap['fullName']),
      ),
    );
  }

  bool _acceptLiveEventId(int? eventId) {
    if (eventId == null || eventId <= 0) return true;
    final currentLast = _socialCallLastEventId;
    if (currentLast != null && eventId <= currentLast) return false;
    _socialCallLastEventId = eventId;
    return true;
  }

  Future<void> _openIncomingSocialCall({
    required int threadId,
    int? sessionId,
    String? remoteDisplayName,
  }) async {
    final nav = _navigatorKey.currentState;
    if (nav == null) {
      _pendingIncomingSocialCall = _PendingIncomingSocialCall(
        threadId: threadId,
        sessionId: sessionId,
        remoteDisplayName: remoteDisplayName,
      );
      return;
    }
    final key = InAppCallOverlayCoordinator.socialKey(
      threadId: threadId,
      sessionId: sessionId,
    );
    if (!InAppCallOverlayCoordinator.tryOpen(key)) return;
    try {
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => SocialCallScreen(
            threadId: threadId,
            isCaller: false,
            initialSessionId: sessionId,
            remoteDisplayName: remoteDisplayName,
          ),
        ),
      );
    } finally {
      InAppCallOverlayCoordinator.close(key);
    }
  }

  int? _readPositiveInt(dynamic value) {
    if (value == null) return null;
    final parsed = int.tryParse('$value');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String? _readText(dynamic value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(appSettingsControllerProvider);
    final startup = ref.watch(appStartupControllerProvider);
    final pendingPayload = _pendingTapPayload;

    if (_hasVerifiedSession(auth) && !_isUserAppRole(auth)) {
      if (!_roleMismatchLogoutInFlight) {
        _roleMismatchLogoutInFlight = true;
        Future.microtask(() async {
          await ref.read(authControllerProvider.notifier).logout();
          _roleMismatchLogoutInFlight = false;
        });
      }
    } else {
      _roleMismatchLogoutInFlight = false;
    }

    if (_hasVerifiedSession(auth) && pendingPayload != null) {
      _pendingTapPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openFromNotificationPayload(pendingPayload);
      });
    }

    if (appInAppCallsEnabled && _hasVerifiedSession(auth)) {
      final pendingSocialCall = _pendingIncomingSocialCall;
      if (pendingSocialCall != null) {
        _pendingIncomingSocialCall = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(
            _openIncomingSocialCall(
              threadId: pendingSocialCall.threadId,
              sessionId: pendingSocialCall.sessionId,
              remoteDisplayName: pendingSocialCall.remoteDisplayName,
            ),
          );
        });
      }
    }

    final appHome = switch (startup.phase) {
      AppStartupPhase.onboarding => const AppFirstLaunchScreen(),
      AppStartupPhase.ready =>
        auth.loading
            ? const AppFirstLaunchScreen()
            : (_hasVerifiedSession(auth)
                  ? _homeForAuth(auth)
                  : auth.isGuest || (auth.token?.trim().isNotEmpty ?? false)
                  ? const MaslakiUserShell()
                  : const LoginScreen()),
      AppStartupPhase.idle ||
      AppStartupPhase.checkingServer ||
      AppStartupPhase.serverCheckFailed => const AppFirstLaunchScreen(),
    };
    Intl.defaultLocale = settings.locale.languageCode;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.appName,
      navigatorKey: _navigatorKey,
      navigatorObservers: [
        _sentryObserver,
        _opsBreadcrumbObserver,
        appRouteObserver,
      ],
      locale: settings.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(preset: settings.themePreset),
      darkTheme: AppTheme.dark(preset: settings.themePreset),
      themeMode: ThemeMode.dark,
      themeAnimationDuration: const Duration(milliseconds: 450),
      themeAnimationCurve: Curves.easeOutCubic,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return AppBackdrop(
          animationsEnabled: settings.animationsEnabled,
          weatherEffectsEnabled: settings.weatherEffectsEnabled,
          child: AppResponsiveShell(child: child),
        );
      },
      home: appHome,
    );
  }
}

class _PendingIncomingSocialCall {
  final int threadId;
  final int? sessionId;
  final String? remoteDisplayName;

  const _PendingIncomingSocialCall({
    required this.threadId,
    required this.sessionId,
    required this.remoteDisplayName,
  });
}

class _OpsBreadcrumbNavigatorObserver extends NavigatorObserver {
  String _routeName(Route<dynamic>? route) {
    if (route == null) return 'unknown';
    final settingsName = route.settings.name;
    if (settingsName != null && settingsName.trim().isNotEmpty) {
      return settingsName.trim();
    }
    return route.runtimeType.toString();
  }

  void _addRouteBreadcrumb(String event, Route<dynamic>? route) {
    if (_sentryDsn.trim().isEmpty) return;
    final name = _routeName(route).toLowerCase();

    String category = 'navigation';
    if (name.contains('login')) category = 'login';
    if (name.contains('order')) category = 'order';
    if (name.contains('payment')) category = 'payment';
    if (name.contains('taxi') || name.contains('driver')) category = 'driver';
    if (name.contains('merchant') || name.contains('store')) {
      category = 'merchant';
    }

    Sentry.addBreadcrumb(
      Breadcrumb(
        message: event,
        category: category,
        type: 'navigation',
        level: SentryLevel.info,
        data: {'route': name},
      ),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _addRouteBreadcrumb('route_push', route);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _addRouteBreadcrumb('route_replace', newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
