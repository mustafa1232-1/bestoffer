import 'package:core_auth/core_auth.dart';
import 'package:core_design_system/core_design_system.dart';
import 'package:core_localization/core_localization.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_storage/core_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _deliveryRuntimeApiProvider = Provider<_DeliveryRuntimeApi>((ref) {
  return _DeliveryRuntimeApi(ref.watch(runtimeDioProvider));
});

final _deliveryCurrentOrdersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      final auth = ref.watch(authControllerProvider);
      if (auth.user == null || !auth.isDelivery) {
        return const <Map<String, dynamic>>[];
      }
      try {
        return await ref.read(_deliveryRuntimeApiProvider).currentOrders();
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    });

final _deliveryAnalyticsProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isDelivery) {
    return null;
  }
  try {
    return await ref.read(_deliveryRuntimeApiProvider).analytics();
  } catch (_) {
    return null;
  }
});

void runAppDelivery() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        appSettingsStorageScopeProvider.overrideWithValue('delivery'),
      ],
      child: const MaslakiDeliveryApp(),
    ),
  );
}

class MaslakiDeliveryApp extends ConsumerStatefulWidget {
  final bool skipBootstrap;
  final bool useNetworkAuth;

  const MaslakiDeliveryApp({
    super.key,
    this.skipBootstrap = false,
    this.useNetworkAuth = true,
  });

  @override
  ConsumerState<MaslakiDeliveryApp> createState() => _MaslakiDeliveryAppState();
}

class _MaslakiDeliveryAppState extends ConsumerState<MaslakiDeliveryApp>
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
    ref.invalidate(_deliveryCurrentOrdersProvider);
    ref.invalidate(_deliveryAnalyticsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);
    final auth = ref.watch(authControllerProvider);

    if (auth.isAuthed && !auth.isDelivery && !_roleMismatchLogoutQueued) {
      _roleMismatchLogoutQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(authControllerProvider.notifier).logout();
        _roleMismatchLogoutQueued = false;
      });
    } else if (!auth.isAuthed || auth.isDelivery) {
      _roleMismatchLogoutQueued = false;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.deliveryAppTitle,
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
          ? const _DeliverySplashScreen()
          : auth.isAuthed && auth.isDelivery
          ? const _DeliveryHomeScreen()
          : (widget.useNetworkAuth
                ? const _DeliveryNetworkLoginScreen()
                : const _RoleLoginScreen(
                    scope: RuntimeAppScope.delivery,
                    role: AuthRoleScope.delivery,
                    loginKey: Key('delivery_login_button'),
                  )),
    );
  }
}

class _DeliverySplashScreen extends StatelessWidget {
  const _DeliverySplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_shipping_rounded,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.deliveryAppTitle,
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
        ref.read(appSettingsControllerProvider.notifier).setLocale(Locale(code));
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
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.34),
          ),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 17),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
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

class _DeliveryNetworkLoginScreen extends ConsumerStatefulWidget {
  const _DeliveryNetworkLoginScreen();

  @override
  ConsumerState<_DeliveryNetworkLoginScreen> createState() =>
      _DeliveryNetworkLoginScreenState();
}

