// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/notifications/attention_alert_service.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../../auth/state/auth_controller.dart';
import '../../pharmacy/ui/pharmacy_conversation_screen.dart';
import '../../tracking/ui/delivery_live_tracking_screen.dart';
import '../models/order_model.dart';
import '../state/orders_controller.dart';
import 'order_chat_screen.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

enum CustomerOrdersFilter {
  all('all'),
  active('active'),
  delivered('delivered'),
  cancelled('cancelled');

  const CustomerOrdersFilter(this.value);
  final String value;
}

double _responsiveFont(
  BuildContext context,
  double base, {
  double minFactor = 0.90,
  double maxFactor = 1.14,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final factor = (width / 390).clamp(minFactor, maxFactor);
  return base * factor;
}

class CustomerOrdersScreen extends ConsumerStatefulWidget {
  final int? initialOrderId;
  final CustomerOrdersFilter initialStatusFilter;

  const CustomerOrdersScreen({
    super.key,
    this.initialOrderId,
    this.initialStatusFilter = CustomerOrdersFilter.all,
  });

  @override
  ConsumerState<CustomerOrdersScreen> createState() =>
      _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends ConsumerState<CustomerOrdersScreen> {
  int? _focusedOrderId;
  Timer? _deliveryConfirmationAlertTimer;
  int _deliveryConfirmationSignature = 0;
  String _statusFilter = 'all';
  late final OrdersController _ordersController;

  @override
  void initState() {
    super.initState();
    _ordersController = ref.read(ordersControllerProvider.notifier);
    _focusedOrderId = widget.initialOrderId;
    _statusFilter = widget.initialStatusFilter.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapOrders());
    });
  }

  Future<void> _bootstrapOrders() async {
    if (!mounted) return;
    await _ordersController.loadMyOrders();
    if (!mounted) return;
    _ordersController.startLiveOrders();
  }

  void _syncDeliveredAlerts(List<OrderModel> orders) {
    final awaitingIds =
        orders
            .where(
              (order) =>
                  order.status == 'delivered' &&
                  order.customerConfirmedAt == null,
            )
            .map((order) => order.id)
            .toList()
          ..sort();

    if (awaitingIds.isEmpty) {
      _stopDeliveredAlerts();
      return;
    }

    final signature = Object.hashAll(awaitingIds);
    if (signature != _deliveryConfirmationSignature) {
      _deliveryConfirmationSignature = signature;
      _playDeliveredAlert();
    }

    _deliveryConfirmationAlertTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _playDeliveredAlert(),
    );
  }

  void _playDeliveredAlert() {
    ref.read(attentionAlertServiceProvider).play();
  }

  void _stopDeliveredAlerts() {
    _deliveryConfirmationAlertTimer?.cancel();
    _deliveryConfirmationAlertTimer = null;
    _deliveryConfirmationSignature = 0;
  }

  @override
  void dispose() {
    _stopDeliveredAlerts();
    _ordersController.stopLiveOrders();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ordersControllerProvider);
    _syncDeliveredAlerts(state.orders);

    ref.listen<OrdersState>(ordersControllerProvider, (prev, next) {
      if (!mounted) return;
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      _syncDeliveredAlerts(next.orders);
    });

    final orders = _prioritizeOrders(state.orders, _focusedOrderId);
    final filteredOrders = _filterOrdersByStatus(orders, _statusFilter);
    final activeCount = _filterOrdersByStatus(orders, 'active').length;
    final deliveredCount = _filterOrdersByStatus(orders, 'delivered').length;
    final cancelledCount = _filterOrdersByStatus(orders, 'cancelled').length;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'طلباتي', en: 'My orders')),
        actions: const [AppBarQuickActions(compact: true)],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(ordersControllerProvider.notifier).loadMyOrders(),
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : filteredOrders.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: 140),
                  Center(
                    child: Text(
                      context.lt(
                        ar: 'لا توجد طلبات حاليًا',
                        en: 'No orders right now',
                      ),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _OrdersFilterStrip(
                    selected: _statusFilter,
                    totalCount: orders.length,
                    activeCount: activeCount,
                    deliveredCount: deliveredCount,
                    cancelledCount: cancelledCount,
                    onSelect: (value) => setState(() => _statusFilter = value),
                  ),
                  const SizedBox(height: 10),
                  ...filteredOrders.map((order) {
                    final highlighted = _focusedOrderId == order.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OrderCard(order: order, highlighted: highlighted),
                    );
                  }),
                ],
              ),
      ),
    );
  }

  List<OrderModel> _filterOrdersByStatus(
    List<OrderModel> orders,
    String filter,
  ) {
    switch (filter) {
      case 'active':
        return orders
            .where(
              (order) =>
                  order.status != 'cancelled' &&
                  order.customerConfirmedAt == null,
            )
            .toList(growable: false);
      case 'delivered':
        return orders
            .where(
              (order) =>
                  order.status == 'delivered' ||
                  order.customerConfirmedAt != null,
            )
            .toList(growable: false);
      case 'cancelled':
        return orders
            .where((order) => order.status == 'cancelled')
            .toList(growable: false);
      default:
        return orders;
    }
  }

  List<OrderModel> _prioritizeOrders(
    List<OrderModel> orders,
    int? focusOrderId,
  ) {
    if (focusOrderId == null) return orders;
    final list = [...orders];
    final index = list.indexWhere((o) => o.id == focusOrderId);
    if (index <= 0) return list;
    final target = list.removeAt(index);
    list.insert(0, target);
    return list;
  }
}

class _OrdersFilterStrip extends StatelessWidget {
  final String selected;
  final int totalCount;
  final int activeCount;
  final int deliveredCount;
  final int cancelledCount;
  final ValueChanged<String> onSelect;

