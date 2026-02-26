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

enum _ProductsSortMode {
  recommended,
  priceLowToHigh,
  priceHighToLow,
  biggestDiscount,
}

enum _SmartBundleStyle { balanced, budget, offers, variety }

class _MerchantProductsScreenState
    extends ConsumerState<MerchantProductsScreen> {
  AsyncValue<_MerchantProductsData> state = const AsyncValue.loading();
  int? selectedCategoryId;
  final productSearchCtrl = TextEditingController();
  String productSearchQuery = '';
  bool onlyAvailable = true;
  bool onlyOffers = false;
  bool favoritesOnly = false;
  _ProductsSortMode sortMode = _ProductsSortMode.recommended;
  final smartBudgetCtrl = TextEditingController();
  int smartPartySize = 1;
  _SmartBundleStyle smartBundleStyle = _SmartBundleStyle.balanced;
  bool generatingSmartBundle = false;

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

  @override
  void dispose() {
    productSearchCtrl.dispose();
    smartBudgetCtrl.dispose();
    super.dispose();
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

  List<ProductModel> _buildVisibleProducts(
    List<ProductModel> products,
    Set<int> favoriteProductIds,
  ) {
    final q = productSearchQuery.trim().toLowerCase();

    var list = selectedCategoryId == null
        ? [...products]
        : products.where((p) => p.categoryId == selectedCategoryId).toList();

    if (q.isNotEmpty) {
      list = list.where((product) {
        final name = product.name.toLowerCase();
        final desc = (product.description ?? '').toLowerCase();
        final category = (product.categoryName ?? '').toLowerCase();
        return name.contains(q) || desc.contains(q) || category.contains(q);
      }).toList();
    }

    if (onlyAvailable) {
      list = list.where((product) => product.isAvailable).toList();
    }

    if (onlyOffers) {
      list = list.where((product) {
        return product.hasDiscount ||
            product.freeDelivery ||
            (product.offerLabel?.trim().isNotEmpty == true);
      }).toList();
    }

    if (favoritesOnly) {
      list = list
          .where((product) => favoriteProductIds.contains(product.id))
          .toList();
    }

    switch (sortMode) {
      case _ProductsSortMode.priceLowToHigh:
        list.sort((a, b) => _effectivePrice(a).compareTo(_effectivePrice(b)));
        break;
      case _ProductsSortMode.priceHighToLow:
        list.sort((a, b) => _effectivePrice(b).compareTo(_effectivePrice(a)));
        break;
      case _ProductsSortMode.biggestDiscount:
        list.sort((a, b) {
          final aDiscount = a.discountPercent ?? 0;
          final bDiscount = b.discountPercent ?? 0;
          final discountDiff = bDiscount.compareTo(aDiscount);
          if (discountDiff != 0) return discountDiff;
          return _effectivePrice(a).compareTo(_effectivePrice(b));
        });
        break;
      case _ProductsSortMode.recommended:
        list.sort((a, b) {
          final aScore = _productScore(a, favoriteProductIds);
          final bScore = _productScore(b, favoriteProductIds);
          final scoreDiff = bScore.compareTo(aScore);
          if (scoreDiff != 0) return scoreDiff;
          return a.sortOrder.compareTo(b.sortOrder);
        });
        break;
    }

    return list;
  }

  double _effectivePrice(ProductModel product) {
    return product.discountedPrice ?? product.price;
  }

  int _productScore(ProductModel product, Set<int> favoriteProductIds) {
    var score = 0;
    if (product.isAvailable) score += 40;
    if (favoriteProductIds.contains(product.id)) score += 35;
    if (product.hasDiscount) score += 25;
    if (product.freeDelivery) score += 18;
    if ((product.offerLabel?.trim().isNotEmpty ?? false)) score += 10;
    return score;
  }

  int? _parseSmartBudget() {
    final digits = smartBudgetCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;
    final parsed = int.tryParse(digits);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  int _smartBaseScore(ProductModel product, Set<int> favorites) {
    var score = _productScore(product, favorites);
    switch (smartBundleStyle) {
      case _SmartBundleStyle.budget:
        score += (100000 / (_effectivePrice(product) + 100)).round();
        break;
      case _SmartBundleStyle.offers:
        if (product.hasDiscount) score += 40;
        if (product.freeDelivery) score += 24;
        if ((product.offerLabel?.trim().isNotEmpty ?? false)) score += 18;
        break;
      case _SmartBundleStyle.variety:
        score += (product.categoryId ?? 0) > 0 ? 16 : 4;
        break;
      case _SmartBundleStyle.balanced:
        score += 8;
        break;
    }
    return score;
  }

  int _targetBundleCount() {
    if (smartPartySize <= 1) return 2;
    if (smartPartySize == 2) return 3;
    if (smartPartySize <= 4) return 4;
    return 6;
  }

  List<ProductModel> _generateSmartBundle({
    required List<ProductModel> products,
    required Set<int> favoriteProductIds,
  }) {
    final available = products.where((p) => p.isAvailable).toList();
    if (available.isEmpty) return const <ProductModel>[];

    final budget = _parseSmartBudget();
    final targetCount = _targetBundleCount();
    final sorted = [...available]
      ..sort((a, b) {
        final scoreDiff = _smartBaseScore(
          b,
          favoriteProductIds,
        ).compareTo(_smartBaseScore(a, favoriteProductIds));
        if (scoreDiff != 0) return scoreDiff;
        return _effectivePrice(a).compareTo(_effectivePrice(b));
      });

    final byCategory = <int, List<ProductModel>>{};
    for (final product in sorted) {
      final key = product.categoryId ?? 0;
      byCategory.putIfAbsent(key, () => <ProductModel>[]).add(product);
    }

    final picked = <ProductModel>[];
    final usedIds = <int>{};
    double total = 0;

    bool tryPick(ProductModel product) {
      if (usedIds.contains(product.id)) return false;
      final price = _effectivePrice(product);
      if (budget != null && budget > 0 && picked.isNotEmpty) {
        if (total + price > budget) return false;
      }
      picked.add(product);
      usedIds.add(product.id);
      total += price;
      return true;
    }

    for (final productsInCategory in byCategory.values) {
      if (picked.length >= targetCount) break;
      for (final product in productsInCategory) {
        if (tryPick(product)) break;
      }
    }

    for (final product in sorted) {
      if (picked.length >= targetCount) break;
      tryPick(product);
    }

    if (picked.isEmpty) {
      picked.add(sorted.first);
    }

    return picked;
  }

  Future<void> _addBundleToCart(List<ProductModel> bundle) async {
    if (bundle.isEmpty) return;
    final cart = ref.read(cartControllerProvider);
    if (cart.merchantId != null &&
        cart.merchantId != widget.merchant.id &&
        cart.items.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('استبدال السلة'),
          content: const Text(
            'السلة الحالية من متجر آخر. هل تريد استبدالها بالسلة الذكية الجديدة؟',
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

    final notifier = ref.read(cartControllerProvider.notifier);
    for (final product in bundle) {
      notifier.addItem(
        product: product,
        merchantId: widget.merchant.id,
        merchantName: widget.merchant.name,
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('تم إنشاء سلة ذكية وإضافة ${bundle.length} منتجات'),
      ),
    );
  }

  Future<void> _generateAndApplySmartBundle(List<ProductModel> products) async {
    if (generatingSmartBundle) return;
    setState(() => generatingSmartBundle = true);
    final favorites = ref.read(ordersControllerProvider).favoriteProductIds;
    final bundle = _generateSmartBundle(
      products: products,
      favoriteProductIds: favorites,
    );
    if (!mounted) return;
    setState(() => generatingSmartBundle = false);
    if (bundle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد منتجات متاحة لإنشاء سلة ذكية')),
      );
      return;
    }

    final total = bundle.fold<double>(
      0,
      (sum, item) => sum + _effectivePrice(item),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'السلة الذكية المقترحة',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ...bundle.map(
                  (product) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '• ${product.name} - ${formatIqd(_effectivePrice(product))}',
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'الإجمالي التقريبي: ${formatIqd(total)}',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _addBundleToCart(bundle);
                  },
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('اعتماد السلة الذكية'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCart() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  Future<void> _openOrders() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text('تمت إضافة ${product.name} إلى السلة'),
      ),
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

    final canOpenCartQuickly =
        _canCustomerActions &&
        cart.totalItems > 0 &&
        cart.merchantId == widget.merchant.id;

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
      bottomNavigationBar: canOpenCartQuickly
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: ElevatedButton.icon(
                  onPressed: _openCart,
                  icon: const Icon(Icons.shopping_cart_checkout_rounded),
                  label: Text(
                    'إكمال الطلب • ${cart.totalItems} منتج • ${formatIqd(cart.total)}',
                  ),
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: state.when(
          data: (data) {
            final visibleProducts = _buildVisibleProducts(
              data.products,
              orders.favoriteProductIds,
            );

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
                TextField(
                  controller: productSearchCtrl,
                  textDirection: TextDirection.rtl,
                  onChanged: (value) =>
                      setState(() => productSearchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن المنتجات',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: productSearchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              productSearchCtrl.clear();
                              setState(() => productSearchQuery = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                _ProductsDiscoveryToolbar(
                  onlyAvailable: onlyAvailable,
                  onlyOffers: onlyOffers,
                  favoritesOnly: favoritesOnly,
                  sortMode: sortMode,
                  onOnlyAvailableChanged: (value) =>
                      setState(() => onlyAvailable = value),
                  onOnlyOffersChanged: (value) =>
                      setState(() => onlyOffers = value),
                  onFavoritesOnlyChanged: (value) =>
                      setState(() => favoritesOnly = value),
                  onSortChanged: (value) => setState(() => sortMode = value),
                ),
                const SizedBox(height: 12),
                if (_canCustomerActions) ...[
                  _SmartBundlePlannerCard(
                    partySize: smartPartySize,
                    style: smartBundleStyle,
                    budgetController: smartBudgetCtrl,
                    generating: generatingSmartBundle,
                    onPartySizeChanged: (value) =>
                        setState(() => smartPartySize = value),
                    onStyleChanged: (value) =>
                        setState(() => smartBundleStyle = value),
                    onGenerate: () =>
                        _generateAndApplySmartBundle(data.products),
                  ),
                  const SizedBox(height: 12),
                ],
                if (visibleProducts.isEmpty)
                  const _EmptyProducts()
                else
                  ...visibleProducts.map((product) {
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

class _ProductsDiscoveryToolbar extends StatelessWidget {
  final bool onlyAvailable;
  final bool onlyOffers;
  final bool favoritesOnly;
  final _ProductsSortMode sortMode;
  final ValueChanged<bool> onOnlyAvailableChanged;
  final ValueChanged<bool> onOnlyOffersChanged;
  final ValueChanged<bool> onFavoritesOnlyChanged;
  final ValueChanged<_ProductsSortMode> onSortChanged;

  const _ProductsDiscoveryToolbar({
    required this.onlyAvailable,
    required this.onlyOffers,
    required this.favoritesOnly,
    required this.sortMode,
    required this.onOnlyAvailableChanged,
    required this.onOnlyOffersChanged,
    required this.onFavoritesOnlyChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                DropdownButton<_ProductsSortMode>(
                  value: sortMode,
                  onChanged: (value) {
                    if (value == null) return;
                    onSortChanged(value);
                  },
                  items: const [
                    DropdownMenuItem(
                      value: _ProductsSortMode.recommended,
                      child: Text('الأكثر مناسبة'),
                    ),
                    DropdownMenuItem(
                      value: _ProductsSortMode.priceLowToHigh,
                      child: Text('السعر: الأقل للأعلى'),
                    ),
                    DropdownMenuItem(
                      value: _ProductsSortMode.priceHighToLow,
                      child: Text('السعر: الأعلى للأقل'),
                    ),
                    DropdownMenuItem(
                      value: _ProductsSortMode.biggestDiscount,
                      child: Text('أعلى خصم'),
                    ),
                  ],
                ),
                const Spacer(),
                const Text(
                  'فلترة المنتجات',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.filter_alt_outlined, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                FilterChip(
                  selected: onlyAvailable,
                  onSelected: onOnlyAvailableChanged,
                  label: const Text('المتاح فقط'),
                ),
                FilterChip(
                  selected: onlyOffers,
                  onSelected: onOnlyOffersChanged,
                  label: const Text('العروض فقط'),
                ),
                FilterChip(
                  selected: favoritesOnly,
                  onSelected: onFavoritesOnlyChanged,
                  label: const Text('المفضلة فقط'),
                  avatar: const Icon(Icons.favorite_rounded, size: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartBundlePlannerCard extends StatelessWidget {
  final int partySize;
  final _SmartBundleStyle style;
  final TextEditingController budgetController;
  final bool generating;
  final ValueChanged<int> onPartySizeChanged;
  final ValueChanged<_SmartBundleStyle> onStyleChanged;
  final Future<void> Function() onGenerate;

  const _SmartBundlePlannerCard({
    required this.partySize,
    required this.style,
    required this.budgetController,
    required this.generating,
    required this.onPartySizeChanged,
    required this.onStyleChanged,
    required this.onGenerate,
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
              'مُولّد السلة الذكي',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'اقترح سلة تلقائية حسب العدد والميزانية ونمط الطلب',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: budgetController,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                      labelText: 'ميزانية اختيارية (IQD)',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: partySize,
                  onChanged: (value) {
                    if (value == null) return;
                    onPartySizeChanged(value);
                  },
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                    DropdownMenuItem(value: 3, child: Text('3')),
                    DropdownMenuItem(value: 4, child: Text('4')),
                    DropdownMenuItem(value: 5, child: Text('5+')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                ChoiceChip(
                  selected: style == _SmartBundleStyle.balanced,
                  label: const Text('متوازن'),
                  onSelected: (_) => onStyleChanged(_SmartBundleStyle.balanced),
                ),
                ChoiceChip(
                  selected: style == _SmartBundleStyle.budget,
                  label: const Text('اقتصادي'),
                  onSelected: (_) => onStyleChanged(_SmartBundleStyle.budget),
                ),
                ChoiceChip(
                  selected: style == _SmartBundleStyle.offers,
                  label: const Text('العروض'),
                  onSelected: (_) => onStyleChanged(_SmartBundleStyle.offers),
                ),
                ChoiceChip(
                  selected: style == _SmartBundleStyle.variety,
                  label: const Text('تنويع'),
                  onSelected: (_) => onStyleChanged(_SmartBundleStyle.variety),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: generating ? null : onGenerate,
              icon: generating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: const Text('ولّد سلة ذكية الآن'),
            ),
          ],
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
