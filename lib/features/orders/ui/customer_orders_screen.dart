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
    Future.microtask(
      () => ref.read(ordersControllerProvider.notifier).loadMyOrders(),
    );
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
    final estimate = order.estimatedDeliveryMinutes;

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
          if (estimate != null && order.status != 'delivered')
            Align(
              alignment: Alignment.centerRight,
              child: Text('الوقت التقريبي للوصول: $estimate دقيقة'),
            ),
          if (order.deliveryFullName != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'ا�"د�"فر�S: ${order.deliveryFullName} - ${order.deliveryPhone ?? ''}',
              ),
            ),
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
    ).showSnackBar(const SnackBar(content: Text('شكرًا لتقييمك')));
  }
}

class _RatingResult {
  final int rating;
  final String review;

  const _RatingResult({required this.rating, required this.review});
}
