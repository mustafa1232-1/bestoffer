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
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle(RuntimeAppScope.company)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
            onPressed: () {
              ref.invalidate(_companyPortalBootstrapProvider);
              ref.invalidate(_companyDashboardProvider);
              ref.invalidate(_companyBranchesProvider);
              ref.invalidate(_companyUsersProvider);
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

String _currencyText(int amount) {
  if (amount <= 0) return '-';
  return '$amount IQD';
}
