import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../models/order_model.dart';
import '../state/orders_controller.dart';

class CustomerOrdersScreen extends ConsumerStatefulWidget {
  const CustomerOrdersScreen({super.key});

  @override
  ConsumerState<CustomerOrdersScreen> createState() =>
      _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends ConsumerState<CustomerOrdersScreen> {
  @override
  void initState() {
    super.initState();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('طلباتي'),
        actions: const [NotificationsBellButton()],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(ordersControllerProvider.notifier).loadMyOrders(),
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.orders.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 140),
                  Center(child: Text('لا توجد طلبات')),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: state.orders.length,
                separatorBuilder: (_, index) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final order = state.orders[index];
                  return _OrderCard(order: order);
                },
              ),
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  final OrderModel order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = orderStatusLabel(order.status);

    return Card(
      child: ExpansionTile(
        title: Text(
          'طلب #${order.id} - $status',
          textDirection: TextDirection.rtl,
        ),
        subtitle: Text(
          'المتجر: ${order.merchantName} | الإجمالي: ${formatIqd(order.totalAmount)}',
          textDirection: TextDirection.rtl,
        ),
        childrenPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        children: [
          _OrderStatusTimeline(order: order),
          if (order.status == 'on_the_way') ...[
            const SizedBox(height: 10),
            _DeliveryEtaPanel(order: order),
          ],
          if (order.deliveryFullName != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الدلفري: ${order.deliveryFullName} - ${order.deliveryPhone ?? ''}',
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
          if (order.imageUrl?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'صورة الطلب',
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                order.imageUrl!,
                height: 130,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 90,
                  alignment: Alignment.center,
                  color: Colors.black12,
                  child: const Icon(Icons.image_not_supported_outlined),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...order.items.map(
            (item) => Align(
              alignment: Alignment.centerRight,
              child: Text(
                '- ${item.productName} x ${item.quantity} (${formatIqd(item.lineTotal)})',
                textDirection: TextDirection.rtl,
              ),
            ),
          ),
          const Divider(height: 22),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'المجموع الفرعي: ${formatIqd(order.subtotal)}\n'
              'رسوم الخدمة: ${formatIqd(order.serviceFee)}\n'
              'أجور التوصيل: ${formatIqd(order.deliveryFee)}\n'
              'الإجمالي: ${formatIqd(order.totalAmount)}',
              textDirection: TextDirection.rtl,
            ),
          ),
          const SizedBox(height: 10),
          if (order.status == 'delivered' && order.customerConfirmedAt == null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final ok = await ref
                      .read(ordersControllerProvider.notifier)
                      .confirmDelivered(order.id);
                  if (!ok || !context.mounted) return;

                  final result = await _showRatingDialog(
                    context,
                    title: 'تقييم المندوب',
                  );
                  if (!context.mounted) return;
                  if (result != null) {
                    await ref
                        .read(ordersControllerProvider.notifier)
                        .rateDelivery(
                          orderId: order.id,
                          rating: result.rating,
                          review: result.review,
                        );
                    if (!context.mounted) return;
                  }

                  await _showFirstAppRating(context, ref);
                },
                child: const Text('الدلفري وصل الطلب'),
              ),
            ),
          if (order.status == 'delivered')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await ref
                      .read(ordersControllerProvider.notifier)
                      .reorder(order.id, note: order.note);
                },
                child: const Text('إعادة الطلب'),
              ),
            ),
          if (order.status == 'delivered' && order.deliveryRating == null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final result = await _showRatingDialog(
                    context,
                    title: 'تقييم الدلفري',
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
                child: const Text('تقييم الدلفري'),
              ),
            ),
          if (order.status == 'delivered' && order.merchantRating == null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final result = await _showRatingDialog(
                    context,
                    title: 'تقييم المتجر',
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
                child: const Text('تقييم المتجر'),
              ),
            ),
          if (order.deliveryRating != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'تقييم المندوب: ${'⭐' * (order.deliveryRating ?? 0)}',
              ),
            ),
          if (order.merchantRating != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text('تقييم المتجر: ${'⭐' * (order.merchantRating ?? 0)}'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
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
                    labelText: 'ملاحظة (اختياري)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
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
                child: const Text('إرسال'),
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
    final appResult = await _showRatingDialog(context, title: 'تقييم التطبيق');
    if (appResult == null) return;

    await store.writeString('app_rating_value', '${appResult.rating}');
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('شكراً لتقييمك')));
  }
}

