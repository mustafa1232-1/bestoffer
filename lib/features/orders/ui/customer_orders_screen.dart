import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../models/order_model.dart';
import '../state/orders_controller.dart';

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

  const CustomerOrdersScreen({super.key, this.initialOrderId});

  @override
  ConsumerState<CustomerOrdersScreen> createState() =>
      _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends ConsumerState<CustomerOrdersScreen> {
  int? _focusedOrderId;

  @override
  void initState() {
    super.initState();
    _focusedOrderId = widget.initialOrderId;
    Future.microtask(() async {
      final controller = ref.read(ordersControllerProvider.notifier);
      await controller.loadMyOrders();
      controller.startLiveOrders();
    });
  }

  @override
  void dispose() {
    ref.read(ordersControllerProvider.notifier).stopLiveOrders();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ordersControllerProvider);

    ref.listen<OrdersState>(ordersControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final orders = _prioritizeOrders(state.orders, _focusedOrderId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u0637\u0644\u0628\u0627\u062a\u064a'),
        actions: const [NotificationsBellButton()],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(ordersControllerProvider.notifier).loadMyOrders(),
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : orders.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 140),
                  Center(
                    child: Text(
                      '\u0644\u0627 \u062a\u0648\u062c\u062f \u0637\u0644\u0628\u0627\u062a \u062d\u0627\u0644\u064a\u0627\u064b',
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: orders.length,
                separatorBuilder: (_, index) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final order = orders[index];
                  final highlighted = _focusedOrderId == order.id;
                  return _OrderCard(order: order, highlighted: highlighted);
                },
              ),
      ),
    );
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

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final bool highlighted;

  const _OrderCard({required this.order, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final status = orderStatusLabel(order.status);
    final progress = _buildProgress(order);
    final stepLabel = _kTrackingSteps[progress.activeIndex].label;
    final completion = _timelineCompletion(order, progress);
    final isLive = order.status != 'cancelled' && order.status != 'delivered';

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
              builder: (_) => _OrderTrackingDetailsScreen(
                orderId: order.id,
                fallbackOrder: order,
              ),
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
    final isDelivered = order.status == 'delivered';
    final isLive = !isCancelled && !isDelivered;
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
            if (order.status == 'on_the_way') ...[
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
                child: Image.network(
                  order.imageUrl!,
                  height: 170,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stackTrace) => Container(
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

  Widget _buildActions(OrderModel order) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _copyTrackingSummary(order),
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('نسخ تحديث الطلب للمشاركة'),
          ),
        ),
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

  Future<void> _copyTrackingSummary(OrderModel order) async {
    final progress = _buildProgress(order);
    final currentStep = _kTrackingSteps[progress.activeIndex].label;
    final eta = _computeEta(order, DateTime.now());
    final etaLabel = order.status == 'on_the_way'
        ? eta.isLate
              ? 'متأخر (${eta.lateByMinutes} دقيقة) - وصول محدث خلال ${eta.minMinutes}-${eta.maxMinutes} دقيقة'
              : 'وصول خلال ${eta.minMinutes}-${eta.maxMinutes} دقيقة'
        : 'غير متاح حاليًا';

    final text =
        'تحديث الطلب #${order.id}\n'
        'المتجر: ${order.merchantName}\n'
        'الحالة: ${orderStatusLabel(order.status)}\n'
        'المرحلة الحالية: $currentStep\n'
        'الوقت التقديري: $etaLabel\n'
        'الإجمالي: ${formatIqd(order.totalAmount)}';

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ التحديث إلى الحافظة')));
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
                : orderStatusLabel(order.status),
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
    final isDelivered = order.status == 'delivered';
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
        '\u062a\u0639\u064a\u064a\u0646 \u0645\u0646\u062f\u0648\u0628 \u0627\u0644\u062a\u0648\u0635\u064a\u0644',
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
        '\u062a\u0645 \u0627\u0633\u062a\u0644\u0627\u0645 \u0627\u0644\u0637\u0644\u0628',
    icon: Icons.check_circle_outline,
  ),
];

double _timelineCompletion(OrderModel order, _TimelineProgress progress) {
  final raw = (progress.activeIndex + 1) / _kTrackingSteps.length;
  if (order.status == 'cancelled') return raw.clamp(0.06, 0.92);
  if (order.status == 'delivered') return 1;
  return raw.clamp(0.08, 0.98);
}

class _OrderStatusTimeline extends StatelessWidget {
  final OrderModel order;

  const _OrderStatusTimeline({required this.order});

  @override
  Widget build(BuildContext context) {
    final progress = _buildProgress(order);
    final isCancelled = order.status == 'cancelled';
    final isDelivered = order.status == 'delivered';

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
          if (order.status == 'pending')
            _TrackingHintBanner(
              color: Colors.orange,
              text:
                  '\u0628\u0627\u0646\u062a\u0638\u0627\u0631 \u0645\u0648\u0627\u0641\u0642\u0629 \u0627\u0644\u0645\u062a\u062c\u0631 \u0639\u0644\u0649 \u0627\u0644\u0637\u0644\u0628',
            ),
          if (order.status == 'cancelled')
            _TrackingHintBanner(
              color: Colors.red,
              text:
                  '\u062a\u0645 \u0625\u0644\u063a\u0627\u0621 \u0627\u0644\u0637\u0644\u0628 \u0645\u0646 \u0627\u0644\u0645\u062a\u062c\u0631',
            ),
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
      return order.deliveryUserId != null
          ? (order.preparingStartedAt ?? order.approvedAt)
          : null;
    case 2:
      return order.preparingStartedAt;
    case 3:
      return order.pickedUpAt;
    case 4:
      return order.deliveredAt;
    case 5:
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
    final title = awaitingPickup
        ? '\u0628\u0627\u0646\u062a\u0638\u0627\u0631 \u0627\u0633\u062a\u0644\u0627\u0645 \u0627\u0644\u0633\u0627\u0626\u0642 \u0644\u0644\u0637\u0644\u0628'
        : eta.isLate
        ? '\u0627\u0644\u0633\u0627\u0626\u0642 \u0645\u062a\u0623\u062e\u0631 ${eta.lateByMinutes} \u062f\u0642\u064a\u0642\u0629'
        : '\u0648\u0642\u062a \u0627\u0644\u0648\u0635\u0648\u0644 \u0627\u0644\u062a\u0642\u062f\u064a\u0631\u064a';
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
              awaitingPickup
                  ? '\u0633\u064a\u0628\u062f\u0623 \u0627\u062d\u062a\u0633\u0627\u0628 \u0627\u0644\u0648\u0642\u062a \u0628\u0639\u062f \u0627\u0633\u062a\u0644\u0627\u0645 \u0627\u0644\u0633\u0627\u0626\u0642 \u0644\u0644\u0637\u0644\u0628'
                  : eta.isLate
                  ? '\u0627\u0644\u0648\u0642\u062a \u0627\u0644\u0645\u062d\u062f\u062b \u0644\u0644\u0648\u0635\u0648\u0644: $etaText'
                  : '\u0627\u0644\u0648\u0635\u0648\u0644 \u062e\u0644\u0627\u0644: $etaText',
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
  final assignedDriverRaw = order.deliveryUserId != null;
  final preparingRaw =
      order.preparingStartedAt != null ||
      const {
        'preparing',
        'ready_for_delivery',
        'on_the_way',
        'delivered',
      }.contains(order.status);
  final pickedRaw =
      order.pickedUpAt != null ||
      const {'on_the_way', 'delivered'}.contains(order.status);
  final arrivedRaw =
      order.deliveredAt != null || const {'delivered'}.contains(order.status);
  final receivedRaw = order.customerConfirmedAt != null;

  // Keep the timeline strictly sequential so stages never jump out of order.
  final assignedDriver = approved && assignedDriverRaw;
  final preparing = assignedDriver && preparingRaw;
  final picked = preparing && pickedRaw;
  final arrived = picked && arrivedRaw;
  final received = arrived && receivedRaw;

  final done = [approved, assignedDriver, preparing, picked, arrived, received];

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
