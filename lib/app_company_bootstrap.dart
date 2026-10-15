import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'core/errors/app_runtime_error_presentation.dart';
import 'core/i18n/app_localizations_context.dart';
import 'core/i18n/locale_text.dart';
import 'core/platform/edge_to_edge_system_ui.dart';
import 'core/platform/app_flavor.dart';
import 'core/media/media_cache_service.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_navigation.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/realtime/maslaki_realtime_service.dart';
import 'core/settings/app_settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/desktop_dashboard_frame.dart';
import 'features/accountant/ui/accountant_dashboard_screen.dart';
import 'features/admin/ui/admin_dashboard_screen.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/company/company_portal_text.dart';
import 'features/company/data/company_api.dart';
import 'features/company/models/company_models.dart';
import 'features/company/state/company_session_controller.dart';
import 'features/company/ui/company_branches_screen.dart';
import 'features/company/ui/company_dashboard_screen.dart';
import 'features/company/ui/company_inventory_screen.dart';
import 'features/company/ui/company_login_screen.dart';
import 'features/company/ui/company_orders_screen.dart';
import 'features/company/ui/company_promotions_screen.dart';
import 'features/company/ui/company_reports_screen.dart';
import 'features/company/ui/company_settings_screen.dart';
import 'features/company/ui/company_users_screen.dart';
import 'features/hr/ui/hr_dashboard_screen.dart';
import 'features/notifications/state/notifications_controller.dart';
import 'features/notifications/ui/notifications_bell.dart';
import 'features/notifications/ui/notifications_screen.dart';
import 'l10n/app_localizations.dart';

/// نقطة الإقلاع الخاصة ببوابة الشركات.
///
/// تستخدم جلسة منفصلة (`CompanySessionController`) لأن البوابة تملك token
/// وسياق شركة نشطة مستقلين عن جلسة التطبيق العامة.
void runCompanyAppBootstrap() {
  AppFlavorContext.setCurrent(AppFlavor.company);
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(configureEdgeToEdgeSystemUi());
  installAppRuntimeErrorPresentation();
  unawaited(MediaCacheService.instance.scheduleMaintenance());
  runApp(
    ProviderScope(
      overrides: [
        appFlavorProvider.overrideWithValue(AppFlavor.company),
        appSettingsStorageScopeProvider.overrideWithValue(
          AppFlavor.company.storageScope,
        ),
      ],
      child: const CompanyPortalApp(),
    ),
  );
}

class CompanyPortalApp extends ConsumerStatefulWidget {
  const CompanyPortalApp({super.key});

  @override
  ConsumerState<CompanyPortalApp> createState() => _CompanyPortalAppState();
}

