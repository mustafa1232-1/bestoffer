import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../../products/models/product_model.dart';

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

  @override
  void initState() {
    super.initState();
    _seedSelections();
  }

  void _seedSelections() {
    final byGroup = <String, String>{};
    for (final entry in widget.initialSelections) {
      final groupCode = '${entry['groupCode'] ?? entry['group_code'] ?? ''}'
          .trim()
          .toLowerCase();
      final optionCode = '${entry['optionCode'] ?? entry['option_code'] ?? ''}'
          .trim()
          .toLowerCase();
      if (groupCode.isNotEmpty && optionCode.isNotEmpty) {
        byGroup[groupCode] = optionCode;
      }
    }

    for (final group in widget.product.variantGroups) {
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
      final available = group.options.where((option) => option.isAvailable).toList();
      if (available.isNotEmpty) {
        _selectedByGroup[group.code] = available.first;
      }
    }
  }

  double get _variantDeltaTotal {
    return _selectedByGroup.values.fold<double>(
      0,
      (sum, option) => sum + option.priceDelta,
    );
  }

  List<Map<String, dynamic>> get _selectedPayload {
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

  ProductVariantOptionModel? _selectedOptionFor(String groupCode) {
    return _selectedByGroup[groupCode];
  }

  @override
  Widget build(BuildContext context) {
    final basePrice = widget.product.discountedPrice ?? widget.product.price;
    final totalPrice = basePrice + _variantDeltaTotal;

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
                context.lt(
                  ar: 'اختر الخيارات',
                  en: 'Choose options',
                ),
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
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  if ((widget.product.displayImageUrl ?? '').isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: Image.network(
                          widget.product.displayImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: Colors.white.withValues(alpha: 0.08),
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_outlined),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatIqd(totalPrice),
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_variantDeltaTotal != 0) ...[
                          const SizedBox(height: 2),
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
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.product.summaryAttributes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: widget.product.summaryAttributes
                      .take(5)
                      .map(
                        (attr) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            '${attr.title}: ${attr.valueText}',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      )
                      .toList(),
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
                          final isSelected = selected?.code == option.code;
                          final enabled = option.isAvailable;
                          final useSwatch =
                              (group.displayMode == 'swatches' ||
                                  (option.swatchHex?.isNotEmpty ?? false));
                          return ChoiceChip(
                            selected: isSelected,
                            onSelected: enabled
                                ? (_) {
                                    setState(() {
                                      _selectedByGroup[group.code] = option;
                                    });
                                  }
                                : null,
                            label: Text(
                              option.title,
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
                                      color: _parseColor(option.swatchHex) ??
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: Text(
                        context.lt(ar: 'إلغاء', en: 'Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
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
