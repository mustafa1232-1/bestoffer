import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../orders/models/order_model.dart';
import '../../orders/ui/order_chat_screen.dart';
import '../../orders/ui/widgets/order_item_widgets.dart';
import '../../settings/ui/pages/settings_account_screen.dart';
import '../../support/ui/support_tickets_screen.dart';
import '../data/delivery_api.dart';
import '../state/delivery_controller.dart';
import '../state/grouped_delivery_controller.dart';
import 'courier_pages.dart';
import 'delivery_reports_screens.dart';
import 'delivery_reconciliation_sheets.dart';
import 'grouped_delivery_screens.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

enum _DeliveryTab { dashboard, current, history, profile }

Future<void> _openMapTarget({
  double? latitude,
  double? longitude,
  required String label,
  String? query,
}) async {
  final uri = latitude != null && longitude != null
      ? Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
        )
      : Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query ?? label)}',
        );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class DeliveryDashboardScreen extends ConsumerStatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  ConsumerState<DeliveryDashboardScreen> createState() =>
      _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState
    extends ConsumerState<DeliveryDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _DeliveryTab activeTab = _DeliveryTab.dashboard;
  DateTime? historyDateFilter;
  DateTime? _lastBackPressAt;
  late final DeliveryController _deliveryController;

  /// Hardware/gesture back handling for the dashboard root:
  /// 1. close an open drawer, else
  /// 2. return to the dashboard tab from any other tab, else
  /// 3. require a second back press within 2s to leave the app.
  void _handleDashboardPop() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen == true) {
      scaffold!.closeDrawer();
      return;
    }
    if (scaffold?.isEndDrawerOpen == true) {
      scaffold!.closeEndDrawer();
      return;
    }
    if (activeTab != _DeliveryTab.dashboard) {
      setState(() => activeTab = _DeliveryTab.dashboard);
      return;
    }
    final now = DateTime.now();
    if (_lastBackPressAt != null &&
        now.difference(_lastBackPressAt!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPressAt = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          context.lt(
            ar: 'اضغط مرة أخرى للخروج',
            en: 'Press back again to exit',
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _deliveryController = ref.read(deliveryControllerProvider.notifier);
    Future.microtask(() async {
      if (!mounted) return;
      await _deliveryController.bootstrap(includeExtended: false);
      if (!mounted) return;
      _deliveryController.startLiveOrders();
    });
  }

  void _showCurrentOrders() {
    setState(() => activeTab = _DeliveryTab.current);
    Future.microtask(
      () => ref
          .read(groupedDeliveryControllerProvider.notifier)
          .bootstrap(silent: true),
    );
  }

  void _showProfile() {
    setState(() => activeTab = _DeliveryTab.profile);
    Future.microtask(() => _deliveryController.bootstrap());
  }

  @override
  void dispose() {
    _deliveryController.stopLiveOrders();
    super.dispose();
  }

  String _tabTitle() {
    final l10n = context.l10n;
    switch (activeTab) {
      case _DeliveryTab.dashboard:
        return l10n.deliveryDashboardTitle;
      case _DeliveryTab.current:
        return l10n.deliveryCurrentOrders;
      case _DeliveryTab.history:
        return l10n.deliveryOrderHistory;
      case _DeliveryTab.profile:
        return l10n.drawerProfile;
    }
  }

  Future<void> _openAccountSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsAccountScreen()));
  }

  Future<void> _openSupportSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SupportTicketsScreen()));
  }

  Future<void> _pickHistoryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: historyDateFilter ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: Localizations.localeOf(context),
    );
    if (picked == null) return;
    setState(() => historyDateFilter = picked);
    final date = intl.DateFormat('yyyy-MM-dd').format(picked);
    await _deliveryController.bootstrap(
      historyDate: date,
      includeExtended: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(deliveryControllerProvider);
    final auth = ref.watch(authControllerProvider);

    ref.listen<DeliveryState>(deliveryControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      if (next.lastArchiveMessage != null &&
          next.lastArchiveMessage != prev?.lastArchiveMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.lastArchiveMessage!)));
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleDashboardPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.brandIvory,
        // End-day readiness is fetched from backend so we can block closure
        // before the submit request if the delivery still owes the store.
        key: _scaffoldKey,
        drawer: AppUserDrawer(
          title: _tabTitle(),
          subtitle: l10n.drawerDeliverySub,
          showProfileButton: false,
          showCommunitySection: false,
          items: [
            AppUserDrawerItem(
              icon: Icons.campaign_outlined,
              label: context.lt(
                ar: 'الطلبات المعيّنة',
                en: 'Assigned deliveries',
              ),
              subtitle: context.lt(
                ar: 'تظهر الطلبات المعيّنة لك فقط مع التحديث اللحظي.',
                en: 'Only your assigned orders are shown with live updates.',
              ),
              onTap: (_) async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CourierOrdersNewPage(),
                  ),
                );
              },
            ),
            AppUserDrawerItem(
              icon: Icons.dashboard_outlined,
              label: l10n.deliveryDashboardTitle,
              onTap: (_) async =>
                  setState(() => activeTab = _DeliveryTab.dashboard),
            ),
            AppUserDrawerItem(
              icon: Icons.local_shipping_outlined,
              label: l10n.deliveryCurrentOrders,
              onTap: (_) async => _showCurrentOrders(),
            ),
            AppUserDrawerItem(
              icon: Icons.history_rounded,
              label: l10n.deliveryOrderHistory,
              onTap: (_) async =>
                  setState(() => activeTab = _DeliveryTab.history),
            ),
            AppUserDrawerItem(
              icon: Icons.person_outline_rounded,
              label: l10n.drawerProfile,
              onTap: (_) async => _showProfile(),
            ),
            AppUserDrawerItem(
              icon: Icons.emoji_events_outlined,
              label: l10n.deliveryCourierCompetitions,
              subtitle: l10n.deliveryCourierCompetitionsSubtitle,
              onTap: (_) async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CourierCompetitionsPage(),
                  ),
                );
              },
            ),
            AppUserDrawerItem(
              icon: Icons.payments_outlined,
              label: l10n.deliveryCourierEarningsTitle,
              onTap: (_) async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DeliveryEarningsScreen(),
                  ),
                );
              },
            ),
            AppUserDrawerItem(
              icon: Icons.insights_outlined,
              label: l10n.deliveryCourierReportsTitle,
              onTap: (_) async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CourierReportsPage(),
                  ),
                );
              },
            ),
            AppUserDrawerItem(
              icon: Icons.refresh_rounded,
              label: l10n.drawerRefresh,
              onTap: (_) async => ref
                  .read(deliveryControllerProvider.notifier)
                  .bootstrap(includeExtended: false),
            ),
            AppUserDrawerItem(
              icon: Icons.archive_outlined,
              label: l10n.deliveryEndDay,
              onTap: (_) async {
                await ref.read(deliveryControllerProvider.notifier).endDay();
              },
            ),
          ],
        ),
        appBar: AppBar(
          backgroundColor: AppColors.brandIvory,
          foregroundColor: AppColors.brandNavy,
          surfaceTintColor: Colors.transparent,
          title: Text(_tabTitle()),
          actions: [
            if (activeTab == _DeliveryTab.dashboard)
              IconButton(
                key: const Key('delivery_online_toggle'),
                onPressed: state.saving
                    ? null
                    : () => ref
                          .read(deliveryControllerProvider.notifier)
                          .setOnline(!state.isOnline),
                icon: Icon(
                  state.isOnline
                      ? Icons.wifi_tethering_rounded
                      : Icons.power_settings_new_rounded,
                  color: state.isOnline
                      ? AppColors.brandGreen
                      : Colors.red.shade700,
                ),
                tooltip: context.lt(
                  ar: state.isOnline ? 'أنت متصل' : 'أنت غير متصل',
                  en: state.isOnline ? 'You are online' : 'You are offline',
                ),
              ),
            if (activeTab == _DeliveryTab.history)
              IconButton(
                onPressed: _pickHistoryDate,
                icon: const Icon(Icons.event_outlined),
                tooltip: l10n.deliveryFilterByDate,
              ),
            const NotificationsBellButton(),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => ref
              .read(deliveryControllerProvider.notifier)
              .bootstrap(includeExtended: false),
          child: Theme(
            data: Theme.of(context).copyWith(
              cardTheme: CardThemeData(
                color: Colors.white.withValues(alpha: 0.96),
                surfaceTintColor: Colors.transparent,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: AppColors.brandGold.withValues(alpha: 0.28),
                  ),
                ),
              ),
            ),
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : _buildDeliveryTabBody(state: state, auth: auth),
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryTabBody({
    required DeliveryState state,
    required AuthState auth,
  }) {
    switch (activeTab) {
      case _DeliveryTab.dashboard:
        return _buildDashboardBody(state);
      case _DeliveryTab.current:
        return _buildCurrentOrdersBody(state);
      case _DeliveryTab.history:
        return _buildHistoryBody(state);
      case _DeliveryTab.profile:
        return _buildProfileBody(state: state, auth: auth);
    }
  }

  Widget _buildEndDayReadinessCard(DeliveryState state) {
    final readiness = state.endDayReadiness;
    if (readiness.isEmpty || readiness['canEndDay'] == true) {
      return const SizedBox.shrink();
    }

    final outstanding =
        num.tryParse('${readiness['outstandingAmount'] ?? 0}') ?? 0;
    final totalAppDue = num.tryParse('${readiness['totalAppDue'] ?? 0}') ?? 0;
    final totalDifferenceDue =
        num.tryParse('${readiness['totalDifferenceDue'] ?? 0}') ?? 0;
    final blockingReasonAr = '${readiness['blockingReasonAr'] ?? ''}'.trim();
    final blockingReasonEn = '${readiness['blockingReasonEn'] ?? ''}'.trim();
    final openSettlements = List<dynamic>.from(
      readiness['openSettlements'] as List? ?? const [],
    );

    return Card(
      color: Colors.red.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.lt(
                ar: 'لا يمكن إنهاء اليوم الآن',
                en: 'You cannot close the day yet',
              ),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              context.lt(
                ar: 'هناك ذمة/ذمم بانتظار الاستلام بقيمة ${formatIqd(outstanding)}.',
                en: 'There is still an open settlement total of ${formatIqd(outstanding)}.',
              ),
            ),
            if (blockingReasonAr.isNotEmpty || blockingReasonEn.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (blockingReasonAr.isNotEmpty) blockingReasonAr,
                  if (blockingReasonEn.isNotEmpty) blockingReasonEn,
                ].join(' / '),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              context.lt(
                ar: 'ذمة التطبيق: ${formatIqd(totalAppDue)}',
                en: 'App due: ${formatIqd(totalAppDue)}',
              ),
            ),
            Text(
              context.lt(
                ar: 'الفروقات غير المغلقة: ${formatIqd(totalDifferenceDue)}',
                en: 'Unresolved differences: ${formatIqd(totalDifferenceDue)}',
              ),
            ),
            if (openSettlements.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...openSettlements
                  .take(3)
                  .map(
                    (row) => Text(
                      context.lt(
                        ar: 'طلب تسوية #${row['id']} - ${formatIqd(row['appDueFromDelivery'] ?? row['app_due_from_delivery'] ?? row['totalAmount'] ?? row['total_amount'] ?? 0)}',
                        en: 'Settlement #${row['id']} - ${formatIqd(row['appDueFromDelivery'] ?? row['app_due_from_delivery'] ?? row['totalAmount'] ?? row['total_amount'] ?? 0)}',
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardBody(DeliveryState state) {
    final metrics = _CourierDashboardMetrics.fromState(state);
    final month = _DeliveryPeriod.fromMap(state.analytics['month']);
    final kpis = _extractDashboardKpis(state.dashboardV2);
    final appDue = _readDouble(kpis, const ['appDueTotal', 'app_due_total']);
    final monthEarnings = _readDouble(kpis, const [
      'monthEarnings',
      'month_earnings',
    ]);
    final openSettlements = _readInt(kpis, const [
      'openSettlements',
      'open_settlements',
    ]);
    final serviceFees = _readDouble(kpis, const [
      'serviceFeeTotal',
      'service_fee_total',
    ]);

    void openEarnings() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DeliveryEarningsScreen()),
    );

    void openReconciliation() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DeliveryReconciliationScreen(),
      ),
    );

    return SingleChildScrollView(
      key: const Key('delivery_home_summary'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DashboardSectionTitle(
            title: context.lt(ar: 'الملخص المالي', en: 'Financial summary'),
            subtitle: context.lt(
              ar: 'كل بطاقة تفتح تقريرها التفصيلي',
              en: 'Each card opens its detailed report',
            ),
          ),
          const SizedBox(height: 12),
          _DeliveryCardGrid(
            children: [
              _DeliveryHomeCard(
                key: const Key('delivery_home_today_earnings'),
                icon: Icons.payments_outlined,
                label: context.lt(ar: 'أرباح اليوم', en: 'Today earnings'),
                value: metrics.hasTodayEarnings
                    ? formatIqd(metrics.todayFees)
                    : '—',
                hint: context.lt(ar: 'أجور التوصيل', en: 'Delivery fees'),
                color: AppColors.brandGreen,
                onTap: openEarnings,
              ),
              _DeliveryHomeCard(
                key: const Key('delivery_home_app_due'),
                icon: Icons.account_balance_wallet_outlined,
                label: context.lt(ar: 'ذمة التطبيق', en: 'App due'),
                value:
                    kpis.containsKey('appDueTotal') ||
                        kpis.containsKey('app_due_total')
                    ? formatIqd(appDue)
                    : '—',
                hint: context.lt(ar: 'الصافي المطلوب', en: 'Net amount due'),
                color: AppColors.brandGold,
                onTap: openReconciliation,
              ),
              _DeliveryHomeCard(
                key: const Key('delivery_home_open_settlements'),
                icon: Icons.receipt_long_outlined,
                label: context.lt(ar: 'تسويات مفتوحة', en: 'Open settlements'),
                value:
                    kpis.containsKey('openSettlements') ||
                        kpis.containsKey('open_settlements')
                    ? '$openSettlements'
                    : '—',
                hint: context.lt(ar: 'بانتظار المراجعة', en: 'Awaiting review'),
                color: Colors.deepOrange,
                onTap: openReconciliation,
              ),
              _DeliveryHomeCard(
                key: const Key('delivery_home_month_earnings'),
                icon: Icons.calendar_month_outlined,
                label: context.lt(ar: 'أرباح الشهر', en: 'Month earnings'),
                value:
                    kpis.containsKey('monthEarnings') ||
                        kpis.containsKey('month_earnings')
                    ? formatIqd(monthEarnings)
                    : state.analytics.containsKey('month')
                    ? formatIqd(month.deliveryFees)
                    : '—',
                hint: context.lt(ar: 'الشهر الحالي', en: 'Current month'),
                color: AppColors.brandNavy,
                onTap: openEarnings,
              ),
              _DeliveryHomeCard(
                key: const Key('delivery_home_service_fees'),
                icon: Icons.price_check_outlined,
                label: context.lt(ar: 'رسوم الخدمة', en: 'Service fees'),
                value:
                    kpis.containsKey('serviceFeeTotal') ||
                        kpis.containsKey('service_fee_total')
                    ? formatIqd(serviceFees)
                    : '—',
                hint: context.lt(
                  ar: 'المجمعة للتطبيق',
                  en: 'Collected for app',
                ),
                color: Colors.teal.shade700,
                onTap: openReconciliation,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _DashboardSectionTitle(
            title: context.lt(ar: 'الطلبات', en: 'Orders'),
            subtitle: context.lt(
              ar: 'افتح القائمة الكاملة لكل حالة',
              en: 'Open the full list for each status',
            ),
          ),
          const SizedBox(height: 12),
          _DeliveryCardGrid(
            children: [
              _DeliveryHomeCard(
                key: const Key('delivery_home_current'),
                icon: Icons.local_shipping_rounded,
                label: context.lt(ar: 'الطلبات الحالية', en: 'Current orders'),
                value: metrics.hasAllOrderCounts
                    ? '${metrics.currentOrders}'
                    : '—',
                hint: context.lt(ar: 'قيد التنفيذ', en: 'In progress'),
                color: AppColors.brandGreen,
                onTap: _showCurrentOrders,
              ),
              _DeliveryHomeCard(
                key: const Key('delivery_home_completed'),
                icon: Icons.task_alt_rounded,
                label: context.lt(
                  ar: 'الطلبات المنتهية',
                  en: 'Completed orders',
                ),
                value: metrics.hasAllOrderCounts
                    ? '${metrics.completedOrders}'
                    : '—',
                hint: context.lt(
                  ar: 'كل الطلبات المكتملة',
                  en: 'All completed',
                ),
                color: AppColors.brandNavy,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CourierOrdersCompletedPage(),
                  ),
                ),
              ),
              _DeliveryHomeCard(
                key: const Key('delivery_home_cancelled'),
                icon: Icons.cancel_outlined,
                label: context.lt(
                  ar: 'الطلبات الملغية',
                  en: 'Cancelled orders',
                ),
                value: metrics.hasAllOrderCounts
                    ? '${metrics.cancelledOrders}'
                    : '—',
                hint: context.lt(
                  ar: 'الملغية والمتعثرة',
                  en: 'Cancelled and failed',
                ),
                color: Colors.red.shade700,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CourierOrdersCancelledPage(),
                  ),
                ),
              ),
              _DeliveryHomeCard(
                key: const Key('delivery_home_all_orders'),
                icon: Icons.inventory_2_outlined,
                label: context.lt(ar: 'إجمالي الطلبات', en: 'All orders'),
                value: metrics.hasAllOrderCounts
                    ? '${metrics.totalOrders}'
                    : '—',
                hint: context.lt(ar: 'السجل الكامل', en: 'Full order history'),
                color: AppColors.brandGold,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CourierOrdersAllPage(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentOrdersBody(DeliveryState state) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const GroupedDeliveryDashboardSection(),
        _SectionTitle(l10n.deliveryCurrentOrders),
        if (state.currentOrders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(l10n.deliveryNoCurrentOrders),
          )
        else
          ...state.currentOrders.map((o) => DeliveryCurrentOrderCard(order: o)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildHistoryBody(DeliveryState state) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ActionCard(
          title: l10n.deliveryHistoryFilter,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  historyDateFilter == null
                      ? l10n.deliveryAllDays
                      : intl.DateFormat(
                          'yyyy-MM-dd',
                        ).format(historyDateFilter!),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickHistoryDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(l10n.deliveryChooseDay),
              ),
              const SizedBox(width: 8),
              if (historyDateFilter != null)
                TextButton(
                  onPressed: () async {
                    setState(() => historyDateFilter = null);
                    await ref
                        .read(deliveryControllerProvider.notifier)
                        .bootstrap(includeExtended: false);
                  },
                  child: Text(l10n.commonClear),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionTitle(l10n.deliveryArchivedOrders),
        if (state.historyOrders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(l10n.deliveryNoArchivedOrders),
          )
        else
          ...state.historyOrders.map((o) => _HistoryOrderCard(order: o)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildProfileBody({
    required DeliveryState state,
    required AuthState auth,
  }) {
    final l10n = context.l10n;
    final user = auth.user;
    final metrics = _CourierDashboardMetrics.fromState(state);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ActionCard(
          title: l10n.drawerProfile,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 20,
                  backgroundImage: user?.imageUrl?.isNotEmpty == true
                      ? AppCachedImageProvider(user!.imageUrl!)
                      : null,
                  child: user?.imageUrl?.isNotEmpty == true
                      ? null
                      : const Icon(Icons.person_outline),
                ),
                title: Text(user?.fullName ?? '-'),
                subtitle: Text(user?.phone ?? '-'),
              ),
              Text(
                l10n.deliveryProfileAddress(
                  (user?.block ?? '-').toString(),
                  (user?.buildingNumber ?? '-').toString(),
                  (user?.apartment ?? '-').toString(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.deliveryProfileCompletedToday(
                  metrics.hasDayAnalytics
                      ? metrics.completedToday.toString()
                      : '—',
                ),
              ),
              Text(
                l10n.deliveryProfileFeesToday(
                  metrics.hasTodayEarnings ? formatIqd(metrics.todayFees) : '—',
                ),
              ),
              Text(
                l10n.deliveryProfileRatingToday(
                  metrics.hasDayAnalytics
                      ? metrics.rating.toStringAsFixed(1)
                      : '—',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DeliveryAvailabilityCard(
          state: state,
          onChanged: (value) =>
              ref.read(deliveryControllerProvider.notifier).setOnline(value),
        ),
        const SizedBox(height: 8),
        _DeliveryEarningsKpiCard(
          state: state,
          onOpenEarnings: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DeliveryEarningsScreen(),
            ),
          ),
          onEndDay: state.saving || state.endDayReadiness['canEndDay'] == false
              ? null
              : () => ref.read(deliveryControllerProvider.notifier).endDay(),
        ),
        const SizedBox(height: 8),
        _buildEndDayReadinessCard(state),
        const SizedBox(height: 12),
        _ActionCard(
          title: l10n.deliveryAccountManagement,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openAccountSettings,
                  icon: const Icon(Icons.security_outlined),
                  label: Text(l10n.deliveryEditPhoneAndPin),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openSupportSettings,
                  icon: const Icon(Icons.support_agent_rounded),
                  label: Text(l10n.deliverySupportAndHelp),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _DashboardSectionTitle extends StatelessWidget {
  const _DashboardSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppColors.brandNavy,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: TextStyle(
          color: AppColors.brandNavy.withValues(alpha: 0.62),
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _DeliveryCardGrid extends StatelessWidget {
  const _DeliveryCardGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(growable: false),
      );
    },
  );
}

class _DeliveryHomeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final Color color;
  final VoidCallback onTap;

  const _DeliveryHomeCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.brandNavy;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_rounded, color: color, size: 18),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.brandNavy,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.58),
            fontSize: 11,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: '$label: $value',
      child: Material(
        color: Colors.white.withValues(alpha: 0.97),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 174,
            child: Padding(padding: const EdgeInsets.all(14), child: content),
          ),
        ),
      ),
    );
  }
}

class _DeliveryMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _DeliveryMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.brandGold.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 152,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18),
                    if (onTap != null) ...[
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppColors.brandGreen,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.brandNavy.withValues(alpha: 0.72),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.brandNavy,
                    fontWeight: FontWeight.w800,
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

class _DeliveryAvailabilityCard extends StatelessWidget {
  final DeliveryState state;
  final ValueChanged<bool> onChanged;

  const _DeliveryAvailabilityCard({
    required this.state,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = state.isOnline;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: (isOnline ? AppColors.brandGreen : Colors.red)
                  .withValues(alpha: 0.14),
              child: Icon(
                isOnline ? Icons.wifi_tethering : Icons.power_settings_new,
                color: isOnline ? AppColors.brandGreen : Colors.red.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.lt(
                      ar: isOnline
                          ? 'الدلفري online ويستقبل الطلبات'
                          : 'الدلفري offline ولا يستقبل طلبات جديدة',
                      en: isOnline
                          ? 'Courier online and receiving orders'
                          : 'Courier offline and not receiving new orders',
                    ),
                    style: const TextStyle(
                      color: AppColors.brandNavy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.lt(
                      ar: 'الحالة ترسل للسيرفر وتؤثر على التعيين التلقائي.',
                      en: 'This status is sent to the server and controls auto-assignment.',
                    ),
                    style: TextStyle(
                      color: AppColors.brandNavy.withValues(alpha: 0.66),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: isOnline, onChanged: state.saving ? null : onChanged),
          ],
        ),
      ),
    );
  }
}

class _DeliveryEarningsKpiCard extends StatelessWidget {
  final DeliveryState state;
  final VoidCallback onOpenEarnings;
  final VoidCallback? onEndDay;

  const _DeliveryEarningsKpiCard({
    required this.state,
    required this.onOpenEarnings,
    required this.onEndDay,
  });

  @override
  Widget build(BuildContext context) {
    final day = _DeliveryPeriod.fromMap(state.analytics['day']);
    final month = _DeliveryPeriod.fromMap(state.analytics['month']);
    final readiness = state.endDayReadiness;
    final outstanding =
        num.tryParse('${readiness['outstandingAmount'] ?? 0}') ?? 0;
    final totalAppDue = num.tryParse('${readiness['totalAppDue'] ?? 0}') ?? 0;
    final canEndDay = readiness['canEndDay'] != false;
    final hasAppDue = readiness.containsKey('totalAppDue');
    final hasOutstanding = readiness.containsKey('outstandingAmount');
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.lt(ar: 'أرباح وذمم اليوم', en: 'Today finance'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onOpenEarnings,
                  icon: const Icon(Icons.insights_outlined, size: 18),
                  label: Text(context.lt(ar: 'التقرير', en: 'Report')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DeliveryMetricTile(
                  icon: Icons.payments_outlined,
                  label: context.lt(ar: 'أرباح اليوم', en: 'Today earnings'),
                  value: state.analytics.containsKey('day')
                      ? formatIqd(day.deliveryFees)
                      : '—',
                  onTap: onOpenEarnings,
                ),
                _DeliveryMetricTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: context.lt(ar: 'ذمة التطبيق', en: 'App due'),
                  value: hasAppDue ? formatIqd(totalAppDue) : '—',
                  onTap: onOpenEarnings,
                ),
                _DeliveryMetricTile(
                  icon: Icons.receipt_long_outlined,
                  label: context.lt(ar: 'تسويات مفتوحة', en: 'Open due'),
                  value: hasOutstanding ? formatIqd(outstanding) : '—',
                  onTap: onOpenEarnings,
                ),
                _DeliveryMetricTile(
                  icon: Icons.calendar_month_outlined,
                  label: context.lt(ar: 'أرباح الشهر', en: 'Month earnings'),
                  value: state.analytics.containsKey('month')
                      ? formatIqd(month.deliveryFees)
                      : '—',
                  onTap: onOpenEarnings,
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: canEndDay ? onEndDay : null,
              icon: const Icon(Icons.archive_outlined),
              label: Text(
                canEndDay
                    ? context.lt(ar: 'إنهاء اليوم', en: 'End day')
                    : context.lt(
                        ar: 'سدد الذمم قبل إنهاء اليوم',
                        en: 'Settle dues before ending the day',
                      ),
              ),
            ),
            if (!canEndDay) ...[
              const SizedBox(height: 6),
              Text(
                context.lt(
                  ar: 'توجد ذمم مفتوحة يجب تسديدها أو تأكيدها قبل الإغلاق.',
                  en: 'Open dues must be paid or confirmed before closure.',
                ),
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ActionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.brandNavy,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _DeliveryPeriod {
  final int deliveredOrdersCount;
  final double deliveryFees;
  final double serviceFeeAmount;
  final double commissionAmount;
  final double storeNetReceivedAmount;
  final double appDueFromDelivery;
  final double differenceAmount;
  final double avgRating;

  const _DeliveryPeriod({
    this.deliveredOrdersCount = 0,
    this.deliveryFees = 0,
    this.serviceFeeAmount = 0,
    this.commissionAmount = 0,
    this.storeNetReceivedAmount = 0,
    this.appDueFromDelivery = 0,
    this.differenceAmount = 0,
    this.avgRating = 0,
  });

  factory _DeliveryPeriod.fromMap(dynamic raw) {
    if (raw is! Map) return const _DeliveryPeriod();
    final map = Map<String, dynamic>.from(raw);
    return _DeliveryPeriod(
      deliveredOrdersCount: _readInt(map, const [
        'delivered_orders_count',
        'deliveredOrdersCount',
      ]),
      deliveryFees: _readDouble(map, const [
        'delivery_fees',
        'deliveryFees',
        'todayEarnings',
      ]),
      serviceFeeAmount: _readDouble(map, const [
        'service_fee_amount',
        'serviceFeeAmount',
      ]),
      commissionAmount: _readDouble(map, const [
        'commission_amount',
        'commissionAmount',
      ]),
      storeNetReceivedAmount: _readDouble(map, const [
        'store_net_received_amount',
        'storeNetReceivedAmount',
      ]),
      appDueFromDelivery: _readDouble(map, const [
        'app_due_from_delivery',
        'appDueFromDelivery',
      ]),
      differenceAmount: _readDouble(map, const [
        'difference_amount',
        'differenceAmount',
      ]),
      avgRating: _readDouble(map, const [
        'avg_rating',
        'avgRating',
        'avg_delivery_rating',
      ]),
    );
  }
}

class _CourierDashboardMetrics {
  final int currentOrders;
  final int completedToday;
  final int completedOrders;
  final int cancelledOrders;
  final int totalOrders;
  final double todayFees;
  final double rating;
  final bool hasAllOrderCounts;
  final bool hasTodayEarnings;
  final bool hasDayAnalytics;

  const _CourierDashboardMetrics({
    required this.currentOrders,
    required this.completedToday,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.totalOrders,
    required this.todayFees,
    required this.rating,
    required this.hasAllOrderCounts,
    required this.hasTodayEarnings,
    required this.hasDayAnalytics,
  });

  factory _CourierDashboardMetrics.fromState(DeliveryState state) {
    final day = _DeliveryPeriod.fromMap(state.analytics['day']);
    final kpis = _extractDashboardKpis(state.dashboardV2);

    final currentOrders = _readInt(kpis, const [
      'activeOrders',
      'active_orders',
    ]);
    final completedOrders = _readInt(kpis, const [
      'allCompletedOrders',
      'all_completed_orders',
    ]);
    final cancelledOrders = _readInt(kpis, const [
      'allCancelledOrders',
      'all_cancelled_orders',
    ]);
    final totalOrders = _readInt(kpis, const ['allOrders', 'all_orders']);
    final todayFees = _readDouble(kpis, const [
      'todayEarnings',
      'today_earnings',
    ]);
    final hasAllOrderCounts =
        const ['activeOrders', 'active_orders'].any(kpis.containsKey) &&
        const [
          'allCompletedOrders',
          'all_completed_orders',
        ].any(kpis.containsKey) &&
        const [
          'allCancelledOrders',
          'all_cancelled_orders',
        ].any(kpis.containsKey) &&
        const ['allOrders', 'all_orders'].any(kpis.containsKey);
    final hasTodayEarnings = const [
      'todayEarnings',
      'today_earnings',
    ].any(kpis.containsKey);

    return _CourierDashboardMetrics(
      currentOrders: currentOrders,
      completedToday: day.deliveredOrdersCount,
      completedOrders: completedOrders,
      cancelledOrders: cancelledOrders,
      totalOrders: totalOrders,
      todayFees: hasTodayEarnings ? todayFees : day.deliveryFees,
      rating: day.avgRating,
      hasAllOrderCounts: hasAllOrderCounts,
      hasTodayEarnings: hasTodayEarnings || state.analytics.containsKey('day'),
      hasDayAnalytics: state.analytics.containsKey('day'),
    );
  }
}

Map<String, dynamic> _extractDashboardKpis(Map<String, dynamic> dashboardV2) {
  final rawKpis = dashboardV2['kpis'];
  if (rawKpis is! Map) return const {};
  final kpis = Map<String, dynamic>.from(rawKpis);
  final day = kpis['day'];
  if (day is Map) {
    final dayMap = Map<String, dynamic>.from(day);
    return {
      'completedOrders': _readInt(dayMap, const [
        'delivered_orders_count',
        'deliveredOrdersCount',
      ]),
      'todayEarnings': _readDouble(dayMap, const [
        'delivery_fees',
        'deliveryFees',
        'todayEarnings',
      ]),
      ...kpis,
    };
  }
  return kpis;
}

int _readInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final parsed = _toNum(value).toInt();
    return parsed;
  }
  return 0;
}

double _readDouble(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    return _toNum(value);
  }
  return 0;
}

double _toNum(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return double.tryParse('$raw') ?? 0;
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }
}

class DeliveryCurrentOrderCard extends ConsumerWidget {
  final OrderModel order;

  const DeliveryCurrentOrderCard({super.key, required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final assignedToMe = order.hasAssignedDelivery;
    final normalized = normalizeOrderStatusForUi(order.status);
    final waitingForMerchant =
        assignedToMe && (normalized == 'pending' || normalized == 'preparing');
    final controller = ref.read(deliveryControllerProvider.notifier);
    final items = order.presentationItems;

    final itemCount = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final subtotal = order.subtotal;
    final afterDiscount =
        order.totalAmount - order.deliveryFee - order.serviceFee;
    final estimatedDiscount = (subtotal - afterDiscount).clamp(0, 1e12);
    final canOpenChat =
        assignedToMe && const {'on_the_way', 'arrived'}.contains(normalized);
    final canRequestCancel =
        assignedToMe &&
        const {
          'ready_for_delivery',
          'on_the_way',
          'arrived',
        }.contains(normalized);

    Future<void> openDetails() async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CourierOrderDetailsPage(orderId: order.id),
        ),
      );
    }

    Future<void> openOrderChat() async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrderChatScreen(
            orderId: order.id,
            title: l10n.deliveryOrderChatTitle(order.id),
            peerPhone: order.customerPhone,
          ),
        ),
      );
    }

    final customerAddressQuery = [
      order.customerCity,
      order.customerBlock,
      order.customerBuildingNumber,
      order.customerApartment,
    ].where((part) => part.trim().isNotEmpty).join(' ');

    Future<void> openCustomerLocation() => _openMapTarget(
      latitude: order.customerLatitude,
      longitude: order.customerLongitude,
      label: order.customerFullName,
      query: customerAddressQuery,
    );

    Future<void> openMerchantLocation() => _openMapTarget(
      latitude: order.merchantLatitude,
      longitude: order.merchantLongitude,
      label: order.merchantName,
      query: order.merchantName,
    );

    Future<void> requestCancelWithReason() async {
      List<DeliveryOrderActionReason> options;
      try {
        options = await ref
            .read(deliveryApiProvider)
            .listOrderActionReasons(
              actorScope: 'courier',
              actionKind: 'cancel',
            );
      } catch (_) {
        options = const <DeliveryOrderActionReason>[];
      }
      if (options.isEmpty) {
        options = const [
          DeliveryOrderActionReason(
            reasonCode: 'customer_no_answer',
            label: 'العميل لا يرد',
            allowsOtherText: false,
          ),
          DeliveryOrderActionReason(
            reasonCode: 'address_not_found',
            label: 'عنوان غير دقيق',
            allowsOtherText: false,
          ),
          DeliveryOrderActionReason(
            reasonCode: 'pickup_issue',
            label: 'تعذر الاستلام من المتجر',
            allowsOtherText: false,
          ),
          DeliveryOrderActionReason(
            reasonCode: 'other',
            label: 'سبب آخر',
            allowsOtherText: true,
          ),
        ];
      }
      if (!context.mounted) return;

      final reasonCtrl = TextEditingController();
      final scrollCoordinator = FormScrollCoordinator();
      DeliveryOrderActionReason? selected = options.first;
      final picked = await showDialog<({String code, String? text})>(
        context: context,
        builder: (dialogContext) {
          var fieldError = '';
          var selectError = '';
          var formError = '';
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: Text(l10n.deliveryRequestOrderCancelTitle),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FormErrorBanner(
                      message: formError.trim().isEmpty ? null : formError,
                    ),
                    DropdownButtonFormField<DeliveryOrderActionReason>(
                      initialValue: selected,
                      items: options
                          .map(
                            (item) =>
                                DropdownMenuItem<DeliveryOrderActionReason>(
                                  value: item,
                                  child: Text(item.label),
                                ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setDialogState(() {
                          selected = value;
                          selectError = '';
                          if (value?.allowsOtherText != true) {
                            fieldError = '';
                          }
                          formError = '';
                        });
                      },
                      decoration: InputDecoration(
                        labelText: l10n.deliveryCancellationReason,
                        errorText: selectError.isEmpty ? null : selectError,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (selected?.allowsOtherText == true)
                      scrollCoordinator.anchor(
                        'reason',
                        TextField(
                          controller: reasonCtrl,
                          focusNode: scrollCoordinator.focusNodeFor('reason'),
                          minLines: 2,
                          maxLines: 5,
                          onChanged: (_) {
                            if (fieldError.isEmpty && formError.isEmpty) return;
                            setDialogState(() {
                              fieldError = '';
                              formError = '';
                            });
                          },
                          textDirection: Directionality.of(dialogContext),
                          decoration: InputDecoration(
                            labelText: l10n.deliveryCancellationReason,
                            hintText: l10n.deliveryCancellationReasonHint,
                            errorText: fieldError.isEmpty ? null : fieldError,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.commonBack),
                ),
                FilledButton(
                  onPressed: () async {
                    final current = selected;
                    if (current == null) {
                      setDialogState(() {
                        selectError = l10n.validationRequiredField(
                          l10n.deliveryCancellationReason,
                        );
                        formError = l10n.validationReviewRequiredFields;
                      });
                      return;
                    }
                    final text = reasonCtrl.text.trim();
                    if (current.allowsOtherText && text.isEmpty) {
                      setDialogState(() {
                        fieldError = l10n.validationRequiredField(
                          l10n.deliveryCancellationReason,
                        );
                        formError = l10n.validationReviewRequiredFields;
                      });
                      await scrollCoordinator.focusFirstError(const ['reason']);
                      return;
                    }
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop((
                      code: current.reasonCode,
                      text: current.allowsOtherText ? text : null,
                    ));
                  },
                  child: Text(l10n.commonSend),
                ),
              ],
            ),
          );
        },
      );
      scrollCoordinator.dispose();
      reasonCtrl.dispose();
      if (picked == null) return;
      await controller.requestCancelOrder(
        order.id,
        reasonCode: picked.code,
        reasonText: picked.text,
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openDetails,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.deliveryOrderCardTitle(
                  order.id,
                  orderStatusLabel(order.status),
                ),
              ),
              const SizedBox(height: 6),
              Text(l10n.deliveryMerchantLine(order.merchantName)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      l10n.deliveryCustomerLine(
                        order.customerFullName,
                        order.customerPhone,
                      ),
                    ),
                  ),
                  if (order.customerImageUrl?.trim().isNotEmpty == true) ...[
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: CachedAppImage(
                        imageUrl: order.customerImageUrl!,
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        errorWidget: (context, error, stackTrace) =>
                            const Icon(Icons.person_outline),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                l10n.deliveryCustomerLocation(
                  order.customerCity,
                  order.customerBlock,
                  order.customerBuildingNumber,
                  order.customerApartment,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: openMerchantLocation,
                    icon: const Icon(Icons.store_mall_directory_outlined),
                    label: Text(
                      context.lt(ar: 'موقع المتجر', en: 'Store location'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: openCustomerLocation,
                    icon: const Icon(Icons.location_on_outlined),
                    label: Text(
                      context.lt(ar: 'موقع الزبون', en: 'Customer location'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Item count is only trustworthy when the list payload actually
              // carried items. The current-orders list endpoint returns a
              // summary without items, so showing "0" there is misleading —
              // we surface "View details" instead and fetch the full invoice
              // (with items) inside DeliveryOrderDetailScreen.
              if (items.isNotEmpty)
                Text(l10n.deliveryOrderItemsCount(itemCount))
              else
                Text(
                  context.lt(
                    ar: 'اضغط "عرض التفاصيل" لرؤية المواد والفاتورة الكاملة',
                    en: 'Tap "View details" to see items and the full invoice',
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(l10n.deliveryOrderPriceLine(formatIqd(subtotal))),
              Text(
                l10n.deliveryOrderDiscountLine(
                  formatIqd(estimatedDiscount.toDouble()),
                ),
              ),
              Text(
                '${context.lt(ar: 'رسوم الخدمة', en: 'Service fee')}: ${formatIqd(order.serviceFee)}',
              ),
              Text(l10n.deliveryDeliveryFeeLine(formatIqd(order.deliveryFee))),
              Text(
                '${context.lt(ar: 'الإجمالي النهائي', en: 'Final total')}: ${formatIqd(order.totalAmount)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    for (final item in items.take(3))
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: OrderItemThumbnail(
                          imageUrl: item.displayImageUrl,
                          activityType: item.activityType,
                          size: 52,
                        ),
                      ),
                    if (items.length > 3)
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          '+${items.length - 3}',
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                OrderItemsSummaryList(
                  items: items,
                  compact: true,
                  groupByStore: false,
                ),
              ],
              if (order.imageUrl?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.deliveryOrderImageLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedAppImage(
                    imageUrl: order.imageUrl!,
                    height: 130,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (context, error, stackTrace) => Container(
                      height: 90,
                      alignment: Alignment.center,
                      color: Colors.black12,
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: openDetails,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(
                    context.lt(
                      ar: 'عرض التفاصيل والفاتورة',
                      en: 'View details & invoice',
                    ),
                  ),
                ),
              ),
              if (waitingForMerchant)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.deliveryWaitingMerchantPrepare),
                ),
              Row(
                children: [
                  if (assignedToMe && normalized == 'ready_for_delivery')
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final input = await showCourierPickupSettlementSheet(
                            context,
                            expectedStoreAmount:
                                (order.totalAmount -
                                        order.serviceFee -
                                        order.deliveryFee)
                                    .clamp(0, double.infinity),
                          );
                          if (input == null) return;
                          await controller.pickedUpOrder(
                            order.id,
                            merchantPaidActual: input.merchantPaidActual,
                            receiptFile: input.receiptFile,
                            withoutReceipt: input.withoutReceipt,
                            merchantPaymentNote: input.note,
                          );
                        },
                        child: Text(l10n.deliveryCourierActionPickedUp),
                      ),
                    ),
                  if (assignedToMe && normalized == 'on_the_way')
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => controller.arrivedOrder(order.id),
                        child: Text(l10n.deliveryCourierActionArrived),
                      ),
                    ),
                  if (assignedToMe && normalized == 'arrived')
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final input = await showCourierDeliveryCashSheet(
                            context,
                            invoiceTotal: order.totalAmount,
                          );
                          if (input == null) return;
                          await controller.deliveredOrder(
                            order.id,
                            customerReceivedActual:
                                input.customerReceivedActual,
                          );
                        },
                        child: Text(l10n.deliveryCourierActionDelivered),
                      ),
                    ),
                ],
              ),
              if (canOpenChat || canRequestCancel) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canOpenChat)
                      OutlinedButton.icon(
                        onPressed: openOrderChat,
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: Text(l10n.deliveryChatCustomer),
                      ),
                    if (canRequestCancel)
                      TextButton.icon(
                        onPressed: requestCancelWithReason,
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(l10n.deliveryCancelRequest),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryOrderCard extends StatelessWidget {
  final OrderModel order;

  const _HistoryOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ListTile(
        title: Text(
          l10n.deliveryHistoryOrderTitle(order.id, order.customerFullName),
        ),
        subtitle: Text(
          l10n.deliveryHistoryOrderSubtitle(
            order.merchantName,
            formatIqd(order.totalAmount),
          ),
        ),
      ),
    );
  }
}
