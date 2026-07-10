// ignore_for_file: prefer_const_constructors, duplicate_ignore

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../auth/state/auth_controller.dart';
import '../../behavior/data/behavior_api.dart';
import '../../orders/state/cart_controller.dart';
import '../../orders/state/orders_controller.dart';
import '../../orders/ui/cart_screen.dart';
import '../../pharmacy/ui/pharmacy_conversation_screen.dart';
import '../../products/models/product_category_model.dart';
import '../../products/models/product_model.dart';
import '../../products/ui/product_summary_card.dart';
import '../../products/ui/product_variant_picker_sheet.dart';
import '../utils/catalog_taxonomy.dart';
import 'merchant_product_details_screen.dart';
import '../models/merchant_model.dart';
import '../state/merchants_controller.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

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

List<ProductModel> filterMerchantDiscountHighlights(
  List<ProductModel> products,
) {
  return products
      .where((product) => product.hasDiscount)
      .where((product) => product.canBeOrdered)
      .toList(growable: false);
}

List<ProductModel> filterMerchantSmartBundleCandidates(
  List<ProductModel> products, {
  required bool supportsPharmacyWorkflow,
}) {
  return products
      .where((product) => product.canBeOrdered)
      .where((product) => !product.hasVariants)
      .where(
        (product) =>
            !supportsPharmacyWorkflow || !product.requiresPharmacyConversation,
      )
      .toList(growable: false);
}