class _CompanyPortalAppState extends ConsumerState<CompanyPortalApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ProviderSubscription<AuthState>? _authStateSub;
  StreamSubscription<NotificationTapPayload>? _notificationTapSub;
  StreamSubscription<NotificationTapPayload>? _pushTapSub;
  NotificationTapPayload? _pendingTapPayload;
  bool _bootstrapped = false;
  bool _logoutInFlight = false;
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
      await ref.read(authControllerProvider.notifier).bootstrap();
      if (!mounted) return;
      final localNotifications = ref.read(localNotificationsProvider);
      await localNotifications.initialize();
      await localNotifications.requestPermissionsIfNeeded();
      _notificationTapSub = localNotifications.tapStream.listen(
        _handleNotificationTap,
      );
      if (!mounted) return;
      await _bootstrapCompanySessionIfNeeded(ref.read(authControllerProvider));
      if (!mounted) return;
      final auth = ref.read(authControllerProvider);
      if (_hasVerifiedSession(auth) && _isCompanySurfaceAuth(auth)) {
        unawaited(_ensurePushReadyAndSync(auth));
      }
      if (!mounted) return;
      setState(() {
        _bootstrapped = true;
      });
      _consumePendingTapIfAny();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authStateSub?.close();
    _notificationTapSub?.cancel();
    _pushTapSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(ref.read(maslakiRealtimeServiceProvider).setAppActive(false));
      return;
    }
    unawaited(ref.read(maslakiRealtimeServiceProvider).setAppActive(true));
    final auth = ref.read(authControllerProvider);
    if (!_hasVerifiedSession(auth) || !_isCompanySurfaceAuth(auth)) return;
    unawaited(_ensurePushReadyAndSync(auth));
  }

  bool _hasVerifiedSession(AuthState auth) =>
      auth.isAuthed && auth.user != null;

  bool _isCompanySurfaceAuth(AuthState auth) {
    return auth.isBackoffice ||
        auth.isStaff ||
        auth.isAccountant ||
        auth.isHr ||
        auth.isCompanyPortal;
  }

  void _handleAuthStateChanged(AuthState? previous, AuthState next) {
    final wasAuthed = previous == null ? false : _hasVerifiedSession(previous);
    final isAuthed = _hasVerifiedSession(next);
    final previousUserId = previous?.user?.id;
    final nextUserId = next.user?.id;

    if (wasAuthed && !isAuthed) {
      _pushSyncedUserId = null;
      unawaited(ref.read(pushNotificationsProvider).unregisterCurrentToken());
      unawaited(ref.read(maslakiRealtimeServiceProvider).clearSession());
      return;
    }

    if (isAuthed && _isCompanySurfaceAuth(next)) {
      unawaited(_bootstrapCompanySessionIfNeeded(next));
      unawaited(
        ref.read(maslakiRealtimeServiceProvider).bindAuthenticatedSession(),
      );
      if (nextUserId != null && previousUserId != nextUserId) {
        unawaited(_ensurePushReadyAndSync(next));
      }
      _consumePendingTapIfAny();
    }
  }

  Future<void> _bootstrapCompanySessionIfNeeded(AuthState auth) async {
    if (!mounted || !auth.isCompanyPortal) return;
    final session = ref.read(companySessionControllerProvider);
    if (session.isAuthenticated || session.bootstrapping) return;

    await ref.read(companySessionControllerProvider.notifier).bootstrap();
    if (!mounted) return;

    final refreshed = ref.read(companySessionControllerProvider);
    if (refreshed.error != null && _hasVerifiedSession(auth)) {
      if (_logoutInFlight) return;
      _logoutInFlight = true;
      try {
        await ref.read(authControllerProvider.notifier).logout();
      } finally {
        _logoutInFlight = false;
      }
    }
  }

  Future<void> _ensurePushReadyAndSync(AuthState auth) async {
    if (!mounted ||
        !_hasVerifiedSession(auth) ||
        !_isCompanySurfaceAuth(auth) ||
        auth.user == null) {
      return;
    }

    ref.read(notificationsControllerProvider.notifier).startRealtime();
    try {
      await ref.read(maslakiRealtimeServiceProvider).bindAuthenticatedSession();
    } catch (_) {
      // Best effort: notification SSE fallback can still keep the inbox fresh.
    }

    final push = ref.read(pushNotificationsProvider);
    try {
      await push.initialize();
      await push.requestPermissionIfNeeded();
    } catch (_) {
      return;
    }
    if (!mounted) return;

    _pushTapSub ??= push.tapStream.listen(_handleNotificationTap);

    final userId = auth.user!.id;
    if (_pushSyncInFlight || _pushSyncedUserId == userId) return;
    _pushSyncInFlight = true;
    try {
      final synced = await push.syncToken(userId: userId);
      if (synced) _pushSyncedUserId = userId;
    } catch (_) {
      // Lifecycle resume and the notification screen both retry token sync.
    } finally {
      _pushSyncInFlight = false;
    }
  }

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
    if (!_hasVerifiedSession(auth) || !_isCompanySurfaceAuth(auth)) {
      _pendingTapPayload = payload;
      return;
    }

    final nav = _navigatorKey.currentState;
    if (nav == null) {
      _pendingTapPayload = payload;
      return;
    }
    if (auth.isCompanyPortal && _openCompanyPortalNotification(nav, payload)) {
      return;
    }
    unawaited(
      NotificationNavigation.open(navigator: nav, auth: auth, payload: payload),
    );
  }

  bool _openCompanyPortalNotification(
    NavigatorState navigator,
    NotificationTapPayload payload,
  ) {
    final session = ref.read(companySessionControllerProvider);
    final companyId = session.activeCompanyId;
    final target = NotificationNavigation.resolveTarget(
      rawTarget: payload.target,
      type: payload.type,
      orderId: payload.orderId,
    );
    final normalizedTarget = target.trim().toLowerCase();
    final isOrderTarget =
        payload.orderId != null ||
        normalizedTarget == 'merchant_order_details' ||
        normalizedTarget == 'owner_order_details' ||
        normalizedTarget == 'merchant_orders_current' ||
        normalizedTarget == 'owner_orders' ||
        normalizedTarget == 'order_tracking' ||
        normalizedTarget == 'company_orders';

    if (isOrderTarget && companyId != null) {
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => CompanyOrdersScreen(
              api: ref.read(companyApiProvider),
              companyId: companyId,
              initialOrderId: payload.orderId,
            ),
          ),
        ),
      );
      return true;
    }

    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
      ),
    );
    return true;
  }

  Widget _homeForAuth(AuthState auth, CompanySessionState session) {
    if (auth.isCompanyPortal) {
      if (session.isAuthenticated) {
        return const CompanyShellScreen();
      }
      if (session.bootstrapping) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return const CompanyLoginScreen();
    }

    if (auth.isBackoffice || auth.isSuperAdmin || auth.isStaff) {
      return const AdminDashboardScreen();
    }
    if (auth.isAccountant) {
      return const AccountantDashboardScreen();
    }
    if (auth.isHr) {
      return const HrDashboardScreen();
    }
    return const CompanyLoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final session = ref.watch(companySessionControllerProvider);
    Intl.defaultLocale = settings.locale.languageCode;

    if (_hasVerifiedSession(auth) && !_isCompanySurfaceAuth(auth)) {
      if (!_logoutInFlight) {
        _logoutInFlight = true;
        Future.microtask(() async {
          await ref.read(authControllerProvider.notifier).logout();
          _logoutInFlight = false;
        });
      }
    } else {
      _logoutInFlight = false;
    }

    final home = !_bootstrapped || auth.isSessionRecoveryInProgress
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : (_hasVerifiedSession(auth)
              ? _homeForAuth(auth, session)
              : const CompanyLoginScreen());

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.companyPortalWindowTitle,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.themed(settings.maslakiTheme),
      darkTheme: AppTheme.themed(settings.maslakiTheme),
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return EdgeToEdgeSystemUi(
          child: AppBackdrop(child: AppResponsiveShell(child: child)),
        );
      },
      home: home,
    );
  }
}

