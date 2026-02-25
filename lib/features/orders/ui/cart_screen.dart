import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/pricing.dart';
import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../state/cart_controller.dart';
import '../state/delivery_address_controller.dart';
import '../state/orders_controller.dart';
import 'delivery_addresses_screen.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final noteCtrl = TextEditingController();
  LocalImageFile? orderImageFile;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(deliveryAddressControllerProvider.notifier).bootstrap(),
    );
  }

  @override
  void dispose() {
    noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final orders = ref.watch(ordersControllerProvider);
    final addresses = ref.watch(deliveryAddressControllerProvider);
    final selectedAddress = addresses.selectedAddress;

    ref.listen<OrdersState>(ordersControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          cart.merchantName == null
              ? 'سلة التسوق'
              : 'سلة ${cart.merchantName}',
        ),
      ),
      body: cart.items.isEmpty
          ? const Center(child: Text('السلة فارغة'))
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: cart.items.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final item = cart.items[index];
                        final price =
                            item.product.discountedPrice ?? item.product.price;
                        final total = price * item.quantity;

                        return Card(
                          child: ListTile(
                            title: Text(
                              item.product.name,
                              textDirection: TextDirection.rtl,
                            ),
                            subtitle: Text(
                              'السعر: ${formatIqd(price)} - الكمية: ${item.quantity} - المجموع: ${formatIqd(total)}',
                              textDirection: TextDirection.rtl,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => ref
                                      .read(cartControllerProvider.notifier)
                                      .decrementItem(item.product.id),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                IconButton(
                                  onPressed: () => ref
                                      .read(cartControllerProvider.notifier)
                                      .addItem(
                                        product: item.product,
                                        merchantId: cart.merchantId!,
                                        merchantName: cart.merchantName ?? '',
                                      ),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                                IconButton(
                                  onPressed: () => ref
                                      .read(cartControllerProvider.notifier)
                                      .removeItem(item.product.id),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات على الطلب (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      title: const Text(
                        'عنوان التوصيل',
                        textDirection: TextDirection.rtl,
                      ),
                      subtitle: Text(
                        selectedAddress?.shortText ??
                            'الرجاء إضافة أو اختيار عنوان توصيل',
                        textDirection: TextDirection.rtl,
                      ),
                      trailing: IconButton(
                        tooltip: 'إدارة العناوين',
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DeliveryAddressesScreen(
                                selectOnTap: true,
                              ),
                            ),
                          );
                          if (!mounted) return;
                          await ref
                              .read(deliveryAddressControllerProvider.notifier)
                              .bootstrap(silent: true);
                        },
                        icon: const Icon(Icons.place_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ImagePickerField(
                    title: 'صورة الطلب (اختياري)',
                    selectedFile: orderImageFile,
                    existingImageUrl: null,
                    onPick: () async {
                      final picked = await pickImageFromDevice();
                      if (!mounted || picked == null) return;
                      setState(() => orderImageFile = picked);
                    },
                    onClear: orderImageFile == null
                        ? null
                        : () => setState(() => orderImageFile = null),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _SummaryRow(
                            'المجموع الفرعي',
                            formatIqd(cart.subtotal),
                          ),
                          _SummaryRow(
                            'رسوم الخدمة (${formatIqd(serviceFeeIqd)})',
                            formatIqd(cart.serviceFee),
                          ),
                          _SummaryRow(
                            cart.deliveryFee <= 0
                                ? 'أجور التوصيل (توصيل مجاني)'
                                : 'أجور التوصيل',
                            formatIqd(cart.deliveryFee),
                          ),
                          const Divider(),
                          _SummaryRow(
                            'الإجمالي النهائي',
                            formatIqd(cart.total),
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: orders.placingOrder
                          ? null
                          : () async {
                              final ok = await ref
                                  .read(ordersControllerProvider.notifier)
                                  .checkout(
                                    note: noteCtrl.text,
                                    imageFile: orderImageFile,
                                  );
                              if (!context.mounted || !ok) return;
                              Navigator.of(context).pop(true);
                            },
                      child: orders.placingOrder
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('إتمام الطلب'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _SummaryRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(value, textAlign: TextAlign.left, style: style),
          ),
          Expanded(
            child: Text(
              label,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