  const _OrdersFilterStrip({
    required this.selected,
    required this.totalCount,
    required this.activeCount,
    required this.deliveredCount,
    required this.cancelledCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        children: [
          _OrdersFilterCard(
            label: 'الكل',
            count: totalCount,
            selected: selected == 'all',
            onTap: () => onSelect('all'),
          ),
          const SizedBox(width: 8),
          _OrdersFilterCard(
            label: 'قيد التنيذ',
            count: activeCount,
            selected: selected == 'active',
            onTap: () => onSelect('active'),
          ),
          const SizedBox(width: 8),
          _OrdersFilterCard(
            label: 'تم التوصيل',
            count: deliveredCount,
            selected: selected == 'delivered',
            onTap: () => onSelect('delivered'),
          ),
          const SizedBox(width: 8),
          _OrdersFilterCard(
            label: 'الملغاة',
            count: cancelledCount,
            selected: selected == 'cancelled',
            onTap: () => onSelect('cancelled'),
          ),
        ],
      ),
    );
  }
}

class _OrdersFilterCard extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _OrdersFilterCard({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          width: 138,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? scheme.primary.withValues(alpha: 0.2)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.42),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.34)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                label,
                textDirection: TextDirection.rtl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final bool highlighted;

  const _OrderCard({required this.order, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final status = orderStatusLabelForCustomer(
      order.status,
      customerConfirmed: order.customerConfirmedAt != null,
    );
    final progress = _buildProgress(order);
    final stepLabel = _kTrackingSteps[progress.activeIndex].label;
    final completion = _timelineCompletion(order, progress);
    final isLive =
        order.status != 'cancelled' && order.customerConfirmedAt == null;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: highlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) {
                // Live map tracking only has data once a courier is actually in
                // transit. For earlier stages (pending/approved/preparing) the
                // live snapshot is empty and the map screen hangs on a spinner —
                // show the status-timeline screen instead, which renders
                // instantly from the already-loaded order.
                const inTransit = {'on_the_way', 'arrived'};
                final showLiveMap = inTransit.contains(order.status) &&
                    order.customerConfirmedAt == null;
                return showLiveMap
                    ? DeliveryLiveTrackingScreen(orderId: order.id)
                    : _OrderTrackingDetailsScreen(
                        orderId: order.id,
                        fallbackOrder: order,
                      );
              },
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: Text(
                      '\u0637\u0644\u0628 #${order.id}',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: _responsiveFont(context, 16.4),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isLive
                          ? Colors.cyan.withValues(alpha: 0.15)
                          : order.status == 'cancelled'
                          ? Colors.red.withValues(alpha: 0.16)
                          : Colors.green.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: _responsiveFont(context, 11.8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '\u0627\u0644\u0645\u062a\u062c\u0631: ${order.merchantName}',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: _responsiveFont(context, 13),
                ),
              ),
              if (order.isPharmacyFlow) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.lightBlue.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'طلب صيدلية',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '\u0627\u0644\u0625\u062c\u0645\u0627\u0644\u064a: ${formatIqd(order.totalAmount)}',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: _responsiveFont(context, 14),
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  if (isLive)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      order.status == 'cancelled'
                          ? Icons.cancel_outlined
                          : Icons.check_circle_outline_rounded,
                      size: 16,
                      color: order.status == 'cancelled'
                          ? Colors.red.shade300
                          : Colors.green.shade300,
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isLive
                          ? '\u0627\u0644\u0645\u0631\u062d\u0644\u0629 \u0627\u0644\u062d\u0627\u0644\u064a\u0629: $stepLabel'
                          : status,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: _responsiveFont(context, 12.5),
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: completion,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderTrackingDetailsScreen extends ConsumerStatefulWidget {
  final int orderId;
  final OrderModel fallbackOrder;

  const _OrderTrackingDetailsScreen({
    required this.orderId,
    required this.fallbackOrder,
  });

  @override
  ConsumerState<_OrderTrackingDetailsScreen> createState() =>
      _OrderTrackingDetailsScreenState();
}

class _OrderTrackingDetailsScreenState
    extends ConsumerState<_OrderTrackingDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ordersControllerProvider);
    final order = _resolveOrder(state.orders);
    final progress = _buildProgress(order);
    final completion = _timelineCompletion(order, progress);
    final isCancelled = order.status == 'cancelled';
    final isLive = !isCancelled && order.customerConfirmedAt == null;
    final currentStep = _kTrackingSteps[progress.activeIndex].label;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '\u062a\u062a\u0628\u0639 \u0637\u0644\u0628 #${order.id}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: _responsiveFont(context, 18),
          ),
        ),
        actions: const [AppBarQuickActions(compact: true)],
      ),
      bottomNavigationBar: _TrackingLiveBottomBar(
        isLive: isLive,
        isCancelled: isCancelled,
        currentStepLabel: currentStep,
        completion: completion,
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(ordersControllerProvider.notifier).loadMyOrders(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 130),
          children: [
            _TrackingHeroCard(
              order: order,
              currentStepLabel: currentStep,
              isLive: isLive,
            ),
            const SizedBox(height: 12),
            _OrderJourneyRibbon(
              order: order,
              progress: progress,
              isCancelled: isCancelled,
            ),
            const SizedBox(height: 12),
            _OrderStatusTimeline(order: order),
            if (const {
                  'on_the_way',
                  'arrived',
                  'delivered',
                }.contains(order.status) &&
                order.customerConfirmedAt == null) ...[
              const SizedBox(height: 12),
              _DeliveryEtaPanel(order: order),
            ],
            if (order.deliveryFullName != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Text(
                  '\u0627\u0644\u0633\u0627\u0626\u0642: ${order.deliveryFullName} - ${order.deliveryPhone ?? ''}',
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
            if (order.imageUrl?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedAppImage(
                  imageUrl: order.imageUrl!,
                  height: 170,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (_, error, stackTrace) => Container(
                    height: 110,
                    alignment: Alignment.center,
                    color: Colors.black12,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _OrderItemsSection(order: order),
            const SizedBox(height: 12),
            _OrderInvoiceSection(order: order),
            const SizedBox(height: 12),
            _buildActions(order),
          ],
        ),
      ),
    );
  }

  OrderModel _resolveOrder(List<OrderModel> orders) {
    for (final item in orders) {
      if (item.id == widget.orderId) return item;
    }
    return widget.fallbackOrder;
  }

  Future<_OrderActionReason?> _pickOrderReason({
    required String title,
    required List<_OrderActionReasonOption> options,
  }) async {
    _OrderActionReasonOption? selected = options.first;
    final otherCtrl = TextEditingController();
    final out = await showDialog<_OrderActionReason>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isOther =
                selected?.allowsOtherText == true || selected?.code == 'other';
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DropdownButtonFormField<_OrderActionReasonOption>(
                    initialValue: selected,
                    items: options
                        .map(
                          (option) =>
                              DropdownMenuItem<_OrderActionReasonOption>(
                                value: option,
                                child: Text(option.label),
                              ),
                        )
                        .toList(),
                    onChanged: (value) => setModalState(() => selected = value),
                    decoration: const InputDecoration(labelText: 'سبب الإجراء'),
                  ),
                  if (isOther) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: otherCtrl,
                      minLines: 2,
                      maxLines: 4,
                      textDirection: TextDirection.rtl,
                      decoration: const InputDecoration(
                        labelText: 'اكتب السبب',
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () {
                    final current = selected;
                    if (current == null) return;
                    final reasonText =
                        current.allowsOtherText || current.code == 'other'
                        ? otherCtrl.text.trim()
                        : null;
                    if ((current.allowsOtherText || current.code == 'other') &&
                        (reasonText ?? '').isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop(
                      _OrderActionReason(code: current.code, text: reasonText),
                    );
                  },
                  child: const Text('تأكيد'),
                ),
              ],
            );
          },
        );
      },
    );
    otherCtrl.dispose();
    return out;
  }

  Future<List<_OrderActionReasonOption>> _loadReasonOptions({
    required String actionKind,
    required List<_OrderActionReasonOption> fallback,
  }) async {
    try {
      final remote = await ref
          .read(ordersApiProvider)
          .listOrderActionReasons(
            actorScope: 'customer',
            actionKind: actionKind,
          );
      if (remote.isNotEmpty) {
        return remote
            .map(
              (item) => _OrderActionReasonOption(
                item.reasonCode,
                item.label,
                allowsOtherText: item.allowsOtherText,
              ),
            )
            .toList(growable: false);
      }
    } catch (_) {
      // Keep fallback options when endpoint is unavailable.
    }
    return fallback;
  }

  Future<void> _cancelOrderByReason(OrderModel order) async {
    final options = await _loadReasonOptions(
      actionKind: 'cancel',
      fallback: const [
        _OrderActionReasonOption('changed_mind', 'غيّرت رغبتي'),
        _OrderActionReasonOption('address_issue', 'مشكلة في العنوان'),
        _OrderActionReasonOption('duplicate_order', 'طلب مكرر'),
        _OrderActionReasonOption('other', 'سبب آخر', allowsOtherText: true),
      ],
    );
    if (options.isEmpty) return;
    final reason = await _pickOrderReason(
      title: 'إلغاء الطلب',
      options: const [
        _OrderActionReasonOption('changed_mind', 'غيّرت رأيي'),
        _OrderActionReasonOption('delay_too_long', 'التأخير طويل'),
        _OrderActionReasonOption('wrong_address', 'تعديل العنوان'),
        _OrderActionReasonOption('other', 'سبب آخر'),
      ],
    );
    if (reason == null || !mounted) return;
    final ok = await ref
        .read(ordersControllerProvider.notifier)
        .cancelOrderByCustomer(
          orderId: order.id,
          reasonCode: reason.code,
          reasonText: reason.text,
        );
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إرسال إلغاء الطلب بنجاح.')),
    );
  }

  Future<void> _requestReturnByReason(OrderModel order) async {
    final reason = await _pickOrderReason(
      title: 'طلب إرجاع',
      options: const [
        _OrderActionReasonOption('item_damaged', 'المنتج تالف'),
        _OrderActionReasonOption('wrong_item', 'تم استلام منتج خاطئ'),
        _OrderActionReasonOption('quality_issue', 'جودة غير مطابقة'),
        _OrderActionReasonOption('other', 'سبب آخر'),
      ],
    );
    if (reason == null || !mounted) return;
    final ok = await ref
        .read(ordersControllerProvider.notifier)
        .requestReturnByCustomer(
          orderId: order.id,
          reasonCode: reason.code,
          reasonText: reason.text,
        );
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إرسال طلب الإرجاع بنجاح.')),
    );
  }

  Future<void> _openOrderGroupBreakdown(OrderModel order) async {
    if (order.orderGroupId == null) return;
    try {
      final data = await ref
          .read(ordersApiProvider)
          .getOrderGroupDetails(order.orderGroupId!);
      if (!mounted) return;
      final children = List<Map<String, dynamic>>.from(
        (data['children'] as List? ?? const []).map(
          (entry) => Map<String, dynamic>.from(entry as Map),
        ),
      );
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تفاصيل الطلب المجمّع #${data['id'] ?? order.orderGroupId}',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: children
                        .map(
                          (child) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                '${child['merchant_name'] ?? child['merchantName'] ?? 'متجر'}',
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                              ),
                              subtitle: Text(
                                'الحالة: ${orderStatusLabelForCustomer('${child['status'] ?? ''}', customerConfirmed: false)}\nالإجمالي: ${formatIqd((child['total_amount'] as num?)?.toDouble() ?? 0)}',
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر تحميل تفاصيل التقسيم: $e')));
    }
  }

  Widget _buildActions(OrderModel order) {
    return Column(
      children: [
        if (order.pharmacyConversationId != null) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PharmacyConversationScreen(
                      conversationId: order.pharmacyConversationId,
                      titleOverride: order.merchantName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.local_pharmacy_outlined),
              label: const Text('فتح محادثة الصيدلية'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (order.deliveryUserId != null &&
            order.status != 'cancelled' &&
            order.customerConfirmedAt == null) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openDeliveryChat(order),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('محادثة الدلري'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _copyTrackingSummary(order),
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('نسخ تحديث الطلب للمشاركة'),
          ),
        ),
        if (order.orderGroupId != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openOrderGroupBreakdown(order),
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('عرض تقسيم الطلب حسب المتاجر'),
            ),
          ),
        ],
        if (const {
          'pending',
          'approved',
          'preparing',
          'courier_requested',
        }.contains(order.status)) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _cancelOrderByReason(order),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('إلغاء الطلب مع ذكر السبب'),
            ),
          ),
        ],
        if (const {
          'delivered',
          'completed',
          'received_by_customer',
        }.contains(order.status)) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _requestReturnByReason(order),
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('طلب إرجاع مع ذكر السبب'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (order.status == 'delivered' && order.customerConfirmedAt == null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final ok = await ref
                    .read(ordersControllerProvider.notifier)
                    .confirmDelivered(order.id);
                if (!ok || !mounted) return;

                final result = await _showRatingDialog(
                  context,
                  title:
                      '\u062a\u0642\u064a\u064a\u0645 \u0627\u0644\u062f\u0644\u0641\u0631\u064a',
                );
                if (!mounted) return;
                if (result != null) {
                  await ref
                      .read(ordersControllerProvider.notifier)
                      .rateDelivery(
                        orderId: order.id,
                        rating: result.rating,
                        review: result.review,
                      );
                }
                if (!mounted) return;
                await _showFirstAppRating(context, ref);
              },
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text(
                '\u062a\u0645 \u0627\u0633\u062a\u0644\u0627\u0645 \u0627\u0644\u0637\u0644\u0628',
              ),
            ),
          ),
        if (order.status == 'delivered') ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref
                    .read(ordersControllerProvider.notifier)
                    .reorder(order.id, note: order.note);
              },
              icon: const Icon(Icons.replay_rounded),
              label: const Text(
                '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0637\u0644\u0628',
              ),
            ),
          ),
        ],
        if (order.status == 'delivered' && order.deliveryRating == null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                final result = await _showRatingDialog(
                  context,
                  title:
                      '\u062a\u0642\u064a\u064a\u0645 \u0627\u0644\u062f\u0644\u0641\u0631\u064a',
                );
                if (result == null) return;
                await ref
                    .read(ordersControllerProvider.notifier)
                    .rateDelivery(
                      orderId: order.id,
                      rating: result.rating,
                      review: result.review,
                    );
              },
              child: const Text(
                '\u062a\u0642\u064a\u064a\u0645 \u0627\u0644\u062f\u0644\u0641\u0631\u064a',
              ),
            ),
          ),
        ],
        if (order.status == 'delivered' && order.merchantRating == null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                final result = await _showRatingDialog(
                  context,
                  title:
                      '\u062a\u0642\u064a\u064a\u0645 \u0627\u0644\u0645\u062a\u062c\u0631',
                );
                if (result == null) return;
                await ref
                    .read(ordersControllerProvider.notifier)
                    .rateMerchant(
                      orderId: order.id,
                      rating: result.rating,
                      review: result.review,
                    );
              },
              child: const Text(
                '\u062a\u0642\u064a\u064a\u0645 \u0627\u0644\u0645\u062a\u062c\u0631',
              ),
            ),
          ),
        ],
        if (order.deliveryRating != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '\u062a\u0642\u064a\u064a\u0645 \u0627\u0644\u062f\u0644\u0641\u0631\u064a: ${'\u2B50' * (order.deliveryRating ?? 0)}',
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
        if (order.merchantRating != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '\u062a\u0642\u064a\u064a\u0645 \u0627\u0644\u0645\u062a\u062c\u0631: ${'\u2B50' * (order.merchantRating ?? 0)}',
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openDeliveryChat(OrderModel order) async {
    final deliveryUserId = order.deliveryUserId;
    if (deliveryUserId == null) return;

    try {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrderChatScreen(
            orderId: order.id,
            title: 'محادثة الطلب #${order.id}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر فتح محادثة الطلب. ($e)')));
    }
  }

  Future<void> _copyTrackingSummary(OrderModel order) async {
    final progress = _buildProgress(order);
    final currentStep = _kTrackingSteps[progress.activeIndex].label;
    final eta = _computeEta(order, DateTime.now());
    final deliveryConfirmationHint = customerOrderTrackingHint(
      order.status,
      hasDeliveryAssigned:
          order.deliveryUserId != null || order.isMerchantDelivery,
      customerConfirmed: order.customerConfirmedAt != null,
    );
    final etaLabel = switch (order.status) {
      'on_the_way' =>
        eta.isLate
            ? 'متأخر (${eta.lateByMinutes} دقيقة) - وصول محدث خلال ${eta.minMinutes}-${eta.maxMinutes} دقيقة'
            : 'وصول خلال ${eta.minMinutes}-${eta.maxMinutes} دقيقة',
      'arrived' => 'الدلري وصل إلى موقعك',
      'delivered' when order.customerConfirmedAt == null =>
        deliveryConfirmationHint ?? 'تم التسليم وبانتظار تأكيدك',
      _ => 'غير متاح حاليًا',
    };

    final text =
        'تحديث الطلب #${order.id}\n'
        'المتجر: ${order.merchantName}\n'
        'الحالة: ${orderStatusLabelForCustomer(order.status, customerConfirmed: order.customerConfirmedAt != null)}\n'
        'المرحلة الحالية: $currentStep\n'
        'الوقت التقديري: $etaLabel\n'
        'الإجمالي: ${formatIqd(order.totalAmount)}';

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ التحديث إلى الحاظة')));
  }

  Future<_RatingResult?> _showRatingDialog(
    BuildContext context, {
    required String title,
  }) async {
    final reviewCtrl = TextEditingController();
    int rating = 5;
    final out = await showDialog<_RatingResult>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 4,
                  children: List.generate(5, (index) {
                    final value = index + 1;
                    final selected = value <= rating;
                    return IconButton(
                      onPressed: () => setState(() => rating = value),
                      icon: Icon(
                        selected
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: selected ? Colors.amber : null,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reviewCtrl,
                  decoration: const InputDecoration(
                    labelText:
                        '\u0645\u0644\u0627\u062d\u0638\u0627\u062a (\u0627\u062e\u062a\u064a\u0627\u0631\u064a)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('\u0625\u0644\u063a\u0627\u0621'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                    _RatingResult(
                      rating: rating,
                      review: reviewCtrl.text.trim(),
                    ),
                  );
                },
                child: const Text('\u0625\u0631\u0633\u0627\u0644'),
              ),
            ],
          );
        },
      ),
    );
    reviewCtrl.dispose();
    return out;
  }

  Future<void> _showFirstAppRating(BuildContext context, WidgetRef ref) async {
    final store = ref.read(secureStoreProvider);
    final alreadyPrompted =
        await store.readBool('app_rating_prompted') ?? false;
    if (alreadyPrompted) return;

    await store.writeBool('app_rating_prompted', true);
    if (!context.mounted) return;
    final appResult = await _showRatingDialog(
      context,
      title:
          '\u062a\u0642\u064a\u064a\u0645 \u0627\u0644\u062a\u0637\u0628\u064a\u0642',
    );
    if (appResult == null) return;

    await store.writeString('app_rating_value', '${appResult.rating}');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '\u0634\u0643\u0631\u0627\u064b \u0639\u0644\u0649 \u062a\u0642\u064a\u064a\u0645\u0643',
        ),
      ),
    );
  }
}

