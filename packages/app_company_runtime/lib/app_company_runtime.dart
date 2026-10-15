import 'package:core_auth/core_auth.dart';
import 'package:core_design_system/core_design_system.dart';
import 'package:core_localization/core_localization.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_storage/core_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _companyRuntimeApiProvider = Provider<_CompanyRuntimeApi>((ref) {
  return _CompanyRuntimeApi(ref.watch(runtimeDioProvider));
});

final _selectedCompanyIdProvider = StateProvider<int?>((_) => null);

final _companyPortalBootstrapProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isCompany) {
    return null;
  }
  try {
    return await ref.read(_companyRuntimeApiProvider).bootstrap();
  } catch (_) {
    return null;
  }
});

final _companyDashboardProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final bootstrap = await ref.watch(_companyPortalBootstrapProvider.future);
  final companyId = _effectiveCompanyId(ref, bootstrap);
  if (companyId == null) return null;
  try {
    return await ref.read(_companyRuntimeApiProvider).dashboard(companyId);
  } catch (_) {
    return null;
  }
});

final _companyBranchesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final bootstrap = await ref.watch(_companyPortalBootstrapProvider.future);
  final companyId = _effectiveCompanyId(ref, bootstrap);
  if (companyId == null) return const <Map<String, dynamic>>[];
  try {
    return await ref.read(_companyRuntimeApiProvider).branches(companyId);
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
});

final _companyUsersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final bootstrap = await ref.watch(_companyPortalBootstrapProvider.future);
  final companyId = _effectiveCompanyId(ref, bootstrap);
  if (companyId == null) return const <Map<String, dynamic>>[];
  try {
    return await ref.read(_companyRuntimeApiProvider).users(companyId);
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
});

final _companyOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final bootstrap = await ref.watch(_companyPortalBootstrapProvider.future);
  final companyId = _effectiveCompanyId(ref, bootstrap);
  if (companyId == null) return const <Map<String, dynamic>>[];
  try {
    return await ref.read(_companyRuntimeApiProvider).currentOrders(companyId);
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
});

final _companyNotificationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      final auth = ref.watch(authControllerProvider);
      if (auth.user == null || !auth.isCompany) {
        return const <Map<String, dynamic>>[];
      }
      try {
        return await ref.read(_companyRuntimeApiProvider).notifications();
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    });

void runAppCompany() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [appSettingsStorageScopeProvider.overrideWithValue('company')],
      child: const MaslakiCompanyApp(),
    ),
  );
}

class MaslakiCompanyApp extends ConsumerStatefulWidget {
  final bool skipBootstrap;
  final bool useNetworkAuth;

  const MaslakiCompanyApp({
    super.key,
    this.skipBootstrap = false,
    this.useNetworkAuth = true,
  });

  @override
  ConsumerState<MaslakiCompanyApp> createState() => _MaslakiCompanyAppState();
}

class _MaslakiCompanyAppState extends ConsumerState<MaslakiCompanyApp>
    with WidgetsBindingObserver {
  bool _bootstrapped = false;
  bool _roleMismatchLogoutQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.skipBootstrap) {
      _bootstrapped = true;
      return;
    }
    Future.microtask(() async {
      await ref.read(authControllerProvider.notifier).bootstrap();
      if (!mounted) return;
      setState(() {
        _bootstrapped = true;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    ref.invalidate(_companyPortalBootstrapProvider);
    ref.invalidate(_companyDashboardProvider);
    ref.invalidate(_companyBranchesProvider);
    ref.invalidate(_companyUsersProvider);
    ref.invalidate(_companyOrdersProvider);
    ref.invalidate(_companyNotificationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);
    final auth = ref.watch(authControllerProvider);

    if (auth.isAuthed && !auth.isCompany && !_roleMismatchLogoutQueued) {
      _roleMismatchLogoutQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(authControllerProvider.notifier).logout();
        _roleMismatchLogoutQueued = false;
      });
    } else if (!auth.isAuthed || auth.isCompany) {
      _roleMismatchLogoutQueued = false;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.companyPortalWindowTitle,
      locale: settings.locale,
      supportedLocales: CoreAppLocalizations.supportedLocales,
      localizationsDelegates: CoreAppLocalizations.localizationsDelegates,
      theme: AppTheme.light(preset: settings.themePreset),
      darkTheme: AppTheme.dark(preset: settings.themePreset),
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return AppBackdrop(
          animationsEnabled: settings.animationsEnabled,
          weatherEffectsEnabled: settings.weatherEffectsEnabled,
          child: AppResponsiveShell(child: child),
        );
      },
      home: !_bootstrapped
          ? const _CompanySplashScreen()
          : auth.isAuthed && auth.isCompany
          ? const _CompanyHomeScreen()
          : (widget.useNetworkAuth
                ? const _CompanyNetworkLoginScreen()
                : const _RoleLoginScreen(
                    scope: RuntimeAppScope.company,
                    role: AuthRoleScope.company,
                    loginKey: Key('company_login_button'),
                  )),
    );
  }
}