class _OrderStatusTimeline extends StatelessWidget {
  final OrderModel order;

  const _OrderStatusTimeline({required this.order});

  @override
  Widget build(BuildContext context) {
    const steps = <_TimelineStep>[
      _TimelineStep(
        id: 'pending',
        label: 'استلام الطلب',
        icon: Icons.receipt_long_outlined,
      ),
      _TimelineStep(
        id: 'preparing',
        label: 'قيد التحضير',
        icon: Icons.local_dining_outlined,
      ),
      _TimelineStep(
        id: 'ready_for_delivery',
        label: 'بانتظار السائق',
        icon: Icons.store_mall_directory_outlined,
      ),
      _TimelineStep(
        id: 'on_the_way',
        label: 'استلم السائق الطلب',
        icon: Icons.two_wheeler_outlined,
      ),
      _TimelineStep(
        id: 'delivered',
        label: 'تم التسليم',
        icon: Icons.check_circle_outline,
      ),
    ];

    final activeIndex = _statusToTimelineIndex(order.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (order.status == 'cancelled')
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
            ),
            child: const Text(
              'تم إلغاء الطلب من المتجر',
              textDirection: TextDirection.rtl,
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                _TimelineChip(
                  step: steps[i],
                  done: i <= activeIndex && order.status != 'cancelled',
                  active: i == activeIndex && order.status != 'cancelled',
                ),
                if (i < steps.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: i < activeIndex
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white54,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineChip extends StatelessWidget {
  final _TimelineStep step;
  final bool done;
  final bool active;

  const _TimelineChip({
    required this.step,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? Theme.of(context).colorScheme.primary
        : Colors.white.withValues(alpha: 0.18);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: done ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.8)),
        boxShadow: active
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle : step.icon,
            size: 16,
            color: done
                ? Theme.of(context).colorScheme.primary
                : Colors.white70,
          ),
          const SizedBox(width: 6),
          Text(step.label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _DeliveryEtaPanel extends StatelessWidget {
  final OrderModel order;

  const _DeliveryEtaPanel({required this.order});

  @override
  Widget build(BuildContext context) {
    final eta = _computeEta(order, DateTime.now());
    final title = eta.isLate
        ? 'السائق متأخر ${eta.lateByMinutes} دقيقة'
        : 'وقت الوصول التقديري';
    final etaText = eta.minMinutes == eta.maxMinutes
        ? '${eta.minMinutes} دقيقة'
        : '${eta.minMinutes} - ${eta.maxMinutes} دقائق';

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
              eta.isLate
                  ? 'الوقت المحدّث للوصول: $etaText'
                  : 'الوصول خلال: $etaText',
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
        ],
      ),
    );
  }
}

class _TimelineStep {
  final String id;
  final String label;
  final IconData icon;

  const _TimelineStep({
    required this.id,
    required this.label,
    required this.icon,
  });
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

int _statusToTimelineIndex(String status) {
  switch (status) {
    case 'pending':
      return 0;
    case 'preparing':
      return 1;
    case 'ready_for_delivery':
      return 2;
    case 'on_the_way':
      return 3;
    case 'delivered':
      return 4;
    case 'cancelled':
      return 0;
    default:
      return 0;
  }
}

_EtaWindow _computeEta(OrderModel order, DateTime now) {
  const baseMin = 7;
  const baseMax = 10;

  final pickupAt =
      order.pickedUpAt ??
      order.preparedAt ??
      order.preparingStartedAt ??
      order.createdAt;

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
