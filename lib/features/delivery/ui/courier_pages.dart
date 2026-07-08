import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../../features/notifications/ui/notifications_screen.dart';
import '../../../features/settings/ui/settings_screen.dart';
import '../../orders/models/order_model.dart';
import '../state/delivery_controller.dart';
import 'delivery_order_detail_screen.dart';
import 'delivery_dashboard_screen.dart';

class CourierDashboardPage extends StatelessWidget {
  const CourierDashboardPage({super.key});

  @override
  Widget build(BuildContext context) => const DeliveryDashboardScreen();
}

class CourierOrdersNewPage extends StatelessWidget {
  const CourierOrdersNewPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _CourierOrdersPage(mode: _OrdersMode.newOffers);
}

class CourierOrdersCurrentPage extends StatelessWidget {
  const CourierOrdersCurrentPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _CourierOrdersPage(mode: _OrdersMode.current);
}

class CourierOrdersWaitingPickupPage extends StatelessWidget {
  const CourierOrdersWaitingPickupPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _CourierOrdersPage(mode: _OrdersMode.waitingPickup);
}

class CourierOrdersInDeliveryPage extends StatelessWidget {
  const CourierOrdersInDeliveryPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _CourierOrdersPage(mode: _OrdersMode.inDelivery);
}

class CourierOrdersCompletedPage extends StatelessWidget {
  const CourierOrdersCompletedPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _CourierOrdersPage(mode: _OrdersMode.completed);
}

class CourierOrdersCancelledPage extends StatelessWidget {
  const CourierOrdersCancelledPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _CourierOrdersPage(mode: _OrdersMode.cancelled);
}

class CourierOrderDetailsPage extends StatelessWidget {
  const CourierOrderDetailsPage({super.key, this.orderId});

  final int? orderId;

  @override
  Widget build(BuildContext context) {
    final id = orderId;
    if (id == null || id <= 0) {
      return Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.deliveryCourierOrderDetailsTitle),
        ),
        body: Center(child: Text(context.l10n.deliveryCourierOrderNotFound)),
      );
    }
    return DeliveryOrderDetailScreen(orderId: id);
  }
}

class CourierEarningsPage extends StatelessWidget {
  const CourierEarningsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _CourierMetricsPage(earnings: true);
}

class CourierReportsPage extends StatelessWidget {
  const CourierReportsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _CourierMetricsPage(earnings: false);
}

class CourierCompetitionsPage extends StatelessWidget {
  const CourierCompetitionsPage({super.key});

  @override
  Widget build(BuildContext context) => const _CourierCompetitionsPage();
}

class CourierNotificationsPage extends StatelessWidget {
  const CourierNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) => const NotificationsScreen();
}

class CourierSettingsPage extends StatelessWidget {
  const CourierSettingsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const SettingsScreen(showUserDrawer: false);
}

class _CourierCompetitionsPage extends ConsumerStatefulWidget {
  const _CourierCompetitionsPage();

  @override
  ConsumerState<_CourierCompetitionsPage> createState() =>
      _CourierCompetitionsPageState();
}

