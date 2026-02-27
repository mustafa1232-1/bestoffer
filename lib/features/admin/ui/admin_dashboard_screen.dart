import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/i18n/app_strings.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/report_printing.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../../auth/state/auth_controller.dart';
import '../../auth/ui/add_merchant_screen.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../models/pending_merchant_model.dart';
import '../models/pending_settlement_model.dart';
import '../models/period_metrics_model.dart';
import '../models/managed_merchant_model.dart';
import '../state/admin_controller.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _analyticsSectionKey = GlobalKey();
  final GlobalKey _settlementsSectionKey = GlobalKey();
  final GlobalKey _approvalsSectionKey = GlobalKey();
  final GlobalKey _customerInsightsSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(adminControllerProvider.notifier).bootstrap(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openCreateUserSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateUserSheet(),
    );
  }

  Future<void> _openCreateMerchant() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddMerchantScreen()));

    if (result == true && mounted) {
      await ref.read(adminControllerProvider.notifier).bootstrap();
    }
  }

  Future<void> _openAnalyticsDetails({
    required String title,
    required List<String> lines,
    required String reportPeriod,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              ...lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line, textDirection: TextDirection.rtl),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final raw = await ref
                        .read(adminApiProvider)
                        .ordersPrintReport(period: reportPeriod);
                    final orders = raw
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    await printOrdersReceiptReport(
                      title: title,
                      summaryLines: lines,
                      orders: orders,
                    );
                  } catch (e) {
                    try {
                      await printSimpleReport(title: title, lines: lines);
                    } catch (_) {}
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'ØªØ¹Ø°Ø± ÙØªØ­ ÙˆØ§Ø¬Ù‡Ø© Ø§Ù„Ø·Ø¨Ø§Ø¹Ø© Ø¹Ù„Ù‰ Ù‡Ø°Ø§ Ø§Ù„Ø¬Ù‡Ø§Ø². ØªÙ… ÙØªØ­ ØªÙ‚Ø±ÙŠØ± Ø¨Ø¯ÙŠÙ„. ($e)',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('Ø·Ø¨Ø§Ø¹Ø© Ø§Ù„ÙˆØµÙ„'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final raw = await ref
                        .read(adminApiProvider)
                        .ordersPrintReport(period: reportPeriod);
                    final orders = raw
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    await exportOrdersExcelReport(
                      title: title,
                      summaryLines: lines,
                      orders: orders,
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('ÙØ´Ù„ ØªØµØ¯ÙŠØ± Excel. ($e)')),
                    );
                  }
                },
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('ØªØµØ¯ÙŠØ± Excel Ù…ÙØµÙ„'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _scrollToSection(GlobalKey sectionKey) async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sectionContext = sectionKey.currentContext;
      if (sectionContext == null) return;
      Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: 0.03,
      );
    });
  }

  Future<void> _openCustomerInsightDetails(int customerUserId) async {
    final details = await ref
        .read(adminControllerProvider.notifier)
        .fetchCustomerInsightDetails(customerUserId);
    if (!mounted || details == null) return;

    final customer = details['customer'] is Map
        ? Map<String, dynamic>.from(details['customer'] as Map)
        : <String, dynamic>{};
    final orderProfile = details['orderProfile'] is Map
        ? Map<String, dynamic>.from(details['orderProfile'] as Map)
        : <String, dynamic>{};
    final behaviorProfile = details['behaviorProfile'] is Map
        ? Map<String, dynamic>.from(details['behaviorProfile'] as Map)
        : <String, dynamic>{};

    final topActions = (behaviorProfile['topActions'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];

    final topCategories = (behaviorProfile['topCategories'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ù…Ù„Ù Ø§Ù„Ø¹Ù…ÙŠÙ„ Ø§Ù„Ø°ÙƒÙŠ - ${customer['fullName'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Text('Ø§Ù„Ù‡Ø§ØªÙ: ${customer['phone'] ?? '-'}'),
                  Text(
                    'Ø§Ù„Ø¹Ù†ÙˆØ§Ù†: Ø¨Ù„ÙˆÙƒ ${customer['block'] ?? '-'} - Ø¹Ù…Ø§Ø±Ø© ${customer['buildingNumber'] ?? '-'} - Ø´Ù‚Ø© ${customer['apartment'] ?? '-'}',
                  ),
                  const SizedBox(height: 8),
                  Text('Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø·Ù„Ø¨Ø§Øª: ${orderProfile['ordersCount'] ?? 0}'),
                  Text('Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„ØµØ±Ù: ${orderProfile['totalSpent'] ?? 0} IQD'),
                  Text('Ù…ØªÙˆØ³Ø· Ø§Ù„Ø³Ù„Ø©: ${orderProfile['avgBasket'] ?? 0} IQD'),
                  const SizedBox(height: 10),
                  const Text(
                    'Ø§Ù„ÙØ¦Ø§Øª Ø§Ù„Ø£ÙƒØ«Ø± Ø§Ø³ØªØ®Ø¯Ø§Ù…Ù‹Ø§',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  if (topCategories.isEmpty)
                    const Text('Ù„Ø§ ØªÙˆØ¬Ø¯ Ø¨ÙŠØ§Ù†Ø§Øª ÙƒØ§ÙÙŠØ©')
                  else
                    ...topCategories.take(8).map(
                      (row) => Text(
                        '- ${row['category'] ?? 'general'} (${row['events_count'] ?? 0})',
                      ),
                    ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ø£Ù‡Ù… Ø§Ù„Ø³Ù„ÙˆÙƒÙŠØ§Øª',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  if (topActions.isEmpty)
                    const Text('Ù„Ø§ ØªÙˆØ¬Ø¯ Ø¨ÙŠØ§Ù†Ø§Øª ÙƒØ§ÙÙŠØ©')
                  else
                    ...topActions.take(10).map(
                      (row) => Text(
                        '- ${row['event_name'] ?? '-'} (${row['events_count'] ?? 0})',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final isAdmin = auth.isAdmin;
    final isSuperAdmin = auth.isSuperAdmin;
    final strings = ref.watch(appStringsProvider);

    ref.listen<AdminState>(adminControllerProvider, (prev, next) {
      final message = next.error ?? next.success;
      final prevMessage = prev?.error ?? prev?.success;
      if (message != null && message != prevMessage && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    final drawerItems = <AppUserDrawerItem>[
      AppUserDrawerItem(
        icon: Icons.dashboard_outlined,
        label: strings.t('drawerHome'),
        onTap: (_) => _scrollToTop(),
      ),
      AppUserDrawerItem(
        icon: Icons.pending_actions_outlined,
        label: strings.t('drawerPendingApprovals'),
        onTap: (_) => _scrollToSection(_approvalsSectionKey),
      ),
      AppUserDrawerItem(
        icon: Icons.account_balance_wallet_outlined,
        label: strings.t('drawerPendingSettlements'),
        onTap: (_) => _scrollToSection(_settlementsSectionKey),
      ),
      AppUserDrawerItem(
        icon: Icons.refresh_rounded,
        label: strings.t('drawerRefresh'),
        onTap: (_) => ref.read(adminControllerProvider.notifier).bootstrap(),
      ),
      if (isSuperAdmin)
        AppUserDrawerItem(
          icon: Icons.manage_search_rounded,
          label: 'Ù…Ù„ÙØ§Øª Ø§Ù„Ø¹Ù…Ù„Ø§Ø¡ Ø§Ù„Ø°ÙƒÙŠØ©',
          onTap: (_) => _scrollToSection(_customerInsightsSectionKey),
        ),
      if (isAdmin)
        AppUserDrawerItem(
          icon: Icons.person_add_alt_1_outlined,
          label: strings.t('drawerCreateUser'),
          onTap: (_) => _openCreateUserSheet(),
        ),
      if (isAdmin)
        AppUserDrawerItem(
          icon: Icons.store_mall_directory_outlined,
          label: strings.t('drawerCreateMerchant'),
          onTap: (_) => _openCreateMerchant(),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isAdmin
              ? strings.t('adminDashboard')
              : strings.t('deputyAdminDashboard'),
        ),
        actions: const [NotificationsBellButton()],
      ),
      drawer: AppUserDrawer(
        title: isAdmin
            ? strings.t('adminDashboard')
            : strings.t('deputyAdminDashboard'),
        subtitle: isAdmin
            ? strings.t('drawerAdminSub')
            : strings.t('drawerDeputyAdminSub'),
        items: drawerItems,
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(adminControllerProvider.notifier).bootstrap(),
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                children: [
                  KeyedSubtree(
                    key: _analyticsSectionKey,
                    child: _AnalyticsSection(
                      day: state.day,
                      month: state.month,
                      year: state.year,
                      onOpenDetails:
                          ({
                            required title,
                            required lines,
                            required reportPeriod,
                          }) {
                            return _openAnalyticsDetails(
                              title: title,
                              lines: lines,
                              reportPeriod: reportPeriod,
                            );
                          },
                    ),
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: _settlementsSectionKey,
                    child: _PendingSettlementsSection(
                      saving: state.saving,
                      canApprove: isAdmin,
                      settlements: state.pendingSettlements,
                      onApprove: (settlementId) async {
                        await ref
                            .read(adminControllerProvider.notifier)
                            .approveSettlement(settlementId);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: _approvalsSectionKey,
                    child: _PendingMerchantsSection(
                      saving: state.saving,
                      canApprove: isAdmin,
                      merchants: state.pendingMerchants,
                      onApprove: (merchantId) async {
                        await ref
                            .read(adminControllerProvider.notifier)
                            .approveMerchant(merchantId);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MerchantsStatusSection(
                    saving: state.saving,
                    canManage: isAdmin,
                    merchants: state.managedMerchants,
                    onToggleDisabled: (merchantId, nextDisabled) async {
                      await ref
                          .read(adminControllerProvider.notifier)
                          .toggleMerchantDisabled(
                            merchantId: merchantId,
                            isDisabled: nextDisabled,
                          );
                    },
                  ),
                  if (isSuperAdmin) const SizedBox(height: 12),
                  if (isSuperAdmin)
                    KeyedSubtree(
                      key: _customerInsightsSectionKey,
                      child: _SuperAdminInsightsSection(
                        loading: state.insightsLoading,
                        items: state.customerInsights,
                        total: state.customerInsightsTotal,
                        onSearch: (query) async {
                          await ref
                              .read(adminControllerProvider.notifier)
                              .searchCustomerInsights(query);
                        },
                        onOpenDetails: _openCustomerInsightDetails,
                      ),
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

class _AnalyticsSection extends StatelessWidget {
  final PeriodMetricsModel day;
  final PeriodMetricsModel month;
  final PeriodMetricsModel year;
  final Future<void> Function({
    required String title,
    required List<String> lines,
    required String reportPeriod,
  })
  onOpenDetails;

  const _AnalyticsSection({
    required this.day,
    required this.month,
    required this.year,
    required this.onOpenDetails,
  });

  List<String> _periodLines({
    required String label,
    required PeriodMetricsModel metric,
  }) {
    return [
      '$label:',
      'Ø¹Ø¯Ø¯ Ø§Ù„Ø·Ù„Ø¨Ø§Øª: ${metric.ordersCount}',
      'Ø§Ù„Ø·Ù„Ø¨Ø§Øª Ø§Ù„Ù…ÙƒØªÙ…Ù„Ø©: ${metric.deliveredOrdersCount}',
      'Ø§Ù„Ø·Ù„Ø¨Ø§Øª Ø§Ù„Ù…Ù„ØºÙŠØ©: ${metric.cancelledOrdersCount}',
      'Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ù…Ø¨ÙŠØ¹Ø§Øª: ${formatIqd(metric.totalAmount)}',
      'Ø±Ø³ÙˆÙ… Ø§Ù„ØªÙˆØµÙŠÙ„: ${formatIqd(metric.deliveryFees)}',
      'Ø¹Ù…ÙˆÙ„Ø© Ø§Ù„ØªØ·Ø¨ÙŠÙ‚: ${formatIqd(metric.appFees)}',
      'ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ø¯Ù„ÙØ±ÙŠ: ${metric.avgDeliveryRating.toStringAsFixed(1)}',
      'ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ù…ØªØ¬Ø±: ${metric.avgMerchantRating.toStringAsFixed(1)}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final deliveredRate = _safeRatio(
      year.deliveredOrdersCount,
      year.ordersCount,
    );
    final cancelledRate = _safeRatio(
      year.cancelledOrdersCount,
      year.ordersCount,
    );
    final appMargin = _safeRatio(year.appFees, year.totalAmount);

    return Column(
      children: [
        Card(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1D4F88).withValues(alpha: 0.72),
                  const Color(0xFF2E7AC6).withValues(alpha: 0.38),
                  const Color(0xFF0E2748).withValues(alpha: 0.82),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ù†Ø¨Ø¶ Ù„ÙˆØ­Ø© Ø§Ù„Ù…ØªØ§Ø¨Ø¹Ø©',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _KpiStatCard(
                        title: 'Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø·Ù„Ø¨Ø§Øª',
                        value: '${year.ordersCount}',
                        icon: Icons.receipt_long_rounded,
                        tint: const Color(0xFF6EE7FF),
                        onTap: () {
                          onOpenDetails(
                            title: 'ØªÙØ§ØµÙŠÙ„ Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø·Ù„Ø¨Ø§Øª',
                            lines: [
                              ..._periodLines(label: 'Ø§Ù„ÙŠÙˆÙ…', metric: day),
                              '',
                              ..._periodLines(label: 'Ø§Ù„Ø´Ù‡Ø±', metric: month),
                              '',
                              ..._periodLines(label: 'Ø§Ù„Ø³Ù†Ø©', metric: year),
                            ],
                            reportPeriod: 'year',
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _KpiStatCard(
                        title: 'Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø¥ÙŠØ±Ø§Ø¯Ø§Øª',
                        value: formatIqd(year.totalAmount),
                        icon: Icons.payments_rounded,
                        tint: const Color(0xFF8BFFC8),
                        onTap: () {
                          onOpenDetails(
                            title: 'ØªÙØ§ØµÙŠÙ„ Ø§Ù„Ø¥ÙŠØ±Ø§Ø¯Ø§Øª',
                            lines: [
                              'Ø§Ù„ÙŠÙˆÙ…: ${formatIqd(day.totalAmount)}',
                              'Ø§Ù„Ø´Ù‡Ø±: ${formatIqd(month.totalAmount)}',
                              'Ø§Ù„Ø³Ù†Ø©: ${formatIqd(year.totalAmount)}',
                              'Ø¹Ù…ÙˆÙ„Ø© Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ (Ø§Ù„Ø³Ù†Ø©): ${formatIqd(year.appFees)}',
                            ],
                            reportPeriod: 'year',
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _KpiStatCard(
                title: 'Ø·Ù„Ø¨Ø§Øª Ø§Ù„ÙŠÙˆÙ…',
                value: '${day.ordersCount}',
                icon: Icons.today_rounded,
                tint: const Color(0xFF9BD7FF),
                onTap: () {
                  onOpenDetails(
                    title: 'ØªÙØ§ØµÙŠÙ„ Ø·Ù„Ø¨Ø§Øª Ø§Ù„ÙŠÙˆÙ…',
                    lines: _periodLines(label: 'Ø§Ù„ÙŠÙˆÙ…', metric: day),
                    reportPeriod: 'day',
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiStatCard(
                title: 'Ø£Ø¬ÙˆØ± ØªÙˆØµÙŠÙ„ Ø§Ù„ÙŠÙˆÙ…',
                value: formatIqd(day.deliveryFees),
                icon: Icons.local_shipping_rounded,
                tint: const Color(0xFFFFD28F),
                onTap: () {
                  onOpenDetails(
                    title: 'ØªÙØ§ØµÙŠÙ„ Ø£Ø¬ÙˆØ± Ø§Ù„ØªÙˆØµÙŠÙ„',
                    lines: [
                      'Ø§Ù„ÙŠÙˆÙ…: ${formatIqd(day.deliveryFees)}',
                      'Ø§Ù„Ø´Ù‡Ø±: ${formatIqd(month.deliveryFees)}',
                      'Ø§Ù„Ø³Ù†Ø©: ${formatIqd(year.deliveryFees)}',
                    ],
                    reportPeriod: 'day',
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _KpiStatCard(
                title: 'Ø¹Ù…ÙˆÙ„Ø© Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ Ø§Ù„ÙŠÙˆÙ…',
                value: formatIqd(day.appFees),
                icon: Icons.account_balance_wallet_rounded,
                tint: const Color(0xFF9EFBA5),
                onTap: () {
                  onOpenDetails(
                    title: 'ØªÙØ§ØµÙŠÙ„ Ø¹Ù…ÙˆÙ„Ø© Ø§Ù„ØªØ·Ø¨ÙŠÙ‚',
                    lines: [
                      'Ø§Ù„ÙŠÙˆÙ…: ${formatIqd(day.appFees)}',
                      'Ø§Ù„Ø´Ù‡Ø±: ${formatIqd(month.appFees)}',
                      'Ø§Ù„Ø³Ù†Ø©: ${formatIqd(year.appFees)}',
                    ],
                    reportPeriod: 'day',
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiStatCard(
                title: 'Ù…ØªÙˆØ³Ø· Ø§Ù„ØªÙ‚ÙŠÙŠÙ…',
                value:
                    '${year.avgDeliveryRating.toStringAsFixed(1)} / ${year.avgMerchantRating.toStringAsFixed(1)}',
                icon: Icons.star_rounded,
                tint: const Color(0xFFFFE48D),
                onTap: () {
                  onOpenDetails(
                    title: 'ØªÙØ§ØµÙŠÙ„ Ø§Ù„ØªÙ‚ÙŠÙŠÙ…',
                    lines: [
                      'ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ø¯Ù„ÙØ±ÙŠ - Ø§Ù„ÙŠÙˆÙ…: ${day.avgDeliveryRating.toStringAsFixed(1)}',
                      'ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ø¯Ù„ÙØ±ÙŠ - Ø§Ù„Ø´Ù‡Ø±: ${month.avgDeliveryRating.toStringAsFixed(1)}',
                      'ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ø¯Ù„ÙØ±ÙŠ - Ø§Ù„Ø³Ù†Ø©: ${year.avgDeliveryRating.toStringAsFixed(1)}',
                      '',
                      'ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ù…ØªØ¬Ø± - Ø§Ù„ÙŠÙˆÙ…: ${day.avgMerchantRating.toStringAsFixed(1)}',
                      'ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ù…ØªØ¬Ø± - Ø§Ù„Ø´Ù‡Ø±: ${month.avgMerchantRating.toStringAsFixed(1)}',
                      'ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ù…ØªØ¬Ø± - Ø§Ù„Ø³Ù†Ø©: ${year.avgMerchantRating.toStringAsFixed(1)}',
                    ],
                    reportPeriod: 'year',
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ù…Ø¤Ø´Ø±Ø§Øª Ø§Ù„Ø£Ø¯Ø§Ø¡',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RingIndicator(
                        label: 'Ù…ÙƒØªÙ…Ù„',
                        percent: deliveredRate,
                        color: const Color(0xFF63E9B4),
                      ),
                    ),
                    Expanded(
                      child: _RingIndicator(
                        label: 'Ù…Ù„ØºÙŠ',
                        percent: cancelledRate,
                        color: const Color(0xFFFF8AA5),
                      ),
                    ),
                    Expanded(
                      child: _RingIndicator(
                        label: 'Ù‡Ø§Ù…Ø´ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚',
                        percent: appMargin,
                        color: const Color(0xFF7ED7FF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _RatingRow(
                  title: 'ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ø¯Ù„ÙØ±ÙŠ',
                  value: year.avgDeliveryRating / 5,
                  color: const Color(0xFF8DDCFF),
                ),
                const SizedBox(height: 8),
                _RatingRow(
                  title: 'ØªÙ‚ÙŠÙŠÙ… Ø§Ù„Ù…ØªØ¬Ø±',
                  value: year.avgMerchantRating / 5,
                  color: const Color(0xFF9FF1B5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ø§ØªØ¬Ø§Ù‡ Ø§Ù„Ø·Ù„Ø¨Ø§Øª (ÙŠÙˆÙ… / Ø´Ù‡Ø± / Ø³Ù†Ø©)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 138,
                  child: CustomPaint(
                    painter: _OrdersTrendPainter(
                      values: [
                        day.ordersCount.toDouble(),
                        month.ordersCount.toDouble(),
                        year.ordersCount.toDouble(),
                      ],
                      lineColor: const Color(0xFF76D8FF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ù…Ø®Ø·Ø· Ø§Ù„Ø±Ø³ÙˆÙ… (Ø§Ù„ØªÙˆØµÙŠÙ„ Ù…Ù‚Ø§Ø¨Ù„ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 156,
                  child: CustomPaint(
                    painter: _FeesBarsPainter(
                      deliveryValues: [
                        day.deliveryFees,
                        month.deliveryFees,
                        year.deliveryFees,
                      ],
                      appValues: [day.appFees, month.appFees, year.appFees],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    _LegendDot(label: 'Ø±Ø³ÙˆÙ… Ø§Ù„ØªÙˆØµÙŠÙ„', color: Color(0xFF78C9FF)),
                    SizedBox(width: 10),
                    _LegendDot(label: 'Ø±Ø³ÙˆÙ… Ø§Ù„ØªØ·Ø¨ÙŠÙ‚', color: Color(0xFF8BF9B9)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;

  const _KpiStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardChild = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF102A4F).withValues(alpha: 0.66),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tint.withValues(alpha: 0.92)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ],
      ),
    );

    if (onTap == null) return cardChild;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: cardChild,
      ),
    );
  }
}

class _RingIndicator extends StatelessWidget {
  final String label;
  final double percent;
  final Color color;

  const _RingIndicator({
    required this.label,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 78,
          height: 78,
          child: CustomPaint(
            painter: _RingPainter(value: percent.clamp(0.0, 1.0), color: color),
            child: Center(
              child: Text(
                '${(percent * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _RatingRow extends StatelessWidget {
  final String title;
  final double value;
  final Color color;

  const _RatingRow({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            Text('${(normalized * 5).toStringAsFixed(1)} / 5'),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: normalized,
            valueColor: AlwaysStoppedAnimation(color),
            backgroundColor: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}

class _OrdersTrendPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;

  const _OrdersTrendPainter({required this.values, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = math.max(
      values.fold<double>(0, (p, e) => e > p ? e : p),
      1.0,
    );

    const left = 12.0;
    const right = 10.0;
    const top = 8.0;
    const bottom = 20.0;
    final chartRect = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = chartRect.top + chartRect.height * (i / 3);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x =
          chartRect.left +
          (chartRect.width * i / math.max(values.length - 1, 1));
      final y = chartRect.bottom - ((values[i] / maxValue) * chartRect.height);
      points.add(Offset(x, y));
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      linePath.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    linePath.lineTo(points.last.dx, points.last.dy);

    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, chartRect.bottom)
      ..lineTo(points.first.dx, chartRect.bottom)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.32),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(chartRect);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = lineColor;
    for (final point in points) {
      canvas.drawCircle(point, 3.2, dotPaint);
      canvas.drawCircle(
        point,
        6.2,
        Paint()..color = lineColor.withValues(alpha: 0.22),
      );
    }

    const labels = ['ÙŠÙˆÙ…', 'Ø´Ù‡Ø±', 'Ø³Ù†Ø©'];
    for (var i = 0; i < labels.length; i++) {
      final x =
          chartRect.left +
          (chartRect.width * i / math.max(labels.length - 1, 1));
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - (tp.width / 2), chartRect.bottom + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _OrdersTrendPainter oldDelegate) {
    if (oldDelegate.lineColor != lineColor) return true;
    if (oldDelegate.values.length != values.length) return true;
    for (var i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) return true;
    }
    return false;
  }
}

class _FeesBarsPainter extends CustomPainter {
  final List<double> deliveryValues;
  final List<double> appValues;

  const _FeesBarsPainter({
    required this.deliveryValues,
    required this.appValues,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 14.0;
    const right = 12.0;
    const top = 8.0;
    const bottom = 22.0;
    final chartRect = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );

    final all = [...deliveryValues, ...appValues];
    final maxValue = math.max(
      all.fold<double>(0, (p, e) => e > p ? e : p),
      1.0,
    );

    final base = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(chartRect.left, chartRect.bottom),
      Offset(chartRect.right, chartRect.bottom),
      base,
    );

    final groups = math.min(deliveryValues.length, appValues.length);
    if (groups == 0) return;

    final slotWidth = chartRect.width / groups;
    const barWidth = 12.0;
    const labels = ['ÙŠ', 'Ø´', 'Ø³'];

    for (var i = 0; i < groups; i++) {
      final xCenter = chartRect.left + (slotWidth * i) + (slotWidth / 2);

      final deliveryHeight =
          (deliveryValues[i] / maxValue).clamp(0.0, 1.0) * chartRect.height;
      final appHeight =
          (appValues[i] / maxValue).clamp(0.0, 1.0) * chartRect.height;

      final deliveryRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          xCenter - barWidth - 2,
          chartRect.bottom - deliveryHeight,
          barWidth,
          deliveryHeight,
        ),
        const Radius.circular(5),
      );
      final appRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          xCenter + 2,
          chartRect.bottom - appHeight,
          barWidth,
          appHeight,
        ),
        const Radius.circular(5),
      );

      canvas.drawRRect(
        deliveryRect,
        Paint()..color = const Color(0xFF78C9FF).withValues(alpha: 0.95),
      );
      canvas.drawRRect(
        appRect,
        Paint()..color = const Color(0xFF8BF9B9).withValues(alpha: 0.95),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i % labels.length],
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(xCenter - (tp.width / 2), chartRect.bottom + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _FeesBarsPainter oldDelegate) {
    if (oldDelegate.deliveryValues.length != deliveryValues.length) return true;
    if (oldDelegate.appValues.length != appValues.length) return true;
    for (var i = 0; i < deliveryValues.length; i++) {
      if (oldDelegate.deliveryValues[i] != deliveryValues[i]) return true;
    }
    for (var i = 0; i < appValues.length; i++) {
      if (oldDelegate.appValues[i] != appValues[i]) return true;
    }
    return false;
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;

  const _RingPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width / 2) - 6;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color;

    final startAngle = -math.pi / 2;
    final sweep = 2 * math.pi * value.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.color != color;
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

double _safeRatio(num part, num total) {
  if (total <= 0) return 0;
  final ratio = part / total;
  if (ratio.isNaN || ratio.isInfinite) return 0;
  return ratio.clamp(0, 1).toDouble();
}

class _PendingMerchantsSection extends StatelessWidget {
  final bool saving;
  final bool canApprove;
  final List<PendingMerchantModel> merchants;
  final Future<void> Function(int merchantId) onApprove;

  const _PendingMerchantsSection({
    required this.saving,
    required this.canApprove,
    required this.merchants,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ø§Ù„Ù…ØªØ§Ø¬Ø± Ø¨Ø§Ù†ØªØ¸Ø§Ø± Ø§Ù„Ù…ÙˆØ§ÙÙ‚Ø©',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (merchants.isEmpty)
              const Text(
                'Ù„Ø§ ØªÙˆØ¬Ø¯ Ù…ØªØ§Ø¬Ø± Ø¨Ø§Ù†ØªØ¸Ø§Ø± Ø§Ù„Ù…ÙˆØ§ÙÙ‚Ø©',
                textAlign: TextAlign.right,
              )
            else
              ...merchants.map((merchant) {
                return ListTile(
                  title: Text(
                    '${merchant.name} (${merchant.type})',
                    textDirection: TextDirection.rtl,
                  ),
                  subtitle: Text(
                    'Ø§Ù„Ù…Ø§Ù„Ùƒ: ${merchant.ownerName ?? '-'} - ${merchant.ownerPhone ?? ''}',
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: ElevatedButton(
                    onPressed: saving || !canApprove
                        ? null
                        : () => onApprove(merchant.id),
                    child: const Text('Ù…ÙˆØ§ÙÙ‚Ø©'),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _PendingSettlementsSection extends StatelessWidget {
  final bool saving;
  final bool canApprove;
  final List<PendingSettlementModel> settlements;
  final Future<void> Function(int settlementId) onApprove;

  const _PendingSettlementsSection({
    required this.saving,
    required this.canApprove,
    required this.settlements,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ø·Ù„Ø¨Ø§Øª ØªØ³Ø¯ÙŠØ¯ Ø§Ù„Ù…Ø³ØªØ­Ù‚Ø§Øª',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (settlements.isEmpty)
              const Text(
                'Ù„Ø§ ØªÙˆØ¬Ø¯ Ø·Ù„Ø¨Ø§Øª ØªØ³Ø¯ÙŠØ¯ Ø­Ø§Ù„ÙŠØ§Ù‹',
                textAlign: TextAlign.right,
              )
            else
              ...settlements.map((s) {
                return ListTile(
                  title: Text(
                    '${s.merchantName} - ${formatIqd(s.amount)}',
                    textDirection: TextDirection.rtl,
                  ),
                  subtitle: Text(
                    'ØµØ§Ø­Ø¨ Ø§Ù„Ù…ØªØ¬Ø±: ${s.ownerName} - ${s.ownerPhone}',
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: ElevatedButton(
                    onPressed: saving || !canApprove
                        ? null
                        : () => onApprove(s.id),
                    child: const Text('Ù…ØµØ§Ø¯Ù‚Ø©'),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _MerchantsStatusSection extends StatelessWidget {
  final bool saving;
  final bool canManage;
  final List<ManagedMerchantModel> merchants;
  final Future<void> Function(int merchantId, bool nextDisabled)
  onToggleDisabled;

  const _MerchantsStatusSection({
    required this.saving,
    required this.canManage,
    required this.merchants,
    required this.onToggleDisabled,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ø¥Ø¯Ø§Ø±Ø© Ø­Ø§Ù„Ø© Ø§Ù„Ù…ØªØ§Ø¬Ø±',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (merchants.isEmpty)
              const Text('Ù„Ø§ ØªÙˆØ¬Ø¯ Ù…ØªØ§Ø¬Ø±', textAlign: TextAlign.right)
            else
              ...merchants.take(12).map((merchant) {
                final statusLabel = merchant.isDisabled ? 'Ù…Ø¹Ø·Ù„' : 'Ù†Ø´Ø·';
                return ListTile(
                  title: Text(
                    '${merchant.name} (${merchant.type})',
                    textDirection: TextDirection.rtl,
                  ),
                  subtitle: Text(
                    'Ø§Ù„Ù…Ø§Ù„Ùƒ: ${merchant.ownerFullName ?? '-'} - Ø§Ù„ÙŠÙˆÙ…: ${merchant.todayOrdersCount} Ø·Ù„Ø¨ - Ø§Ù„Ø­Ø§Ù„Ø©: $statusLabel',
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: Switch(
                    value: !merchant.isDisabled,
                    onChanged: !canManage || saving
                        ? null
                        : (value) => onToggleDisabled(merchant.id, !value),
                  ),
                );
              }),
            if (merchants.length > 12)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '... +${merchants.length - 12} Ù…ØªØ¬Ø±',
                  textDirection: TextDirection.rtl,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuperAdminInsightsSection extends StatefulWidget {
  final bool loading;
  final int total;
  final List<Map<String, dynamic>> items;
  final Future<void> Function(String query) onSearch;
  final Future<void> Function(int customerUserId) onOpenDetails;

  const _SuperAdminInsightsSection({
    required this.loading,
    required this.total,
    required this.items,
    required this.onSearch,
    required this.onOpenDetails,
  });

  @override
  State<_SuperAdminInsightsSection> createState() =>
      _SuperAdminInsightsSectionState();
}

class _SuperAdminInsightsSectionState extends State<_SuperAdminInsightsSection> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ù…Ù„ÙØ§Øª Ø§Ù„Ø¹Ù…Ù„Ø§Ø¡ Ø§Ù„Ø°ÙƒÙŠØ©',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 4),
              Text(
                'Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø¹Ù…Ù„Ø§Ø¡: ${widget.total}',
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      textDirection: TextDirection.rtl,
                      decoration: const InputDecoration(
                        hintText: 'Ø§Ø¨Ø­Ø« Ø¨Ø§Ù„Ø§Ø³Ù… Ø£Ùˆ Ø§Ù„Ù‡Ø§ØªÙ Ø£Ùˆ Ø§Ù„Ø¨Ù„ÙˆÙƒ',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (value) => widget.onSearch(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => widget.onSearch(_searchCtrl.text),
                    child: const Text('Ø¨Ø­Ø«'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (widget.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Ù„Ø§ ØªÙˆØ¬Ø¯ Ù…Ù„ÙØ§Øª Ù„Ø¹Ø±Ø¶Ù‡Ø§',
                    textAlign: TextAlign.right,
                  ),
                )
              else
                ...widget.items.take(20).map((item) {
                  final userId = (item['id'] is int)
                      ? item['id'] as int
                      : int.tryParse('${item['id'] ?? ''}') ?? 0;
                  return ListTile(
                    title: Text(
                      '${item['full_name'] ?? '-'}',
                      textDirection: TextDirection.rtl,
                    ),
                    subtitle: Text(
                      'Ù‡Ø§ØªÙ: ${item['phone'] ?? '-'} â€¢ Ø·Ù„Ø¨Ø§Øª: ${item['orders_count'] ?? 0} â€¢ ØµØ±Ù: ${item['total_spent'] ?? 0} IQD',
                      textDirection: TextDirection.rtl,
                    ),
                    trailing: TextButton(
                      onPressed: userId > 0
                          ? () => widget.onOpenDetails(userId)
                          : null,
                      child: const Text('Ø¹Ø±Ø¶'),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateUserSheet extends ConsumerStatefulWidget {
  const _CreateUserSheet();

  @override
  ConsumerState<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends ConsumerState<_CreateUserSheet> {
  final fullNameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final blockCtrl = TextEditingController(text: 'A');
  final buildingCtrl = TextEditingController(text: '1');
  final apartmentCtrl = TextEditingController(text: '1');
  LocalImageFile? userImageFile;
  String selectedRole = 'user';

  @override
  void dispose() {
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    pinCtrl.dispose();
    blockCtrl.dispose();
    buildingCtrl.dispose();
    apartmentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(adminControllerProvider).saving;
    final auth = ref.watch(authControllerProvider);
    final isAdmin = auth.isAdmin;
    final isSuperAdmin = auth.isSuperAdmin;

    final roleItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'user', child: Text('مستخدم عادي')),
      const DropdownMenuItem(value: 'owner', child: Text('صاحب متجر')),
      const DropdownMenuItem(value: 'delivery', child: Text('دلفري')),
      const DropdownMenuItem(value: 'deputy_admin', child: Text('نائب أدمن')),
      const DropdownMenuItem(value: 'call_center', child: Text('كول سنتر')),
      if (isSuperAdmin)
        const DropdownMenuItem(value: 'admin', child: Text('أدمن')),
    ];

    if (!isSuperAdmin && selectedRole == 'admin') {
      selectedRole = 'user';
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إنشاء حساب جديد',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fullNameCtrl,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'PIN'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                items: roleItems,
                onChanged: (v) => setState(() => selectedRole = v ?? 'user'),
                decoration: const InputDecoration(labelText: 'الدور'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: blockCtrl,
                      decoration: const InputDecoration(labelText: 'البلوك'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: buildingCtrl,
                      decoration: const InputDecoration(labelText: 'العمارة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: apartmentCtrl,
                      decoration: const InputDecoration(labelText: 'الشقة'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ImagePickerField(
                title: 'صورة الحساب (اختياري)',
                selectedFile: userImageFile,
                existingImageUrl: null,
                onPick: () async {
                  final picked = await pickImageFromDevice();
                  if (!mounted || picked == null) return;
                  setState(() => userImageFile = picked);
                },
                onClear: userImageFile == null
                    ? null
                    : () => setState(() => userImageFile = null),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: saving || !isAdmin
                    ? null
                    : () async {
                        await ref
                            .read(adminControllerProvider.notifier)
                            .createUser({
                              'fullName': fullNameCtrl.text,
                              'phone': phoneCtrl.text,
                              'pin': pinCtrl.text,
                              'block': blockCtrl.text,
                              'buildingNumber': buildingCtrl.text,
                              'apartment': apartmentCtrl.text,
                              'role': selectedRole,
                            }, imageFile: userImageFile);

                        if (!context.mounted) return;
                        final adminState = ref.read(adminControllerProvider);
                        if (adminState.error == null) {
                          Navigator.of(context).pop();
                        }
                      },
                child: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('إنشاء الحساب'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