class _MerchantProductsScreenState
    extends ConsumerState<MerchantProductsScreen> {
  AsyncValue<_MerchantProductsData> state = const AsyncValue.loading();
  int? selectedCategoryId;
  final Map<int, ProductSummaryCardSelection> _cardSelections = {};
  final productSearchCtrl = TextEditingController();
  String productSearchQuery = '';
  bool onlyAvailable = false;
  bool onlyOffers = false;
  bool favoritesOnly = false;
  _ProductsSortMode sortMode = _ProductsSortMode.recommended;
  final smartBudgetCtrl = TextEditingController();
  int smartPartySize = 1;
  _SmartBundleStyle smartBundleStyle = _SmartBundleStyle.balanced;
  bool generatingSmartBundle = false;
  final bool _legacySingleStoreReplacementEnabled = false;

  bool get _canCustomerActions {
    final auth = ref.read(authControllerProvider);
    return !auth.isBackoffice && !auth.isOwner && !auth.isDelivery;
  }

  bool _requiresStrictVariantSelection(ProductModel product) {
    final hasColor = product.variantGroups.any(
      (group) => group.code.trim().toLowerCase() == 'color',
    );
    final hasSize = product.variantGroups.any(
      (group) => group.code.trim().toLowerCase() == 'size',
    );
    return hasColor && hasSize;
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
      final visibleCategories = filterCategoriesForActivity(
        categories,
        widget.merchant.activityType,
      );

      final availableCategoryIds = products
          .map((p) => p.categoryId)
          .whereType<int>()
          .toSet();
      final visibleCategoryIds = visibleCategories.map((c) => c.id).toSet();
      if (selectedCategoryId != null &&
          (!availableCategoryIds.contains(selectedCategoryId) ||
              !visibleCategoryIds.contains(selectedCategoryId))) {
        selectedCategoryId = null;
      }

      setState(
        () => state = AsyncValue.data(
          _MerchantProductsData(
            products: products,
            categories: visibleCategories,
          ),
        ),
      );
      await ref
          .read(behaviorApiProvider)
          .trackEvent(
            eventName: 'shopping.merchant_open',
            category: 'shopping',
            action: 'open_merchant',
            entityType: 'merchant',
            entityId: widget.merchant.id,
            metadata: {
              'merchantId': widget.merchant.id,
              'merchantName': widget.merchant.name,
              'merchantType': widget.merchant.type,
              'activityType': widget.merchant.activityType,
              'route': widget.merchant.type == 'market'
                  ? 'main_market'
                  : 'shopping',
              'screenLabel': widget.merchant.name,
              'recentTitle': 'كنت تتصفح متجر: ${widget.merchant.name}',
              'recentSubtitle': 'اضغط للعودة إلى ${widget.merchant.name}',
            },
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
    Set<int> allowedCategoryIds,
  ) {
    final q = productSearchQuery.trim().toLowerCase();

    var list = selectedCategoryId == null
        ? [...products]
        : products.where((p) => p.categoryId == selectedCategoryId).toList();

    list = list.where((product) {
      final categoryId = product.categoryId;
      return categoryId != null && allowedCategoryIds.contains(categoryId);
    }).toList();

    if (q.isNotEmpty) {
      list = list.where((product) {
        final name = product.name.toLowerCase();
        final desc = (product.description ?? '').toLowerCase();
        final category = (product.categoryName ?? '').toLowerCase();
        return name.contains(q) || desc.contains(q) || category.contains(q);
      }).toList();
    }

    if (onlyAvailable) {
      list = list.where((product) => product.canBeOrdered).toList();
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

  Map<int, int> _countProductsByCategory(List<ProductModel> products) {
    final counts = <int, int>{};
    for (final product in products) {
      final categoryId = product.categoryId;
      if (categoryId == null) continue;
      counts.update(categoryId, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  List<Widget> _buildProductCards(
    List<ProductModel> products,
    List<ProductModel> allProducts,
  ) {
    final appearance = ProductSummaryCardAppearance.fromContext(context);
    final locale = Localizations.localeOf(context);
    return products.map((product) {
      final canOrder = widget.merchant.isOpen && product.canBeOrdered;
      final usesPharmacyConversation = _requiresPharmacyConversation(product);
      final strictVariantSelection = _requiresStrictVariantSelection(product);
      final cardData = ProductSummaryCardData.fromProduct(
        product,
        locale: locale,
        strictVariantSelection: strictVariantSelection,
      );
      final selection =
          _cardSelections[product.id] ?? cardData.resolveSelection();
      _cardSelections[product.id] ??= selection;

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ProductSummaryCard.fromProduct(
          product,
          key: ValueKey(product.id),
          appearance: appearance,
          locale: locale,
          onTap: () =>
              _openProductDetails(product: product, allProducts: allProducts),
          compact: true,
          maxAttributeBadges: 2,
          maxVariantBadges: 3,
          maxStatusBadges: 3,
          heroAspectRatio: 1.38,
          selectedColorCode: selection.colorCode,
          selectedSizeCode: selection.sizeCode,
          strictVariantSelection: strictVariantSelection,
          onSelectionChanged: (next) {
            setState(() => _cardSelections[product.id] = next);
          },
          trailing: _buildProductSummaryTrailing(
            product: product,
            canOrder: canOrder,
            usesPharmacyConversation: usesPharmacyConversation,
            showActions: _canCustomerActions,
            selectedVariantId: selection.variantId,
            selectedVariantSelections: selection.selectedVariantSelections,
            strictVariantSelection: strictVariantSelection,
          ),
        ),
      );
    }).toList();
  }

  Widget _buildProductSummaryTrailing({
    required ProductModel product,
    required bool canOrder,
    required bool usesPharmacyConversation,
    required bool showActions,
    required int? selectedVariantId,
    required List<Map<String, dynamic>> selectedVariantSelections,
    required bool strictVariantSelection,
  }) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    if (!showActions) {
      return Text(
        canOrder
            ? 'متاح'
            : (widget.merchant.isOpen
                  ? 'غير متوفر حالياً'
                  : 'المتجر مغلق الآن'),
        style: TextStyle(
          color: canOrder ? tokens.success : tokens.danger,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return GestureDetector(
      onTap: canOrder
          ? () => _addToCart(
              product,
              quantity: 1,
              initialVariantSelections: selectedVariantSelections,
              initialSelectedVariantId: selectedVariantId,
              strictVariantSelection: strictVariantSelection,
            )
          : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: canOrder
              ? visual.accentCyan.withValues(alpha: 0.15)
              : tokens.borderSubtle.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: canOrder
                ? visual.accentCyan.withValues(alpha: 0.4)
                : tokens.borderSubtle,
          ),
        ),
        child: Icon(
          usesPharmacyConversation
              ? Icons.chat_bubble_outline_rounded
              : product.hasVariants
              ? Icons.tune_rounded
              : Icons.add_rounded,
          color: canOrder ? visual.accentCyan : tokens.textMuted,
          size: 22,
        ),
      ),
    );
  }

  List<Widget> _buildProductSections(
    List<ProductModel> visibleProducts,
    List<ProductModel> allProducts,
    List<ProductCategoryModel> categories,
    Set<int> favoriteProductIds,
  ) {
    if (visibleProducts.isEmpty) return const [_EmptyProducts()];

    if (selectedCategoryId != null) {
      return _buildProductCards(visibleProducts, allProducts);
    }

    final sections = <Widget>[];
    final grouped = <int, List<ProductModel>>{};
    final uncategorized = <ProductModel>[];

    for (final product in visibleProducts) {
      final categoryId = product.categoryId;
      if (categoryId == null) {
        uncategorized.add(product);
        continue;
      }
      grouped.putIfAbsent(categoryId, () => <ProductModel>[]).add(product);
    }

    for (final category in categories) {
      final items = grouped[category.id];
      if (items == null || items.isEmpty) continue;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _CategorySectionHeader(
            title: category.name,
            countLabel: '${items.length} مادة',
          ),
        ),
      );
      sections.addAll(_buildProductCards(items, allProducts));
    }

    if (uncategorized.isNotEmpty) {
      sections.add(
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: _CategorySectionHeader(
            title: 'مواد أخرى',
            countLabel: 'بدون تصنيف',
          ),
        ),
      );
      sections.addAll(_buildProductCards(uncategorized, allProducts));
    }

    return sections.isEmpty ? const [_EmptyProducts()] : sections;
  }

  List<ProductModel> _buildDiscountHighlights(List<ProductModel> products) {
    final discounted = filterMerchantDiscountHighlights(products).toList();
    discounted.sort((a, b) {
      final aDiscount = a.discountPercent ?? 0;
      final bDiscount = b.discountPercent ?? 0;
      final byDiscount = bDiscount.compareTo(aDiscount);
      if (byDiscount != 0) return byDiscount;
      return _effectivePrice(a).compareTo(_effectivePrice(b));
    });
    return discounted.take(12).toList();
  }

  double _effectivePrice(ProductModel product) {
    return product.discountedPrice ?? product.price;
  }

  bool _requiresPharmacyConversation(ProductModel product) {
    return widget.merchant.supportsPharmacyWorkflow &&
        product.requiresPharmacyConversation;
  }

  String _buildPharmacyContextMessage(
    ProductModel product, {
    int quantity = 1,
    List<Map<String, dynamic>> selectedVariantSelections = const [],
  }) {
    final pieces = <String>[
      context.lt(
        ar: 'أرغب بمراجعة هذا المنتج الصيدلي:',
        en: 'I want this pharmacy product to be reviewed:',
      ),
      product.name,
      context.lt(
        ar: 'الكمية المطلوبة: $quantity',
        en: 'Requested quantity: $quantity',
      ),
    ];
    if ((product.description ?? '').trim().isNotEmpty) {
      pieces.add(
        context.lt(
          ar: 'ملاحظات المنتج: ${product.description!.trim()}',
          en: 'Product notes: ${product.description!.trim()}',
        ),
      );
    }
    if (selectedVariantSelections.isNotEmpty) {
      pieces.add(
        context.lt(
          ar: 'الاختيارات: ${selectedVariantSelections.map(_formatVariantSelectionLabel).join(' | ')}',
          en: 'Selected options: ${selectedVariantSelections.map(_formatVariantSelectionLabel).join(' | ')}',
        ),
      );
    }
    return pieces.join('\n');
  }

  Map<String, dynamic> _buildPharmacyContextMetadata(
    ProductModel product, {
    int quantity = 1,
    List<Map<String, dynamic>> selectedVariantSelections = const [],
  }) {
    return <String, dynamic>{
      'source': 'product_catalog',
      'productId': product.id,
      'productName': product.name,
      'quantity': quantity,
      'requiresPrescription': product.requiresPrescription,
      'requiresReview': product.requiresReview,
      'merchantId': widget.merchant.id,
      if (selectedVariantSelections.isNotEmpty)
        'selectedVariantSelections': selectedVariantSelections,
    };
  }

  int _productScore(ProductModel product, Set<int> favoriteProductIds) {
    var score = 0;
    if (product.canBeOrdered) score += 40;
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
    final available = filterMerchantSmartBundleCandidates(
      products,
      supportsPharmacyWorkflow: widget.merchant.supportsPharmacyWorkflow,
    );
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

  // ignore: unused_element
  Future<void> _addBundleToCart(List<ProductModel> bundle) async {
    if (bundle.isEmpty) return;
    final cart = ref.read(cartControllerProvider);
    if (_legacySingleStoreReplacementEnabled &&
        cart.merchantId != null &&
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

  Future<void> _addBundleToCartSafe(List<ProductModel> bundle) async {
    if (bundle.isEmpty) return;
    final notifier = ref.read(cartControllerProvider.notifier);
    var addedCount = 0;
    var rejectedCount = 0;
    for (final product in bundle) {
      final status = notifier.addItem(
        product: product,
        merchantId: widget.merchant.id,
        merchantName: widget.merchant.name,
      );
      if (status == CartAddStatus.added) {
        addedCount += 1;
      } else {
        rejectedCount += 1;
      }
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
    if (addedCount == 0) {
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'لا يمكن إضافة منتجات من متجر رابع. الحد الأقصى 3 متاجر.',
          ),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          rejectedCount > 0
              ? 'تمت إضافة $addedCount منتجات وتعذر إضافة $rejectedCount بسبب حد 3 متاجر.'
              : 'تمت إضافة $addedCount منتجات إلى السلة.',
        ),
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
                    await _addBundleToCartSafe(bundle);
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

  List<ProductModel> _buildSimilarProducts(
    ProductModel product,
    List<ProductModel> allProducts,
  ) {
    final others = allProducts.where((item) => item.id != product.id).toList();
    if (others.isEmpty) return const <ProductModel>[];

    final sameCategory = others
        .where(
          (item) =>
              product.categoryId != null &&
              item.categoryId == product.categoryId,
        )
        .toList();
    final differentCategory = others
        .where((item) => !sameCategory.any((same) => same.id == item.id))
        .toList();
    final merged = <ProductModel>[...sameCategory, ...differentCategory];

    merged.sort((a, b) {
      final availabilityDiff = (b.canBeOrdered ? 1 : 0).compareTo(
        a.canBeOrdered ? 1 : 0,
      );
      if (availabilityDiff != 0) return availabilityDiff;
      final aPrice = _effectivePrice(a);
      final bPrice = _effectivePrice(b);
      return aPrice.compareTo(bPrice);
    });

    return merged.take(12).toList();
  }

  Future<void> _openProductDetails({
    required ProductModel product,
    required List<ProductModel> allProducts,
  }) async {
    final canOrder = widget.merchant.isOpen && product.canBeOrdered;
    final similar = _buildSimilarProducts(product, allProducts);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantProductDetailsScreen(
          merchant: widget.merchant,
          product: product,
          similarProducts: similar,
          canOrder: canOrder,
          unavailableLabel: widget.merchant.isOpen
              ? 'غير متوفر حالياً'
              : 'المتجر مغلق الآن',
          onAddToCart: _canCustomerActions
              ? (
                  selectedProduct,
                  quantity, {
                  List<Map<String, dynamic>> selectedVariantSelections =
                      const [],
                  int? selectedVariantId,
                }) async => _addToCart(
                  selectedProduct,
                  quantity: quantity,
                  initialVariantSelections: selectedVariantSelections,
                  initialSelectedVariantId: selectedVariantId,
                  showFeedback: false,
                )
              : null,
          onOpenProduct: (selectedProduct) => _openProductDetails(
            product: selectedProduct,
            allProducts: allProducts,
          ),
        ),
      ),
    );
  }

  Future<void> _openPharmacyConversation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PharmacyConversationScreen(
          merchantId: widget.merchant.id,
          titleOverride: widget.merchant.name,
        ),
      ),
    );
  }

  Future<void> _openPharmacyConversationForProduct(
    ProductModel product, {
    int quantity = 1,
    List<Map<String, dynamic>> selectedVariantSelections = const [],
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PharmacyConversationScreen(
          merchantId: widget.merchant.id,
          titleOverride: widget.merchant.name,
          pendingProductContextMessage: _buildPharmacyContextMessage(
            product,
            quantity: quantity,
            selectedVariantSelections: selectedVariantSelections,
          ),
          pendingProductContextMetadata: _buildPharmacyContextMetadata(
            product,
            quantity: quantity,
            selectedVariantSelections: selectedVariantSelections,
          ),
        ),
      ),
    );
  }

  Future<void> _addToCart(
    ProductModel product, {
    int quantity = 1,
    List<Map<String, dynamic>> initialVariantSelections = const [],
    int? initialSelectedVariantId,
    bool showFeedback = true,
    bool strictVariantSelection = false,
  }) async {
    final safeQuantity = quantity < 1 ? 1 : quantity;
    var variantSelections = initialVariantSelections;
    final selectedVariant = product.variantForSelectionEntries(
      variantSelections,
    );
    if (product.hasVariants) {
      if (strictVariantSelection && selectedVariant == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              context.lt(
                ar: 'اختر اللون والمقاس أولاً',
                en: 'Choose color and size first',
              ),
            ),
          ),
        );
        return;
      }
      if (selectedVariant == null) {
        final picked = await showProductVariantPickerSheet(
          context,
          product: product,
          initialSelections: initialVariantSelections,
        );
        if (!mounted || picked == null) return;
        variantSelections = picked;
      }
    }
    final resolvedVariant = product.variantForSelectionEntries(
      variantSelections,
    );
    if (_requiresPharmacyConversation(product)) {
      if (!widget.merchant.isOpen || !product.canBeOrdered) return;
      await _openPharmacyConversationForProduct(
        product,
        quantity: safeQuantity,
        selectedVariantSelections: variantSelections,
      );
      return;
    }
    final cart = ref.read(cartControllerProvider);

    if (_legacySingleStoreReplacementEnabled &&
        cart.merchantId != null &&
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

    final addStatus = ref
        .read(cartControllerProvider.notifier)
        .addItem(
          product: product,
          merchantId: widget.merchant.id,
          merchantName: widget.merchant.name,
          quantity: safeQuantity,
          selectedVariantId: resolvedVariant?.id ?? initialSelectedVariantId,
          selectedVariantSelections: variantSelections,
        );

    if (!mounted) return;
    if (addStatus == CartAddStatus.storeLimitExceeded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('لا يمكن إضافة متجر رابع. الحد الأقصى للسلة 3 متاجر.'),
        ),
      );
      return;
    }
    if (!showFeedback) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(
          context.lt(
            ar: 'تمت إضافة المنتج إلى السلة',
            en: 'The product was added to the cart.',
          ),
        ),
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

    final canOpenCartQuickly = _canCustomerActions && cart.totalItems > 0;

    final tokens = context.maslakiTokens;
    return Scaffold(
      backgroundColor: tokens.backgroundPrimary,
      appBar: MaslakiTopBar(
        title: widget.merchant.name,
        subtitle:
            widget.merchant.tagline ??
            widget.merchant.description ??
            merchantScopeTag(
              merchantType: widget.merchant.type,
              activityType: widget.merchant.activityType,
            ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 20,
            color: tokens.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_canCustomerActions && widget.merchant.supportsPharmacyWorkflow)
            IconButton(
              tooltip: context.l10n.pharmacyConversationTitle,
              onPressed: _openPharmacyConversation,
              icon: Icon(
                Icons.local_hospital_outlined,
                color: tokens.textPrimary,
              ),
            ),
          IconButton(
            tooltip: 'مشاركة',
            onPressed: () {},
            icon: Icon(Icons.ios_share_rounded, color: tokens.textPrimary),
          ),
          IconButton(
            tooltip: 'المفضلة',
            onPressed: () {},
            icon: Icon(
              Icons.favorite_border_rounded,
              color: tokens.textPrimary,
            ),
          ),
        ],
      ),
      bottomNavigationBar: canOpenCartQuickly
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: MaslakiCard(
                  radius: 20,
                  backgroundColor: tokens.surfacePrimary,
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.primaryAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: tokens.primaryAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shopping_cart_rounded,
                              color: tokens.primaryAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${cart.totalItems}',
                              style: TextStyle(
                                color: tokens.primaryAccent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${formatIqd(cart.total)} الإجمالي',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 124,
                        child: MaslakiPrimaryButton(
                          label: 'عرض السلة',
                          onPressed: _openCart,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: state.when(
          data: (data) {
            final visibleCategoryIds = data.categories.map((c) => c.id).toSet();
            final visibleProducts = _buildVisibleProducts(
              data.products,
              orders.favoriteProductIds,
              visibleCategoryIds,
            );
            final productCounts = _countProductsByCategory(visibleProducts);
            final productSections = _buildProductSections(
              visibleProducts,
              visibleProducts,
              data.categories,
              orders.favoriteProductIds,
            );
            final discountHighlights = _buildDiscountHighlights(
              visibleProducts,
            );

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _MerchantHeader(merchant: widget.merchant),
                if (widget.merchant.supportsPharmacyWorkflow) ...[
                  const SizedBox(height: 12),
                  _PharmacyWorkflowCard(
                    onOpenConversation: _openPharmacyConversation,
                  ),
                ],
                const SizedBox(height: 12),
                _CategoryFilterRow(
                  categories: data.categories,
                  selectedCategoryId: selectedCategoryId,
                  totalProductsCount: visibleProducts.length,
                  productCounts: productCounts,
                  onSelect: (id) => setState(() => selectedCategoryId = id),
                ),
                const SizedBox(height: 12),
                MaslakiSearchField(
                  controller: productSearchCtrl,
                  onChanged: (value) =>
                      setState(() => productSearchQuery = value),
                  hintText: 'ابحث عن المنتجات',
                  trailing: productSearchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            productSearchCtrl.clear();
                            setState(() => productSearchQuery = '');
                          },
                          icon: const Icon(Icons.close_rounded),
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
                        _generateAndApplySmartBundle(visibleProducts),
                  ),
                  const SizedBox(height: 12),
                ],
                if (discountHighlights.isNotEmpty) ...[
                  _CategorySectionHeader(
                    title: 'العروض',
                    countLabel: '${discountHighlights.length} منتجات مخفضة',
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 152,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      itemCount: discountHighlights.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final product = discountHighlights[index];
                        final finalPrice = _effectivePrice(product);
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _openProductDetails(
                            product: product,
                            allProducts: visibleProducts,
                          ),
                          child: Ink(
                            width: 210,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white.withValues(alpha: 0.04),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 62,
                                      height: 62,
                                      child:
                                          (product.imageUrl?.isNotEmpty ??
                                              false)
                                          ? CachedAppImage(
                                              imageUrl: product.imageUrl!,
                                              cacheIdentity:
                                                  'product_${product.id}',
                                              fit: BoxFit.cover,
                                            )
                                          : Container(
                                              color: Colors.white.withValues(
                                                alpha: 0.08,
                                              ),
                                              alignment: Alignment.center,
                                              child: const Icon(
                                                Icons.local_offer_outlined,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          product.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textDirection: TextDirection.rtl,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              formatIqd(finalPrice),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              formatIqd(product.price),
                                              style: TextStyle(
                                                decoration:
                                                    TextDecoration.lineThrough,
                                                color: Colors.white.withValues(
                                                  alpha: 0.62,
                                                ),
                                                fontSize: 12,
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                color: Colors.orange.withValues(
                                                  alpha: 0.20,
                                                ),
                                              ),
                                              child: Text(
                                                '-${product.discountPercent ?? 0}%',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (_canCustomerActions)
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: IconButton.filledTonal(
                                              onPressed:
                                                  widget.merchant.isOpen &&
                                                      product.canBeOrdered
                                                  ? () => _addToCart(
                                                      product,
                                                      quantity: 1,
                                                      initialVariantSelections:
                                                          _cardSelections[product
                                                                  .id]
                                                              ?.selectedVariantSelections ??
                                                          const [],
                                                      initialSelectedVariantId:
                                                          _cardSelections[product
                                                                  .id]
                                                              ?.variantId,
                                                    )
                                                  : null,
                                              icon: const Icon(
                                                Icons.add_shopping_cart_rounded,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ...productSections,
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
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: tokens.cardPrimary.withValues(alpha: 0.85),
        border: Border.all(color: tokens.borderSubtle.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Store logo + name row
          Row(
            textDirection: TextDirection.rtl,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      merchant.name,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (merchant.description?.trim().isNotEmpty == true)
                      Text(
                        merchant.description!,
                        textDirection: TextDirection.rtl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tokens.textMuted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Logo box
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: tokens.surfaceSecondary,
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: merchant.imageUrl == null || merchant.imageUrl!.isEmpty
                    ? Icon(
                        merchant.type == 'restaurant'
                            ? Icons.restaurant_rounded
                            : Icons.storefront_rounded,
                        color: visual.accentCyan,
                        size: 32,
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedAppImage(
                          imageUrl: merchant.imageUrl!,
                          cacheIdentity: 'merchant_${merchant.id}',
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Icon(
                            Icons.storefront_rounded,
                            color: visual.accentCyan,
                            size: 32,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Stats row
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(Icons.star_rounded, color: visual.accentGold, size: 16),
              const SizedBox(width: 3),
              Text(
                '4.7 (1.2k)',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.access_time_rounded,
                color: tokens.textMuted,
                size: 14,
              ),
              const SizedBox(width: 3),
              Text(
                '15-25 دقيقة',
                style: TextStyle(color: tokens.textMuted, fontSize: 12),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.delivery_dining_rounded,
                color: tokens.textMuted,
                size: 14,
              ),
              const SizedBox(width: 3),
              Text(
                merchant.hasFreeDeliveryOffer ? 'مجاني' : '6 رس',
                style: TextStyle(color: tokens.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Badges row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              _Badge(
                text: merchant.isOpen ? 'مفتوح الآن' : 'مغلق الآن',
                color: merchant.isOpen
                    ? tokens.success.withValues(alpha: 0.18)
                    : tokens.danger.withValues(alpha: 0.18),
                textColor: merchant.isOpen ? tokens.success : tokens.danger,
              ),
              if (merchant.hasDiscountOffer)
                _Badge(
                  text: 'طبق اليوم',
                  color: tokens.success.withValues(alpha: 0.18),
                  textColor: tokens.success,
                ),
              if (merchant.hasFreeDeliveryOffer)
                _Badge(
                  text: 'توصيل مجاني فوق 75',
                  color: visual.accentCyan.withValues(alpha: 0.12),
                  textColor: visual.accentCyan,
                ),
              if (merchant.workingHours?.trim().isNotEmpty == true)
                _Badge(
                  text: merchant.workingHours!,
                  color: tokens.borderSubtle.withValues(alpha: 0.5),
                  textColor: tokens.textMuted,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PharmacyWorkflowCard extends StatelessWidget {
  final Future<void> Function() onOpenConversation;

  const _PharmacyWorkflowCard({required this.onOpenConversation});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Color(0xFF0F436D), Color(0xFF113B89)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.medical_services_outlined, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.pharmacyWorkflowBannerTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pharmacyWorkflowBannerSubtitle,
            textDirection: TextDirection.rtl,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.92)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpenConversation,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: Text(l10n.pharmacyChatCta),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategorySectionHeader extends StatelessWidget {
  final String title;
  final String countLabel;

  const _CategorySectionHeader({required this.title, required this.countLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Text(
            countLabel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            title,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
  final Map<int, int> productCounts;
  final void Function(int? categoryId) onSelect;

  const _CategoryFilterRow({
    required this.categories,
    required this.selectedCategoryId,
    required this.totalProductsCount,
    required this.productCounts,
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
                label: '${category.name} (${productCounts[category.id] ?? 0})',
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

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final Color? textColor;

  const _Badge({required this.text, required this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts();

  @override
  Widget build(BuildContext context) {
    return const MaslakiEmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'لا توجد منتجات متاحة',
      body: 'غيّر الفئة أو أزل بعض الفلاتر لرؤية خيارات أخرى من المتجر.',
    );
  }
}

String _formatVariantSelectionLabel(Map<String, dynamic> entry) {
  final group = (entry['groupLabel'] ?? entry['groupCode'] ?? '')
      .toString()
      .trim();
  final option =
      (entry['optionLabel'] ?? entry['optionCode'] ?? entry['value'] ?? '')
          .toString()
          .trim();
  if (group.isEmpty && option.isEmpty) return '';
  if (group.isEmpty) return option;
  if (option.isEmpty) return group;
  return '$group: $option';
}