class _OrderActionReasonOption {
  final String code;
  final String label;
  final bool allowsOtherText;

  const _OrderActionReasonOption(
    this.code,
    this.label, {
    this.allowsOtherText = false,
  });
}

class _OrderActionReason {
  final String code;
  final String? text;

  const _OrderActionReason({required this.code, required this.text});
}

class _TrackingHeroCard extends StatelessWidget {
  final OrderModel order;
  final String currentStepLabel;
  final bool isLive;

  const _TrackingHeroCard({
    required this.order,
    required this.currentStepLabel,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.cyan.withValues(alpha: 0.22),
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: Text(
                  '\u0637\u0644\u0628 #${order.id}',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: _responsiveFont(context, 18.5),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (isLive)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  order.status == 'cancelled'
                      ? Icons.cancel_outlined
                      : Icons.check_circle_rounded,
                  color: order.status == 'cancelled'
                      ? Colors.red.shade300
                      : Colors.green.shade300,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '\u0627\u0644\u0645\u062a\u062c\u0631: ${order.merchantName}',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: _responsiveFont(context, 13.2),
            ),
          ),
          if (order.isPharmacyFlow) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.lightBlue.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'طلب صيدلية',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '\u0627\u0644\u0625\u062c\u0645\u0627\u0644\u064a: ${formatIqd(order.totalAmount)}',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: _responsiveFont(context, 14.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isLive
                ? '\u0627\u0644\u0645\u0631\u062d\u0644\u0629 \u0627\u0644\u062d\u0627\u0644\u064a\u0629: $currentStepLabel'
                : orderStatusLabelForCustomer(
                    order.status,
                    customerConfirmed: order.customerConfirmedAt != null,
                  ),
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: _responsiveFont(context, 13.5),
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderJourneyRibbon extends StatelessWidget {
  final OrderModel order;
  final _TimelineProgress progress;
  final bool isCancelled;

  const _OrderJourneyRibbon({
    required this.order,
    required this.progress,
    required this.isCancelled,
  });

  @override
  Widget build(BuildContext context) {
    final isDelivered = order.customerConfirmedAt != null;
    final doneFlags = List<bool>.generate(
      _kTrackingSteps.length,
      (index) =>
          index < progress.doneFlags.length ? progress.doneFlags[index] : false,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'رحلة الطلب المباشرة',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.4),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                for (var i = 0; i < _kTrackingSteps.length; i++) ...[
                  _JourneyStepNode(
                    step: _kTrackingSteps[i],
                    done: doneFlags[i] && !isCancelled,
                    active:
                        i == progress.activeIndex &&
                        !isCancelled &&
                        !isDelivered,
                  ),
                  if (i < _kTrackingSteps.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 17,
                        color: doneFlags[i]
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white54,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyStepNode extends StatelessWidget {
  final _TimelineStep step;
  final bool done;
  final bool active;

  const _JourneyStepNode({
    required this.step,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final border = done
        ? primary
        : active
        ? Colors.cyanAccent
        : Colors.white54;
    final bg = done
        ? primary.withValues(alpha: 0.18)
        : active
        ? Colors.cyan.withValues(alpha: 0.20)
        : Colors.white.withValues(alpha: 0.06);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 104, maxWidth: 124),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              border: Border.all(color: border, width: 1.6),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: border.withValues(alpha: 0.42),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: active
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    done ? Icons.check_rounded : step.icon,
                    size: 18,
                    color: done ? border : Colors.white,
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            step.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: _responsiveFont(context, 11.2),
              fontWeight: done || active ? FontWeight.w800 : FontWeight.w700,
              color: done || active ? Colors.white : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderItemsSection extends StatelessWidget {
  final OrderModel order;

  const _OrderItemsSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '\u062a\u0641\u0627\u0635\u064a\u0644 \u0627\u0644\u0637\u0644\u0628',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '- ${item.productName} \u00D7 ${item.quantity} (${formatIqd(item.lineTotal)})',
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderInvoiceSection extends StatelessWidget {
  final OrderModel order;

  const _OrderInvoiceSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        '\u0627\u0644\u0645\u062c\u0645\u0648\u0639 \u0627\u0644\u0641\u0631\u0639\u064a: ${formatIqd(order.subtotal)}\n'
        '\u0631\u0633\u0648\u0645 \u0627\u0644\u062e\u062f\u0645\u0629: ${formatIqd(order.serviceFee)}\n'
        '\u0623\u062c\u0648\u0631 \u0627\u0644\u062a\u0648\u0635\u064a\u0644: ${formatIqd(order.deliveryFee)}\n'
        '\u0627\u0644\u0625\u062c\u0645\u0627\u0644\u064a: ${formatIqd(order.totalAmount)}',
        textDirection: TextDirection.rtl,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 14,
          height: 1.55,
        ),
      ),
    );
  }
}

class _TrackingLiveBottomBar extends StatelessWidget {
  final bool isLive;
  final bool isCancelled;
  final String currentStepLabel;
  final double completion;

  const _TrackingLiveBottomBar({
    required this.isLive,
    required this.isCancelled,
    required this.currentStepLabel,
    required this.completion,
  });

  @override
  Widget build(BuildContext context) {
    final panelColor = isLive
        ? Colors.cyan.withValues(alpha: 0.14)
        : isCancelled
        ? Colors.red.withValues(alpha: 0.14)
        : Colors.green.withValues(alpha: 0.14);

    final borderColor = isLive
        ? Colors.cyan.withValues(alpha: 0.34)
        : isCancelled
        ? Colors.red.withValues(alpha: 0.32)
        : Colors.green.withValues(alpha: 0.32);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: panelColor,
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                if (isLive)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    isCancelled
                        ? Icons.cancel_outlined
                        : Icons.check_circle_outline_rounded,
                    size: 16,
                    color: isCancelled
                        ? Colors.red.shade300
                        : Colors.green.shade300,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isLive
                        ? '\u062c\u0627\u0631\u064a \u0645\u062a\u0627\u0628\u0639\u0629 \u0627\u0644\u0637\u0644\u0628 \u0627\u0644\u0622\u0646: $currentStepLabel'
                        : isCancelled
                        ? '\u062a\u0645 \u0625\u0644\u063a\u0627\u0621 \u0627\u0644\u0637\u0644\u0628'
                        : '\u062a\u0645 \u0625\u0643\u0645\u0627\u0644 \u062c\u0645\u064a\u0639 \u0627\u0644\u0645\u0631\u0627\u062d\u0644',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: _responsiveFont(context, 13.2),
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: isLive ? null : completion,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _kTrackingSteps = <_TimelineStep>[
  _TimelineStep(
    label:
        '\u0645\u0648\u0627\u0641\u0642\u0629 \u0627\u0644\u0645\u062a\u062c\u0631 \u0639\u0644\u0649 \u0627\u0644\u0637\u0644\u0628',
    icon: Icons.verified_outlined,
  ),
  _TimelineStep(
    label:
        '\u062a\u0639\u064a\u064a\u0646/\u0642\u0628\u0648\u0644 \u0627\u0644\u062f\u0644\u0641\u0631\u064a',
    icon: Icons.assignment_ind_outlined,
  ),
  _TimelineStep(
    label:
        '\u0628\u062f\u0621 \u062a\u062d\u0636\u064a\u0631 \u0627\u0644\u0637\u0644\u0628',
    icon: Icons.restaurant_menu_outlined,
  ),
  _TimelineStep(
    label:
        '\u0627\u0633\u062a\u0644\u0627\u0645 \u0627\u0644\u0633\u0627\u0626\u0642 \u0644\u0644\u0637\u0644\u0628',
    icon: Icons.two_wheeler_outlined,
  ),
  _TimelineStep(
    label: '\u0648\u0635\u0648\u0644 \u0627\u0644\u0633\u0627\u0626\u0642',
    icon: Icons.location_on_outlined,
  ),
  _TimelineStep(
    label:
        '\u062a\u0645 \u0627\u0644\u062a\u0633\u0644\u064a\u0645 \u0648\u0628\u0627\u0646\u062a\u0638\u0627\u0631 \u062a\u0623\u0643\u064a\u062f\u0643',
    icon: Icons.inventory_2_outlined,
  ),
  _TimelineStep(
    label:
        '\u062a\u0645 \u0627\u0633\u062a\u0644\u0627\u0645 \u0627\u0644\u0637\u0644\u0628',
    icon: Icons.check_circle_outline,
  ),
];

double _timelineCompletion(OrderModel order, _TimelineProgress progress) {
  final raw = (progress.activeIndex + 1) / _kTrackingSteps.length;
  if (order.status == 'cancelled') return raw.clamp(0.06, 0.92);
  if (order.customerConfirmedAt != null) return 1;
  return raw.clamp(0.08, 0.98);
}

class _OrderStatusTimeline extends StatelessWidget {
  final OrderModel order;

  const _OrderStatusTimeline({required this.order});

  @override
  Widget build(BuildContext context) {
    final progress = _buildProgress(order);
    final isCancelled = order.status == 'cancelled';
    final isDelivered = order.customerConfirmedAt != null;
    final trackingHint = customerOrderTrackingHint(
      order.status,
      hasDeliveryAssigned:
          order.deliveryUserId != null || order.isMerchantDelivery,
      customerConfirmed: order.customerConfirmedAt != null,
    );

    final doneFlags = List<bool>.generate(
      _kTrackingSteps.length,
      (i) => i < progress.doneFlags.length ? progress.doneFlags[i] : false,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '\u0645\u0633\u0627\u0631 \u0627\u0644\u0637\u0644\u0628',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.4),
          ),
          const SizedBox(height: 8),
          if (order.status == 'pending' && trackingHint != null)
            _TrackingHintBanner(color: Colors.orange, text: trackingHint),
          if (order.status == 'approved' &&
              order.deliveryUserId == null &&
              !order.isMerchantDelivery &&
              trackingHint != null)
            _TrackingHintBanner(color: Colors.cyan, text: trackingHint),
          if (const {
                'preparing',
                'ready_for_delivery',
                'on_the_way',
                'arrived',
              }.contains(order.status) &&
              trackingHint != null)
            _TrackingHintBanner(color: Colors.cyan, text: trackingHint),
          if (order.status == 'cancelled')
            const _TrackingHintBanner(
              color: Colors.red,
              text:
                  '\u062a\u0645 \u0625\u0644\u063a\u0627\u0621 \u0627\u0644\u0637\u0644\u0628 \u0645\u0646 \u0627\u0644\u0645\u062a\u062c\u0631',
            ),
          if (order.status == 'delivered' &&
              order.customerConfirmedAt == null &&
              trackingHint != null)
            _TrackingHintBanner(color: Colors.green, text: trackingHint),
          const SizedBox(height: 6),
          for (var i = 0; i < _kTrackingSteps.length; i++)
            _TrackingStageTile(
              step: _kTrackingSteps[i],
              done: doneFlags[i] && !isCancelled,
              active: i == progress.activeIndex && !isCancelled && !isDelivered,
              isLast: i == _kTrackingSteps.length - 1,
              timestamp: _stageTimestamp(order, i),
            ),
        ],
      ),
    );
  }
}

class _TrackingHintBanner extends StatelessWidget {
  final Color color;
  final String text;

  const _TrackingHintBanner({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: _responsiveFont(context, 13),
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TrackingStageTile extends StatelessWidget {
  final _TimelineStep step;
  final bool done;
  final bool active;
  final bool isLast;
  final DateTime? timestamp;

  const _TrackingStageTile({
    required this.step,
    required this.done,
    required this.active,
    required this.isLast,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final markerColor = done
        ? primary
        : active
        ? Colors.cyanAccent
        : Colors.white54;

    return Row(
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  step.label,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontWeight: done || active
                        ? FontWeight.w800
                        : FontWeight.w700,
                    fontSize: _responsiveFont(context, 13.8),
                    color: done || active ? Colors.white : Colors.white70,
                  ),
                ),
                if (timestamp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _formatStageTime(timestamp!),
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: _responsiveFont(context, 12),
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 26,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: markerColor.withValues(alpha: 0.18),
                  border: Border.all(color: markerColor, width: 1.6),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: markerColor.withValues(alpha: 0.45),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: active
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          done ? Icons.check_rounded : step.icon,
                          size: 13,
                          color: done ? markerColor : Colors.white70,
                        ),
                ),
              ),
              if (!isLast)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  width: 2,
                  height: 28,
                  color: done ? markerColor : Colors.white24,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

DateTime? _stageTimestamp(OrderModel order, int stageIndex) {
  switch (stageIndex) {
    case 0:
      return order.approvedAt;
    case 1:
      if (order.deliveryUserId == null && !order.isMerchantDelivery) {
        return null;
      }
      return order.pickedUpAt ??
          order.preparedAt ??
          order.preparingStartedAt ??
          order.approvedAt;
    case 2:
      return order.preparingStartedAt;
    case 3:
      return order.pickedUpAt;
    case 4:
      return order.arrivedAt;
    case 5:
      return order.deliveredAt;
    case 6:
      return order.customerConfirmedAt;
    default:
      return null;
  }
}

String _formatStageTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

class _DeliveryEtaPanel extends StatelessWidget {
  final OrderModel order;

  const _DeliveryEtaPanel({required this.order});

  @override
  Widget build(BuildContext context) {
    final eta = _computeEta(order, DateTime.now());
    final awaitingPickup = order.pickedUpAt == null;
    final title = switch (order.status) {
      'arrived' => 'الدلري وصل إلى موقعك',
      'delivered' when order.customerConfirmedAt == null =>
        'تم التسليم وبانتظار تأكيدك',
      _ =>
        awaitingPickup
            ? '\u0628\u0627\u0646\u062a\u0638\u0627\u0631 \u0627\u0633\u062a\u0644\u0627\u0645 \u0627\u0644\u0633\u0627\u0626\u0642 \u0644\u0644\u0637\u0644\u0628'
            : eta.isLate
            ? '\u0627\u0644\u0633\u0627\u0626\u0642 \u0645\u062a\u0623\u062e\u0631 ${eta.lateByMinutes} \u062f\u0642\u064a\u0642\u0629'
            : '\u0648\u0642\u062a \u0627\u0644\u0648\u0635\u0648\u0644 \u0627\u0644\u062a\u0642\u062f\u064a\u0631\u064a',
    };
    final etaText = eta.minMinutes == eta.maxMinutes
        ? '${eta.minMinutes} \u062f\u0642\u064a\u0642\u0629'
        : '${eta.minMinutes} - ${eta.maxMinutes} \u062f\u0642\u064a\u0642\u0629';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: eta.isLate
            ? Colors.orange.withValues(alpha: 0.15)
            : Colors.cyan.withValues(alpha: 0.12),
        border: Border.all(
          color: eta.isLate
              ? Colors.orange.withValues(alpha: 0.45)
              : Colors.cyan.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, textDirection: TextDirection.rtl),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Text(
              key: ValueKey('$title|$etaText'),
              switch (order.status) {
                'arrived' =>
                  'يمكنك الآن التواصل مباشرة مع الدلري إذا لزم الأمر.',
                'delivered' when order.customerConfirmedAt == null =>
                  'اضغط على "تم استلام الطلب" لإيقا التنبيه وإكمال الطلب.',
                _ =>
                  awaitingPickup
                      ? '\u0633\u064a\u0628\u062f\u0623 \u0627\u062d\u062a\u0633\u0627\u0628 \u0627\u0644\u0648\u0642\u062a \u0628\u0639\u062f \u0627\u0633\u062a\u0644\u0627\u0645 \u0627\u0644\u0633\u0627\u0626\u0642 \u0644\u0644\u0637\u0644\u0628'
                      : eta.isLate
                      ? '\u0627\u0644\u0648\u0642\u062a \u0627\u0644\u0645\u062d\u062f\u062b \u0644\u0644\u0648\u0635\u0648\u0644: $etaText'
                      : '\u0627\u0644\u0648\u0635\u0648\u0644 \u062e\u0644\u0627\u0644: $etaText',
              },
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: eta.progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 10),
          _MotorcycleRoadLane(progress: eta.progress, isLate: eta.isLate),
        ],
      ),
    );
  }
}

class _MotorcycleRoadLane extends StatefulWidget {
  final double progress;
  final bool isLate;

  const _MotorcycleRoadLane({required this.progress, required this.isLate});

  @override
  State<_MotorcycleRoadLane> createState() => _MotorcycleRoadLaneState();
}

class _MotorcycleRoadLaneState extends State<_MotorcycleRoadLane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..repeat();

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clamped = widget.progress.clamp(0.0, 1.0);
    return SizedBox(
      height: 42,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final laneWidth = (constraints.maxWidth - 58).clamp(20.0, 5000.0);
          return Stack(
            children: [
              Positioned(
                left: 22,
                right: 22,
                top: 20,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 10,
                child: Icon(
                  Icons.storefront_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              Positioned(
                left: 0,
                top: 10,
                child: Icon(
                  Icons.home_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: clamped),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, animatedProgress, child) {
                  return AnimatedBuilder(
                    animation: _floatController,
                    builder: (context, _) {
                      final bounce =
                          math.sin(_floatController.value * math.pi * 2) *
                          (widget.isLate ? 1.6 : 3.0);
                      final x = 22 + (laneWidth * (1 - animatedProgress));
                      return Positioned(
                        left: x,
                        top: 10 + bounce,
                        child: Icon(
                          Icons.two_wheeler_rounded,
                          size: 20,
                          color: widget.isLate
                              ? Colors.orange.shade300
                              : Theme.of(context).colorScheme.primary,
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineStep {
  final String label;
  final IconData icon;

  const _TimelineStep({required this.label, required this.icon});
}

class _TimelineProgress {
  final List<bool> doneFlags;
  final int activeIndex;

  const _TimelineProgress({required this.doneFlags, required this.activeIndex});
}

class _EtaWindow {
  final int minMinutes;
  final int maxMinutes;
  final bool isLate;
  final int lateByMinutes;
  final double progress;

  const _EtaWindow({
    required this.minMinutes,
    required this.maxMinutes,
    required this.isLate,
    required this.lateByMinutes,
    required this.progress,
  });
}

_TimelineProgress _buildProgress(OrderModel order) {
  final approved = order.approvedAt != null || order.status != 'pending';
  final assignedDriverRaw =
      order.deliveryUserId != null ||
      order.isMerchantDelivery ||
      const {'on_the_way', 'arrived', 'delivered'}.contains(order.status);
  final preparingRaw =
      order.preparingStartedAt != null ||
      const {
        'preparing',
        'ready_for_delivery',
        'on_the_way',
        'arrived',
        'delivered',
      }.contains(order.status);
  final pickedRaw =
      order.pickedUpAt != null ||
      const {'on_the_way', 'arrived', 'delivered'}.contains(order.status);
  final arrivedRaw =
      order.arrivedAt != null ||
      const {'arrived', 'delivered'}.contains(order.status);
  final handedOverRaw =
      order.deliveredAt != null || const {'delivered'}.contains(order.status);
  final receivedRaw = order.customerConfirmedAt != null;

  final assignedDriver = approved && assignedDriverRaw;
  final preparing = approved && preparingRaw;
  final picked = preparing && pickedRaw;
  final arrived = picked && arrivedRaw;
  final handedOver = arrived && handedOverRaw;
  final received = handedOver && receivedRaw;

  final done = [
    approved,
    assignedDriver,
    preparing,
    picked,
    arrived,
    handedOver,
    received,
  ];

  var activeIndex = 0;
  for (var i = 0; i < done.length; i++) {
    if (done[i]) activeIndex = i;
  }
  return _TimelineProgress(doneFlags: done, activeIndex: activeIndex);
}

_EtaWindow _computeEta(OrderModel order, DateTime now) {
  const baseMin = 7;
  const baseMax = 10;

  final pickupAt = order.pickedUpAt;

  if (pickupAt == null) {
    return const _EtaWindow(
      minMinutes: baseMin,
      maxMinutes: baseMax,
      isLate: false,
      lateByMinutes: 0,
      progress: 0,
    );
  }

  final elapsed = now.difference(pickupAt).inMinutes;
  final remainingMin = baseMin - elapsed;
  final remainingMax = baseMax - elapsed;

  if (remainingMax >= 0) {
    return _EtaWindow(
      minMinutes: remainingMin < 0 ? 0 : remainingMin,
      maxMinutes: remainingMax < 1 ? 1 : remainingMax,
      isLate: false,
      lateByMinutes: 0,
      progress: (elapsed / baseMax).clamp(0, 1),
    );
  }

  final lateBy = -remainingMax;
  final updatedMin = 2 + (lateBy ~/ 2);
  final updatedMax = updatedMin + 3;
  return _EtaWindow(
    minMinutes: updatedMin,
    maxMinutes: updatedMax,
    isLate: true,
    lateByMinutes: lateBy,
    progress: 1,
  );
}

class _RatingResult {
  final int rating;
  final String review;

  const _RatingResult({required this.rating, required this.review});
}
