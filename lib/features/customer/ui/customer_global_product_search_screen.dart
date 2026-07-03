import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../../orders/state/cart_controller.dart';
import '../../orders/state/orders_controller.dart';
import '../../orders/ui/cart_screen.dart';
import '../../products/models/product_model.dart';
import '../../products/ui/product_summary_card.dart';
import '../../products/ui/product_variant_picker_sheet.dart';

class CustomerGlobalProductSearchScreen extends ConsumerStatefulWidget {
  const CustomerGlobalProductSearchScreen({super.key});

  @override
  ConsumerState<CustomerGlobalProductSearchScreen> createState() =>
      _CustomerGlobalProductSearchScreenState();
}

class _CustomerGlobalProductSearchScreenState
    extends ConsumerState<CustomerGlobalProductSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<int, ProductSummaryCardSelection> _cardSelections = {};
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  int _offset = 0;
  int? _nextOffset;
  bool _onlyAvailable = true;
  bool _onlyDiscounted = false;
  _SearchSort _sort = _SearchSort.bestOffers;
  String _merchantType = '';
  double? _minRating;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search({bool reset = false}) async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _offset = 0;
      }
    });
    try {
      final api = ref.read(ordersApiProvider);
      final data = await api.searchProductsGlobal(
        query: query,
        sort: _sort.apiValue,
        merchantType: _merchantType.isEmpty ? null : _merchantType,
        onlyAvailable: _onlyAvailable,
        onlyDiscounted: _onlyDiscounted,
        minRating: _minRating,
        limit: 30,
        offset: reset ? 0 : _offset,
      );
      final raw = List<dynamic>.from(data['items'] as List? ?? const []);
      final mapped = raw
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
      setState(() {
        if (reset) {
          _items = mapped;
        } else {
          _items = [..._items, ...mapped];
        }
        _nextOffset = int.tryParse(
          '${data['pagination']?['nextOffset'] ?? ''}',
        );
        _offset = _nextOffset ?? _offset;
      });
    } catch (_) {
      setState(() {
        _error = 'تعذر تنفيذ البحث الآن، حاول مرة أخرى.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      } else {
        _loading = false;
      }
    }
  }

  ProductModel _toProduct(Map<String, dynamic> item) {
    final merchant = Map<String, dynamic>.from(
      item['merchant'] as Map? ?? const {},
    );
    final payload = <String, dynamic>{
      ...item,
      'id': item['productId'] ?? item['id'],
      'merchant_id':
          merchant['id'] ?? item['merchantId'] ?? item['merchant_id'],
      'merchantId': merchant['id'] ?? item['merchantId'] ?? item['merchant_id'],
      'category_id': item['categoryId'] ?? item['category_id'],
      'categoryId': item['categoryId'] ?? item['category_id'],
      'image_url': item['imageUrl'] ?? item['image_url'],
      'discounted_price':
          item['discountedPrice'] ??
          item['discounted_price'] ??
          item['finalPrice'],
      'discountedPrice':
          item['discountedPrice'] ??
          item['discounted_price'] ??
          item['finalPrice'],
      'free_delivery': item['freeDelivery'] ?? item['free_delivery'] ?? false,
      'freeDelivery': item['freeDelivery'] ?? item['free_delivery'] ?? false,
      'requires_prescription':
          item['requiresPrescription'] ??
          item['requires_prescription'] ??
          false,
      'requiresPrescription':
          item['requiresPrescription'] ??
          item['requires_prescription'] ??
          false,
      'requires_review':
          item['requiresReview'] ?? item['requires_review'] ?? false,
      'requiresReview':
          item['requiresReview'] ?? item['requires_review'] ?? false,
      'attributes': item['attributes'] ?? const [],
      'summaryAttributes':
          item['summaryAttributes'] ??
          item['summary_attributes'] ??
          item['attributes'] ??
          const [],
      'variantGroups':
          item['variantGroups'] ?? item['variant_groups'] ?? const [],
      'media': item['media'] ?? const [],
      'primaryMedia': item['primaryMedia'] ?? item['primary_media'],
      'hasVariants': item['hasVariants'] ?? item['has_variants'],
      'metadata_json':
          item['metadata_json'] ?? item['metadataJson'] ?? const {},
    };
    return ProductModel.fromJson(payload);
  }

  MerchantModel _toMerchant(Map<String, dynamic> item) {
    final merchant = Map<String, dynamic>.from(
      item['merchant'] as Map? ?? const {},
    );
    return MerchantModel(
      id: (merchant['id'] as num?)?.toInt() ?? 0,
      name: merchant['name']?.toString() ?? 'متجر',
      type: merchant['type']?.toString() ?? 'market',
      imageUrl: merchant['imageUrl']?.toString(),
      isOpen: true,
      hasDiscountOffer:
          (item['discountPercent'] as num?) != null &&
          ((item['discountPercent'] as num?)?.toDouble() ?? 0) > 0,
      hasFreeDeliveryOffer: item['freeDelivery'] == true,
    );
  }

  Future<void> _addToCart(
    Map<String, dynamic> item, {
    bool openCartAfterAdd = false,
    bool bypassVariantPickerWhenSelectionComplete = false,
  }) async {
    final product = _toProduct(item);
    final merchant = Map<String, dynamic>.from(
      item['merchant'] as Map? ?? const {},
    );
    final selected =
        _cardSelections[product.id] ??
        ProductSummaryCardData.fromProduct(
          product,
          locale: Localizations.localeOf(context),
        ).resolveSelection();
    var variantSelections = selected.selectedVariantSelections;
    final hasCompleteVariantSelection = variantSelections.isNotEmpty;
    if (product.hasVariants &&
        (!bypassVariantPickerWhenSelectionComplete ||
            !hasCompleteVariantSelection)) {
      final picked = await showProductVariantPickerSheet(
        context,
        product: product,
        initialSelections: variantSelections,
      );
      if (!mounted || picked == null) return;
      variantSelections = picked;
    }
    final selectedVariant = product.variantForSelectionEntries(
      variantSelections,
    );
    final status = ref
        .read(cartControllerProvider.notifier)
        .addItem(
          product: product,
          merchantId: (merchant['id'] as num?)?.toInt() ?? 0,
          merchantName: merchant['name']?.toString() ?? 'متجر',
          selectedVariantId: selectedVariant?.id ?? selected.variantId,
          selectedVariantSelections: variantSelections,
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
    if (status == CartAddStatus.storeLimitExceeded) {
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('لا يمكن إضافة متجر رابع. الحد الأقصى 3 متاجر.'),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('تمت إضافة ${product.name} إلى السلة'),
      ),
    );
    if (openCartAfterAdd && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CartScreen()));
      });
    }
  }

  Future<void> _quickOrder(Map<String, dynamic> item) async {
    await _addToCart(
      item,
      openCartAfterAdd: true,
      bypassVariantPickerWhenSelectionComplete: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بحث المنتجات')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _searchCtrl,
            textDirection: TextDirection.rtl,
            onSubmitted: (_) => _search(reset: true),
            decoration: InputDecoration(
              hintText: 'ابحث عن منتج أو طبق',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () => _search(reset: true),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownButton<_SearchSort>(
                value: _sort,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _sort = value);
                  _search(reset: true);
                },
                items: _SearchSort.values
                    .map(
                      (sort) => DropdownMenuItem<_SearchSort>(
                        value: sort,
                        child: Text(sort.label),
                      ),
                    )
                    .toList(),
              ),
              FilterChip(
                label: const Text('المتوفر فقط'),
                selected: _onlyAvailable,
                onSelected: (value) {
                  setState(() => _onlyAvailable = value);
                  _search(reset: true);
                },
              ),
              FilterChip(
                label: const Text('عروض فقط'),
                selected: _onlyDiscounted,
                onSelected: (value) {
                  setState(() => _onlyDiscounted = value);
                  _search(reset: true);
                },
              ),
              DropdownButton<String>(
                value: _merchantType,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _merchantType = value);
                  _search(reset: true);
                },
                items: const [
                  DropdownMenuItem(value: '', child: Text('كل المتاجر')),
                  DropdownMenuItem(value: 'restaurant', child: Text('مطاعم')),
                  DropdownMenuItem(value: 'market', child: Text('أسواق')),
                  DropdownMenuItem(value: 'pharmacy', child: Text('صيدليات')),
                ],
              ),
              DropdownButton<double?>(
                value: _minRating,
                onChanged: (value) {
                  setState(() => _minRating = value);
                  _search(reset: true);
                },
                items: const [
                  DropdownMenuItem<double?>(
                    value: null,
                    child: Text('كل التقييمات'),
                  ),
                  DropdownMenuItem<double?>(value: 3, child: Text('3★ فأعلى')),
                  DropdownMenuItem<double?>(value: 4, child: Text('4★ فأعلى')),
                  DropdownMenuItem<double?>(
                    value: 4.5,
                    child: Text('4.5★ فأعلى'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          if (_loading && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ..._items.map((item) {
            final merchant = Map<String, dynamic>.from(
              item['merchant'] as Map? ?? const {},
            );
            final product = _toProduct(item);
            final cardData = ProductSummaryCardData.fromProduct(
              product,
              locale: Localizations.localeOf(context),
            );
            final selection =
                _cardSelections[product.id] ?? cardData.resolveSelection();
            _cardSelections[product.id] ??= selection;
            final etaMinutes = (item['stats']?['etaMinutes'] as num?)
                ?.toDouble();
            final etaLabel = etaMinutes == null
                ? 'غير محدد'
                : '${etaMinutes.toStringAsFixed(0)} دقيقة';
            final merchantName = merchant['name']?.toString() ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ProductSummaryCard.fromProduct(
                product,
                key: ValueKey(product.id),
                appearance: ProductSummaryCardAppearance.fromContext(context),
                locale: Localizations.localeOf(context),
                compact: true,
                heroAspectRatio: 1.36,
                maxAttributeBadges: 3,
                maxVariantBadges: 2,
                maxStatusBadges: 2,
                selectedColorCode: selection.colorCode,
                selectedSizeCode: selection.sizeCode,
                onSelectionChanged: (next) {
                  setState(() => _cardSelections[product.id] = next);
                },
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        MerchantProductsScreen(merchant: _toMerchant(item)),
                  ),
                ),
                trailing: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (merchantName.isNotEmpty)
                      Text(
                        merchantName,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (etaLabel.isNotEmpty)
                      Text(
                        '⏱ $etaLabel',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.68),
                        ),
                      ),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MerchantProductsScreen(
                            merchant: _toMerchant(item),
                          ),
                        ),
                      ),
                      child: const Text('فتح المتجر'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _quickOrder(item),
                      icon: const Icon(Icons.flash_on_rounded),
                      label: const Text('طلب سريع'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _addToCart(item),
                      icon: Icon(
                        product.hasVariants
                            ? Icons.tune_rounded
                            : Icons.add_shopping_cart_rounded,
                      ),
                      label: const Text('إضافة'),
                    ),
                  ],
                ),
                showDescription: false,
                showVariantControls: true,
                interactiveGallery: false,
              ),
            );
          }),
          if (_nextOffset != null) ...[
            const SizedBox(height: 6),
            FilledButton(
              onPressed: _loading
                  ? null
                  : () {
                      _offset = _nextOffset!;
                      _search(reset: false);
                    },
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('تحميل المزيد'),
            ),
          ],
        ],
      ),
    );
  }
}

enum _SearchSort {
  bestOffers('العروض أولًا', 'best_offers'),
  priceAsc('الأرخص سعرًا', 'price_asc'),
  mostOrdered('الأكثر طلبًا', 'most_ordered'),
  ratingDesc('الأعلى تقييمًا', 'rating_desc'),
  nearest('الأقرب', 'nearest'),
  fastest('الأسرع توصيلًا', 'fastest_delivery');

  final String label;
  final String apiValue;
  const _SearchSort(this.label, this.apiValue);
}
