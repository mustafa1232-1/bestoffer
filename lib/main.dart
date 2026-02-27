import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/local_notification_service.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/settings/app_settings_controller.dart';
import 'core/theme/app_backdrop.dart';
import 'core/theme/app_responsive_shell.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/ui/admin_dashboard_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/customer/ui/customer_discovery_screen.dart';
import 'features/notifications/ui/notifications_screen.dart';
import 'features/owner/ui/owner_dashboard_screen.dart';
import 'features/orders/ui/customer_orders_screen.dart';
import 'features/taxi/ui/taxi_captain_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const ProviderScope(child: BestOfferApp()));
}

class BestOfferApp extends ConsumerStatefulWidget {
  const BestOfferApp({super.key});

  @override
  ConsumerState<BestOfferApp> createState() => _BestOfferAppState();
}

class _BestOfferAppState extends ConsumerState<BestOfferApp> {
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
      final localNotifications = ref.read(localNotificationsProvider);
      await localNotifications.initialize();
      _notificationTapSub = localNotifications.tapStream.listen(
        _handleNotificationTap,
      );
      final push = ref.read(pushNotificationsProvider);
      await push.initialize();
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
    if (!auth.isBackoffice && !auth.isOwner && !auth.isDelivery) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => CustomerOrdersScreen(initialOrderId: payload.orderId),
        ),
      );
      return;
    }

    nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
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
