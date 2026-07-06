import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../../merchants/models/merchant_model.dart';
import '../../products/models/product_model.dart';
import '../../products/ui/product_summary_card.dart';
import '../../products/ui/product_variant_picker_sheet.dart';

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
    int? selectedVariantId,
  })?
  onAddToCart;
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
  final Map<String, Set<ProductVariantOptionModel>> _multiSelectedByGroup = {};

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
    _multiSelectedByGroup.clear();
    final availableVariant = widget.product.variants.where(
      (variant) => widget.product.canOrderVariant(variant),
    );
    final seeded = availableVariant.isEmpty
        ? const <String, String>{}
        : {
            for (final item in availableVariant.first.selections)
              item['groupCode']!: item['optionCode']!,
          };
    for (final group in widget.product.variantGroups) {
      if (group.selectionMode == 'multiple') {
        _multiSelectedByGroup[group.code] = <ProductVariantOptionModel>{};
        continue;
      }
      final available = group.options
          .where((option) => option.isAvailable)
          .toList();
      final seededCode = seeded[group.code];
      if (seededCode != null) {
        final matches = available.where((option) => option.code == seededCode);
        if (matches.isNotEmpty) {
          _selectedByGroup[group.code] = matches.first;
          continue;
        }
      }
      if (available.isNotEmpty) {
        _selectedByGroup[group.code] = available.first;
      }
    }
  }

  double get _effectivePrice =>
      _selectedVariant?.discountedPriceOverride ??
      _selectedVariant?.priceOverride ??
      ((widget.product.discountedPrice ?? widget.product.price) +
          _variantDeltaTotal);

  ProductVariantModel? get _selectedVariant =>
      widget.product.variantForSelections({
        for (final entry in _selectedByGroup.entries)
          entry.key: entry.value.code,
      });

  bool _optionCanLeadToStock(
    String groupCode,
    ProductVariantOptionModel option,
  ) {
    if (!option.isAvailable) return false;
    if (widget.product.variantGroups.any(
      (group) => group.code == groupCode && group.selectionMode == 'multiple',
    )) {
      return true;
    }
    if (widget.product.variants.isEmpty) return true;
    final proposed = <String, String>{
      for (final entry in _selectedByGroup.entries)
        entry.key.toLowerCase(): entry.value.code.toLowerCase(),
      groupCode.toLowerCase(): option.code.toLowerCase(),
    };
    return widget.product.variants.any((variant) {
      if (!widget.product.canOrderVariant(variant)) return false;
      final values = {
        for (final item in variant.selections)
          item['groupCode']!.toLowerCase(): item['optionCode']!.toLowerCase(),
      };
      return proposed.entries.every(
        (entry) => values[entry.key] == entry.value,
      );
    });
  }

  double get _variantDeltaTotal {
    final single = _selectedByGroup.values.fold<double>(
      0,
      (sum, option) => sum + option.priceDelta,
    );
    return _multiSelectedByGroup.values
        .expand((options) => options)
        .fold<double>(single, (sum, option) => sum + option.priceDelta);
  }

  List<Map<String, dynamic>> get _selectedVariantSelections {
    final selections = widget.product.variantGroups
        .map((group) {
          if (group.selectionMode == 'multiple') return null;
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
        .toList(growable: true);
    for (final group in widget.product.variantGroups.where(
      (group) => group.selectionMode == 'multiple',
    )) {
      for (final option
          in _multiSelectedByGroup[group.code] ??
              const <ProductVariantOptionModel>{}) {
        selections.add({
          'groupCode': group.code,
          'groupLabel': group.title,
          'optionCode': option.code,
          'optionLabel': option.title,
          'optionId': option.optionId,
          'priceDelta': option.priceDelta,
          'imageUrl': option.imageUrl,
        });
      }
    }
    return selections;
  }

  String? get _selectedColorCode => _selectedByGroup['color']?.code;
  String? get _selectedSizeCode => _selectedByGroup['size']?.code;

  void _applyCardSelection(ProductSummaryCardSelection selection) {
    setState(() {
      for (final entry in selection.selectedVariantSelections) {
        final groupCode = '${entry['groupCode'] ?? entry['group_code'] ?? ''}'
            .trim();
        final optionCode =
            '${entry['optionCode'] ?? entry['option_code'] ?? ''}'.trim();
        if (groupCode.isEmpty || optionCode.isEmpty) continue;
        final group = widget.product.variantGroups.firstWhere(
          (candidate) => candidate.code == groupCode,
          orElse: () => ProductVariantGroupModel(
            groupId: 0,
            code: groupCode,
            labelAr: groupCode,
            labelEn: groupCode,
            displayMode: 'chips',
            selectionMode: 'single',
            required: false,
            sortOrder: 0,
            metadata: const {},
            options: const [],
          ),
        );
        if (group.selectionMode == 'multiple') continue;
        final matches = group.options.where(
          (option) => option.code == optionCode,
        );
        if (matches.isNotEmpty) {
          _selectedByGroup[group.code] = matches.first;
        }
      }
    });
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
    if (widget.product.variants.isNotEmpty &&
        (_selectedVariant == null ||
            !widget.product.canOrderVariant(_selectedVariant!))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه التركيبة غير متوفرة حالياً')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onAddToCart!(
        widget.product,
        _quantity,
        selectedVariantId: _selectedVariant?.id,
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
        ? await showProductVariantPickerSheet(context, product: product)
        : const <Map<String, dynamic>>[];
    if (!mounted || selections == null) return;
    final selectedVariant = product.variantForSelectionEntries(selections);
    await widget.onAddToCart!(
      product,
      1,
      selectedVariantId: selectedVariant?.id,
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
          context.lt(ar: 'الخيارات المتاحة', en: 'Available options'),
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.90),
          ),
        ),
        const SizedBox(height: 8),
        ...widget.product.variantGroups
            .where((group) => group.code != 'color' && group.code != 'size')
            .map((group) {
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
                        final isMultiple = group.selectionMode == 'multiple';
                        final isSelected = isMultiple
                            ? (_multiSelectedByGroup[group.code]?.contains(
                                    option,
                                  ) ??
                                  false)
                            : selected?.code == option.code;
                        final enabled = _optionCanLeadToStock(
                          group.code,
                          option,
                        );
                        final useSwatch =
                            (group.displayMode == 'swatches' ||
                            (option.swatchHex?.isNotEmpty ?? false));
                        return ChoiceChip(
                          selected: isSelected,
                          onSelected: enabled
                              ? (_) {
                                  if (isMultiple) {
                                    setState(() {
                                      final selectedOptions =
                                          _multiSelectedByGroup.putIfAbsent(
                                            group.code,
                                            () => <ProductVariantOptionModel>{},
                                          );
                                      if (!selectedOptions.add(option)) {
                                        selectedOptions.remove(option);
                                      }
                                    });
                                  } else {
                                    setState(() {
                                      _selectedByGroup[group.code] = option;
                                    });
                                  }
                                }
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
                                    color:
                                        _parseVariantSwatch(option.swatchHex) ??
                                        Colors.white.withValues(alpha: 0.25),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
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

  @override
  Widget build(BuildContext context) {
    final textDirection = context.appTextDirection;
    final specs = _specLines();
    final appearance = ProductSummaryCardAppearance.fromContext(context);
    final locale = Localizations.localeOf(context);
    final canSubmitCurrentSelection =
        !widget.product.hasVariants ||
        (_selectedVariant != null &&
            widget.product.canOrderVariant(_selectedVariant!));
    final summaryData = ProductSummaryCardData.fromProduct(
      widget.product,
      locale: locale,
      priceTextOverride: formatIqd(_effectivePrice),
      selectedColorCode: _selectedColorCode,
      selectedSizeCode: _selectedSizeCode,
    );
    final submitLabel = !widget.canOrder
        ? widget.unavailableLabel
        : !_usesPharmacyConversation
        ? context.lt(ar: 'إضافة إلى السلة', en: 'Add to cart')
        : context.lt(
            ar: 'إرسال للوصفة/المراجعة',
            en: 'Send for prescription/review',
          );
    final submitUnavailableLabel = context.lt(
      ar: 'اختر تركيبة متاحة أولاً',
      en: 'Select an available variant first',
    );

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ProductSummaryCard(
              data: summaryData,
              appearance: appearance,
              compact: false,
              heroAspectRatio: 1.08,
              interactiveGallery: true,
              showVariantControls: true,
              maxAttributeBadges: 5,
              maxVariantBadges: 4,
              maxStatusBadges: 4,
              onSelectionChanged: _applyCardSelection,
            ),
            const SizedBox(height: 12),
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
                style: TextStyle(color: Colors.white.withValues(alpha: 0.74)),
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
                            () => _quantity = _quantity > 1 ? _quantity - 1 : 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: widget.canOrder && canSubmitCurrentSelection
                          ? _addCurrentProduct
                          : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _usesPharmacyConversation
                                  ? Icons.chat_bubble_outline_rounded
                                  : widget.product.hasVariants
                                  ? Icons.tune_rounded
                                  : Icons.add_shopping_cart_rounded,
                            ),
                      label: Text(
                        widget.canOrder && canSubmitCurrentSelection
                            ? submitLabel
                            : widget.canOrder
                            ? submitUnavailableLabel
                            : widget.unavailableLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
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
            if (widget.similarProducts.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
                ),
              )
            else
              ListView.separated(
                itemCount: widget.similarProducts.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = widget.similarProducts[index];
                  final canOrderSimilar =
                      widget.merchant.isOpen && item.canBeOrdered;
                  return ProductSummaryCard.fromProduct(
                    item,
                    appearance: appearance,
                    locale: locale,
                    onTap: widget.onOpenProduct == null
                        ? null
                        : () => widget.onOpenProduct!(item),
                    showDescription: false,
                    compact: true,
                    maxAttributeBadges: 2,
                    maxVariantBadges: 3,
                    maxStatusBadges: 2,
                    imageSize: 56,
                    trailing: widget.onAddToCart != null
                        ? canOrderSimilar
                              ? IconButton(
                                  tooltip: context.lt(
                                    ar: 'إضافة إلى السلة',
                                    en: 'Add to cart',
                                  ),
                                  onPressed: () => _addSimilar(item),
                                  icon: Icon(
                                    item.hasVariants
                                        ? Icons.tune_rounded
                                        : Icons.add_shopping_cart_rounded,
                                  ),
                                )
                              : Text(
                                  widget.unavailableLabel,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 12,
                                  ),
                                )
                        : null,
                  );
                },
              ),
          ],
        ),
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
