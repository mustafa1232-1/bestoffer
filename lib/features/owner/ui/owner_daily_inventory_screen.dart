import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maslaki/core/media/cached_app_image.dart';

import '../../products/models/product_model.dart';
import '../state/owner_controller.dart';

class OwnerDailyInventoryScreen extends ConsumerStatefulWidget {
  const OwnerDailyInventoryScreen({super.key});

  @override
  ConsumerState<OwnerDailyInventoryScreen> createState() =>
      _OwnerDailyInventoryScreenState();
}

class _OwnerDailyInventoryScreenState
    extends ConsumerState<OwnerDailyInventoryScreen> {
  final Map<int, TextEditingController> _quantityControllers = {};
  final Map<int, bool> _availabilityByProductId = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(ownerControllerProvider.notifier).bootstrap(force: true);
    });
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _quantityControllerFor(ProductModel product) {
    return _quantityControllers.putIfAbsent(
      product.id,
      () => TextEditingController(
        text: product.stockQuantity == null ? '' : '${product.stockQuantity}',
      ),
    );
  }

  bool _availableFor(ProductModel product) {
    final override = _availabilityByProductId[product.id];
    if (override != null) return override;
    if (!product.isAvailable) return false;
    if (product.stockQuantity != null && product.stockQuantity! <= 0) {
      return false;
    }
    return true;
  }

  Future<void> _saveProduct(ProductModel product) async {
    final controller = _quantityControllerFor(product);
    final quantity = int.tryParse(controller.text.trim());
    if (quantity == null || quantity < 0) {
      _showMessage('أدخل عدد صحيح للمخزون');
      return;
    }
    final requestedAvailable = _availableFor(product);
    final saved = await ref
        .read(ownerControllerProvider.notifier)
        .updateDailyInventoryItem(
          productId: product.id,
          quantity: quantity,
          isAvailable: requestedAvailable,
        );
    if (!mounted) return;
    if (saved) {
      setState(() {
        _availabilityByProductId[product.id] =
            requestedAvailable && quantity > 0;
      });
      _showMessage(
        quantity > 0 && requestedAvailable
            ? 'تم حفظ الجرد'
            : 'تم حفظ الجرد وإيقاف المنتج',
      );
    } else {
      final error = ref.read(ownerControllerProvider).error;
      _showMessage(error ?? 'تعذر حفظ الجرد');
    }
  }

  Future<void> _confirmDailyCheck() async {
    final confirmed = await ref
        .read(ownerControllerProvider.notifier)
        .confirmDailyInventoryCheck();
    if (!mounted) return;
    _showMessage(confirmed ? 'تم تأكيد جرد اليوم' : 'تعذر تأكيد الجرد');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, textDirection: TextDirection.rtl)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerControllerProvider);
    final products = state.products;
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الجرد اليومي'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: state.loading
                  ? null
                  : () => ref
                        .read(ownerControllerProvider.notifier)
                        .bootstrap(force: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => ref
                .read(ownerControllerProvider.notifier)
                .bootstrap(force: true),
            child: products.isEmpty && state.loading
                ? const Center(child: CircularProgressIndicator())
                : products.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: const [_EmptyInventoryState()],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: products.length + 1,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final unavailable = products
                            .where(
                              (product) =>
                                  !_availableFor(product) ||
                                  (product.stockQuantity != null &&
                                      product.stockQuantity! <= 0),
                            )
                            .length;
                        return _InventoryHeader(
                          total: products.length,
                          unavailable: unavailable,
                          saving: state.savingProduct,
                          onConfirm: _confirmDailyCheck,
                        );
                      }
                      final product = products[index - 1];
                      return _InventoryProductTile(
                        product: product,
                        controller: _quantityControllerFor(product),
                        available: _availableFor(product),
                        saving: state.savingProduct,
                        onAvailabilityChanged: (value) {
                          setState(() {
                            _availabilityByProductId[product.id] = value;
                          });
                        },
                        onSave: () => _saveProduct(product),
                      );
                    },
                  ),
          ),
        ),
        bottomNavigationBar: products.isEmpty
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(
                      top: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: FilledButton.icon(
                    onPressed: state.savingProduct ? null : _confirmDailyCheck,
                    icon: state.savingProduct
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('تأكيد جرد اليوم'),
                  ),
                ),
              ),
      ),
    );
  }
}

class _InventoryHeader extends StatelessWidget {
  final int total;
  final int unavailable;
  final bool saving;
  final VoidCallback onConfirm;

  const _InventoryHeader({
    required this.total,
    required this.unavailable,
    required this.saving,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'جرد مخزون المتجر',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'المنتجات: $total   غير متوفر: $unavailable',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'تأكيد جرد اليوم',
            onPressed: saving ? null : onConfirm,
            icon: const Icon(Icons.done_all_rounded),
          ),
        ],
      ),
    );
  }
}

class _InventoryProductTile extends StatelessWidget {
  final ProductModel product;
  final TextEditingController controller;
  final bool available;
  final bool saving;
  final ValueChanged<bool> onAvailabilityChanged;
  final VoidCallback onSave;

  const _InventoryProductTile({
    required this.product,
    required this.controller,
    required this.available,
    required this.saving,
    required this.onAvailabilityChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = available ? const Color(0xFF2E7D57) : scheme.error;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ProductThumb(product: product),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product.categoryName?.trim().isNotEmpty == true
                            ? product.categoryName!
                            : 'بدون قسم',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    available ? 'متوفر' : 'غير متوفر',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToggleButtons(
                  constraints: const BoxConstraints(
                    minHeight: 40,
                    minWidth: 92,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  isSelected: [available, !available],
                  onPressed: saving
                      ? null
                      : (index) => onAvailabilityChanged(index == 0),
                  children: const [Text('متوفر'), Text('غير متوفر')],
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: controller,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'العدد',
                      prefixIcon: Icon(Icons.numbers_rounded),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) {
                      if (!saving) onSave();
                    },
                  ),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('حفظ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  final ProductModel product;

  const _ProductThumb({required this.product});

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.imageUrl;
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56,
        height: 56,
        color: scheme.surfaceContainerHighest,
        child: imageUrl == null || imageUrl.trim().isEmpty
            ? Icon(Icons.inventory_2_outlined, color: scheme.onSurfaceVariant)
            : CachedAppImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: 56,
                height: 56,
              ),
      ),
    );
  }
}

class _EmptyInventoryState extends StatelessWidget {
  const _EmptyInventoryState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 44, color: scheme.primary),
          const SizedBox(height: 10),
          const Text(
            'لا توجد منتجات للجرد',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'أضف المنتجات أولا ثم ارجع للجرد اليومي.',
            style: TextStyle(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
