import 'package:core_auth/core_auth.dart';
import 'package:core_design_system/core_design_system.dart';
import 'package:core_localization/core_localization.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_storage/core_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _storeMerchantProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isOwner) return null;
  try {
    return await ref.read(_storeRuntimeApiProvider).merchant();
  } catch (_) {
    return null;
  }
});

final _storeOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isOwner) return const <Map<String, dynamic>>[];
  try {
    return await ref.read(_storeRuntimeApiProvider).currentOrders();
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
});

final _storeAnalyticsProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isOwner) return null;
  try {
    return await ref.read(_storeRuntimeApiProvider).analytics();
  } catch (_) {
    return null;
  }
});

final _storeProductsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isOwner) return const <Map<String, dynamic>>[];
  try {
    return await ref.read(_storeRuntimeApiProvider).products();
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
});

final _storeCategoriesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isOwner) return const <Map<String, dynamic>>[];
  try {
    return await ref.read(_storeRuntimeApiProvider).categories();
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
});

final _storeDeliveryAgentsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) async {
    final auth = ref.watch(authControllerProvider);
    if (auth.user == null || !auth.isOwner) {
      return const <Map<String, dynamic>>[];
    }
    try {
      return await ref.read(_storeRuntimeApiProvider).deliveryAgents();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  },
);

final _storeRuntimeApiProvider = Provider<_StoreRuntimeApi>((ref) {
  return _StoreRuntimeApi(ref.watch(runtimeDioProvider));
});

void runAppStore() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [appSettingsStorageScopeProvider.overrideWithValue('store')],
      child: const MaslakiStoreApp(),
    ),
  );
}

class MaslakiStoreApp extends ConsumerStatefulWidget {
  final bool skipBootstrap;
  final bool useNetworkAuth;

  const MaslakiStoreApp({
    super.key,
    this.skipBootstrap = false,
    this.useNetworkAuth = true,
  });

  @override
  ConsumerState<MaslakiStoreApp> createState() => _MaslakiStoreAppState();
}

class _MaslakiStoreAppState extends ConsumerState<MaslakiStoreApp>
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
    ref.invalidate(_storeMerchantProvider);
    ref.invalidate(_storeOrdersProvider);
    ref.invalidate(_storeAnalyticsProvider);
    ref.invalidate(_storeProductsProvider);
    ref.invalidate(_storeCategoriesProvider);
    ref.invalidate(_storeDeliveryAgentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);
    final auth = ref.watch(authControllerProvider);

    if (auth.isAuthed && !auth.isOwner && !_roleMismatchLogoutQueued) {
      _roleMismatchLogoutQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(authControllerProvider.notifier).logout();
        _roleMismatchLogoutQueued = false;
      });
    } else if (!auth.isAuthed || auth.isOwner) {
      _roleMismatchLogoutQueued = false;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.storePortalWindowTitle,
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
          ? const _StoreSplashScreen()
          : auth.isAuthed && auth.isOwner
          ? const _StoreHomeScreen()
          : (widget.useNetworkAuth
                ? const _StoreNetworkLoginScreen()
                : const _RoleLoginScreen(
                    scope: RuntimeAppScope.store,
                    role: AuthRoleScope.owner,
                    loginKey: Key('store_login_button'),
                  )),
    );
  }
}

class _StoreSplashScreen extends StatelessWidget {
  const _StoreSplashScreen();

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
              context.l10n.storePortalWindowTitle,
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

class _StoreNetworkLoginScreen extends ConsumerStatefulWidget {
  const _StoreNetworkLoginScreen();

