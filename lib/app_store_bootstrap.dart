import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'core/diagnostics/build_identity_guard.dart';
import 'core/errors/app_runtime_error_presentation.dart';
import 'core/i18n/app_localizations_context.dart';
import 'core/platform/edge_to_edge_system_ui.dart';
import 'core/platform/app_flavor.dart';
import 'core/media/media_cache_service.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_navigation.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/settings/app_settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/maslaki_brand_mark.dart';
import 'core/widgets/maslaki_wordmark.dart';
import 'features/auth/presentation/role_login_screen.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/owner/ui/owner_dashboard_screen.dart';
import 'l10n/app_localizations.dart';

/// Dedicated bootstrap for the store app surface in the root app.
///
/// Uses the full owner workspace (`OwnerDashboardScreen`) instead of the
/// lightweight runtime shell.
void runStoreAppBootstrap() {
  AppFlavorContext.setCurrent(AppFlavor.store);
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(configureEdgeToEdgeSystemUi());
  installAppRuntimeErrorPresentation();
  unawaited(_runStoreAppBootstrap());
}

Future<void> _runStoreAppBootstrap() async {
  if (!await BuildIdentityGuard.validateOrShow(BuildIdentitySpec.store)) {
    return;
  }
  runApp(
    ProviderScope(
      overrides: [
        appFlavorProvider.overrideWithValue(AppFlavor.store),
        appSettingsStorageScopeProvider.overrideWithValue(
          AppFlavor.store.storageScope,
        ),
      ],
      child: const MaslakiStoreApp(),
    ),
  );
}

class MaslakiStoreApp extends ConsumerStatefulWidget {
  const MaslakiStoreApp({super.key});

  @override
  ConsumerState<MaslakiStoreApp> createState() => _MaslakiStoreAppState();
}

class _MaslakiStoreAppState extends ConsumerState<MaslakiStoreApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ProviderSubscription<AuthState>? _authStateSub;
  StreamSubscription<NotificationTapPayload>? _notificationTapSub;
  StreamSubscription<NotificationTapPayload>? _pushTapSub;
  NotificationTapPayload? _pendingTapPayload;

  bool _bootstrapped = false;
  bool _roleMismatchLogoutInFlight = false;
  bool _pushSyncInFlight = false;
  int? _pushSyncedUserId;

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
      await ref.read(mediaCacheServiceProvider).scheduleMaintenance();
      await ref.read(authControllerProvider.notifier).bootstrap();

      if (!mounted) return;
      final localNotifications = ref.read(localNotificationsProvider);
      await localNotifications.initialize();
      await localNotifications.requestPermissionsIfNeeded();
      _notificationTapSub = localNotifications.tapStream.listen(
        _handleNotificationTap,
      );

      if (!mounted) return;
      final auth = ref.read(authControllerProvider);
      if (_hasVerifiedSession(auth) && auth.isOwner) {
        await _ensurePushReadyAndSync(auth);
      }
      if (!mounted) return;
      setState(() {
        _bootstrapped = true;
      });
      _consumePendingTapIfAny();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed || !auth.isOwner || auth.user == null) return;
    unawaited(_ensurePushReadyAndSync(auth));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authStateSub?.close();
    _notificationTapSub?.cancel();
    _pushTapSub?.cancel();
    super.dispose();
  }

  void _handleAuthStateChanged(AuthState? previous, AuthState next) {
    final wasAuthed = previous == null ? false : _hasVerifiedSession(previous);
    final isAuthed = _hasVerifiedSession(next);
    final previousUserId = previous?.user?.id;
    final nextUserId = next.user?.id;

    if (wasAuthed && !isAuthed) {
      _pushSyncedUserId = null;
      unawaited(ref.read(pushNotificationsProvider).unregisterCurrentToken());
      return;
    }

    if (isAuthed &&
        next.isOwner &&
        nextUserId != null &&
        previousUserId != nextUserId) {
      unawaited(_ensurePushReadyAndSync(next));
    }

    if (isAuthed && next.isOwner) {
      _consumePendingTapIfAny();
    }
  }

  Future<void> _ensurePushReadyAndSync(AuthState auth) async {
    if (!mounted || !auth.isAuthed || !auth.isOwner || auth.user == null) {
      return;
    }

    final push = ref.read(pushNotificationsProvider);
    await push.initialize();
    await push.requestPermissionIfNeeded();
    if (!mounted) return;

    _pushTapSub ??= push.tapStream.listen(_handleNotificationTap);

    final userId = auth.user!.id;
    if (_pushSyncInFlight || _pushSyncedUserId == userId) return;
    _pushSyncInFlight = true;
    try {
      await push.syncToken(userId: userId);
      _pushSyncedUserId = userId;
    } finally {
      _pushSyncInFlight = false;
    }
  }

  bool _hasVerifiedSession(AuthState auth) =>
      auth.isAuthed && auth.user != null;

  void _consumePendingTapIfAny() {
    final payload = _pendingTapPayload;
    if (payload == null) return;
    _pendingTapPayload = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleNotificationTap(payload);
    });
  }

  void _handleNotificationTap(NotificationTapPayload payload) {
    final auth = ref.read(authControllerProvider);
    if (!_hasVerifiedSession(auth) || !auth.isOwner) {
      _pendingTapPayload = payload;
      return;
    }

    final nav = _navigatorKey.currentState;
    if (nav == null) {
      _pendingTapPayload = payload;
      return;
    }
    unawaited(
      NotificationNavigation.open(navigator: nav, auth: auth, payload: payload),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    Intl.defaultLocale = settings.locale.languageCode;

    if (_hasVerifiedSession(auth) &&
        !auth.isOwner &&
        !_roleMismatchLogoutInFlight) {
      _roleMismatchLogoutInFlight = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(authControllerProvider.notifier).logout();
        _roleMismatchLogoutInFlight = false;
      });
    } else if (!_hasVerifiedSession(auth) || auth.isOwner) {
      _roleMismatchLogoutInFlight = false;
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (ctx) => ctx.l10n.storePortalWindowTitle,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.themed(settings.maslakiTheme),
      darkTheme: AppTheme.themed(settings.maslakiTheme),
      themeMode: ThemeMode.dark,
      builder: (ctx, child) {
        if (child == null) return const SizedBox.shrink();
        return EdgeToEdgeSystemUi(
          child: AppBackdrop(
            // Keep operational apps lightweight by default.
            animationsEnabled: false,
            weatherEffectsEnabled: false,
            child: AppResponsiveShell(child: child),
          ),
        );
      },
      home: !_bootstrapped
          ? const _StoreSplashScreen()
          : _hasVerifiedSession(auth) && auth.isOwner
          ? const OwnerDashboardScreen()
          : const RoleLoginScreen(scope: RoleLoginScope.owner),
    );
  }
}

class _StoreSplashScreen extends StatelessWidget {
  const _StoreSplashScreen();

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: MaslakiCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MaslakiBrandMark(
                  size: 72,
                  shape: MaslakiBrandShape.circle,
                ),
                const SizedBox(height: 16),
                const MaslakiWordmark(
                  arabicSize: 30,
                  subtitle: 'بوابة المتجر',
                  crossAxisAlignment: CrossAxisAlignment.center,
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.storePortalWindowTitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    backgroundColor: tokens.surfaceSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
