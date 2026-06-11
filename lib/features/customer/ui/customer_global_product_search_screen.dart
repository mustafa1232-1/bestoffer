import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/currency.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../../orders/state/cart_controller.dart';
import '../../orders/state/orders_controller.dart';
import '../../products/models/product_model.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class CustomerGlobalProductSearchScreen extends ConsumerStatefulWidget {
  const CustomerGlobalProductSearchScreen({super.key});

  @override
  ConsumerState<CustomerGlobalProductSearchScreen> createState() =>
      _CustomerGlobalProductSearchScreenState();
}

class _CustomerGlobalProductSearchScreenState
    extends ConsumerState<CustomerGlobalProductSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
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
    return ProductModel(
      id: (item['productId'] as num?)?.toInt() ?? 0,
      merchantId: (item['merchant']?['id'] as num?)?.toInt() ?? 0,
      name: '${item['name'] ?? ''}',
      description: item['description']?.toString(),
      price: (item['price'] as num?)?.toDouble() ?? 0,
      discountedPrice: (item['discountedPrice'] as num?)?.toDouble(),
      imageUrl: item['imageUrl']?.toString(),
      freeDelivery: item['freeDelivery'] == true,
      offerLabel: item['offerLabel']?.toString(),
      isAvailable: item['isAvailable'] == true,
      sortOrder: 0,
    );
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

  Future<void> _addToCart(Map<String, dynamic> item) async {
    final product = _toProduct(item);
    final merchant = Map<String, dynamic>.from(
      item['merchant'] as Map? ?? const {},
    );
    final status = ref
        .read(cartControllerProvider.notifier)
        .addItem(
          product: product,
          merchantId: (merchant['id'] as num?)?.toInt() ?? 0,
          merchantName: merchant['name']?.toString() ?? 'متجر',
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
            final hasDiscount =
                ((item['discountPercent'] as num?)?.toDouble() ?? 0) > 0;
            final finalPrice = (item['finalPrice'] as num?)?.toDouble() ?? 0;
            final basePrice = (item['price'] as num?)?.toDouble() ?? 0;
            final rating = (merchant['rating'] as num?)?.toDouble() ?? 0;
            final etaMinutes = (item['stats']?['etaMinutes'] as num?)
                ?.toDouble();
            final etaLabel = etaMinutes == null
                ? 'غير محدد'
                : '${etaMinutes.toStringAsFixed(0)} دقيقة';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 78,
                        height: 78,
                        child:
                            (item['imageUrl']?.toString().isNotEmpty ?? false)
                            ? CachedAppImage(
                                imageUrl: item['imageUrl'].toString(),
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: Colors.white.withValues(alpha: 0.08),
                                alignment: Alignment.center,
                                child: const Icon(Icons.fastfood_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item['name']?.toString() ?? '',
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            merchant['name']?.toString() ?? '',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '⭐ ${rating.toStringAsFixed(1)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '⏱ $etaLabel',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                formatIqd(finalPrice),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (hasDiscount) ...[
                                const SizedBox(width: 8),
                                Text(
                                  formatIqd(basePrice),
                                  style: TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              if (hasDiscount)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(
                                      alpha: 0.18,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '-${(item['discountPercent'] as num?)?.toStringAsFixed(0) ?? '0'}%',
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
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
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () => _addToCart(item),
                                icon: const Icon(
                                  Icons.add_shopping_cart_rounded,
                                ),
                                label: const Text('إضافة'),
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