class _DeliveryNetworkLoginScreenState
    extends ConsumerState<_DeliveryNetworkLoginScreen> {
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
                      l10n.roleLoginTitle(RuntimeAppScope.delivery),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.runtimeAuthHint, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    TextField(
                      key: const Key('delivery_phone_field'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: l10n.runtimePhoneLabel,
                        prefixIcon: const Icon(Icons.phone_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('delivery_pin_field'),
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
                        key: const Key('delivery_login_button'),
                        onPressed: auth.loading
                            ? null
                            : () async {
                                await ref
                                    .read(authControllerProvider.notifier)
                                    .loginWithPhonePin(
                                      phone: _phoneController.text,
                                      pin: _pinController.text,
                                      expectedRole: AuthRoleScope.delivery,
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
                                l10n.loginButtonLabel(RuntimeAppScope.delivery),
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

class _DeliveryHomeScreen extends ConsumerWidget {
  const _DeliveryHomeScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final orders = ref.watch(_deliveryCurrentOrdersProvider);
    final analytics = ref.watch(_deliveryAnalyticsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle(RuntimeAppScope.delivery)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
            onPressed: () {
              ref.invalidate(_deliveryCurrentOrdersProvider);
              ref.invalidate(_deliveryAnalyticsProvider);
            },
          ),
          IconButton(
            key: const Key('delivery_logout_button'),
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
          const _SummaryHeroCard(
            titleIcon: Icons.local_shipping_rounded,
            titleKey: RuntimeAppScope.delivery,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _DeliveryOrdersScreen(),
                  ),
                ),
                icon: const Icon(Icons.receipt_long_rounded),
                label: Text(l10n.runtimeOpenOrdersLabel),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _DeliveryAnalyticsScreen(),
                  ),
                ),
                icon: const Icon(Icons.analytics_outlined),
                label: Text(l10n.runtimeOpenAnalyticsLabel),
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
                      '${_readInt(value, const ['activeOrders', 'pendingOrders', 'todayOrders'])}',
                ),
                _MetricRow(
                  label: l10n.runtimeTodayLabel,
                  value:
                      '${_readInt(value, const ['deliveredToday', 'completedToday', 'todayDelivered'])}',
                ),
                _MetricRow(
                  label: l10n.runtimeTaxiFareFieldLabel,
                  value: _currencyText(
                    _readInt(value, const [
                      'earningsTodayIqd',
                      'todayEarningsIqd',
                      'netTodayIqd',
                    ]),
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
              title: l10n.ordersLabel,
              emptyTitle: l10n.ordersEmptyTitle,
              emptySubtitle: l10n.ordersEmptySubtitle,
              items: items
                  .take(6)
                  .map(
                    (order) => _ListItemView(
                      title: _stringOf(
                        order['customerName'] ?? order['customerNameAr'],
                        fallback: _stringOf(
                          order['orderNumber'],
                          fallback: '#${_intOf(order['id'])}',
                        ),
                      ),
                      subtitle: _stringOf(
                        order['merchantName'] ?? order['pickupLabel'],
                        fallback: _stringOf(order['status']),
                      ),
                      trailing: _stringOf(
                        order['status'],
                        fallback: _stringOf(order['deliveryStatus']),
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

class _DeliveryOrdersScreen extends ConsumerWidget {
  const _DeliveryOrdersScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final orders = ref.watch(_deliveryCurrentOrdersProvider);
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
                    _DeliveryOrderCard(order: items[i]),
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

class _DeliveryAnalyticsScreen extends ConsumerWidget {
  const _DeliveryAnalyticsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final analytics = ref.watch(_deliveryAnalyticsProvider);
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
                      '${_readInt(value, const ['activeOrders', 'pendingOrders', 'todayOrders'])}',
                ),
                _MetricRow(
                  label: l10n.runtimeTodayLabel,
                  value:
                      '${_readInt(value, const ['deliveredToday', 'completedToday', 'todayDelivered'])}',
                ),
                _MetricRow(
                  label: l10n.runtimeTaxiFareFieldLabel,
                  value: _currencyText(
                    _readInt(value, const [
                      'earningsTodayIqd',
                      'todayEarningsIqd',
                      'netTodayIqd',
                    ]),
                  ),
                ),
              ],
            ),
            loading: () => const _LoadingCard(),
            error: (_, _) => _RuntimeListCard(
              title: l10n.runtimeOpenAnalyticsLabel,
              emptyTitle: l10n.runtimeEmptyTitle(l10n.runtimeOpenAnalyticsLabel),
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

class _DeliveryOrderCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;

  const _DeliveryOrderCard({required this.order});

  @override
  ConsumerState<_DeliveryOrderCard> createState() => _DeliveryOrderCardState();
}

class _DeliveryOrderCardState extends ConsumerState<_DeliveryOrderCard> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final order = widget.order;
    final status = _stringOf(
      order['status'],
      fallback: _stringOf(order['deliveryStatus'], fallback: 'pending'),
    ).toLowerCase();
    final action = _resolveDeliveryAction(status, l10n);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _stringOf(
                order['customerName'] ?? order['customerNameAr'],
                fallback: _stringOf(
                  order['orderNumber'],
                  fallback: '#${_intOf(order['id'])}',
                ),
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _stringOf(
                order['merchantName'] ?? order['pickupLabel'],
                fallback: _stringOf(order['status']),
              ),
            ),
            const SizedBox(height: 6),
            Text(_stringOf(order['status'], fallback: '-')),
            if (action != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _submitting
                    ? null
                    : () => _applyAction(context, order, action.$1),
                icon: Icon(action.$2),
                label: Text(action.$3),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (String, IconData, String)? _resolveDeliveryAction(
    String status,
    CoreAppLocalizations l10n,
  ) {
    if (status.contains('pending') || status.contains('request')) {
      return ('accept', Icons.check_circle_outline_rounded, l10n.runtimeClaimOrderLabel);
    }
    if (status.contains('ready') || status.contains('accepted') || status.contains('claimed')) {
      return ('start', Icons.route_rounded, l10n.runtimeStartDeliveryLabel);
    }
    if (status.contains('on_the_way')) {
      return ('arrived', Icons.place_rounded, l10n.runtimeMarkArrivedLabel);
    }
    if (status.contains('arrived')) {
      return ('delivered', Icons.done_all_rounded, l10n.runtimeDeliveredLabel);
    }
    return null;
  }

  Future<void> _applyAction(
    BuildContext context,
    Map<String, dynamic> order,
    String action,
  ) async {
    final orderId = _intOf(order['id']);
    if (orderId <= 0) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() {
      _submitting = true;
    });
    try {
      switch (action) {
        case 'accept':
          await ref.read(_deliveryRuntimeApiProvider).acceptOrder(orderId);
          break;
        case 'start':
          await ref.read(_deliveryRuntimeApiProvider).startOrder(orderId);
          break;
        case 'arrived':
          await ref.read(_deliveryRuntimeApiProvider).markArrived(orderId);
          break;
        case 'delivered':
          await ref.read(_deliveryRuntimeApiProvider).markDelivered(orderId);
          break;
      }
      if (!mounted) return;
      ref.invalidate(_deliveryCurrentOrdersProvider);
      ref.invalidate(_deliveryAnalyticsProvider);
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

class _DeliveryRuntimeApi {
  final Dio _dio;

  const _DeliveryRuntimeApi(this._dio);

  Future<List<Map<String, dynamic>>> currentOrders() async {
    final response = await _dio.get('/api/delivery/orders/current');
    return _extractList(response.data, const ['orders', 'items', 'data']);
  }

  Future<Map<String, dynamic>?> analytics() async {
    final response = await _dio.get('/api/delivery/analytics');
    return _extractObject(response.data, const [
      'analytics',
      'data',
      'summary',
    ]);
  }

  Future<Map<String, dynamic>?> acceptOrder(int orderId) async {
    final response = await _dio.patch('/api/delivery/orders/$orderId/claim');
    return _extractObject(response.data, const ['data', 'order', 'item']);
  }

  Future<Map<String, dynamic>?> startOrder(int orderId) async {
    final response = await _dio.patch('/api/delivery/orders/$orderId/start');
    return _extractObject(response.data, const ['data', 'order', 'item']);
  }

  Future<Map<String, dynamic>?> markArrived(int orderId) async {
    final response = await _dio.patch('/api/delivery/orders/$orderId/arrived');
    return _extractObject(response.data, const ['data', 'order', 'item']);
  }

  Future<Map<String, dynamic>?> markDelivered(int orderId) async {
    final response = await _dio.patch('/api/delivery/orders/$orderId/delivered');
    return _extractObject(response.data, const ['data', 'order', 'item']);
  }
}

class _SummaryHeroCard extends StatelessWidget {
  final IconData titleIcon;
  final RuntimeAppScope titleKey;

  const _SummaryHeroCard({required this.titleIcon, required this.titleKey});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(radius: 26, child: Icon(titleIcon)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.dashboardTitle(titleKey),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(context.l10n.ordersLabel),
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

String _currencyText(int amount) {
  if (amount <= 0) return '-';
  return '$amount IQD';
}