class _CompanySplashScreen extends StatelessWidget {
  const _CompanySplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/branding/maslaki_official_logo.png',
                width: 78,
                height: 78,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.companyPortalWindowTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 140,
              child: LinearProgressIndicator(minHeight: 4),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuntimeLoginLanguageButton extends ConsumerWidget {
  const _RuntimeLoginLanguageButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(appSettingsControllerProvider);
    final localeCode = settings.locale.languageCode.toLowerCase();
    final label = localeCode == 'ar' ? 'AR' : 'EN';

    return PopupMenuButton<String>(
      tooltip: l10n.languageSectionTitle,
      onSelected: (code) {
        ref
            .read(appSettingsControllerProvider.notifier)
            .setLocale(Locale(code));
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'ar', child: Text(l10n.languageArabic)),
        PopupMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.34),
          ),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 17),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _RoleLoginScreen extends ConsumerWidget {
  final RuntimeAppScope scope;
  final AuthRoleScope role;
  final Key loginKey;

  const _RoleLoginScreen({
    required this.scope,
    required this.role,
    required this.loginKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _RuntimeLoginLanguageButton(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.roleLoginTitle(scope),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.loginHeadline, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    key: loginKey,
                    onPressed: () async {
                      await ref
                          .read(authControllerProvider.notifier)
                          .login(role);
                    },
                    child: Text(l10n.loginButtonLabel(scope)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyNetworkLoginScreen extends ConsumerStatefulWidget {
  const _CompanyNetworkLoginScreen();

  @override
  ConsumerState<_CompanyNetworkLoginScreen> createState() =>
      _CompanyNetworkLoginScreenState();
}

class _CompanyNetworkLoginScreenState
    extends ConsumerState<_CompanyNetworkLoginScreen> {
  late final TextEditingController _phoneController;
  late final TextEditingController _pinController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: _RuntimeLoginLanguageButton(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.roleLoginTitle(RuntimeAppScope.company),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.runtimeAuthHint, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    TextField(
                      key: const Key('company_phone_field'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: l10n.runtimePhoneLabel,
                        prefixIcon: const Icon(Icons.phone_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('company_pin_field'),
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.runtimePinLabel,
                        prefixIcon: const Icon(Icons.lock_rounded),
                      ),
                    ),
                    if ((auth.error ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        auth.error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('company_login_button'),
                        onPressed: auth.loading
                            ? null
                            : () async {
                                await ref
                                    .read(authControllerProvider.notifier)
                                    .loginWithPhonePin(
                                      phone: _phoneController.text,
                                      pin: _pinController.text,
                                      expectedRole: AuthRoleScope.company,
                                    );
                              },
                        child: auth.loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                l10n.loginButtonLabel(RuntimeAppScope.company),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyHomeScreen extends ConsumerWidget {
  const _CompanyHomeScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final bootstrap = ref.watch(_companyPortalBootstrapProvider);
    final dashboard = ref.watch(_companyDashboardProvider);
    final branches = ref.watch(_companyBranchesProvider);
    final users = ref.watch(_companyUsersProvider);
    final orders = ref.watch(_companyOrdersProvider);
    final unreadNotifications = ref
        .watch(_companyNotificationsProvider)
        .maybeWhen(
          data: (items) =>
              items.where((item) => !_isNotificationRead(item)).length,
          orElse: () => 0,
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle(RuntimeAppScope.company)),
        actions: [
          _NotificationBell(
            unreadCount: unreadNotifications,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const _CompanyNotificationsScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
            onPressed: () {
              ref.invalidate(_companyPortalBootstrapProvider);
              ref.invalidate(_companyDashboardProvider);
              ref.invalidate(_companyBranchesProvider);
              ref.invalidate(_companyUsersProvider);
              ref.invalidate(_companyOrdersProvider);
              ref.invalidate(_companyNotificationsProvider);
            },
          ),
          IconButton(
            key: const Key('company_logout_button'),
            tooltip: l10n.commonLogout,
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          bootstrap.when(
            data: (value) {
              final membership = _selectedMembership(ref, value);
              if (membership == null) {
                return _SummaryHeroCard(
                  title: l10n.companyPortalWindowTitle,
                  subtitle: l10n.runtimeCompanySelectionRequiredSubtitle,
                  icon: Icons.business_center_rounded,
                );
              }
              return _SummaryHeroCard(
                title: _stringOf(
                  membership['companyName'] ?? membership['company_name'],
                  fallback: l10n.companyPortalWindowTitle,
                ),
                subtitle: _stringOf(
                  membership['role'],
                  fallback: l10n.dashboardTitle(RuntimeAppScope.company),
                ),
                icon: Icons.business_center_rounded,
              );
            },
            loading: () => const _LoadingCard(),
            error: (_, _) => _SummaryHeroCard(
              title: l10n.companyPortalWindowTitle,
              subtitle: l10n.dashboardTitle(RuntimeAppScope.company),
              icon: Icons.business_center_rounded,
            ),
          ),
          const SizedBox(height: 16),
          bootstrap.when(
            data: (value) {
              final memberships = _companyMemberships(value);
              if (memberships.length <= 1) return const SizedBox.shrink();
              final selectedCompanyId = ref.watch(_selectedCompanyIdProvider);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.runtimeCompanySelectorLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey<int?>(selectedCompanyId),
                        initialValue: selectedCompanyId,
                        hint: Text(l10n.runtimeCompanySelectorLabel),
                        items: memberships
                            .map(
                              (membership) => DropdownMenuItem<int>(
                                value: _readInt(membership, const [
                                  'companyId',
                                  'company_id',
                                ]),
                                child: Text(
                                  _stringOf(
                                    membership['companyName'] ??
                                        membership['company_name'],
                                    fallback:
                                        '#${_readInt(membership, const ['companyId', 'company_id'])}',
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          ref.read(_selectedCompanyIdProvider.notifier).state =
                              value;
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          bootstrap.when(
            data: (value) {
              final memberships = _companyMemberships(value);
              if (memberships.length <= 1 ||
                  _selectedMembership(ref, value) != null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.runtimeCompanySelectionRequiredTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.runtimeCompanySelectionRequiredSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          bootstrap.when(
            data: (value) => _selectedMembership(ref, value) == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const _CompanyBranchesScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.account_tree_outlined),
                          label: Text(l10n.runtimeOpenBranchesLabel),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const _CompanyOrdersScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.receipt_long_rounded),
                          label: Text(_lt(context, 'الطلبات', 'Orders')),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const _CompanyUsersScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.groups_rounded),
                          label: Text(l10n.runtimeOpenUsersLabel),
                        ),
                      ],
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          dashboard.when(
            data: (value) => _SummaryMetricsCard(
              rows: [
                _MetricRow(
                  label: l10n.storesLabel,
                  value:
                      '${_readInt(_extractObject(value, const ['totals', 'summary']) ?? value, const ['branchesCount', 'branches_count', 'activeBranches'])}',
                ),
                _MetricRow(
                  label: l10n.ordersLabel,
                  value:
                      '${_readInt(_extractObject(value, const ['totals', 'summary']) ?? value, const ['ordersCount', 'orders_count', 'activeOrders'])}',
                ),
                _MetricRow(
                  label: l10n.runtimeTaxiFareFieldLabel,
                  value: _currencyText(
                    _readInt(
                      _extractObject(value, const ['totals', 'summary']) ??
                          value,
                      const ['grossSales', 'gross_sales', 'revenueIqd'],
                    ),
                  ),
                ),
              ],
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          orders.when(
            data: (items) => _RuntimeListCard(
              title: _lt(context, 'طلبات الفروع', 'Branch orders'),
              emptyTitle: _lt(context, 'لا توجد طلبات حالية', 'No orders'),
              emptySubtitle: _lt(
                context,
                'ستظهر هنا طلبات فروع الشركة عند وصولها.',
                'New branch orders will appear here.',
              ),
              items: items
                  .take(5)
                  .map(
                    (order) => _ListItemView(
                      title:
                          '${_lt(context, 'طلب', 'Order')} #${_intOf(order['id'])}',
                      subtitle: _stringOf(
                        order['merchant_name'] ?? order['merchantName'],
                        fallback: _statusLabel(
                          context,
                          _stringOf(order['status']),
                        ),
                      ),
                      trailing: _currencyText(
                        _readInt(order, const ['total_amount', 'totalAmount']),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: _lt(context, 'طلبات الفروع', 'Branch orders'),
              emptyTitle: _lt(context, 'لا توجد طلبات حالية', 'No orders'),
              emptySubtitle: _lt(
                context,
                'ستظهر هنا طلبات فروع الشركة عند وصولها.',
                'New branch orders will appear here.',
              ),
              items: const <_ListItemView>[],
            ),
          ),
          const SizedBox(height: 16),
          branches.when(
            data: (items) => _RuntimeListCard(
              title: l10n.storesLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.storesLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(l10n.storesLabel),
              items: items
                  .take(5)
                  .map(
                    (branch) => _ListItemView(
                      title: _stringOf(
                        branch['name'],
                        fallback: '#${_intOf(branch['id'])}',
                      ),
                      subtitle: _stringOf(
                        branch['type'],
                        fallback: _stringOf(branch['status']),
                      ),
                      trailing:
                          '${_readInt(branch, const ['activeOrders', 'active_orders'])}',
                    ),
                  )
                  .toList(growable: false),
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.storesLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.storesLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(l10n.storesLabel),
              items: const <_ListItemView>[],
            ),
          ),
          const SizedBox(height: 16),
          users.when(
            data: (items) => _RuntimeListCard(
              title: l10n.profileLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.profileLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(l10n.profileLabel),
              items: items
                  .take(5)
                  .map(
                    (user) => _ListItemView(
                      title: _stringOf(
                        _extractObject(user, const ['user'])?['fullName'] ??
                            _extractObject(user, const ['user'])?['full_name'],
                        fallback: '#${_intOf(user['id'])}',
                      ),
                      subtitle: _stringOf(
                        user['role'],
                        fallback: _stringOf(
                          _extractObject(user, const ['user'])?['phone'],
                        ),
                      ),
                      trailing: _stringOf(
                        _extractObject(user, const ['user'])?['phone'],
                        fallback: '-',
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.profileLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.profileLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(l10n.profileLabel),
              items: const <_ListItemView>[],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyBranchesScreen extends ConsumerWidget {
  const _CompanyBranchesScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final branches = ref.watch(_companyBranchesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.runtimeOpenBranchesLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          branches.when(
            data: (items) => _RuntimeListCard(
              title: l10n.storesLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.storesLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(l10n.storesLabel),
              items: items
                  .map(
                    (branch) => _ListItemView(
                      title: _stringOf(
                        branch['name'],
                        fallback: '#${_intOf(branch['id'])}',
                      ),
                      subtitle: _stringOf(
                        branch['type'],
                        fallback: _stringOf(branch['status']),
                      ),
                      trailing:
                          '${_readInt(branch, const ['activeOrders', 'active_orders'])}',
                    ),
                  )
                  .toList(growable: false),
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.storesLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.storesLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(l10n.storesLabel),
              items: const <_ListItemView>[],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyNotificationsScreen extends ConsumerWidget {
  const _CompanyNotificationsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(_companyNotificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_lt(context, 'الإشعارات', 'Notifications')),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(_companyNotificationsProvider),
            tooltip: context.l10n.commonRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: notifications.when(
        data: (items) {
          if (items.isEmpty) {
            return _RuntimeListCard(
              title: _lt(context, 'الإشعارات', 'Notifications'),
              emptyTitle: _lt(context, 'لا توجد إشعارات', 'No notifications'),
              emptySubtitle: _lt(
                context,
                'ستظهر إشعارات طلبات الفروع هنا.',
                'Branch order notifications will appear here.',
              ),
              items: const <_ListItemView>[],
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_companyNotificationsProvider);
              await ref.read(_companyNotificationsProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RuntimeNotificationCard(
                    notification: item,
                    onTap: () async {
                      final id = _intOf(item['id']);
                      if (id > 0 && !_isNotificationRead(item)) {
                        await ref
                            .read(_companyRuntimeApiProvider)
                            .markNotificationRead(id);
                        ref.invalidate(_companyNotificationsProvider);
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
      ),
    );
  }
}

class _RuntimeNotificationCard extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback onTap;

  const _RuntimeNotificationCard({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final read = _isNotificationRead(notification);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: read ? null : scheme.primaryContainer.withValues(alpha: 0.28),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          read ? Icons.notifications_none_rounded : Icons.notifications_rounded,
        ),
        title: Text(
          _stringOf(
            notification['title'],
            fallback: _lt(context, 'إشعار', 'Notification'),
          ),
          style: TextStyle(
            fontWeight: read ? FontWeight.w600 : FontWeight.w900,
          ),
        ),
        subtitle: Text(
          _stringOf(notification['body']),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing:
            _intOf(notification['order_id'] ?? notification['orderId']) > 0
            ? Text(
                '#${_intOf(notification['order_id'] ?? notification['orderId'])}',
              )
            : null,
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onPressed;

  const _NotificationBell({required this.unreadCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          onPressed: onPressed,
          tooltip: _lt(context, 'الإشعارات', 'Notifications'),
          icon: const Icon(Icons.notifications_outlined),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 7,
            top: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CompanyOrdersScreen extends ConsumerStatefulWidget {
  const _CompanyOrdersScreen();

  @override
  ConsumerState<_CompanyOrdersScreen> createState() =>
      _CompanyOrdersScreenState();
}

class _CompanyOrdersScreenState extends ConsumerState<_CompanyOrdersScreen> {
  int? _selectedMerchantId;
  int? _busyOrderId;

  Future<void> _refresh() async {
    ref.invalidate(_companyOrdersProvider);
    ref.invalidate(_companyBranchesProvider);
    await ref.read(_companyOrdersProvider.future);
  }

  Future<void> _updateStatus(Map<String, dynamic> order, String status) async {
    final orderId = _intOf(order['id']);
    if (orderId <= 0) return;
    if (status == 'cancelled') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_lt(context, 'رفض الطلب', 'Reject order')),
          content: Text(
            _lt(context, 'هل تريد رفض هذا الطلب؟', 'Reject this order?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_lt(context, 'رجوع', 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_lt(context, 'رفض', 'Reject')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busyOrderId = orderId);
    try {
      final bootstrap = await ref.read(_companyPortalBootstrapProvider.future);
      final membership = _selectedMembership(ref, bootstrap);
      final companyId = _readInt(membership, const ['companyId', 'company_id']);
      if (companyId <= 0) return;
      await ref
          .read(_companyRuntimeApiProvider)
          .updateOrderStatus(companyId, orderId, status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lt(context, 'تم تحديث الطلب.', 'Order updated.')),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_lt(context, 'تعذر تحديث الطلب', 'Update failed')}: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches =
        ref.watch(_companyBranchesProvider).valueOrNull ??
        const <Map<String, dynamic>>[];
    final ordersValue = ref.watch(_companyOrdersProvider);
    final allOrders = ordersValue.valueOrNull ?? const <Map<String, dynamic>>[];
    final orders = _selectedMerchantId == null
        ? allOrders
        : allOrders
              .where(
                (order) =>
                    _readInt(order, const ['merchant_id', 'merchantId']) ==
                    _selectedMerchantId,
              )
              .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_lt(context, 'طلبات الفروع', 'Branch orders')),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: context.l10n.commonRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<int?>(
              initialValue: _selectedMerchantId,
              decoration: InputDecoration(
                labelText: _lt(context, 'الفرع', 'Branch'),
                prefixIcon: const Icon(Icons.store_rounded),
              ),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(_lt(context, 'كل الفروع', 'All branches')),
                ),
                ...branches.map(
                  (branch) => DropdownMenuItem<int?>(
                    value: _intOf(branch['id']),
                    child: Text(_stringOf(branch['name'])),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _selectedMerchantId = value),
            ),
            const SizedBox(height: 16),
            if (ordersValue.isLoading && orders.isEmpty)
              const _LoadingCard()
            else if (orders.isEmpty)
              _RuntimeListCard(
                title: _lt(context, 'طلبات الفروع', 'Branch orders'),
                emptyTitle: _lt(context, 'لا توجد طلبات حالية', 'No orders'),
                emptySubtitle: _lt(
                  context,
                  'ستظهر هنا طلبات فروع الشركة عند وصولها.',
                  'New branch orders will appear here.',
                ),
                items: const <_ListItemView>[],
              )
            else
              ...orders.map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RuntimeOrderCard(
                    order: order,
                    busy: _busyOrderId == _intOf(order['id']),
                    onAction: (status) => _updateStatus(order, status),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RuntimeOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool busy;
  final ValueChanged<String> onAction;

  const _RuntimeOrderCard({
    required this.order,
    required this.busy,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final status = _normalizeStatus(_stringOf(order['status']));
    final orderId = _intOf(order['id']);
    final merchantName = _stringOf(
      order['merchant_name'] ?? order['merchantName'],
    );
    final customerName = _stringOf(
      order['customer_full_name'] ?? order['customerFullName'],
      fallback: _lt(context, 'زبون', 'Customer'),
    );
    final total = _readNum(order, const ['total_amount', 'totalAmount']);
    final items = _extractList(order, const ['items']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.receipt_long_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_lt(context, 'طلب', 'Order')} #$orderId',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(merchantName),
                    ],
                  ),
                ),
                Chip(label: Text(_statusLabel(context, status))),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.person_rounded, size: 17),
                  label: Text(customerName),
                ),
                Chip(
                  avatar: const Icon(Icons.payments_rounded, size: 17),
                  label: Text(_currencyText(total)),
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...items
                  .take(3)
                  .map(
                    (item) => Row(
                      children: [
                        Expanded(
                          child: Text(
                            _stringOf(
                              item['product_name'] ?? item['productName'],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('x${_readInt(item, const ['quantity'])}'),
                      ],
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            if (busy)
              const LinearProgressIndicator(minHeight: 2)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _actionsFor(order)
                    .map(
                      (action) => action.destructive
                          ? OutlinedButton.icon(
                              onPressed: () => onAction(action.status),
                              icon: Icon(action.icon),
                              label: Text(action.label(context)),
                            )
                          : FilledButton.icon(
                              onPressed: () => onAction(action.status),
                              icon: Icon(action.icon),
                              label: Text(action.label(context)),
                            ),
                    )
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  List<_RuntimeOrderAction> _actionsFor(Map<String, dynamic> order) {
    switch (_normalizeStatus(_stringOf(order['status']))) {
      case 'pending':
        return const [
          _RuntimeOrderAction('approved', Icons.check_rounded, 'approve'),
          _RuntimeOrderAction('cancelled', Icons.close_rounded, 'reject', true),
        ];
      case 'approved':
        return const [
          _RuntimeOrderAction(
            'preparing',
            Icons.restaurant_menu_rounded,
            'prepare',
          ),
          _RuntimeOrderAction('cancelled', Icons.close_rounded, 'reject', true),
        ];
      case 'preparing':
        return const [
          _RuntimeOrderAction(
            'ready_for_delivery',
            Icons.done_all_rounded,
            'ready',
          ),
          _RuntimeOrderAction('cancelled', Icons.close_rounded, 'reject', true),
        ];
      case 'ready_for_delivery':
        if (order['is_merchant_delivery'] != true &&
            order['isMerchantDelivery'] != true) {
          return const [];
        }
        return const [
          _RuntimeOrderAction(
            'on_the_way',
            Icons.delivery_dining_rounded,
            'way',
          ),
        ];
      case 'on_the_way':
        return const [
          _RuntimeOrderAction('arrived', Icons.location_on_rounded, 'arrived'),
        ];
      case 'arrived':
        return const [
          _RuntimeOrderAction('delivered', Icons.task_alt_rounded, 'delivered'),
        ];
      default:
        return const [];
    }
  }
}

class _RuntimeOrderAction {
  final String status;
  final IconData icon;
  final String key;
  final bool destructive;

  const _RuntimeOrderAction(
    this.status,
    this.icon,
    this.key, [
    this.destructive = false,
  ]);

  String label(BuildContext context) {
    switch (key) {
      case 'approve':
        return _lt(context, 'قبول', 'Approve');
      case 'reject':
        return _lt(context, 'رفض', 'Reject');
      case 'prepare':
        return _lt(context, 'تجهيز', 'Prepare');
      case 'ready':
        return _lt(context, 'جاهز', 'Ready');
      case 'way':
        return _lt(context, 'بالطريق', 'On the way');
      case 'arrived':
        return _lt(context, 'وصل', 'Arrived');
      case 'delivered':
        return _lt(context, 'تم التسليم', 'Delivered');
      default:
        return status;
    }
  }
}

class _CompanyUsersScreen extends ConsumerWidget {
  const _CompanyUsersScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final users = ref.watch(_companyUsersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.runtimeOpenUsersLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          users.when(
            data: (items) => _RuntimeListCard(
              title: l10n.profileLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.profileLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(l10n.profileLabel),
              items: items
                  .map(
                    (user) => _ListItemView(
                      title: _stringOf(
                        _extractObject(user, const ['user'])?['fullName'] ??
                            _extractObject(user, const ['user'])?['full_name'],
                        fallback: '#${_intOf(user['id'])}',
                      ),
                      subtitle: _stringOf(
                        user['role'],
                        fallback: _stringOf(
                          _extractObject(user, const ['user'])?['phone'],
                        ),
                      ),
                      trailing: _stringOf(
                        _extractObject(user, const ['user'])?['phone'],
                        fallback: '-',
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.profileLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.profileLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(l10n.profileLabel),
              items: const <_ListItemView>[],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyRuntimeApi {
  final Dio _dio;

  const _CompanyRuntimeApi(this._dio);

  Future<Map<String, dynamic>?> bootstrap() async {
    final response = await _dio.get('/api/company/auth/bootstrap');
    return _extractObject(response.data, const ['data']) ??
        (response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : null);
  }

  Future<Map<String, dynamic>?> dashboard(int companyId) async {
    final response = await _dio.get(
      '/api/company/dashboard',
      options: Options(headers: {'X-Company-Id': '$companyId'}),
    );
    return _extractObject(response.data, const ['data', 'dashboard']) ??
        (response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : null);
  }

  Future<List<Map<String, dynamic>>> branches(int companyId) async {
    final response = await _dio.get(
      '/api/company/branches',
      options: Options(headers: {'X-Company-Id': '$companyId'}),
    );
    return _extractList(response.data, const ['branches', 'items', 'data']);
  }

  Future<List<Map<String, dynamic>>> users(int companyId) async {
    final response = await _dio.get(
      '/api/company/users',
      options: Options(headers: {'X-Company-Id': '$companyId'}),
    );
    return _extractList(response.data, const ['users', 'items', 'data']);
  }

  Future<List<Map<String, dynamic>>> currentOrders(int companyId) async {
    final response = await _dio.get(
      '/api/company/orders/current',
      options: Options(headers: {'X-Company-Id': '$companyId'}),
    );
    return _extractList(response.data, const ['orders', 'items', 'data']);
  }

  Future<void> updateOrderStatus(
    int companyId,
    int orderId,
    String status,
  ) async {
    await _dio.patch(
      '/api/company/orders/$orderId/status',
      options: Options(headers: {'X-Company-Id': '$companyId'}),
      data: {'status': status},
    );
  }

  Future<List<Map<String, dynamic>>> notifications() async {
    final response = await _dio.get(
      '/api/notifications',
      queryParameters: {'unreadOnly': 0, 'limit': 80},
    );
    return _extractList(response.data, const [
      'notifications',
      'items',
      'data',
    ]);
  }

  Future<void> markNotificationRead(int notificationId) async {
    await _dio.patch('/api/notifications/$notificationId/read');
  }
}

Map<String, dynamic>? _firstCompanyMembership(Map<String, dynamic>? bootstrap) {
  if (bootstrap == null) return null;
  final memberships = _extractList(bootstrap, const ['memberships', 'items']);
  if (memberships.isEmpty) return null;
  return memberships.first;
}

List<Map<String, dynamic>> _companyMemberships(
  Map<String, dynamic>? bootstrap,
) {
  if (bootstrap == null) return const <Map<String, dynamic>>[];
  return _extractList(bootstrap, const ['memberships', 'items']);
}

Map<String, dynamic>? _selectedMembership(
  WidgetRef ref,
  Map<String, dynamic>? bootstrap,
) {
  final memberships = _companyMemberships(bootstrap);
  if (memberships.isEmpty) return null;
  final selectedCompanyId = ref.watch(_selectedCompanyIdProvider);
  if (selectedCompanyId == null) {
    return memberships.length == 1 ? memberships.first : null;
  }
  for (final membership in memberships) {
    if (_readInt(membership, const ['companyId', 'company_id']) ==
        selectedCompanyId) {
      return membership;
    }
  }
  return memberships.length == 1 ? memberships.first : null;
}

int? _effectiveCompanyId(Ref ref, Map<String, dynamic>? bootstrap) {
  final selected = ref.watch(_selectedCompanyIdProvider);
  if (selected != null) return selected;
  final membership = _firstCompanyMembership(bootstrap);
  final memberships = _companyMemberships(bootstrap);
  if (membership == null || memberships.length > 1) return null;
  return _readInt(membership, const ['companyId', 'company_id']);
}

class _SummaryHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SummaryHeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(radius: 26, child: Icon(icon)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow {
  final String label;
  final String value;

  const _MetricRow({required this.label, required this.value});
}

class _SummaryMetricsCard extends StatelessWidget {
  final List<_MetricRow> rows;

  const _SummaryMetricsCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 20),
              Row(
                children: [
                  Expanded(child: Text(rows[i].label)),
                  Text(
                    rows[i].value,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListItemView {
  final String title;
  final String subtitle;
  final String trailing;

  const _ListItemView({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
}

class _RuntimeListCard extends StatelessWidget {
  final String title;
  final String emptyTitle;
  final String emptySubtitle;
  final List<_ListItemView> items;

  const _RuntimeListCard({
    required this.title,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Column(
                children: [
                  const Icon(Icons.inbox_outlined, size: 42),
                  const SizedBox(height: 8),
                  Text(
                    emptyTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(emptySubtitle, textAlign: TextAlign.center),
                ],
              )
            else
              Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(items[i].title),
                              const SizedBox(height: 4),
                              Text(
                                items[i].subtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(items[i].trailing),
                      ],
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

Map<String, dynamic>? _extractObject(dynamic data, List<String> keys) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) {
    final source = Map<String, dynamic>.from(data);
    for (final key in keys) {
      final candidate = source[key];
      if (candidate is Map) {
        return Map<String, dynamic>.from(candidate);
      }
    }
  }
  return null;
}

List<Map<String, dynamic>> _extractList(dynamic data, List<String> keys) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
  if (data is Map) {
    final source = Map<String, dynamic>.from(data);
    for (final key in keys) {
      final candidate = source[key];
      if (candidate is List) {
        return candidate
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
    }
  }
  return const <Map<String, dynamic>>[];
}

String _stringOf(dynamic value, {String fallback = '-'}) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}

int _readInt(Map<String, dynamic>? data, List<String> keys) {
  if (data == null) return 0;
  for (final key in keys) {
    final value = int.tryParse('${data[key] ?? ''}');
    if (value != null) return value;
  }
  return 0;
}

int _intOf(dynamic value) {
  return int.tryParse('${value ?? ''}') ?? 0;
}

num _readNum(Map<String, dynamic>? data, List<String> keys) {
  if (data == null) return 0;
  for (final key in keys) {
    final raw = data[key];
    if (raw is num) return raw;
    final value = num.tryParse('${raw ?? ''}');
    if (value != null) return value;
  }
  return 0;
}

String _currencyText(num amount) {
  if (amount <= 0) return '-';
  return '${amount.round()} IQD';
}

bool _isNotificationRead(Map<String, dynamic> notification) {
  return notification['is_read'] == true ||
      notification['isRead'] == true ||
      notification['read_at'] != null ||
      notification['readAt'] != null;
}

String _lt(BuildContext context, String ar, String en) {
  return Localizations.localeOf(context).languageCode.toLowerCase() == 'ar'
      ? ar
      : en;
}

String _normalizeStatus(String status) {
  switch (status.trim().toLowerCase()) {
    case 'accepted_by_store':
      return 'approved';
    case 'courier_requested':
    case 'courier_assigned':
      return 'preparing';
    case 'ready_for_pickup':
      return 'ready_for_delivery';
    case 'picked_up':
      return 'on_the_way';
    case 'delivered_by_courier':
      return 'delivered';
    case 'received_by_customer':
    case 'completed':
      return 'received';
    case 'cancelled_by_customer':
    case 'cancelled_by_store':
    case 'cancelled_by_admin':
      return 'cancelled';
    default:
      return status.trim().toLowerCase();
  }
}

String _statusLabel(BuildContext context, String status) {
  switch (_normalizeStatus(status)) {
    case 'pending':
      return _lt(context, 'قيد الانتظار', 'Pending');
    case 'approved':
      return _lt(context, 'تمت الموافقة', 'Approved');
    case 'preparing':
      return _lt(context, 'قيد التجهيز', 'Preparing');
    case 'ready_for_delivery':
      return _lt(context, 'جاهز للتوصيل', 'Ready');
    case 'on_the_way':
      return _lt(context, 'في الطريق', 'On the way');
    case 'arrived':
      return _lt(context, 'وصل', 'Arrived');
    case 'delivered':
      return _lt(context, 'تم التسليم', 'Delivered');
    case 'cancelled':
      return _lt(context, 'ملغي', 'Cancelled');
    case 'received':
      return _lt(context, 'تم الاستلام', 'Received');
    default:
      return status;
  }
}
