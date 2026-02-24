import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/currency.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../orders/state/cart_controller.dart';
import '../../orders/state/orders_controller.dart';
import '../../orders/ui/cart_screen.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../../products/models/product_category_model.dart';
import '../../products/models/product_model.dart';
import '../models/merchant_model.dart';
import '../state/merchants_controller.dart';

class MerchantProductsScreen extends ConsumerStatefulWidget {
  final MerchantModel merchant;

  const MerchantProductsScreen({super.key, required this.merchant});

  @override
  ConsumerState<MerchantProductsScreen> createState() =>
      _MerchantProductsScreenState();
}

class _MerchantProductsScreenState
    extends ConsumerState<MerchantProductsScreen> {
  AsyncValue<_MerchantProductsData> state = const AsyncValue.loading();
  int? selectedCategoryId;

  bool get _canCustomerActions {
    final auth = ref.read(authControllerProvider);
    return !auth.isBackoffice && !auth.isOwner && !auth.isDelivery;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _load();
      if (_canCustomerActions) {
        await ref
            .read(ordersControllerProvider.notifier)
            .loadFavoriteProductIds();
      }
    });
  }

  Future<void> _load() async {
    setState(() => state = const AsyncValue.loading());
    try {
      final api = ref.read(merchantsApiProvider);
      final productsFuture = api.listProducts(widget.merchant.id);
      final categoriesFuture = api.listCategories(widget.merchant.id);
      final responses = await Future.wait([productsFuture, categoriesFuture]);

      final products = List<dynamic>.from(responses[0])
          .map(
            (e) => ProductModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      final categories = List<dynamic>.from(responses[1])
          .map(
            (e) => ProductCategoryModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();

      final availableCategoryIds = products
          .map((p) => p.categoryId)
          .whereType<int>()
          .toSet();
      if (selectedCategoryId != null &&
          !availableCategoryIds.contains(selectedCategoryId)) {
        selectedCategoryId = null;
      }

      setState(
        () => state = AsyncValue.data(
          _MerchantProductsData(products: products, categories: categories),
        ),
      );
    } catch (_) {
      setState(
        () => state = const AsyncValue.error(
          'فشل تحميل منتجات المتجر',
          StackTrace.empty,
        ),
      );
    }
  }

  Future<void> _openCart() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  Future<void> _openOrders() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomerOrdersScreen()));
  }

  Future<void> _addToCart(ProductModel product) async {
    final cart = ref.read(cartControllerProvider);

    if (cart.merchantId != null &&
        cart.merchantId != widget.merchant.id &&
        cart.items.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('استبدال السلة'),
          content: const Text(
            'السلة تحتوي منتجات من متجر آخر. هل تريد إفراغها وإضافة هذا المنتج؟',
            textDirection: TextDirection.rtl,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('استبدال'),
            ),
          ],
        ),
      );
      if (!mounted || replace != true) return;
      ref.read(cartControllerProvider.notifier).clear();
    }

    ref
        .read(cartControllerProvider.notifier)
        .addItem(
          product: product,
          merchantId: widget.merchant.id,
          merchantName: widget.merchant.name,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت إضافة ${product.name} إلى السلة')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final orders = ref.watch(ordersControllerProvider);

    ref.listen<OrdersState>(ordersControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.merchant.name),
        actions: [
          if (_canCustomerActions)
            IconButton(
              tooltip: 'طلباتي',
              onPressed: _openOrders,
              icon: const Icon(Icons.receipt_long),
            ),
          if (_canCustomerActions)
            Stack(
              children: [
                IconButton(
                  tooltip: 'السلة',
                  onPressed: _openCart,
                  icon: const Icon(Icons.shopping_cart_outlined),
                ),
                if (cart.totalItems > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${cart.totalItems}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          const NotificationsBellButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: state.when(
          data: (data) {
            final selectedProducts = selectedCategoryId == null
                ? data.products
                : data.products
                      .where((p) => p.categoryId == selectedCategoryId)
                      .toList();

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _MerchantHeader(merchant: widget.merchant),
                const SizedBox(height: 12),
                _CategoryFilterRow(
                  categories: data.categories,
                  selectedCategoryId: selectedCategoryId,
                  totalProductsCount: data.products.length,
                  onSelect: (id) => setState(() => selectedCategoryId = id),
                ),
                const SizedBox(height: 12),
                if (selectedProducts.isEmpty)
                  const _EmptyProducts()
                else
                  ...selectedProducts.map((product) {
                    final canOrder =
                        widget.merchant.isOpen && product.isAvailable;
                    final isFavorite = orders.favoriteProductIds.contains(
                      product.id,
                    );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ProductCard(
                        product: product,
                        canOrder: canOrder,
                        isFavorite: isFavorite,
                        showCustomerActions: _canCustomerActions,
                        onToggleFavorite: _canCustomerActions
                            ? () => ref
                                  .read(ordersControllerProvider.notifier)
                                  .toggleFavoriteProduct(
                                    product.id,
                                    !isFavorite,
                                  )
                            : null,
                        onAddToCart: _canCustomerActions && canOrder
                            ? () => _addToCart(product)
                            : null,
                        closedLabel: widget.merchant.isOpen
                            ? 'غير متاح حالياً'
                            : 'المتجر مغلق الآن',
                      ),
                    );
                  }),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
        ),
      ),
    );
  }
}

class _MerchantProductsData {
  final List<ProductModel> products;
  final List<ProductCategoryModel> categories;

  const _MerchantProductsData({
    required this.products,
    required this.categories,
  });
}

class _MerchantHeader extends StatelessWidget {
  final MerchantModel merchant;

  const _MerchantHeader({required this.merchant});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: AspectRatio(
              aspectRatio: 16 / 8,
              child: merchant.imageUrl == null || merchant.imageUrl!.isEmpty
                  ? Container(
                      color: Colors.black.withValues(alpha: 0.18),
                      alignment: Alignment.center,
                      child: Icon(
                        merchant.type == 'restaurant'
                            ? Icons.restaurant_rounded
                            : Icons.storefront_rounded,
                        size: 46,
                      ),
                    )
                  : Image.network(
                      merchant.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.black.withValues(alpha: 0.18),
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_not_supported_rounded),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  merchant.name,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  merchant.description?.trim().isNotEmpty == true
                      ? merchant.description!
                      : 'متجر من مدينة بسماية',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.84)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    _Badge(
                      text: merchant.isOpen ? 'مفتوح الآن' : 'مغلق الآن',
                      color: merchant.isOpen
                          ? Colors.green.withValues(alpha: 0.20)
                          : Colors.red.withValues(alpha: 0.18),
                    ),
                    if (merchant.hasDiscountOffer)
                      _Badge(
                        text: 'عروض خصم',
                        color: Colors.orange.withValues(alpha: 0.24),
                      ),
                    if (merchant.hasFreeDeliveryOffer)
                      _Badge(
                        text: 'يوجد توصيل مجاني',
                        color: Colors.teal.withValues(alpha: 0.24),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryFilterRow extends StatelessWidget {
  final List<ProductCategoryModel> categories;
  final int? selectedCategoryId;
  final int totalProductsCount;
  final void Function(int? categoryId) onSelect;

  const _CategoryFilterRow({
    required this.categories,
    required this.selectedCategoryId,
    required this.totalProductsCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CategoryChip(
            label: 'الكل ($totalProductsCount)',
            selected: selectedCategoryId == null,
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: 8),
          ...categories.map(
            (category) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _CategoryChip(
                label: '${category.name} (${category.availableProductsCount})',
                selected: selectedCategoryId == category.id,
                onTap: () => onSelect(category.id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final bool canOrder;
  final bool isFavorite;
  final bool showCustomerActions;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onAddToCart;
  final String closedLabel;

  const _ProductCard({
    required this.product,
    required this.canOrder,
    required this.isFavorite,
    required this.showCustomerActions,
    required this.onToggleFavorite,
    required this.onAddToCart,
    required this.closedLabel,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePrice = product.discountedPrice ?? product.price;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 88,
                height: 88,
                child: product.imageUrl == null || product.imageUrl!.isEmpty
                    ? Container(
                        color: Colors.white.withValues(alpha: 0.08),
                        alignment: Alignment.center,
                        child: const Icon(Icons.fastfood_rounded),
                      )
                    : Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.white.withValues(alpha: 0.08),
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_rounded),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    product.name,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (product.categoryName?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      product.categoryName!,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.70),
                      ),
                    ),
                  ],
                  if (product.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description!,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      if (product.hasDiscount &&
                          product.discountPercent != null)
                        _Badge(
                          text: 'خصم ${product.discountPercent}%',
                          color: Colors.orange.withValues(alpha: 0.24),
                        ),
                      if (product.freeDelivery)
                        _Badge(
                          text: 'توصيل مجاني',
                          color: Colors.teal.withValues(alpha: 0.24),
                        ),
                      if (product.offerLabel?.trim().isNotEmpty == true)
                        _Badge(
                          text: product.offerLabel!.trim(),
                          color: Colors.pink.withValues(alpha: 0.22),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        formatIqd(effectivePrice),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (product.hasDiscount)
                        Text(
                          formatIqd(product.price),
                          style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 12,
                          ),
                        ),
                      const Spacer(),
                      if (showCustomerActions) ...[
                        IconButton(
                          tooltip: isFavorite
                              ? 'إزالة من المفضلة'
                              : 'إضافة إلى المفضلة',
                          onPressed: onToggleFavorite,
                          icon: Icon(
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFavorite ? Colors.red : null,
                          ),
                        ),
                        if (canOrder)
                          IconButton(
                            tooltip: 'إضافة إلى السلة',
                            onPressed: onAddToCart,
                            icon: const Icon(Icons.add_shopping_cart_rounded),
                          )
                        else
                          Text(
                            closedLabel,
                            style: TextStyle(
                              color: Colors.red.shade300,
                              fontSize: 12,
                            ),
                          ),
                      ] else
                        Text(
                          canOrder ? 'متاح' : 'غير متاح',
                          style: TextStyle(
                            color: canOrder
                                ? Colors.green.shade400
                                : Colors.red.shade300,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: const [
            Icon(Icons.inventory_2_outlined, size: 34),
            SizedBox(height: 8),
            Text(
              'لا توجد منتجات متاحة في هذا القسم',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
