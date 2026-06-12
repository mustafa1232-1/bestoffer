import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../../auth/ui/merchants_list_screen.dart';
import '../state/orders_controller.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class FavoriteProductsScreen extends ConsumerStatefulWidget {
  const FavoriteProductsScreen({super.key});

  @override
  ConsumerState<FavoriteProductsScreen> createState() =>
      _FavoriteProductsScreenState();
}

class _FavoriteProductsScreenState
    extends ConsumerState<FavoriteProductsScreen> {
  static const int _pageSize = 40;

  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  String? _error;
  List<_FavoriteProductItem> _items = const [];
  int? _nextOffset;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load(reset: true));
  }

  Future<void> _load({required bool reset, bool silent = false}) async {
    if (_loadingMore) return;
    if (!reset && _nextOffset == null) return;

    if (reset) {
      if (!silent) {
        setState(() {
          _loading = true;
          _error = null;
        });
      } else {
        setState(() => _refreshing = true);
      }
    } else {
      setState(() => _loadingMore = true);
    }

    final offset = reset ? 0 : (_nextOffset ?? 0);
    try {
      final page = await ref
          .read(ordersApiProvider)
          .listFavoriteProducts(limit: _pageSize, offset: offset);
      final parsed = page.items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map(_FavoriteProductItem.fromJson)
          .toList(growable: false);
      if (!mounted) return;

      final merged = reset ? <_FavoriteProductItem>[] : [..._items];
      if (reset) {
        merged.addAll(parsed);
      } else {
        final seen = merged.map((e) => e.id).toSet();
        for (final item in parsed) {
          if (seen.add(item.id)) merged.add(item);
        }
      }

      setState(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        _error = null;
        _items = merged;
        _nextOffset = page.nextOffset;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        _error = reset
            ? context.lt(
                ar: 'تعذر تحميل المفضلة حاليًا.',
                en: 'Unable to load favorites right now.',
              )
            : context.lt(
                ar: 'تعذر تحميل المزيد من عناصر المفضلة.',
                en: 'Unable to load more favorite items.',
              );
      });
    }
  }

  Future<void> _removeFavorite(_FavoriteProductItem item) async {
    try {
      await ref.read(ordersApiProvider).removeFavoriteProduct(item.id);
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != item.id).toList());
      await ref
          .read(ordersControllerProvider.notifier)
          .loadFavoriteProductIds();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(
              ar: 'تمت الإزالة من المفضلة.',
              en: 'Removed from favorites.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(
              ar: 'تعذر تحديث المفضلة حاليًا.',
              en: 'Unable to update favorites right now.',
            ),
          ),
        ),
      );
    }
  }

  void _openSearch(_FavoriteProductItem item) {
    final query = item.merchantName == null || item.merchantName!.isEmpty
        ? item.name
        : '${item.name} ${item.merchantName}';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: 'market',
          initialSearchQuery: query,
          overrideTitle: context.lt(
            ar: 'منتجات مفضلة',
            en: 'Favorite products',
          ),
          compactCustomerMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.lt(ar: 'منتجاتي المفضلة', en: 'My favorite products'),
        ),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _loading || _refreshing || _loadingMore
                ? null
                : () => _load(reset: true, silent: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textDirection: Directionality.of(context)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _load(reset: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.commonRetry),
                  ),
                ],
              ),
            )
          : _items.isEmpty
          ? Center(
              child: Text(
                context.lt(
                  ar: 'ما عندك منتجات مفضلة بعد.',
                  en: 'You do not have favorite products yet.',
                ),
                textDirection: Directionality.of(context),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  if (_loadingMore) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (_nextOffset == null) {
                    return Center(
                      child: Text(
                        context.lt(ar: 'انتهت القائمة', en: 'End of list'),
                        textDirection: Directionality.of(context),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }
                  return Center(
                    child: OutlinedButton.icon(
                      onPressed: () => _load(reset: false),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(
                        context.lt(ar: 'تحميل المزيد', en: 'Load more'),
                      ),
                    ),
                  );
                }

                final item = _items[index];
                final effectivePrice = item.discountedPrice ?? item.price;
                return Card(
                  child: ListTile(
                    leading: _ProductThumb(imageUrl: item.imageUrl),
                    title: Text(
                      item.name,
                      textDirection: Directionality.of(context),
                    ),
                    subtitle: Text(
                      [
                        if ((item.merchantName ?? '').isNotEmpty)
                          '${context.lt(ar: 'المتجر', en: 'Store')}: ${item.merchantName}',
                        '${context.lt(ar: 'السعر', en: 'Price')}: ${formatIqd(effectivePrice)}',
                      ].join('\n'),
                      textDirection: Directionality.of(context),
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: l10n.commonRemove,
                          onPressed: () => _removeFavorite(item),
                          icon: const Icon(Icons.favorite_rounded),
                        ),
                        IconButton(
                          tooltip: l10n.commonSearch,
                          onPressed: () => _openSearch(item),
                          icon: const Icon(Icons.search_rounded),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  final String? imageUrl;

  const _ProductThumb({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = (imageUrl ?? '').trim();
    if (url.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.inventory_2_outlined));
    }
    return CircleAvatar(
      backgroundImage: AppCachedImageProvider(url),
      onBackgroundImageError: (_, _) {},
      child: const SizedBox.shrink(),
    );
  }
}

class _FavoriteProductItem {
  final int id;
  final int merchantId;
  final String name;
  final String? merchantName;
  final String? imageUrl;
  final double price;
  final double? discountedPrice;

  const _FavoriteProductItem({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.merchantName,
    required this.imageUrl,
    required this.price,
    required this.discountedPrice,
  });

  factory _FavoriteProductItem.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse('$value') ?? 0;
    }

    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    }

    return _FavoriteProductItem(
      id: parseInt(json['id']),
      merchantId: parseInt(json['merchant_id'] ?? json['merchantId']),
      name: '${json['name'] ?? ''}'.trim(),
      merchantName: () {
        final value = '${json['merchant_name'] ?? json['merchantName']}'.trim();
        return value.isEmpty ? null : value;
      }(),
      imageUrl: () {
        final value = '${json['image_url'] ?? json['imageUrl']}'.trim();
        return value.isEmpty ? null : value;
      }(),
      price: parseDouble(json['price']),
      discountedPrice: json['discounted_price'] == null
          ? null
          : parseDouble(json['discounted_price']),
    );
  }
}
