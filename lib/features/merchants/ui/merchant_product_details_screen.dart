import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../../merchants/models/merchant_model.dart';
import '../../products/models/product_model.dart';
import '../../products/ui/product_variant_picker_sheet.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class MerchantProductDetailsScreen extends StatefulWidget {
  final MerchantModel merchant;
  final ProductModel product;
  final List<ProductModel> similarProducts;
  final bool canOrder;
  final String unavailableLabel;
  final Future<void> Function(
    ProductModel product,
    int quantity, {
    List<Map<String, dynamic>> selectedVariantSelections,
  })? onAddToCart;
  final ValueChanged<ProductModel>? onOpenProduct;

  const MerchantProductDetailsScreen({
    super.key,
    required this.merchant,
    required this.product,
    required this.similarProducts,
    required this.canOrder,
    required this.unavailableLabel,
    required this.onAddToCart,
    required this.onOpenProduct,
  });

  @override
  State<MerchantProductDetailsScreen> createState() =>
      _MerchantProductDetailsScreenState();
}

class _MerchantProductDetailsScreenState
    extends State<MerchantProductDetailsScreen> {
  int _quantity = 1;
  bool _submitting = false;
  final Map<String, ProductVariantOptionModel> _selectedByGroup = {};
  int _galleryIndex = 0;

  @override
  void initState() {
    super.initState();
    _seedVariantSelections();
  }

  @override
  void didUpdateWidget(covariant MerchantProductDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _seedVariantSelections();
    }
  }

  void _seedVariantSelections() {
    _selectedByGroup.clear();
    for (final group in widget.product.variantGroups) {
      final available = group.options.where((option) => option.isAvailable).toList();
      if (available.isNotEmpty) {
        _selectedByGroup[group.code] = available.first;
      }
    }
  }

  double get _effectivePrice =>
      (widget.product.discountedPrice ?? widget.product.price) +
      _variantDeltaTotal;

  double get _variantDeltaTotal {
    return _selectedByGroup.values.fold<double>(
      0,
      (sum, option) => sum + option.priceDelta,
    );
  }

  List<Map<String, dynamic>> get _selectedVariantSelections {
    return widget.product.variantGroups
        .map((group) {
          final option = _selectedByGroup[group.code];
          if (option == null) return null;
          return <String, dynamic>{
            'groupCode': group.code,
            'groupLabel': group.title,
            'optionCode': option.code,
            'optionLabel': option.title,
            'optionId': option.optionId,
            'swatchHex': option.swatchHex,
            'priceDelta': option.priceDelta,
            'imageUrl': option.imageUrl,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  String? get _selectedVariantHeroImageUrl {
    for (final option in _selectedByGroup.values) {
      if (option.imageUrl?.trim().isNotEmpty == true) {
        return option.imageUrl;
      }
    }
    return widget.product.displayImageUrl;
  }

  bool get _usesPharmacyConversation =>
      widget.merchant.supportsPharmacyWorkflow &&
      widget.product.requiresPharmacyConversation;

  Future<void> _addCurrentProduct() async {
    if (!widget.canOrder ||
        widget.onAddToCart == null ||
        _submitting ||
        _quantity < 1) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onAddToCart!(
        widget.product,
        _quantity,
        selectedVariantSelections: _selectedVariantSelections,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss)
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            content: Text(
              _usesPharmacyConversation
                  ? context.lt(
                      ar: 'تم إرسال المنتج للصيدلية للمراجعة.',
                      en: 'The product was sent to the pharmacy for review.',
                    )
                  : context.lt(
                      ar: 'تمت إضافة المنتج إلى السلة.',
                      en: 'The product was added to cart.',
                    ),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _addSimilar(ProductModel product) async {
    if (widget.onAddToCart == null) return;
    final selections = product.hasVariants
        ? await showProductVariantPickerSheet(
            context,
            product: product,
          )
        : const <Map<String, dynamic>>[];
    if (!mounted || selections == null) return;
    await widget.onAddToCart!(
      product,
      1,
      selectedVariantSelections: selections,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss)
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: Text(
            context.lt(
              ar: 'تمت إضافة المنتج إلى السلة.',
              en: 'The product was added to cart.',
            ),
          ),
        ),
      );
  }

  List<String> _specLines() {
    final raw = widget.product.description?.trim() ?? '';
    if (raw.isEmpty) return const <String>[];

    final newlineParts = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (newlineParts.length > 1) return newlineParts;

    final commaParts = raw
        .split(RegExp(r'[,،]'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (commaParts.length > 1) return commaParts;

    return <String>[raw];
  }

  Widget _buildVariantSection(BuildContext context) {
    if (!widget.product.hasVariants) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(height: 12),
        Text(
          context.lt(
            ar: 'الخيارات المتاحة',
            en: 'Available options',
          ),
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.90),
          ),
        ),
        const SizedBox(height: 8),
        ...widget.product.variantGroups.map((group) {
          final selected = _selectedByGroup[group.code];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  group.title,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: group.options.map((option) {
                    final isSelected = selected?.code == option.code;
                    final enabled = option.isAvailable;
                    final useSwatch =
                        (group.displayMode == 'swatches' ||
                            (option.swatchHex?.isNotEmpty ?? false));
                    return ChoiceChip(
                      selected: isSelected,
                      onSelected: enabled
                          ? (_) => _setVariantOption(group.code, option)
                          : null,
                      label: Text(
                        option.title,
                        textDirection: TextDirection.rtl,
                      ),
                      avatar: useSwatch
                          ? Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _parseVariantSwatch(option.swatchHex) ??
                                    Colors.white.withValues(alpha: 0.25),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                            )
                          : null,
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  List<String> _galleryImageUrls() {
    final seen = <String>{};
    final out = <String>[];
    void addUrl(String? url) {
      final normalized = url?.trim();
      if (normalized == null || normalized.isEmpty) return;
      if (!seen.add(normalized)) return;
      out.add(normalized);
    }

    addUrl(_selectedVariantHeroImageUrl);
    for (final media in widget.product.media) {
      addUrl(media.imageUrl);
    }
    addUrl(widget.product.displayImageUrl);
    return out;
  }

  void _setVariantOption(String groupCode, ProductVariantOptionModel option) {
    if (!mounted) return;
    setState(() {
      _selectedByGroup[groupCode] = option;
      if (option.imageUrl?.trim().isNotEmpty == true) {
        _galleryIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = context.appTextDirection;
    final specs = _specLines();
    final galleryImages = _galleryImageUrls();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: galleryImages.isEmpty
                          ? Container(
                              color: Colors.white.withValues(alpha: 0.08),
                              alignment: Alignment.center,
                              child: Icon(
                                widget.merchant.type == 'restaurant'
                                    ? Icons.fastfood_rounded
                                    : Icons.inventory_2_rounded,
                                size: 42,
                              ),
                            )
                          : Stack(
                              children: [
                                PageView.builder(
                                  itemCount: galleryImages.length,
                                  onPageChanged: (index) {
                                    if (_galleryIndex == index) return;
                                    setState(() => _galleryIndex = index);
                                  },
                                  itemBuilder: (context, index) {
                                    return CachedAppImage(
                                      imageUrl: galleryImages[index],
                                      cacheIdentity:
                                          'product_${widget.product.id}_$index',
                                      fit: BoxFit.cover,
                                      errorWidget:
                                          (context, error, stackTrace) =>
                                              Container(
                                                color: Colors.white.withValues(
                                                  alpha: 0.08,
                                                ),
                                                alignment: Alignment.center,
                                                child: const Icon(
                                                  Icons.image_not_supported_rounded,
                                                ),
                                              ),
                                    );
                                  },
                                ),
                                if (galleryImages.length > 1)
                                  Positioned(
                                    left: 12,
                                    right: 12,
                                    bottom: 12,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: List.generate(
                                        galleryImages.length,
                                        (index) => AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 180),
                                          margin:
                                              const EdgeInsets.symmetric(
                                                horizontal: 3,
                                              ),
                                          width: _galleryIndex == index ? 20 : 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: _galleryIndex == index
                                                ? Colors.white
                                                : Colors.white.withValues(
                                                    alpha: 0.4,
                                                  ),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.product.name,
                    textDirection: textDirection,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatIqd(_effectivePrice),
                    textDirection: textDirection,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.product.hasDiscount) ...[
                    const SizedBox(height: 4),
                    Text(
                      formatIqd(widget.product.price),
                      style: TextStyle(
                        decoration: TextDecoration.lineThrough,
                      color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                  if (widget.product.summaryAttributes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: widget.product.summaryAttributes
                          .take(5)
                          .map(
                            (attr) => _ProductFlagBadge(
                              text: '${attr.title}: ${attr.valueText}',
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (widget.product.requiresPrescription ||
                      widget.product.requiresReview) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        if (widget.product.requiresPrescription)
                          _ProductFlagBadge(
                            text: context.lt(
                              ar: 'وصفة مطلوبة',
                              en: 'Prescription required',
                            ),
                            color: Colors.purple.withValues(alpha: 0.18),
                          ),
                        if (widget.product.requiresReview)
                          _ProductFlagBadge(
                            text: context.lt(
                              ar: 'مراجعة صيدلانية',
                              en: 'Pharmacist review',
                            ),
                            color: Colors.lightBlue.withValues(alpha: 0.18),
                          ),
                      ],
                    ),
                  ],
                  _buildVariantSection(context),
                  const SizedBox(height: 12),
                  Text(
                    context.lt(
                      ar: 'المواصفات / المكونات',
                      en: 'Specifications / ingredients',
                    ),
                    textDirection: textDirection,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (specs.isEmpty)
                    Text(
                      context.lt(
                        ar: 'لا توجد تفاصيل إضافية حالياً.',
                        en: 'No extra details available right now.',
                      ),
                      textDirection: textDirection,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.74),
                      ),
                    )
                  else
                    ...specs.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          textDirection: textDirection,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.circle, size: 7),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line,
                                textDirection: textDirection,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (widget.onAddToCart != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: context.lt(ar: 'زيادة', en: 'Increase'),
                                icon: const Icon(Icons.add_rounded),
                                onPressed: () => setState(() => _quantity += 1),
                              ),
                              Text(
                                '$_quantity',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: context.lt(ar: 'تنقيص', en: 'Decrease'),
                                icon: const Icon(Icons.remove_rounded),
                                onPressed: () => setState(
                                  () => _quantity = _quantity > 1
                                      ? _quantity - 1
                                      : 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.canOrder
                                ? _addCurrentProduct
                                : null,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _usesPharmacyConversation
                                        ? Icons.chat_bubble_outline_rounded
                                        : widget.product.hasVariants
                                            ? Icons.tune_rounded
                                            : Icons.add_shopping_cart_rounded,
                                  ),
                            label: Text(
                              widget.canOrder
                                  ? _usesPharmacyConversation
                                      ? context.lt(
                                          ar: 'إرسال للوصفة/المراجعة',
                                          en: 'Send for prescription/review',
                                        )
                                      : context.lt(
                                          ar: 'إضافة إلى السلة',
                                          en: 'Add to cart',
                                        )
                                  : widget.unavailableLabel,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    context.lt(
                      ar: 'مواد مشابهة من نفس المتجر',
                      en: 'Similar items from this store',
                    ),
                    textDirection: textDirection,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: widget.similarProducts.isEmpty
                        ? Center(
                            child: Text(
                              context.lt(
                                ar: 'لا توجد مواد مشابهة حالياً.',
                                en: 'No similar items available right now.',
                              ),
                              textDirection: textDirection,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: widget.similarProducts.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = widget.similarProducts[index];
                              final canOrderSimilar =
                                  widget.merchant.isOpen && item.isAvailable;
                              final price = item.discountedPrice ?? item.price;

                              return Card(
                                margin: EdgeInsets.zero,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: widget.onOpenProduct == null
                                      ? null
                                      : () => widget.onOpenProduct!(item),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: SizedBox(
                                            width: 56,
                                            height: 56,
                                            child:
                                                item.displayImageUrl == null ||
                                                    item.displayImageUrl!.isEmpty
                                                ? Container(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    alignment: Alignment.center,
                                                    child: const Icon(
                                                      Icons.image_outlined,
                                                      size: 18,
                                                    ),
                                                  )
                                                : CachedAppImage(
                                                    imageUrl: item.displayImageUrl!,
                                                    cacheIdentity:
                                                        'product_${item.id}',
                                                    fit: BoxFit.cover,
                                                    errorWidget:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => Container(
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.08,
                                                              ),
                                                          alignment:
                                                              Alignment.center,
                                                          child: const Icon(
                                                            Icons
                                                                .broken_image_rounded,
                                                            size: 18,
                                                          ),
                                                        ),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                item.name,
                                                textDirection: textDirection,
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              if (item.summaryAttributes.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                    bottom: 4,
                                                  ),
                                                  child: Text(
                                                    item.summaryAttributes
                                                        .take(2)
                                                        .map(
                                                          (attr) =>
                                                              '${attr.title}: ${attr.valueText}',
                                                        )
                                                        .join(' · '),
                                                    textDirection:
                                                        textDirection,
                                                    textAlign: TextAlign.right,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.72,
                                                          ),
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              Text(
                                                formatIqd(price),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (widget.onAddToCart != null &&
                                            canOrderSimilar)
                                          IconButton(
                                            tooltip: context.lt(
                                              ar: 'إضافة للسلة',
                                              en: 'Add to cart',
                                            ),
                                            onPressed: () => _addSimilar(item),
                                            icon: Icon(
                                              item.hasVariants
                                                  ? Icons.tune_rounded
                                                  : Icons.add_shopping_cart_rounded,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color? _parseVariantSwatch(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final normalized = raw.replaceAll('#', '');
  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}

class _ProductFlagBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _ProductFlagBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