class _CourierCompetitionsPageState
    extends ConsumerState<_CourierCompetitionsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(deliveryControllerProvider.notifier).bootstrap(),
    );
  }

  List<Map<String, dynamic>> _list(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  int _i(dynamic value) => value is int
      ? value
      : (value is num ? value.toInt() : int.tryParse('$value') ?? 0);

  double _d(dynamic value) => value is double
      ? value
      : (value is num ? value.toDouble() : double.tryParse('$value') ?? 0);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(deliveryControllerProvider);
    final active = _list(state.competitionsV2['competitions']);
    final history = _list(state.competitionsHistoryV2['competitions']);
    final progress = _list(
      state.competitionProgressV2['items'] ??
          state.competitionProgressV2['progress'],
    );
    final summary = Map<String, dynamic>.from(
      (state.competitionAchievementsV2['summary'] as Map?) ?? const {},
    );

    Map<String, dynamic>? findProgress(int competitionId) {
      for (final row in progress) {
        if (_i(row['competition_id'] ?? row['competitionId']) ==
            competitionId) {
          return row;
        }
      }
      return null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.deliveryCourierCompetitionsTitle),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(deliveryControllerProvider.notifier).bootstrap(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(deliveryControllerProvider.notifier).bootstrap(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (state.error != null) _Banner(text: state.error!, danger: true),
            _MetricCard(
              title: l10n.deliveryCourierCompetitionsParticipated,
              value: '${_i(summary['competitions_participated'])}',
            ),
            _MetricCard(
              title: l10n.deliveryCourierCompetitionsWins,
              value: '${_i(summary['competitions_won'])}',
            ),
            _MetricCard(
              title: l10n.deliveryCourierCompetitionsTotalRewards,
              value: formatIqd(_d(summary['total_rewards'])),
            ),
            const SizedBox(height: 8),
            Text(l10n.deliveryCourierCompetitionsActive),
            const SizedBox(height: 8),
            if (active.isEmpty)
              _Empty(text: l10n.deliveryCourierCompetitionsNoActive)
            else
              ...active.map((competition) {
                final progressRow = findProgress(_i(competition['id']));
                final title =
                    '${competition['title'] ?? l10n.deliveryCourierCompetitionsCompetitionFallback}';
                final rank =
                    '${progressRow?['current_rank_title'] ?? competition['current_rank_title'] ?? ''}'
                        .trim();
                final current = _d(
                  progressRow?['current_value'] ?? competition['current_value'],
                );
                final percent = _d(
                  progressRow?['progress_percent'] ??
                      competition['progress_percent'],
                ).clamp(0, 100);
                final remaining = _i(
                  progressRow?['remaining_to_next_rank'] ??
                      competition['remaining_to_next_rank'],
                );
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if ('${competition['description'] ?? ''}'
                            .trim()
                            .isNotEmpty)
                          Text('${competition['description']}'),
                        Text(
                          l10n.deliveryCourierCompetitionsCurrentProgress(
                            current.toStringAsFixed(0),
                          ),
                        ),
                        if (rank.isNotEmpty)
                          Text(
                            l10n.deliveryCourierCompetitionsCurrentRank(rank),
                          ),
                        if (remaining > 0)
                          Text(
                            l10n.deliveryCourierCompetitionsOrdersToNextRank(
                              '$remaining',
                            ),
                          ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (percent / 100).clamp(0, 1),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            Text(l10n.deliveryCourierCompetitionsPast),
            const SizedBox(height: 8),
            if (history.isEmpty)
              _Empty(text: l10n.deliveryCourierCompetitionsNoPast)
            else
              ...history.map(
                (competition) => ListTile(
                  title: Text(
                    '${competition['title'] ?? l10n.deliveryCourierCompetitionsCompetitionFallback}',
                  ),
                  subtitle: Text(
                    '${competition['status'] ?? l10n.deliveryCourierCompetitionsEnded}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _OrdersMode {
  newOffers,
  current,
  waitingPickup,
  inDelivery,
  completed,
  cancelled,
}

class _CourierOrdersPage extends ConsumerStatefulWidget {
  const _CourierOrdersPage({required this.mode});

  final _OrdersMode mode;

  @override
  ConsumerState<_CourierOrdersPage> createState() => _CourierOrdersPageState();
}

class _CourierOrdersPageState extends ConsumerState<_CourierOrdersPage> {
  bool _bootstrapped = false;
  late final DeliveryController _deliveryController;

  bool get _live =>
      widget.mode == _OrdersMode.current ||
      widget.mode == _OrdersMode.waitingPickup ||
      widget.mode == _OrdersMode.inDelivery ||
      widget.mode == _OrdersMode.newOffers;

  @override
  void initState() {
    super.initState();
    _deliveryController = ref.read(deliveryControllerProvider.notifier);
    Future.microtask(() async {
      if (!mounted) return;
      await _deliveryController.bootstrap();
      if (!mounted) return;
      if (_live) _deliveryController.startLiveOrders();
      setState(() => _bootstrapped = true);
    });
  }

  @override
  void dispose() {
    if (_live) _deliveryController.stopLiveOrders();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_live) {
      await _deliveryController.refreshCurrentOrders();
    } else {
      await _deliveryController.bootstrap();
    }
  }

  List<OrderModel> _orders(DeliveryState state) {
    final all = [...state.currentOrders, ...state.historyOrders];
    switch (widget.mode) {
      case _OrdersMode.current:
        return all
            .where(
              (order) => !const {
                'delivered',
                'received',
                'completed',
                'cancelled',
                'failed_delivery',
                'returned_if_needed',
              }.contains(normalizeOrderStatusForUi(order.status)),
            )
            .toList();
      case _OrdersMode.completed:
        return all
            .where(
              (order) => const {
                'delivered',
                'received',
                'completed',
              }.contains(normalizeOrderStatusForUi(order.status)),
            )
            .toList();
      case _OrdersMode.cancelled:
        return all
            .where(
              (order) => const {
                'cancelled',
                'failed_delivery',
                'returned_if_needed',
              }.contains(normalizeOrderStatusForUi(order.status)),
            )
            .toList();
      case _OrdersMode.waitingPickup:
        // Assigned to this courier, accepted, merchant preparing/ready, but not
        // picked up yet — this is NOT the same as new (unaccepted) offers.
        return all
            .where(
              (order) =>
                  order.deliveryUserId != null &&
                  const {
                    'approved',
                    'preparing',
                    'ready_for_delivery',
                  }.contains(normalizeOrderStatusForUi(order.status)),
            )
            .toList();
      case _OrdersMode.inDelivery:
        // Only orders that are actually in transit to the customer.
        return all
            .where(
              (order) =>
                  order.deliveryUserId != null &&
                  const {
                    'picked_up',
                    'on_the_way',
                    'arrived',
                  }.contains(normalizeOrderStatusForUi(order.status)),
            )
            .toList();
      case _OrdersMode.newOffers:
        return const [];
    }
  }

  List<Map<String, dynamic>> _offers(DeliveryState state) => state
      .pendingRequests
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();

  String _title(BuildContext context) {
    final l10n = context.l10n;
    switch (widget.mode) {
      case _OrdersMode.newOffers:
        return l10n.deliveryCourierNewOffersTitle;
      case _OrdersMode.current:
        return l10n.deliveryCourierCurrentOrdersTitle;
      case _OrdersMode.waitingPickup:
        return l10n.deliveryWaitingPickup;
      case _OrdersMode.inDelivery:
        return l10n.deliveryOnTheWay;
      case _OrdersMode.completed:
        return l10n.deliveryCourierCompletedOrdersTitle;
      case _OrdersMode.cancelled:
        return l10n.deliveryCourierCancelledOrdersTitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(deliveryControllerProvider);
    final controller = ref.read(deliveryControllerProvider.notifier);
    final orders = _orders(state);
    final offers = _offers(state);

    return Scaffold(
      appBar: AppBar(title: Text(_title(context))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (state.error != null) _Banner(text: state.error!, danger: true),
            if (!_bootstrapped && state.loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (widget.mode == _OrdersMode.newOffers)
              if (offers.isEmpty)
                _Empty(text: l10n.deliveryCourierNoNewOffers)
              else
                ...offers.map(
                  (row) => _OfferCard(
                    data: row,
                    saving: state.saving,
                    onAccept: (id) => controller.acceptRequest(id),
                    onReject: (id) => controller.rejectRequest(id),
                  ),
                )
            else if (orders.isEmpty)
              _Empty(text: l10n.deliveryCourierNoItems)
            else
              ...orders.map(
                (order) => _OrderCard(
                  order: order,
                  saving: state.saving,
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CourierOrderDetailsPage(orderId: order.id),
                    ),
                  ),
                  onPickedUp: () => controller.pickedUpOrder(order.id),
                  onArrived: () => controller.arrivedOrder(order.id),
                  onDelivered: () => controller.deliveredOrder(order.id),
                  showActions:
                      widget.mode == _OrdersMode.current ||
                      widget.mode == _OrdersMode.waitingPickup ||
                      widget.mode == _OrdersMode.inDelivery,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CourierMetricsPage extends ConsumerStatefulWidget {
  const _CourierMetricsPage({required this.earnings});

  final bool earnings;

  @override
  ConsumerState<_CourierMetricsPage> createState() =>
      _CourierMetricsPageState();
}

class _CourierMetricsPageState extends ConsumerState<_CourierMetricsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(deliveryControllerProvider.notifier).bootstrap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(deliveryControllerProvider);
    final day = Map<String, dynamic>.from(
      (state.analytics['day'] as Map?) ?? const {},
    );
    final dashboardKpis = _extractCourierDashboardKpis(state.dashboardV2);
    final todayFees = _readMetricDouble(
      dashboardKpis,
      const ['todayEarnings', 'today_earnings'],
      fallback: _readMetricDouble(day, const ['delivery_fees', 'deliveryFees']),
    );
    final completedToday = _readMetricInt(
      dashboardKpis,
      const ['completedOrders', 'completed_orders'],
      fallback: _readMetricInt(day, const [
        'delivered_orders_count',
        'deliveredOrdersCount',
      ]),
    );
    final averageRating = _readMetricDouble(day, const [
      'avg_rating',
      'avgRating',
      'avg_delivery_rating',
    ]);
    final reports = Map<String, dynamic>.from(state.reportsV2);
    final reportSummary = Map<String, dynamic>.from(
      (reports['summary'] as Map?) ?? reports,
    );
    final reportPeriods = _courierReportPeriods(reportSummary);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.earnings
              ? l10n.deliveryCourierEarningsTitle
              : l10n.deliveryCourierReportsTitle,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(deliveryControllerProvider.notifier).bootstrap(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (widget.earnings) ...[
              _MetricCard(
                title: l10n.deliveryCourierTodayFees,
                value: formatIqd(todayFees),
              ),
              _MetricCard(
                title: l10n.deliveryCourierCompletedToday,
                value: '$completedToday',
              ),
              _MetricCard(
                title: l10n.deliveryCourierAverageRating,
                value: averageRating.toStringAsFixed(1),
              ),
            ] else if (reportPeriods.isEmpty) ...[
              _Empty(text: l10n.deliveryCourierNoReportData),
            ] else ...[
              ...reportPeriods.map(
                (period) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          period.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        _MetricCard(
                          title: l10n.deliveryCourierTodayFees,
                          value: formatIqd(period.deliveryFees),
                        ),
                        _MetricCard(
                          title: l10n.deliveryCourierCompletedToday,
                          value: '${period.deliveredOrdersCount}',
                        ),
                        _MetricCard(
                          title: l10n.deliveryCourierAverageRating,
                          value: period.avgRating.toStringAsFixed(1),
                        ),
                        _MetricCard(
                          title: context.lt(
                            ar: 'رسوم الخدمة',
                            en: 'Service fee',
                          ),
                          value: formatIqd(period.serviceFeeAmount),
                        ),
                        _MetricCard(
                          title: context.lt(ar: 'العمولة', en: 'Commission'),
                          value: formatIqd(period.commissionAmount),
                        ),
                        _MetricCard(
                          title: context.lt(ar: 'ذمة التطبيق', en: 'App due'),
                          value: formatIqd(period.appDueFromDelivery),
                        ),
                        _MetricCard(
                          title: context.lt(ar: 'الفروقات', en: 'Differences'),
                          value: formatIqd(period.differenceAmount),
                        ),
                        _MetricCard(
                          title: context.lt(ar: 'صافي المتجر', en: 'Store net'),
                          value: formatIqd(period.storeNetReceivedAmount),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _extractCourierDashboardKpis(
  Map<String, dynamic> dashboardV2,
) {
  final rawKpis = dashboardV2['kpis'];
  if (rawKpis is! Map) return const {};
  final kpis = Map<String, dynamic>.from(rawKpis);
  final day = kpis['day'];
  if (day is! Map) return kpis;
  final dayMap = Map<String, dynamic>.from(day);
  return {
    'completedOrders': _readMetricInt(dayMap, const [
      'delivered_orders_count',
      'deliveredOrdersCount',
    ]),
    'todayEarnings': _readMetricDouble(dayMap, const [
      'delivery_fees',
      'deliveryFees',
      'todayEarnings',
    ]),
    ...kpis,
  };
}

double _readMetricDouble(
  Map<String, dynamic> map,
  List<String> keys, {
  double fallback = 0,
}) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse('$value');
    if (parsed != null) return parsed;
  }
  return fallback;
}

int _readMetricInt(
  Map<String, dynamic> map,
  List<String> keys, {
  int fallback = 0,
}) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    if (value is num) return value.toInt();
    final parsed = int.tryParse('$value');
    if (parsed != null) return parsed;
  }
  return fallback;
}

List<_CourierReportPeriod> _courierReportPeriods(Map<String, dynamic> summary) {
  const keys = ['day', 'week', 'month', 'year', 'all'];
  return [
    for (final key in keys)
      if (summary[key] is Map)
        _CourierReportPeriod.fromMap(
          key,
          Map<String, dynamic>.from(summary[key] as Map),
        ),
  ];
}

class _CourierReportPeriod {
  final String key;
  final String label;
  final int deliveredOrdersCount;
  final double deliveryFees;
  final double serviceFeeAmount;
  final double commissionAmount;
  final double storeNetReceivedAmount;
  final double appDueFromDelivery;
  final double differenceAmount;
  final double avgRating;

  const _CourierReportPeriod({
    required this.key,
    required this.label,
    required this.deliveredOrdersCount,
    required this.deliveryFees,
    required this.serviceFeeAmount,
    required this.commissionAmount,
    required this.storeNetReceivedAmount,
    required this.appDueFromDelivery,
    required this.differenceAmount,
    required this.avgRating,
  });

  factory _CourierReportPeriod.fromMap(String key, Map<String, dynamic> map) {
    final label = switch (key) {
      'day' => 'Today / اليوم',
      'week' => 'Week / الأسبوع',
      'month' => 'Month / الشهر',
      'year' => 'Year / السنة',
      _ => 'All time / الكل',
    };
    return _CourierReportPeriod(
      key: key,
      label: label,
      deliveredOrdersCount: _readMetricInt(map, const [
        'delivered_orders_count',
        'deliveredOrdersCount',
      ]),
      deliveryFees: _readMetricDouble(map, const [
        'delivery_fees',
        'deliveryFees',
        'todayEarnings',
      ]),
      serviceFeeAmount: _readMetricDouble(map, const [
        'service_fee_amount',
        'serviceFeeAmount',
      ]),
      commissionAmount: _readMetricDouble(map, const [
        'commission_amount',
        'commissionAmount',
      ]),
      storeNetReceivedAmount: _readMetricDouble(map, const [
        'store_net_received_amount',
        'storeNetReceivedAmount',
      ]),
      appDueFromDelivery: _readMetricDouble(map, const [
        'app_due_from_delivery',
        'appDueFromDelivery',
      ]),
      differenceAmount: _readMetricDouble(map, const [
        'difference_amount',
        'differenceAmount',
      ]),
      avgRating: _readMetricDouble(map, const [
        'avg_rating',
        'avgRating',
        'avg_delivery_rating',
      ]),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.data,
    required this.saving,
    required this.onAccept,
    required this.onReject,
  });

  final Map<String, dynamic> data;
  final bool saving;
  final Future<void> Function(int orderId) onAccept;
  final Future<void> Function(int orderId) onReject;

  int? _id(dynamic value) => value is int ? value : int.tryParse('$value');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final orderId =
        _id(data['orderId']) ?? _id(data['order_id']) ?? _id(data['id']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.deliveryCourierOfferTitle} #${orderId ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '${l10n.deliveryCourierLabelMerchant}: ${data['merchant_name'] ?? data['merchantName'] ?? '-'}',
            ),
            Text(
              '${l10n.deliveryCourierLabelCustomer}: ${data['customer_name'] ?? data['customerName'] ?? '-'}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: saving || orderId == null
                      ? null
                      : () => onAccept(orderId),
                  child: Text(l10n.deliveryCourierAccept),
                ),
                OutlinedButton(
                  onPressed: saving || orderId == null
                      ? null
                      : () => onReject(orderId),
                  child: Text(l10n.deliveryCourierReject),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.saving,
    required this.showActions,
    required this.onOpen,
    required this.onPickedUp,
    required this.onArrived,
    required this.onDelivered,
  });

  final OrderModel order;
  final bool saving;
  final bool showActions;
  final VoidCallback? onOpen;
  final Future<void> Function() onPickedUp;
  final Future<void> Function() onArrived;
  final Future<void> Function() onDelivered;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = normalizeOrderStatusForUi(order.status);
    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.deliveryCourierOrderLabel} #${order.id}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(orderStatusLabel(order.status)),
              Text(
                '${l10n.deliveryCourierLabelMerchant}: ${order.merchantName}',
              ),
              Text(
                '${l10n.deliveryCourierLabelCustomer}: ${order.customerFullName}',
              ),
              Text(
                '${l10n.deliveryCourierLabelTotal}: ${formatIqd(order.totalAmount)}',
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(
                    context.lt(ar: 'عرض التفاصيل', en: 'View details'),
                  ),
                ),
              ),
              if (showActions)
                Wrap(
                  spacing: 8,
                  children: [
                    if (const {
                      'ready_for_delivery',
                      'preparing',
                      'approved',
                    }.contains(status))
                      ElevatedButton(
                        onPressed: saving ? null : onPickedUp,
                        child: Text(l10n.deliveryCourierActionPickedUp),
                      ),
                    if (status == 'on_the_way')
                      ElevatedButton(
                        onPressed: saving ? null : onArrived,
                        child: Text(l10n.deliveryCourierActionArrived),
                      ),
                    if (status == 'arrived')
                      ElevatedButton(
                        onPressed: saving ? null : onDelivered,
                        child: Text(l10n.deliveryCourierActionDelivered),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(title),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: Colors.white.withValues(alpha: 0.06),
    ),
    child: Text(text, textAlign: TextAlign.center),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: (danger ? Colors.red : Colors.blue).withValues(alpha: 0.12),
    ),
    child: Text(text),
  );
}
