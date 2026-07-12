import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../../products/models/product_model.dart';
import 'product_summary_card.dart';

Future<List<Map<String, dynamic>>?> showProductVariantPickerSheet(
  BuildContext context, {
  required ProductModel product,
  List<Map<String, dynamic>> initialSelections = const [],
}) {
  if (!product.hasVariants || product.variantGroups.isEmpty) {
    return Future.value(const <Map<String, dynamic>>[]);
  }

  return showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _ProductVariantPickerSheet(
        product: product,
        initialSelections: initialSelections,
      );
    },
  );
}

class _ProductVariantPickerSheet extends StatefulWidget {
  final ProductModel product;
  final List<Map<String, dynamic>> initialSelections;

  const _ProductVariantPickerSheet({
    required this.product,
    required this.initialSelections,
  });

  @override
  State<_ProductVariantPickerSheet> createState() =>
      _ProductVariantPickerSheetState();
}

class _ProductVariantPickerSheetState
    extends State<_ProductVariantPickerSheet> {
  final Map<String, ProductVariantOptionModel> _selectedByGroup = {};
  final Map<String, Set<ProductVariantOptionModel>> _multiSelectedByGroup = {};

  String? get _selectedColorCode => _selectedByGroup['color']?.code;
  String? get _selectedSizeCode => _selectedByGroup['size']?.code;

  @override
  void initState() {
    super.initState();
    _seedSelections();
  }

  void _seedSelections() {
    final byGroup = <String, String>{};
    final requestedByGroup = <String, Set<String>>{};
    for (final entry in widget.initialSelections) {
      final groupCode = '${entry['groupCode'] ?? entry['group_code'] ?? ''}'
          .trim()
          .toLowerCase();
      final optionCode = '${entry['optionCode'] ?? entry['option_code'] ?? ''}'
          .trim()
          .toLowerCase();
      if (groupCode.isNotEmpty && optionCode.isNotEmpty) {
        byGroup[groupCode] = optionCode;
        requestedByGroup
            .putIfAbsent(groupCode, () => <String>{})
            .add(optionCode);
      }
    }
    if (byGroup.isEmpty && widget.product.variants.isNotEmpty) {
      final available = widget.product.variants.where(
        (variant) => widget.product.canOrderVariant(variant),
      );
      if (available.isNotEmpty) {
        for (final selection in available.first.selections) {
          byGroup[selection['groupCode']!.toLowerCase()] =
              selection['optionCode']!.toLowerCase();
        }
      }
    }

    for (final group in widget.product.variantGroups) {
      if (group.selectionMode == 'multiple') {
        final requested =
            requestedByGroup[group.code.toLowerCase()] ?? const <String>{};
        _multiSelectedByGroup[group.code] = group.options
            .where(
              (option) =>
                  option.isAvailable &&
                  requested.contains(option.code.toLowerCase()),
            )
            .toSet();
        continue;
      }
      final initialCode = byGroup[group.code.toLowerCase()];
      final matching = group.options.firstWhere(
        (option) => option.code.toLowerCase() == initialCode,
        orElse: () => const ProductVariantOptionModel(
          optionId: 0,
          code: '',
          labelAr: null,
          labelEn: null,
          swatchHex: null,
          priceDelta: 0,
          imageUrl: null,
          isAvailable: false,
          sortOrder: 0,
          metadata: {},
        ),
      );
      if (matching.code.isNotEmpty && matching.isAvailable) {
        _selectedByGroup[group.code] = matching;
        continue;
      }
      final available = group.options
          .where((option) => option.isAvailable)
          .toList();
      if (available.isNotEmpty) {
        _selectedByGroup[group.code] = available.first;
      }
    }
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
        entry.key.trim().toLowerCase(): entry.value.code.trim().toLowerCase(),
      groupCode.trim().toLowerCase(): option.code.trim().toLowerCase(),
    };
    return widget.product.variants.any((variant) {
      if (!widget.product.canOrderVariant(variant)) return false;
      final values = {
        for (final item in variant.selections)
          item['groupCode']!.trim().toLowerCase():
              item['optionCode']!.trim().toLowerCase(),
      };
      return proposed.entries.every(
        (entry) => values[entry.key] == entry.value,
      );
    });
  }

  List<Map<String, dynamic>> get _selectedPayload {
    final singles = widget.product.variantGroups
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
        singles.add({
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
    return singles;
  }

  ProductVariantOptionModel? _selectedOptionFor(String groupCode) {
    return _selectedByGroup[groupCode];
  }

  /// After a single-select option changes, drop any other single-select
  /// selection that can no longer combine into an orderable variant (e.g. a
  /// size that is not stocked for the newly chosen color). This forces the user
  /// to re-pick a valid value instead of leaving a stale, invalid combination
  /// that keeps the confirm button disabled.
  void _pruneInvalidSelections(String changedGroupCode) {
    if (widget.product.variants.isEmpty) return;
    final staleGroups = <String>[];
    for (final entry in _selectedByGroup.entries) {
      if (entry.key == changedGroupCode) continue;
      if (!_optionCanLeadToStock(entry.key, entry.value)) {
        staleGroups.add(entry.key);
      }
    }
    for (final groupCode in staleGroups) {
      _selectedByGroup.remove(groupCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final basePrice = widget.product.discountedPrice ?? widget.product.price;
    final locale = Localizations.localeOf(context);
    final totalPrice =
        _selectedVariant?.discountedPriceOverride ??
        _selectedVariant?.priceOverride ??
        (basePrice + _variantDeltaTotal);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.only(top: 48),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1B2A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.lt(ar: 'اختر الخيارات', en: 'Choose options'),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.product.name,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 12),
              ProductSummaryCard(
                data: ProductSummaryCardData.fromProduct(
                  widget.product,
                  locale: locale,
                  priceTextOverride: formatIqd(totalPrice),
                  selectedColorCode: _selectedColorCode,
                  selectedSizeCode: _selectedSizeCode,
                ),
                appearance: ProductSummaryCardAppearance.fromContext(context),
                compact: false,
                showVariantControls: false,
                interactiveGallery: false,
                maxAttributeBadges: 5,
                maxVariantBadges: 6,
                maxStatusBadges: 4,
              ),
              if (_variantDeltaTotal != 0) ...[
                const SizedBox(height: 6),
                Text(
                  context.lt(
                    ar: 'تحديث السعر حسب الاختيارات',
                    en: 'Price updates with selections',
                  ),
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...widget.product.variantGroups.map((group) {
                final selected = _selectedOptionFor(group.code);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        group.title,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontSize: 14,
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
                                    setState(() {
                                      if (isMultiple) {
                                        final selectedOptions =
                                            _multiSelectedByGroup.putIfAbsent(
                                              group.code,
                                              () =>
                                                  <ProductVariantOptionModel>{},
                                            );
                                        if (!selectedOptions.add(option)) {
                                          selectedOptions.remove(option);
                                        }
                                      } else {
                                        _selectedByGroup[group.code] = option;
                                        _pruneInvalidSelections(group.code);
                                      }
                                    });
                                  }
                                : null,
                            label: Text(
                              enabled
                                  ? option.title
                                  : '${option.title} · غير متوفر',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                color: enabled
                                    ? null
                                    : Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                            avatar: useSwatch
                                ? Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          _parseColor(option.swatchHex) ??
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
              if (widget.product.variants.isNotEmpty &&
                  (_selectedVariant == null ||
                      !widget.product.canOrderVariant(_selectedVariant!)))
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Text(
                    context.lt(
                      ar: 'هذا اللون/المقاس غير متوفر حالياً',
                      en: 'This color/size is currently unavailable',
                    ),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: Text(context.lt(ar: 'إلغاء', en: 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          widget.product.variants.isNotEmpty &&
                              (_selectedVariant == null ||
                                  !widget.product.canOrderVariant(
                                    _selectedVariant!,
                                  ))
                          ? null
                          : () {
                              Navigator.of(context).pop(_selectedPayload);
                            },
                      child: Text(
                        context.lt(ar: 'اعتماد الاختيارات', en: 'Confirm'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color? _parseColor(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final normalized = raw.replaceAll('#', '');
  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}