enum _CompanySection {
  dashboard,
  branches,
  orders,
  reports,
  promotions,
  inventory,
  users,
  settings,
}

class CompanyShellScreen extends ConsumerStatefulWidget {
  const CompanyShellScreen({super.key});

  @override
  ConsumerState<CompanyShellScreen> createState() => _CompanyShellScreenState();
}

class _CompanyShellScreenState extends ConsumerState<CompanyShellScreen> {
  _CompanySection _section = _CompanySection.dashboard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = ref.watch(companySessionControllerProvider);
    final membership = session.activeMembership;
    final companyId = session.activeCompanyId;
    if (membership == null || companyId == null) {
      return const CompanyLoginScreen();
    }
    final api = ref.read(companyApiProvider);
    final useDesktop = DesktopDashboardFrame.shouldUse(context);
    final body = _buildSection(
      section: _section,
      api: api,
      companyId: companyId,
      membership: membership,
    );

    if (useDesktop) {
      return Scaffold(
        body: AppBackdrop(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: DesktopDashboardFrame(
                title: l10n.companyPortalTitle,
                subtitle: l10n.companyPortalSubtitle(
                  membership.companyName,
                  companyRoleLabel(context, membership.role),
                ),
                statusLabel: l10n.companyPortalTitle,
                sidebarWidth: 300,
                sidebar: _CompanySidebar(
                  selected: _section,
                  onSelect: (section) => setState(() => _section = section),
                  session: session,
                  onSelectCompany: (value) => ref
                      .read(companySessionControllerProvider.notifier)
                      .selectCompany(value),
                  onLogout: () => ref
                      .read(companySessionControllerProvider.notifier)
                      .logout(),
                ),
                child: body,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: MaslakiTopBar(
        title: membership.companyName,
        subtitle: companyRoleLabel(context, membership.role),
        actions: [
          const NotificationsBellButton(),
          PopupMenuButton<int>(
            tooltip: l10n.companySwitchCompany,
            onSelected: (value) => ref
                .read(companySessionControllerProvider.notifier)
                .selectCompany(value),
            itemBuilder: (context) => session.memberships
                .map(
                  (item) => PopupMenuItem<int>(
                    value: item.companyId,
                    child: Text(item.companyName),
                  ),
                )
                .toList(),
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
          IconButton(
            tooltip: l10n.commonLogout,
            onPressed: () =>
                ref.read(companySessionControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: AppBackdrop(child: SafeArea(child: body)),
      bottomNavigationBar: MaslakiBottomNavShell(
        currentIndex: _section.index,
        onTap: (index) {
          setState(() => _section = _CompanySection.values[index]);
        },
        items: [
          MaslakiBottomNavItem(
            icon: Icons.dashboard_outlined,
            activeIcon: Icons.dashboard_rounded,
            label: l10n.companyNavDashboard,
          ),
          MaslakiBottomNavItem(
            icon: Icons.store_mall_directory_outlined,
            activeIcon: Icons.store_mall_directory_rounded,
            label: l10n.companyNavBranches,
          ),
          MaslakiBottomNavItem(
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long_rounded,
            label: context.lt(ar: 'الطلبات', en: 'Orders'),
          ),
          MaslakiBottomNavItem(
            icon: Icons.bar_chart_outlined,
            activeIcon: Icons.bar_chart_rounded,
            label: l10n.companyNavReports,
          ),
          MaslakiBottomNavItem(
            icon: Icons.local_offer_outlined,
            activeIcon: Icons.local_offer_rounded,
            label: l10n.companyNavPromotions,
          ),
          MaslakiBottomNavItem(
            icon: Icons.inventory_2_outlined,
            activeIcon: Icons.inventory_2_rounded,
            label: l10n.companyNavInventory,
          ),
          MaslakiBottomNavItem(
            icon: Icons.groups_outlined,
            activeIcon: Icons.groups_rounded,
            label: l10n.companyNavUsers,
          ),
          MaslakiBottomNavItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings_rounded,
            label: l10n.companyNavSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required _CompanySection section,
    required CompanyApi api,
    required int companyId,
    required CompanyMembership membership,
  }) {
    final key = ValueKey('${section.name}-$companyId');
    switch (section) {
      case _CompanySection.dashboard:
        return CompanyDashboardScreen(
          key: key,
          api: api,
          companyId: companyId,
          onOpenBranches: () =>
              setState(() => _section = _CompanySection.branches),
          onOpenInventory: () =>
              setState(() => _section = _CompanySection.inventory),
          onOpenPromotions: () =>
              setState(() => _section = _CompanySection.promotions),
          onOpenUsers: () => setState(() => _section = _CompanySection.users),
          onOpenSettings: () =>
              setState(() => _section = _CompanySection.settings),
        );
      case _CompanySection.branches:
        return CompanyBranchesScreen(key: key, api: api, companyId: companyId);
      case _CompanySection.orders:
        return CompanyOrdersScreen(key: key, api: api, companyId: companyId);
      case _CompanySection.reports:
        return CompanyReportsScreen(key: key, api: api, companyId: companyId);
      case _CompanySection.promotions:
        return CompanyPromotionsScreen(
          key: key,
          api: api,
          companyId: companyId,
        );
      case _CompanySection.inventory:
        return CompanyInventoryScreen(key: key, api: api, companyId: companyId);
      case _CompanySection.users:
        return CompanyUsersScreen(key: key, api: api, companyId: companyId);
      case _CompanySection.settings:
        return CompanySettingsScreen(
          key: key,
          api: api,
          companyId: companyId,
          activeMembership: membership,
          onLogout: () =>
              ref.read(companySessionControllerProvider.notifier).logout(),
        );
    }
  }
}

class _CompanySidebar extends StatelessWidget {
  final _CompanySection selected;
  final ValueChanged<_CompanySection> onSelect;
  final CompanySessionState session;
  final ValueChanged<int> onSelectCompany;
  final VoidCallback onLogout;

  const _CompanySidebar({
    required this.selected,
    required this.onSelect,
    required this.session,
    required this.onSelectCompany,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.companyPortalTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const NotificationsBellButton(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.companyPortalWorkspaceDescription,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<int>(
            initialValue: session.activeCompanyId,
            decoration: InputDecoration(
              labelText: l10n.companyActiveCompanyLabel,
            ),
            items: session.memberships
                .map(
                  (item) => DropdownMenuItem<int>(
                    value: item.companyId,
                    child: Text(item.companyName),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onSelectCompany(value);
            },
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                _SidebarItem(
                  icon: Icons.dashboard_rounded,
                  label: l10n.companyNavDashboard,
                  selected: selected == _CompanySection.dashboard,
                  onTap: () => onSelect(_CompanySection.dashboard),
                ),
                _SidebarItem(
                  icon: Icons.store_mall_directory_rounded,
                  label: l10n.companyNavBranches,
                  selected: selected == _CompanySection.branches,
                  onTap: () => onSelect(_CompanySection.branches),
                ),
                _SidebarItem(
                  icon: Icons.receipt_long_rounded,
                  label: context.lt(ar: 'الطلبات', en: 'Orders'),
                  selected: selected == _CompanySection.orders,
                  onTap: () => onSelect(_CompanySection.orders),
                ),
                _SidebarItem(
                  icon: Icons.bar_chart_rounded,
                  label: l10n.companyNavReports,
                  selected: selected == _CompanySection.reports,
                  onTap: () => onSelect(_CompanySection.reports),
                ),
                _SidebarItem(
                  icon: Icons.local_offer_rounded,
                  label: l10n.companyNavPromotions,
                  selected: selected == _CompanySection.promotions,
                  onTap: () => onSelect(_CompanySection.promotions),
                ),
                _SidebarItem(
                  icon: Icons.inventory_2_rounded,
                  label: l10n.companyNavInventory,
                  selected: selected == _CompanySection.inventory,
                  onTap: () => onSelect(_CompanySection.inventory),
                ),
                _SidebarItem(
                  icon: Icons.groups_rounded,
                  label: l10n.companyPortalTeamAccess,
                  selected: selected == _CompanySection.users,
                  onTap: () => onSelect(_CompanySection.users),
                ),
                _SidebarItem(
                  icon: Icons.settings_rounded,
                  label: l10n.companyPortalSettings,
                  selected: selected == _CompanySection.settings,
                  onTap: () => onSelect(_CompanySection.settings),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.18),
              child: const Icon(Icons.person_rounded),
            ),
            title: Text(
              session.user?.fullName ?? l10n.companyPortalUserFallback,
            ),
            subtitle: Text(
              companyRoleLabel(
                context,
                session.activeMembership?.role ?? 'company_manager',
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: Text(l10n.commonLogout),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tileColor: selected ? scheme.primary.withValues(alpha: 0.14) : null,
        leading: Icon(icon, color: selected ? scheme.primary : null),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? scheme.primary : null,
          ),
        ),
      ),
    );
  }
}