  @override
  ConsumerState<_StoreNetworkLoginScreen> createState() =>
      _StoreNetworkLoginScreenState();
}

class _StoreNetworkLoginScreenState
    extends ConsumerState<_StoreNetworkLoginScreen> {
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
                      l10n.roleLoginTitle(RuntimeAppScope.store),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.runtimeAuthHint, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    TextField(
                      key: const Key('store_phone_field'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: l10n.runtimePhoneLabel,
                        prefixIcon: const Icon(Icons.phone_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('store_pin_field'),
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
                        key: const Key('store_login_button'),
                        onPressed: auth.loading
                            ? null
                            : () async {
                                await ref
                                    .read(authControllerProvider.notifier)
                                    .loginWithPhonePin(
                                      phone: _phoneController.text,
                                      pin: _pinController.text,
                                      expectedRole: AuthRoleScope.owner,
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
                                l10n.loginButtonLabel(RuntimeAppScope.store),
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

class _StoreHomeScreen extends ConsumerWidget {
  const _StoreHomeScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final merchant = ref.watch(_storeMerchantProvider);
    final orders = ref.watch(_storeOrdersProvider);
    final analytics = ref.watch(_storeAnalyticsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle(RuntimeAppScope.store)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
            onPressed: () {
              ref.invalidate(_storeMerchantProvider);
              ref.invalidate(_storeOrdersProvider);
              ref.invalidate(_storeAnalyticsProvider);
            },
          ),
          IconButton(
            key: const Key('store_logout_button'),
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
          merchant.when(
            data: (value) => _SummaryHeroCard(
              title: _storeMerchantName(value, l10n),
              subtitle: _storeMerchantSubtitle(value, l10n),
              icon: Icons.storefront_rounded,
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _SummaryHeroCard(
              title: l10n.dashboardTitle(RuntimeAppScope.store),
              subtitle: l10n.storesLabel,
              icon: Icons.storefront_rounded,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _StoreProfileScreen(),
                  ),
                ),
                icon: const Icon(Icons.storefront_rounded),
                label: Text(l10n.runtimeOpenStoreProfileLabel),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _StoreOrdersScreen(),
                  ),
                ),
                icon: const Icon(Icons.receipt_long_rounded),
                label: Text(l10n.runtimeOpenOrdersLabel),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _StoreAnalyticsScreen(),
                  ),
                ),
                icon: const Icon(Icons.analytics_outlined),
                label: Text(l10n.runtimeOpenAnalyticsLabel),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _StoreProductsScreen(),
                  ),
                ),
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(l10n.runtimeOpenProductsLabel),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _StoreCategoriesScreen(),
                  ),
                ),
                icon: const Icon(Icons.category_outlined),
                label: Text(l10n.runtimeOpenCategoriesLabel),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _StoreDeliveryAgentsScreen(),
                  ),
                ),
                icon: const Icon(Icons.delivery_dining_rounded),
                label: Text(l10n.runtimeOpenDeliveryAgentsLabel),
              ),
            ],
          ),
          const SizedBox(height: 16),
          analytics.when(
            data: (value) => _SummaryMetricsCard(
              rows: [
                _MetricRow(
                  label: l10n.ordersLabel,
                  value:
                      '${_readInt(value, const ['activeOrders', 'openOrders', 'pendingOrders'])}',
                ),
                _MetricRow(
                  label: l10n.storesLabel,
                  value:
                      '${_readInt(value, const ['productsCount', 'activeProducts', 'itemsCount'])}',
                ),
              ],
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          orders.when(
            data: (items) => _RuntimeListCard(
              title: l10n.ordersLabel,
              emptyTitle: l10n.ordersEmptyTitle,
              emptySubtitle: l10n.ordersEmptySubtitle,
              items: items
                  .take(5)
                  .map(
                    (order) => _ListItemView(
                      title: _stringOf(
                        order['customerName'] ?? order['orderNumber'],
                        fallback: '#${_intOf(order['id'])}',
                      ),
                      subtitle: _stringOf(
                        order['status'],
                        fallback: _stringOf(order['deliveryStatus']),
                      ),
                      trailing: _stringOf(
                        order['total'],
                        fallback: _stringOf(order['grandTotal']),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.ordersLabel,
              emptyTitle: l10n.ordersEmptyTitle,
              emptySubtitle: l10n.ordersEmptySubtitle,
              items: const <_ListItemView>[],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreProfileScreen extends ConsumerWidget {
  const _StoreProfileScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final merchant = ref.watch(_storeMerchantProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.runtimeOpenStoreProfileLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          merchant.when(
            data: (value) {
              final merchantName = _storeMerchantName(value, l10n);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchantName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(_storeMerchantSubtitle(value, l10n)),
                      const SizedBox(height: 12),
                      Text(_stringOf(value?['workingHours'] ?? value?['type'])),
                      const SizedBox(height: 8),
                      Text(_stringOf(value?['phone'])),
                    ],
                  ),
                ),
              );
            },
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.runtimeOpenStoreProfileLabel,
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

class _StoreOrdersScreen extends ConsumerWidget {
  const _StoreOrdersScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final orders = ref.watch(_storeOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.runtimeOpenOrdersLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          orders.when(
            data: (items) {
              if (items.isEmpty) {
                return _RuntimeListCard(
                  title: l10n.ordersLabel,
                  emptyTitle: l10n.ordersEmptyTitle,
                  emptySubtitle: l10n.ordersEmptySubtitle,
                  items: const <_ListItemView>[],
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _StoreOrderActionCard(order: items[i]),
                    if (i != items.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            },
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.ordersLabel,
              emptyTitle: l10n.ordersEmptyTitle,
              emptySubtitle: l10n.ordersEmptySubtitle,
              items: const <_ListItemView>[],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreAnalyticsScreen extends ConsumerWidget {
  const _StoreAnalyticsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final analytics = ref.watch(_storeAnalyticsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.runtimeOpenAnalyticsLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          analytics.when(
            data: (value) => _SummaryMetricsCard(
              rows: [
                _MetricRow(
                  label: l10n.ordersLabel,
                  value:
                      '${_readInt(value, const ['activeOrders', 'openOrders', 'pendingOrders'])}',
                ),
                _MetricRow(
                  label: l10n.storesLabel,
                  value:
                      '${_readInt(value, const ['productsCount', 'activeProducts', 'itemsCount'])}',
                ),
              ],
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.runtimeOpenAnalyticsLabel,
              emptyTitle: l10n.runtimeEmptyTitle(
                l10n.runtimeOpenAnalyticsLabel,
              ),
              emptySubtitle: l10n.runtimeEmptySubtitle(
                l10n.runtimeOpenAnalyticsLabel,
              ),
              items: const <_ListItemView>[],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreProductsScreen extends ConsumerWidget {
  const _StoreProductsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final products = ref.watch(_storeProductsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.runtimeOpenProductsLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          products.when(
            data: (items) => _RuntimeListCard(
              title: l10n.runtimeProductsLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.runtimeProductsLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(
                l10n.runtimeProductsLabel,
              ),
              items: items
                  .map(
                    (product) => _ListItemView(
                      title: _stringOf(
                        product['name'],
                        fallback: '#${_intOf(product['id'])}',
                      ),
                      subtitle: _stringOf(
                        product['description'] ?? product['categoryName'],
                        fallback: _stringOf(product['status']),
                      ),
                      trailing: _stringOf(
                        product['price'],
                        fallback: _stringOf(product['discountedPrice']),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.runtimeProductsLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.runtimeProductsLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(
                l10n.runtimeProductsLabel,
              ),
              items: const <_ListItemView>[],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreCategoriesScreen extends ConsumerWidget {
  const _StoreCategoriesScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final categories = ref.watch(_storeCategoriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.runtimeOpenCategoriesLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          categories.when(
            data: (items) => _RuntimeListCard(
              title: l10n.runtimeCategoriesLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.runtimeCategoriesLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(
                l10n.runtimeCategoriesLabel,
              ),
              items: items
                  .map(
                    (category) => _ListItemView(
                      title: _stringOf(
                        category['name'],
                        fallback: '#${_intOf(category['id'])}',
                      ),
                      subtitle: _stringOf(
                        category['sortOrder'],
                        fallback: _stringOf(category['createdAt']),
                      ),
                      trailing: '#${_intOf(category['id'])}',
                    ),
                  )
                  .toList(growable: false),
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.runtimeCategoriesLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.runtimeCategoriesLabel),
              emptySubtitle: l10n.runtimeEmptySubtitle(
                l10n.runtimeCategoriesLabel,
              ),
              items: const <_ListItemView>[],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreDeliveryAgentsScreen extends ConsumerWidget {
  const _StoreDeliveryAgentsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final deliveryAgents = ref.watch(_storeDeliveryAgentsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.runtimeOpenDeliveryAgentsLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          deliveryAgents.when(
            data: (items) => _RuntimeListCard(
              title: l10n.runtimeOpenDeliveryAgentsLabel,
              emptyTitle: l10n.runtimeEmptyTitle(
                l10n.runtimeOpenDeliveryAgentsLabel,
              ),
              emptySubtitle: l10n.runtimeEmptySubtitle(
                l10n.runtimeOpenDeliveryAgentsLabel,
              ),
              items: items
                  .map(
                    (agent) => _ListItemView(
                      title: _stringOf(
                        agent['fullName'],
                        fallback: '#${_intOf(agent['id'])}',
                      ),
                      subtitle: _stringOf(
                        agent['phone'],
                        fallback: _stringOf(agent['createdAt']),
                      ),
                      trailing: '#${_intOf(agent['id'])}',
                    ),
                  )
                  .toList(growable: false),
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.runtimeOpenDeliveryAgentsLabel,
              emptyTitle: l10n.runtimeEmptyTitle(
                l10n.runtimeOpenDeliveryAgentsLabel,
              ),
              emptySubtitle: l10n.runtimeEmptySubtitle(
                l10n.runtimeOpenDeliveryAgentsLabel,
              ),
              items: const <_ListItemView>[],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreOrderActionCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;

  const _StoreOrderActionCard({required this.order});

  @override
  ConsumerState<_StoreOrderActionCard> createState() =>
      _StoreOrderActionCardState();
}

class _StoreOrderActionCardState extends ConsumerState<_StoreOrderActionCard> {
  static const _statusOptions = <String>[
    'accepted',
    'preparing',
    'ready_for_delivery',
    'delivered',
    'cancelled',
  ];

  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final order = widget.order;
    final orderId = _intOf(order['id']);
    final status = _stringOf(
      order['status'],
      fallback: _stringOf(order['deliveryStatus'], fallback: 'pending'),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _stringOf(
                order['customerName'] ?? order['orderNumber'],
                fallback: '#$orderId',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _stringOf(
                order['status'],
                fallback: _stringOf(order['deliveryStatus']),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final candidate in _statusOptions)
                  FilledButton.tonal(
                    onPressed: _submitting || candidate == status
                        ? null
                        : () => _updateStatus(context, orderId, candidate),
                    child: Text(candidate),
                  ),
                OutlinedButton.icon(
                  onPressed: _submitting || orderId <= 0
                      ? null
                      : () => _assignDelivery(context, orderId),
                  icon: const Icon(Icons.delivery_dining_rounded),
                  label: Text(l10n.runtimeAssignDeliveryLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(
    BuildContext context,
    int orderId,
    String status,
  ) async {
    if (orderId <= 0) return;
    await _runAction(
      context,
      () =>
          ref.read(_storeRuntimeApiProvider).updateOrderStatus(orderId, status),
    );
  }

  Future<void> _assignDelivery(BuildContext context, int orderId) async {
    final l10n = context.l10n;
    final agents = await ref.read(_storeDeliveryAgentsProvider.future);
    if (!mounted || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (agents.isEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            l10n.runtimeEmptySubtitle(l10n.runtimeOpenDeliveryAgentsLabel),
          ),
        ),
      );
      return;
    }

    final selectedId = await showModalBottomSheet<int>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(l10n.runtimeAssignDeliveryLabel),
                subtitle: Text(l10n.runtimeOpenDeliveryAgentsLabel),
              ),
              for (final agent in agents)
                ListTile(
                  leading: const Icon(Icons.delivery_dining_rounded),
                  title: Text(
                    _stringOf(
                      agent['fullName'],
                      fallback: '#${_intOf(agent['id'])}',
                    ),
                  ),
                  subtitle: Text(_stringOf(agent['phone'], fallback: '-')),
                  onTap: () => Navigator.of(context).pop(_intOf(agent['id'])),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || !context.mounted || selectedId == null || selectedId <= 0) {
      return;
    }
    await _runAction(
      context,
      () => ref
          .read(_storeRuntimeApiProvider)
          .assignDelivery(orderId, selectedId),
    );
  }

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() {
      _submitting = true;
    });
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(_storeOrdersProvider);
      ref.invalidate(_storeAnalyticsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.runtimeActionCompletedLabel)),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.runtimeActionFailedLabel)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}

class _StoreRuntimeApi {
  final Dio _dio;

  const _StoreRuntimeApi(this._dio);

  Future<Map<String, dynamic>?> merchant() async {
    final response = await _dio.get('/api/owner/merchant');
    return _extractObject(response.data, const ['merchant', 'item', 'data']);
  }

  Future<List<Map<String, dynamic>>> currentOrders() async {
    final response = await _dio.get('/api/owner/orders/current');
    return _extractList(response.data, const ['orders', 'items', 'data']);
  }

  Future<Map<String, dynamic>?> analytics() async {
    final response = await _dio.get('/api/owner/analytics');
    return _extractObject(response.data, const ['analytics', 'data', 'item']);
  }

  Future<List<Map<String, dynamic>>> products() async {
    final response = await _dio.get('/api/owner/products');
    return _extractList(response.data, const ['products', 'items', 'data']);
  }

  Future<List<Map<String, dynamic>>> categories() async {
    final response = await _dio.get('/api/owner/categories');
    return _extractList(response.data, const ['categories', 'items', 'data']);
  }

  Future<List<Map<String, dynamic>>> deliveryAgents() async {
    final response = await _dio.get('/api/owner/delivery-agents');
    return _extractList(response.data, const ['agents', 'items', 'data']);
  }

  Future<void> updateOrderStatus(int orderId, String status) async {
    await _dio.patch(
      '/api/owner/orders/$orderId/status',
      data: {'status': status},
    );
  }

  Future<void> assignDelivery(int orderId, int deliveryUserId) async {
    await _dio.patch(
      '/api/owner/orders/$orderId/assign-delivery',
      data: {'deliveryUserId': deliveryUserId},
    );
  }
}

String _storeMerchantName(
  Map<String, dynamic>? merchant,
  CoreAppLocalizations l10n,
) {
  return _stringOf(
    merchant?['name'],
    fallback: l10n.dashboardTitle(RuntimeAppScope.store),
  );
}

String _storeMerchantSubtitle(
  Map<String, dynamic>? merchant,
  CoreAppLocalizations l10n,
) {
  return _stringOf(
    merchant?['description'] ?? merchant?['workingHours'],
    fallback: l10n.storesLabel,
  );
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

int _intOf(dynamic value) {
  return int.tryParse('${value ?? ''}') ?? 0;
}

int _readInt(Map<String, dynamic>? data, List<String> keys) {
  if (data == null) return 0;
  for (final key in keys) {
    final value = int.tryParse('${data[key] ?? ''}');
    if (value != null) return value;
  }
  return 0;
}
