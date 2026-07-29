// ignore_for_file: prefer_const_constructors, duplicate_ignore

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/loading_skeletons.dart';
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
import '../../products/utils/product_variant_label_set.dart';
import '../data/merchants_api.dart';
import '../utils/catalog_taxonomy.dart';
import 'merchant_product_details_screen.dart';
import '../models/merchant_model.dart';
import '../state/merchants_controller.dart';
import '../state/customer_merchant_prefs_controller.dart';

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

/// Product display density: one large card per row, or a two-column grid.
enum _ProductViewMode { list, grid }

List<ProductModel> filterMerchantDiscountHighlights(
  List<ProductModel> products,
) {
  return products
      .where((product) => product.hasDiscount)
      .where((product) => product.canBeOrdered)
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
  _ProductViewMode productViewMode = _ProductViewMode.list;
  static const String _viewModePrefsKey = 'merchant_products_view_mode';
  // Legacy single-store cart replacement, kept disabled; multi-store carts
  // (up to 3 merchants) are the current behavior.
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
    _restoreViewMode();
  }

  Future<void> _restoreViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_viewModePrefsKey);
      if (!mounted || stored == null) return;
      final restored = stored == 'grid'
          ? _ProductViewMode.grid
          : _ProductViewMode.list;
      if (restored != productViewMode) {
        setState(() => productViewMode = restored);
      }
    } catch (_) {
      // Non-fatal: fall back to the default list view.
    }
  }

  void _setViewMode(_ProductViewMode mode) {
    if (mode == productViewMode) return;
    setState(() => productViewMode = mode);
    // Persist without blocking the instant UI switch.
    SharedPreferences.getInstance()
        .then(
          (prefs) => prefs.setString(
            _viewModePrefsKey,
            mode == _ProductViewMode.grid ? 'grid' : 'list',
          ),
        )
        .catchError((_) => false);
  }

  @override
  void dispose() {
    productSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => state = const AsyncValue.loading());
    try {
      final api = ref.read(merchantsApiProvider);
      final productsFuture = _loadAllProducts(api);
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

  Future<List<dynamic>> _loadAllProducts(MerchantsApi api) async {
    const pageSize = 200;
    const maxProducts = 5000;
    final products = <dynamic>[];
    var offset = 0;
    while (products.length < maxProducts) {
      final page = await api.listProducts(
        widget.merchant.id,
        limit: pageSize,
        offset: offset,
      );
      products.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return products;
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

  Widget _buildSingleProductCard(
    ProductModel product,
    List<ProductModel> allProducts, {
    required ProductSummaryCardAppearance appearance,
    required Locale locale,
    required bool grid,
  }) {
    final canOrder = widget.merchant.isOpen && product.canBeOrdered;
    final usesPharmacyConversation = _requiresPharmacyConversation(product);
    final strictVariantSelection = _requiresStrictVariantSelection(product);
    final variantLabels = _variantLabels();
    final detailLines = _productDetailLines(product);
    final cardData = ProductSummaryCardData.fromProduct(
      product,
      locale: locale,
      strictVariantSelection: strictVariantSelection,
      colorGroupLabelAr: variantLabels.colorLabelAr,
      colorGroupLabelEn: variantLabels.colorLabelEn,
      sizeGroupLabelAr: variantLabels.sizeLabelAr,
      sizeGroupLabelEn: variantLabels.sizeLabelEn,
      detailedSpecificationLines: detailLines,
    );
    final selection =
        _cardSelections[product.id] ?? cardData.resolveSelection();
    _cardSelections[product.id] ??= selection;

    return ProductSummaryCard.fromProduct(
      product,
      key: ValueKey(product.id),
      appearance: appearance,
      locale: locale,
      onTap: () =>
          _openProductDetails(product: product, allProducts: allProducts),
      compact: true,
      showDetailedSpecifications: !grid,
      maxAttributeBadges: grid ? 1 : 2,
      maxVariantBadges: grid ? 2 : 3,
      maxStatusBadges: grid ? 2 : 3,
      heroAspectRatio: grid ? 1.2 : 1.38,
      selectedColorCode: selection.colorCode,
      selectedSizeCode: selection.sizeCode,
      strictVariantSelection: strictVariantSelection,
      colorGroupLabelAr: variantLabels.colorLabelAr,
      colorGroupLabelEn: variantLabels.colorLabelEn,
      sizeGroupLabelAr: variantLabels.sizeLabelAr,
      sizeGroupLabelEn: variantLabels.sizeLabelEn,
      onSelectionChanged: (next) {
        setState(() => _cardSelections[product.id] = next);
      },
      trailing: _buildProductSummaryTrailing(
        cardData: cardData,
        product: product,
        canOrder: canOrder,
        usesPharmacyConversation: usesPharmacyConversation,
        showActions: _canCustomerActions,
        selectedVariantId: selection.variantId,
        selectedVariantSelections: selection.selectedVariantSelections,
        strictVariantSelection: strictVariantSelection,
      ),
    );
  }

  List<String> _productDetailLines(ProductModel product) {
    final raw = product.description?.trim();
    if (raw == null || raw.isEmpty) return const [];
    final lines = raw
        .split('\n')
        .expand((line) => line.split(RegExp(r'[,،]')))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return lines;
  }

  List<Widget> _buildProductCards(
    List<ProductModel> products,
    List<ProductModel> allProducts,
  ) {
    final appearance = ProductSummaryCardAppearance.fromContext(context);
    final locale = Localizations.localeOf(context);

    if (productViewMode == _ProductViewMode.grid) {
      // GRID_2_COLUMNS: chunk into rows of two equal-width cards.
      final rows = <Widget>[];
      for (var i = 0; i < products.length; i += 2) {
        final left = products[i];
        final right = i + 1 < products.length ? products[i + 1] : null;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildSingleProductCard(
                      left,
                      allProducts,
                      appearance: appearance,
                      locale: locale,
                      grid: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: right == null
                        ? const SizedBox.shrink()
                        : _buildSingleProductCard(
                            right,
                            allProducts,
                            appearance: appearance,
                            locale: locale,
                            grid: true,
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return rows;
    }

    // LARGE_CARD: one card per row.
    return products
        .map(
          (product) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildSingleProductCard(
              product,
              allProducts,
              appearance: appearance,
              locale: locale,
              grid: false,
            ),
          ),
        )
        .toList();
  }

  Widget _buildProductSummaryTrailing({
    required ProductSummaryCardData cardData,
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
    final requiresSelection =
        strictVariantSelection &&
        product.hasVariants &&
        selectedVariantId == null;
    final selectionPrompt = context.lt(
      ar: 'اختر ${cardData.colorGroupLabelAr} و${cardData.sizeGroupLabelAr} أولاً',
      en: 'Choose ${cardData.colorGroupLabelEn} and ${cardData.sizeGroupLabelEn} first',
    );
    final label = !canOrder
        ? (widget.merchant.isOpen ? 'غير متوفر حالياً' : 'المتجر مغلق الآن')
        : requiresSelection
        ? selectionPrompt
        : usesPharmacyConversation
        ? context.lt(ar: 'إرسال للمراجعة', en: 'Send for review')
        : context.lt(ar: 'إضافة إلى السلة', en: 'Add to cart');
    final icon = !canOrder
        ? Icons.block_outlined
        : requiresSelection
        ? Icons.tune_rounded
        : usesPharmacyConversation
        ? Icons.chat_bubble_outline_rounded
        : Icons.add_shopping_cart_rounded;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: canOrder
              ? () => _addToCart(
                  product,
                  quantity: 1,
                  initialVariantSelections: selectedVariantSelections,
                  initialSelectedVariantId: selectedVariantId,
                  strictVariantSelection: strictVariantSelection,
                )
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: canOrder
                ? visual.accentCyan.withValues(alpha: 0.15)
                : tokens.borderSubtle.withValues(alpha: 0.3),
            foregroundColor: canOrder ? visual.accentCyan : tokens.textMuted,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: canOrder
                    ? visual.accentCyan.withValues(alpha: 0.28)
                    : tokens.borderSubtle,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.rtl,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
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

  ProductVariantLabelSet _variantLabels() {
    return productVariantLabelsForCatalogType(widget.merchant.type);
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

  Future<void> _toggleFavorite() async {
    final userId = ref.read(authControllerProvider).user?.id;
    if (userId == null || userId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سجّل الدخول لإضافة المتجر إلى المفضلة')),
      );
      return;
    }
    try {
      await ref
          .read(customerMerchantPrefsProvider.notifier)
          .toggleFavorite(userId: userId, merchantId: widget.merchant.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر تحديث المفضلة حالياً')),
      );
    }
  }

  Future<void> _shareMerchant() async {
    final m = widget.merchant;
    final scope = merchantScopeTag(
      merchantType: m.type,
      activityType: m.activityType,
    );
    final lines = <String>[
      m.name,
      if ((m.description ?? '').trim().isNotEmpty)
        m.description!.trim()
      else
        scope,
      'عبر تطبيق مسلكي',
    ];
    try {
      await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذّرت المشاركة حالياً')));
    }
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
    final variantLabels = _variantLabels();
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
          colorGroupLabelAr: variantLabels.colorLabelAr,
          colorGroupLabelEn: variantLabels.colorLabelEn,
          sizeGroupLabelAr: variantLabels.sizeLabelAr,
          sizeGroupLabelEn: variantLabels.sizeLabelEn,
          unavailablePromptAr: variantLabels.unavailablePromptAr,
          unavailablePromptEn: variantLabels.unavailablePromptEn,
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
        // Scope tag (not the description) so the hero header below is the only
        // place the name+description pair is shown in full.
        subtitle: merchantScopeTag(
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
          if (_canCustomerActions)
            Consumer(
              builder: (context, ref, _) {
                final isFavorite = ref
                    .watch(customerMerchantPrefsProvider)
                    .favoriteMerchantIds
                    .contains(widget.merchant.id);
                return IconButton(
                  tooltip: 'المفضلة',
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFavorite ? Colors.redAccent : tokens.textPrimary,
                  ),
                );
              },
            ),
          IconButton(
            tooltip: 'مشاركة',
            onPressed: _shareMerchant,
            icon: Icon(Icons.ios_share_rounded, color: tokens.textPrimary),
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
                const SizedBox(height: 8),
                _ProductViewModeToggle(
                  mode: productViewMode,
                  onChanged: _setViewMode,
                ),
                const SizedBox(height: 12),
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
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
            children: const [
              SkeletonBox(
                height: 150,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              SizedBox(height: 14),
              ProductRowSkeleton(),
              ProductRowSkeleton(),
              ProductRowSkeleton(),
              ProductRowSkeleton(),
            ],
          ),
          error: (error, _) => MaslakiErrorRetry(
            message:
                'تعذّر تحميل منتجات المتجر. تحقق من اتصالك ثم أعد المحاولة.',
            onRetry: _load,
          ),
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

  String? get _coverSource {
    final cover = merchant.coverImageUrl?.trim();
    if (cover != null && cover.isNotEmpty) return cover;
    final image = merchant.imageUrl?.trim();
    return (image != null && image.isNotEmpty) ? image : null;
  }

  String? get _logoSource {
    final logo = merchant.logoUrl?.trim();
    if (logo != null && logo.isNotEmpty) return logo;
    final image = merchant.imageUrl?.trim();
    final cover = merchant.coverImageUrl?.trim();
    if (image != null && image.isNotEmpty && image != cover) return image;
    return null;
  }

  String? _etaLabel(BuildContext context) {
    if (!merchant.hasDeliveryEta) return null;
    final min = merchant.deliveryEtaMinMinutes;
    final max = merchant.deliveryEtaMaxMinutes;
    if (min != null && max != null) return '$min–$max دقيقة';
    if (max != null) return 'حتى $max دقيقة';
    return 'من $min دقيقة';
  }

  String? _feeLabel(BuildContext context) {
    if (merchant.hasFreeDeliveryOffer ||
        (merchant.deliveryFee != null && merchant.deliveryFee == 0)) {
      return 'توصيل مجاني';
    }
    final fee = merchant.deliveryFee;
    if (fee != null && fee > 0) return 'توصيل ${formatIqd(fee)}';
    return null;
  }

  void _showInfo(BuildContext context) {
    final tokens = context.maslakiTokens;
    final rows = <(IconData, String, String)>[
      if ((merchant.phone ?? '').trim().isNotEmpty)
        (Icons.phone_rounded, 'الهاتف', merchant.phone!.trim()),
      if ((merchant.workingHours ?? '').trim().isNotEmpty)
        (Icons.schedule_rounded, 'أوقات العمل', merchant.workingHours!.trim()),
      if ((merchant.serviceAreaNote ?? '').trim().isNotEmpty)
        (Icons.map_rounded, 'منطقة الخدمة', merchant.serviceAreaNote!.trim()),
      if (merchant.minimumOrder != null)
        (
          Icons.shopping_bag_rounded,
          'الحد الأدنى للطلب',
          formatIqd(merchant.minimumOrder!),
        ),
      if (_feeLabel(context) != null)
        (Icons.local_shipping_rounded, 'التوصيل', _feeLabel(context)!),
      if (_etaLabel(context) != null)
        (Icons.timer_rounded, 'وقت التوصيل', _etaLabel(context)!),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surfacePrimary,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                merchant.name,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Text(
                  'لا توجد معلومات إضافية متاحة لهذا المتجر.',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(color: tokens.textMuted),
                )
              else
                ...rows.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Icon(r.$1, size: 18, color: tokens.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          '${r.$2}: ',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            r.$3,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(color: tokens.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    final cover = _coverSource;
    final logo = _logoSource;
    final storeIcon = merchant.type == 'restaurant'
        ? Icons.restaurant_rounded
        : Icons.storefront_rounded;
    final etaLabel = _etaLabel(context);
    final feeLabel = _feeLabel(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: tokens.cardPrimary.withValues(alpha: 0.85),
        border: Border.all(color: tokens.borderSubtle.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Large cover ----
          AspectRatio(
            aspectRatio: 3.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null)
                  CachedAppImage(
                    imageUrl: cover,
                    cacheIdentity: 'merchant_cover_${merchant.id}',
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        _HeaderCoverPlaceholder(icon: storeIcon),
                  )
                else
                  _HeaderCoverPlaceholder(icon: storeIcon),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black45],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (merchant.hasActiveOffer)
                        _HeaderCoverBadge(
                          icon: Icons.local_offer_rounded,
                          label: 'عرض',
                          color: const Color(0xFFE0752D),
                        ),
                      if (merchant.isVerified) ...[
                        if (merchant.hasActiveOffer) const SizedBox(width: 6),
                        _HeaderCoverBadge(
                          icon: Icons.verified_rounded,
                          label: 'موثّق',
                          color: const Color(0xFF2E7CD6),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo + name/desc + info button
                Row(
                  textDirection: TextDirection.rtl,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tokens.surfaceSecondary,
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: logo != null
                          ? CachedAppImage(
                              imageUrl: logo,
                              cacheIdentity: 'merchant_logo_${merchant.id}',
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Icon(
                                storeIcon,
                                color: visual.accentCyan,
                                size: 28,
                              ),
                            )
                          : Icon(storeIcon, color: visual.accentCyan, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            merchant.name,
                            textDirection: TextDirection.rtl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            merchant.description?.trim().isNotEmpty == true
                                ? merchant.description!.trim()
                                : merchantScopeTag(
                                    merchantType: merchant.type,
                                    activityType: merchant.activityType,
                                  ),
                            textDirection: TextDirection.rtl,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'معلومات المتجر',
                      onPressed: () => _showInfo(context),
                      icon: Icon(
                        Icons.info_outline_rounded,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Real stats: rating / new store, ETA, fee, min order.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  textDirection: TextDirection.rtl,
                  children: [
                    _Badge(
                      text: merchant.isOpen ? 'مفتوح الآن' : 'مغلق الآن',
                      color: merchant.isOpen
                          ? tokens.success.withValues(alpha: 0.18)
                          : tokens.danger.withValues(alpha: 0.18),
                      textColor: merchant.isOpen
                          ? tokens.success
                          : tokens.danger,
                    ),
                    if (merchant.ratingCount > 0 &&
                        merchant.avgMerchantRating != null)
                      _HeaderStat(
                        icon: Icons.star_rounded,
                        iconColor: visual.accentGold,
                        text:
                            '${merchant.avgMerchantRating!.toStringAsFixed(1)} (${merchant.ratingCount} تقييم)',
                      )
                    else
                      _HeaderStat(
                        icon: Icons.fiber_new_rounded,
                        iconColor: visual.accentCyan,
                        text: 'متجر جديد',
                      ),
                    if (etaLabel != null)
                      _HeaderStat(
                        icon: Icons.schedule_rounded,
                        iconColor: tokens.textSecondary,
                        text: etaLabel,
                      ),
                    if (feeLabel != null)
                      _HeaderStat(
                        icon: Icons.local_shipping_rounded,
                        iconColor: tokens.success,
                        text: feeLabel,
                      ),
                    if (merchant.minimumOrder != null)
                      _HeaderStat(
                        icon: Icons.shopping_bag_rounded,
                        iconColor: tokens.textSecondary,
                        text: 'أدنى طلب ${formatIqd(merchant.minimumOrder!)}',
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

class _HeaderCoverPlaceholder extends StatelessWidget {
  final IconData icon;
  const _HeaderCoverPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1C355F), Color(0xFF122A4C)],
        ),
      ),
      child: Center(
        child: Icon(icon, size: 40, color: Colors.white.withValues(alpha: 0.5)),
      ),
    );
  }
}

class _HeaderCoverBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _HeaderCoverBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.92),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  const _HeaderStat({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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

/// Compact segmented control to switch products between a one-per-row list and
/// a two-column grid. The choice is applied instantly and persisted.
class _ProductViewModeToggle extends StatelessWidget {
  final _ProductViewMode mode;
  final ValueChanged<_ProductViewMode> onChanged;

  const _ProductViewModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final selectedColor = context.visualTheme.accentCyan;
    Widget button(_ProductViewMode target, IconData icon, String tooltip) {
      final selected = mode == target;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(target),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Icon(
              icon,
              size: 20,
              color: selected ? selectedColor : tokens.textMuted,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(
              _ProductViewMode.list,
              Icons.view_agenda_outlined,
              context.lt(ar: 'عرض قائمة', en: 'List view'),
            ),
            Container(width: 1, height: 22, color: tokens.borderSubtle),
            button(
              _ProductViewMode.grid,
              Icons.grid_view_rounded,
              context.lt(ar: 'عرض شبكة', en: 'Grid view'),
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
