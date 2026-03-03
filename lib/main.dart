import 'dart:async';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_navigation.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/settings/app_settings_controller.dart';
import 'core/theme/app_backdrop.dart';
import 'core/theme/app_responsive_shell.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/ui/admin_dashboard_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/customer/ui/customer_discovery_screen.dart';
import 'features/owner/ui/owner_dashboard_screen.dart';
import 'features/taxi/ui/taxi_captain_dashboard_screen.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      final stack = details.stack ?? StackTrace.current;
      Zone.current.handleUncaughtError(details.exception, stack);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _reportFatalError('platform', error, stack);
      return true;
    };

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    runApp(const ProviderScope(child: ShakakyApp()));
  }, (error, stack) => _reportFatalError('zone', error, stack));
}

void _reportFatalError(String source, Object error, StackTrace stack) {
  // Keep this lightweight: survives both debug and release.
  debugPrint('[fatal][$source] $error');
  debugPrintStack(stackTrace: stack, label: '[fatal][$source] stack');
}

class ShakakyApp extends ConsumerStatefulWidget {
  const ShakakyApp({super.key});

  @override
  ConsumerState<ShakakyApp> createState() => _ShakakyAppState();
}

class _ShakakyAppState extends ConsumerState<ShakakyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<NotificationTapPayload>? _notificationTapSub;
  StreamSubscription<NotificationTapPayload>? _pushTapSub;
  NotificationTapPayload? _pendingTapPayload;
  int? _pushSyncedUserId;
  bool _pushSyncInFlight = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      final localNotifications = ref.read(localNotificationsProvider);
      await localNotifications.initialize();
      if (!mounted) return;
      _notificationTapSub = localNotifications.tapStream.listen(
        _handleNotificationTap,
      );
      final push = ref.read(pushNotificationsProvider);
      await push.initialize();
      if (!mounted) return;
      _pushTapSub = push.tapStream.listen(_handleNotificationTap);
      await ref.read(authControllerProvider.notifier).bootstrap();
    });
  }

  @override
  void dispose() {
    _notificationTapSub?.cancel();
    _pushTapSub?.cancel();
    super.dispose();
  }

  void _handleNotificationTap(NotificationTapPayload payload) {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed) {
      _pendingTapPayload = payload;
      return;
    }
    _openFromNotificationPayload(payload);
  }

  void _openFromNotificationPayload(NotificationTapPayload payload) {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;

    final auth = ref.read(authControllerProvider);
    NotificationNavigation.open(navigator: nav, auth: auth, payload: payload);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(appSettingsControllerProvider);
    final pendingPayload = _pendingTapPayload;

    if (auth.isAuthed && auth.user != null) {
      final userId = auth.user!.id;
      if (_pushSyncedUserId != userId && !_pushSyncInFlight) {
        _pushSyncInFlight = true;
        Future.microtask(() async {
          try {
            await ref.read(pushNotificationsProvider).syncToken();
            _pushSyncedUserId = userId;
          } catch (_) {
            // Keep _pushSyncedUserId unchanged to allow retry on next rebuild.
          } finally {
            _pushSyncInFlight = false;
          }
        });
      }
    } else if (_pushSyncedUserId != null) {
      _pushSyncedUserId = null;
      Future.microtask(() async {
        await ref.read(pushNotificationsProvider).unregisterCurrentToken();
      });
    }

    if (auth.isAuthed && pendingPayload != null) {
      _pendingTapPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openFromNotificationPayload(pendingPayload);
      });
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      locale: settings.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
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
      home: auth.isAuthed
          ? (auth.isBackoffice
                ? const AdminDashboardScreen()
                : auth.isOwner
                ? const OwnerDashboardScreen()
                : auth.isDelivery
                ? const TaxiCaptainDashboardScreen()
                : const CustomerDiscoveryScreen())
          : const LoginScreen(),
    );
  }
}
