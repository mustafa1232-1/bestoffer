import 'package:flutter/material.dart';

import '../../../core/files/local_image_file.dart';
import '../../../core/media/cached_app_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/product_offer_pricing.dart';
import '../models/product_model.dart';
import '../utils/product_variant_label_set.dart';

enum ProductSummaryBadgeKind {
  attribute,
  variant,
  status,
  discount,
  success,
  warning,
  danger,
}

class ProductSummaryBadgeData {
  final String text;
  final ProductSummaryBadgeKind kind;

  const ProductSummaryBadgeData({
    required this.text,
    this.kind = ProductSummaryBadgeKind.attribute,
  });
}

class ProductSummaryColorData {
  final int? optionId;
  final String code;
  final String label;
  final String? hex;
  final String? imageUrl;
  final bool available;
  final List<String> availableSizeCodes;
  final double? priceOverride;

  const ProductSummaryColorData({
    required this.optionId,
    required this.code,
    required this.label,
    required this.hex,
    required this.imageUrl,
    required this.available,
    required this.availableSizeCodes,
    this.priceOverride,
  });
}

class ProductSummarySizeData {
  final int? optionId;
  final String code;
  final String label;
  final bool available;
  final List<String> availableColorCodes;
  final double? priceOverride;

  const ProductSummarySizeData({
    required this.optionId,
    required this.code,
    required this.label,
    required this.available,
    required this.availableColorCodes,
    this.priceOverride,
  });
}

class ProductSummaryGalleryImageData {
  final String? imageUrl;
  final LocalImageFile? imageFile;
  final String? colorCode;
  final String? colorLabel;
  final String? colorHex;
  final bool isPrimary;
  final int sortOrder;

  const ProductSummaryGalleryImageData({
    required this.imageUrl,
    required this.imageFile,
    required this.colorCode,
    required this.colorLabel,
    required this.colorHex,
    required this.isPrimary,
    required this.sortOrder,
  });
}

class ProductSummaryCardSelection {
  final String? colorCode;
  final String? colorLabel;
  final String? colorHex;
  final String? colorImageUrl;
  final String? sizeCode;
  final String? sizeLabel;
  final String? imageUrl;
  final int galleryIndex;
  final int? variantId;
  final List<Map<String, dynamic>> selectedVariantSelections;

  const ProductSummaryCardSelection({
    required this.colorCode,
    required this.colorLabel,
    required this.colorHex,
    required this.colorImageUrl,
    required this.sizeCode,
    required this.sizeLabel,
    required this.imageUrl,
    required this.galleryIndex,
    required this.variantId,
    required this.selectedVariantSelections,
  });

  bool get hasColor => colorCode != null && colorCode!.trim().isNotEmpty;
  bool get hasSize => sizeCode != null && sizeCode!.trim().isNotEmpty;
  bool get isComplete => hasColor && hasSize;
}

class ProductSummaryCardData {
  final String title;
  final String? categoryLabel;
  final String? description;
  final String? imageUrl;
  final LocalImageFile? imageFile;
  final String priceText;
  final String? originalPriceText;
  final ProductSummaryBadgeData? discountBadge;
  final ProductSummaryBadgeData? availabilityBadge;
  final List<ProductSummaryBadgeData> attributeBadges;
  final List<ProductSummaryBadgeData> specificationBadges;
  final List<String> detailedSpecificationLines;
  final List<ProductSummaryBadgeData> variantBadges;
  final List<ProductSummaryBadgeData> statusBadges;
  final List<ProductSummaryColorData> colors;
  final List<ProductSummarySizeData> sizes;
  final List<ProductSummaryGalleryImageData> galleryImages;
  final List<ProductVariantModel> variants;
  final String? selectedColorCode;
  final String? selectedSizeCode;
  final bool strictVariantSelection;
  final String colorGroupLabelAr;
  final String colorGroupLabelEn;
  final String sizeGroupLabelAr;
  final String sizeGroupLabelEn;

  const ProductSummaryCardData({
    required this.title,
    this.categoryLabel,
    this.description,
    this.imageUrl,
    this.imageFile,
    required this.priceText,
    this.originalPriceText,
    this.discountBadge,
    this.availabilityBadge,
    this.attributeBadges = const [],
    this.specificationBadges = const [],
    this.detailedSpecificationLines = const [],
    this.variantBadges = const [],
    this.statusBadges = const [],
    this.colors = const [],
    this.sizes = const [],
    this.galleryImages = const [],
    this.variants = const [],
    this.selectedColorCode,
    this.selectedSizeCode,
    this.strictVariantSelection = false,
    this.colorGroupLabelAr = 'اللون',
    this.colorGroupLabelEn = 'Color',
    this.sizeGroupLabelAr = 'المقاس',
    this.sizeGroupLabelEn = 'Size',
  });

  factory ProductSummaryCardData.fromProduct(
    ProductModel product, {
    Locale? locale,
    String? priceTextOverride,
    LocalImageFile? imageFile,
    String? selectedColorCode,
    String? selectedSizeCode,
    bool strictVariantSelection = false,
    String? colorGroupLabelAr,
    String? colorGroupLabelEn,
    String? sizeGroupLabelAr,
    String? sizeGroupLabelEn,
    List<String> detailedSpecificationLines = const [],
  }) {
    final categoryLabel = _displayCategoryLabel(product.categoryName);
    final availableLabel = _localizedText(
      locale,
      ar: product.isAvailable
          ? (product.isInStock ? 'متاح' : 'نفد المخزون')
          : 'غير متاح',
      en: product.isAvailable
          ? (product.isInStock ? 'Available' : 'Out of stock')
          : 'Unavailable',
    );
    final availabilityKind = product.isAvailable
        ? (product.isInStock
              ? ProductSummaryBadgeKind.success
              : ProductSummaryBadgeKind.warning)
        : ProductSummaryBadgeKind.danger;

    final attributeBadges = product.summaryAttributes
        .map(
          (attr) => ProductSummaryBadgeData(
            text: '${attr.title}: ${attr.valueText}',
            kind: ProductSummaryBadgeKind.attribute,
          ),
        )
        .toList(growable: false);
    final specificationSource = product.attributes.isNotEmpty
        ? product.attributes
              .where((attr) => attr.showInDetails || attr.showInCard)
              .toList(growable: false)
        : product.summaryAttributes;
    final specificationBadges = specificationSource
        .map(
          (attr) => ProductSummaryBadgeData(
            text: '${attr.title}: ${attr.valueText}',
            kind: ProductSummaryBadgeKind.attribute,
          ),
        )
        .toList(growable: false);

    final availability = _buildVariantAvailability(product);
    final colorGroup = _findVariantGroup(product, _isColorGroup);
    final sizeGroup = _findVariantGroup(product, _isSizeGroup);
    final resolvedColorGroupLabelAr = _normalizedText(
      colorGroupLabelAr ?? colorGroup?.labelAr,
      fallback: productVariantDefaultLabels.colorLabelAr,
    );
    final resolvedColorGroupLabelEn = _normalizedText(
      colorGroupLabelEn ?? colorGroup?.labelEn,
      fallback: productVariantDefaultLabels.colorLabelEn,
    );
    final resolvedSizeGroupLabelAr = _normalizedText(
      sizeGroupLabelAr ?? sizeGroup?.labelAr,
      fallback: productVariantDefaultLabels.sizeLabelAr,
    );
    final resolvedSizeGroupLabelEn = _normalizedText(
      sizeGroupLabelEn ?? sizeGroup?.labelEn,
      fallback: productVariantDefaultLabels.sizeLabelEn,
    );
    final colors = _buildColorOptions(
      product,
      colorGroup: colorGroup,
      availability: availability,
    );
    final sizes = _buildSizeOptions(
      product,
      sizeGroup: sizeGroup,
      availability: availability,
    );
    final galleryImages = _buildGalleryImages(product, colors);
    final resolvedColorCode = strictVariantSelection
        ? selectedColorCode
        : _resolveInitialColorCode(
            selectedColorCode: selectedColorCode,
            colors: colors,
            galleryImages: galleryImages,
          );
    final resolvedSizeCode = strictVariantSelection
        ? selectedSizeCode
        : _resolveInitialSizeCode(
            selectedColorCode: resolvedColorCode,
            selectedSizeCode: selectedSizeCode,
            sizes: sizes,
          );

    final variantBadges = <ProductSummaryBadgeData>[];
    for (final group in product.variantGroups) {
      if (_isColorGroup(group) || _isSizeGroup(group)) continue;
      if (group.options.isEmpty) continue;
      final label =
          (group.labelAr?.trim().isNotEmpty == true
                  ? group.labelAr
                  : group.labelEn)
              ?.trim() ??
          group.code;
      variantBadges.add(
        ProductSummaryBadgeData(
          text: '$label: ${group.options.length}',
          kind: ProductSummaryBadgeKind.variant,
        ),
      );
    }

    final statusBadges = <ProductSummaryBadgeData>[
      if (product.requiresPrescription)
        ProductSummaryBadgeData(
          text: _localizedText(
            locale,
            ar: 'وصفة مطلوبة',
            en: 'Prescription required',
          ),
          kind: ProductSummaryBadgeKind.status,
        ),
      if (product.requiresReview)
        ProductSummaryBadgeData(
          text: _localizedText(
            locale,
            ar: 'مراجعة صيدلانية',
            en: 'Pharmacist review',
          ),
          kind: ProductSummaryBadgeKind.status,
        ),
      if (!product.hasVariants &&
          product.isStockTracked &&
          product.stockQuantity != null)
        ProductSummaryBadgeData(
          text: _localizedText(
            locale,
            ar: 'المخزون: ${product.stockQuantity}',
            en: 'Stock: ${product.stockQuantity}',
          ),
          kind: ProductSummaryBadgeKind.status,
        ),
      if (product.hasVariants)
        ProductSummaryBadgeData(
          text: product.isInStock
              ? _localizedText(
                  locale,
                  ar: '${product.variantGroups.length} خيارات',
                  en: '${product.variantGroups.length} options',
                )
              : _localizedText(locale, ar: 'نفد المخزون', en: 'Out of stock'),
          kind: product.isInStock
              ? ProductSummaryBadgeKind.status
              : ProductSummaryBadgeKind.danger,
        ),
    ];

    return ProductSummaryCardData(
      title: product.name,
      categoryLabel: categoryLabel,
      description: product.description,
      imageUrl: product.displayImageUrl,
      imageFile: imageFile,
      priceText:
          priceTextOverride ??
          formatIqd(
            variantSelectionUnitPriceOverride(
                  product,
                  selections: [
                    if (resolvedColorCode != null)
                      {'groupCode': 'color', 'optionCode': resolvedColorCode},
                    if (resolvedSizeCode != null)
                      {'groupCode': 'size', 'optionCode': resolvedSizeCode},
                  ],
                ) ??
                (product.discountedPrice ?? product.price),
          ),
      originalPriceText: product.hasDiscount ? formatIqd(product.price) : null,
      discountBadge: product.hasDiscount
          ? ProductSummaryBadgeData(
              text: '-${product.discountPercent ?? 0}%',
              kind: ProductSummaryBadgeKind.discount,
            )
          : null,
      availabilityBadge: ProductSummaryBadgeData(
        text: availableLabel,
        kind: availabilityKind,
      ),
      attributeBadges: attributeBadges,
      specificationBadges: specificationBadges,
      detailedSpecificationLines: _normalizeDetailLines(
        detailedSpecificationLines,
      ),
      variantBadges: variantBadges,
      statusBadges: statusBadges,
      colors: colors,
      sizes: sizes,
      galleryImages: galleryImages,
      variants: product.variants,
      selectedColorCode: resolvedColorCode,
      selectedSizeCode: resolvedSizeCode,
      strictVariantSelection: strictVariantSelection,
      colorGroupLabelAr: resolvedColorGroupLabelAr,
      colorGroupLabelEn: resolvedColorGroupLabelEn,
      sizeGroupLabelAr: resolvedSizeGroupLabelAr,
      sizeGroupLabelEn: resolvedSizeGroupLabelEn,
    );
  }

  ProductSummaryCardSelection resolveSelection({
    String? selectedColorCode,
    String? selectedSizeCode,
    int galleryIndex = 0,
  }) {
    final color = _resolveColor(selectedColorCode ?? this.selectedColorCode);
    final size = _resolveSize(
      colorCode: color?.code,
      requestedSizeCode: selectedSizeCode ?? this.selectedSizeCode,
    );
    final imageIndex = resolveGalleryIndex(
      colorCode: color?.code,
      fallbackIndex: galleryIndex,
    );
    final image = resolveGalleryImage(
      colorCode: color?.code,
      fallbackIndex: imageIndex,
    );

    final selections = <Map<String, dynamic>>[];
    if (color != null) {
      selections.add({
        'groupCode': 'color',
        'groupLabel': colorGroupLabelAr,
        'optionCode': color.code,
        'optionLabel': color.label,
        'optionId': color.optionId,
        'swatchHex': color.hex,
        'imageUrl': color.imageUrl ?? image?.imageUrl,
      });
    }
    if (size != null) {
      selections.add({
        'groupCode': 'size',
        'groupLabel': sizeGroupLabelAr,
        'optionCode': size.code,
        'optionLabel': size.label,
        'optionId': size.optionId,
      });
    }
    final variant = variantForSelectionEntries(selections);

    return ProductSummaryCardSelection(
      colorCode: color?.code,
      colorLabel: color?.label,
      colorHex: color?.hex,
      colorImageUrl: color?.imageUrl,
      sizeCode: size?.code,
      sizeLabel: size?.label,
      imageUrl: image?.imageUrl ?? imageUrl,
      galleryIndex: imageIndex,
      variantId: variant?.id,
      selectedVariantSelections: selections,
    );
  }

  ProductVariantModel? variantForSelectionEntries(
    List<Map<String, dynamic>> selections,
  ) {
    if (variants.isEmpty || selections.isEmpty) return null;
    final normalized = <String, String>{};
    for (final entry in selections) {
      final groupCode = _normalizeCode(
        entry['groupCode'] ?? entry['group_code'] ?? entry['group'],
      );
      final optionCode = _normalizeCode(
        entry['optionCode'] ?? entry['option_code'] ?? entry['option'],
      );
      if (groupCode == null || optionCode == null) continue;
      normalized[groupCode] = optionCode;
    }
    if (normalized.isEmpty) return null;
    final signatureParts =
        normalized.entries
            .map((entry) => '${entry.key}:${entry.value}')
            .toList()
          ..sort();
    final fallbackSignature = signatureParts.join('|');
    for (final variant in variants) {
      final variantSelections = <String, String>{};
      for (final item in variant.selections) {
        final groupCode = _normalizeCode(item['groupCode']);
        final optionCode = _normalizeCode(item['optionCode']);
        if (groupCode == null || optionCode == null) continue;
        variantSelections[groupCode] = optionCode;
      }
      if (variantSelections.isEmpty) {
        if (variant.signature.toLowerCase() == fallbackSignature) {
          return variant;
        }
        continue;
      }
      if (variantSelections.length != normalized.length) continue;
      final matches = normalized.entries.every(
        (entry) => variantSelections[entry.key] == entry.value,
      );
      if (matches) return variant;
    }
    return null;
  }

  ProductSummaryColorData? _resolveColor(String? code) {
    final availableColors = colors
        .where((color) => color.available)
        .toList(growable: false);
    if (availableColors.isEmpty) return null;
    final normalized = _normalizeCode(code);
    if (normalized == null) {
      return strictVariantSelection ? null : availableColors.first;
    }
    for (final color in availableColors) {
      if (_sameCode(color.code, normalized)) return color;
    }
    return strictVariantSelection ? null : availableColors.first;
  }

  ProductSummarySizeData? _resolveSize({
    required String? colorCode,
    required String? requestedSizeCode,
  }) {
    final eligible = availableSizesForColor(colorCode);
    if (eligible.isEmpty) return null;
    final normalizedRequested = _normalizeCode(requestedSizeCode);
    if (normalizedRequested == null) {
      return strictVariantSelection ? null : eligible.first;
    }
    for (final size in eligible) {
      if (_sameCode(size.code, normalizedRequested)) return size;
    }
    return strictVariantSelection ? null : eligible.first;
  }

  List<ProductSummarySizeData> availableSizesForColor(String? colorCode) {
    if (sizes.isEmpty) return const [];
    if (colors.isEmpty) {
      return sizes.where((size) => size.available).toList(growable: false);
    }
    final normalizedColor = _normalizeCode(colorCode);
    if (normalizedColor == null) {
      return sizes.where((size) => size.available).toList(growable: false);
    }
    final eligible = sizes
        .where((size) {
          if (!size.available) return false;
          if (size.availableColorCodes.isEmpty) return true;
          return size.availableColorCodes
              .map(_normalizeCode)
              .whereType<String>()
              .any((value) => _sameCode(value, normalizedColor));
        })
        .toList(growable: false);
    return eligible.isNotEmpty
        ? eligible
        : sizes.where((size) => size.available).toList(growable: false);
  }

  int resolveGalleryIndex({required String? colorCode, int fallbackIndex = 0}) {
    if (galleryImages.isEmpty) return 0;
    final normalizedColor = _normalizeCode(colorCode);
    if (normalizedColor != null) {
      for (var i = 0; i < galleryImages.length; i += 1) {
        final image = galleryImages[i];
        if (_sameCode(image.colorCode, normalizedColor)) return i;
      }
    }
    if (fallbackIndex >= 0 && fallbackIndex < galleryImages.length) {
      return fallbackIndex;
    }
    return 0;
  }

  ProductSummaryGalleryImageData? resolveGalleryImage({
    required String? colorCode,
    int fallbackIndex = 0,
  }) {
    if (galleryImages.isEmpty) return null;
    final index = resolveGalleryIndex(
      colorCode: colorCode,
      fallbackIndex: fallbackIndex,
    );
    if (index < 0 || index >= galleryImages.length) return galleryImages.first;
    return galleryImages[index];
  }
}

String _localizedText(
  Locale? locale, {
  required String ar,
  required String en,
}) {
  final languageCode = locale?.languageCode.toLowerCase();
  if (languageCode == 'en') return en;
  return ar;
}

String _normalizedText(String? value, {required String fallback}) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return fallback;
  return normalized;
}

String? _displayCategoryLabel(String? categoryName) {
  final normalized = categoryName?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  final lowered = normalized.toLowerCase();
  if (const {'cloths', 'clothes', 'clothing', 'fashion'}.contains(lowered)) {
    return 'Clothes / ملابس';
  }
  return normalized;
}

bool _isColorGroup(ProductVariantGroupModel group) {
  final code = group.code.trim().toLowerCase();
  return code == 'color' || group.displayMode == 'swatches';
}

bool _isSizeGroup(ProductVariantGroupModel group) {
  final code = group.code.trim().toLowerCase();
  return code == 'size';
}

String? _normalizeCode(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

bool _sameCode(String? a, String? b) {
  final left = _normalizeCode(a);
  final right = _normalizeCode(b);
  if (left == null || right == null) return false;
  return left == right;
}

ProductVariantGroupModel? _findVariantGroup(
  ProductModel product,
  bool Function(ProductVariantGroupModel group) test,
) {
  for (final group in product.variantGroups) {
    if (test(group)) return group;
  }
  return null;
}

({
  Map<String, Set<String>> colorToSizes,
  Map<String, Set<String>> sizeToColors,
  Set<String> colorsWithStock,
  Set<String> sizesWithStock,
})
_buildVariantAvailability(ProductModel product) {
  final colorToSizes = <String, Set<String>>{};
  final sizeToColors = <String, Set<String>>{};
  final colorsWithStock = <String>{};
  final sizesWithStock = <String>{};

  for (final variant in product.variants) {
    if (!product.canOrderVariant(variant)) continue;
    String? colorCode;
    String? sizeCode;
    for (final selection in variant.selections) {
      final groupCode = _normalizeCode(selection['groupCode']);
      final optionCode = _normalizeCode(selection['optionCode']);
      if (groupCode == null || optionCode == null) continue;
      if (groupCode == 'color') colorCode = optionCode;
      if (groupCode == 'size') sizeCode = optionCode;
    }
    if (colorCode != null) {
      colorsWithStock.add(colorCode);
    }
    if (sizeCode != null) {
      sizesWithStock.add(sizeCode);
    }
    if (colorCode != null && sizeCode != null) {
      colorToSizes.putIfAbsent(colorCode, () => <String>{}).add(sizeCode);
      sizeToColors.putIfAbsent(sizeCode, () => <String>{}).add(colorCode);
    } else if (colorCode != null) {
      colorToSizes.putIfAbsent(colorCode, () => <String>{});
    } else if (sizeCode != null) {
      sizeToColors.putIfAbsent(sizeCode, () => <String>{});
    }
  }

  return (
    colorToSizes: colorToSizes,
    sizeToColors: sizeToColors,
    colorsWithStock: colorsWithStock,
    sizesWithStock: sizesWithStock,
  );
}

List<ProductSummaryColorData> _buildColorOptions(
  ProductModel product, {
  required ProductVariantGroupModel? colorGroup,
  required ({
    Map<String, Set<String>> colorToSizes,
    Map<String, Set<String>> sizeToColors,
    Set<String> colorsWithStock,
    Set<String> sizesWithStock,
  })
  availability,
}) {
  if (colorGroup == null) return const [];
  return colorGroup.options
      .map((option) {
        final code = _normalizeCode(option.code) ?? option.code.toLowerCase();
        final linkedSizes = availability.colorToSizes[code] ?? const <String>{};
        final enabled = product.variants.isEmpty
            ? option.isAvailable
            : availability.colorsWithStock.contains(code);
        return ProductSummaryColorData(
          optionId: option.optionId <= 0 ? null : option.optionId,
          code: option.code,
          label: option.title,
          hex: option.swatchHex,
          imageUrl: option.imageUrl?.trim().isNotEmpty == true
              ? option.imageUrl!.trim()
              : _resolveColorMediaUrl(product, code),
          available: enabled,
          availableSizeCodes: linkedSizes.toList(growable: false)..sort(),
          priceOverride: option.priceOverride,
        );
      })
      .toList(growable: false);
}

List<ProductSummarySizeData> _buildSizeOptions(
  ProductModel product, {
  required ProductVariantGroupModel? sizeGroup,
  required ({
    Map<String, Set<String>> colorToSizes,
    Map<String, Set<String>> sizeToColors,
    Set<String> colorsWithStock,
    Set<String> sizesWithStock,
  })
  availability,
}) {
  if (sizeGroup == null) return const [];
  return sizeGroup.options
      .map((option) {
        final code = _normalizeCode(option.code) ?? option.code.toLowerCase();
        final colors = availability.sizeToColors[code] ?? const <String>{};
        final enabled = product.variants.isEmpty
            ? option.isAvailable
            : availability.sizesWithStock.contains(code) || colors.isNotEmpty;
        return ProductSummarySizeData(
          optionId: option.optionId <= 0 ? null : option.optionId,
          code: option.code,
          label: option.title,
          available: enabled,
          availableColorCodes: colors.toList(growable: false)..sort(),
          priceOverride: option.priceOverride,
        );
      })
      .toList(growable: false);
}

List<ProductSummaryGalleryImageData> _buildGalleryImages(
  ProductModel product,
  List<ProductSummaryColorData> colors,
) {
  final colorByCode = <String, ProductSummaryColorData>{
    for (final color in colors)
      _normalizeCode(color.code) ?? color.code.toLowerCase(): color,
  };
  final images = <ProductSummaryGalleryImageData>[];
  final seen = <String>{};

  void addImage({
    required String? imageUrl,
    LocalImageFile? imageFile,
    String? colorCode,
    String? colorLabel,
    String? colorHex,
    bool isPrimary = false,
    int sortOrder = 0,
  }) {
    final normalizedUrl = imageUrl?.trim();
    final normalizedColor = _normalizeCode(colorCode);
    final cacheKey = [
      normalizedUrl ?? 'local:${imageFile?.name ?? 'image'}',
      normalizedColor ?? '',
      isPrimary ? '1' : '0',
    ].join('|');
    if (normalizedUrl == null && imageFile == null) return;
    if (!seen.add(cacheKey)) return;
    images.add(
      ProductSummaryGalleryImageData(
        imageUrl: normalizedUrl,
        imageFile: imageFile,
        colorCode: normalizedColor,
        colorLabel: colorLabel,
        colorHex: colorHex,
        isPrimary: isPrimary,
        sortOrder: sortOrder,
      ),
    );
  }

  addImage(
    imageUrl: product.displayImageUrl ?? product.imageUrl,
    isPrimary: true,
    sortOrder: -100,
  );

  final sortedMedia = [...product.media]
    ..sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return a.sortOrder.compareTo(b.sortOrder);
    });
  for (final media in sortedMedia) {
    final normalizedColor = _normalizeCode(media.variantOptionCode);
    final color = normalizedColor == null ? null : colorByCode[normalizedColor];
    addImage(
      imageUrl: media.imageUrl,
      colorCode: normalizedColor,
      colorLabel: color?.label,
      colorHex: color?.hex,
      isPrimary: media.isPrimary,
      sortOrder: media.sortOrder,
    );
  }

  for (var i = 0; i < colors.length; i += 1) {
    final color = colors[i];
    addImage(
      imageUrl: color.imageUrl,
      colorCode: color.code,
      colorLabel: color.label,
      colorHex: color.hex,
      sortOrder: 1000 + i,
    );
  }

  if (images.isEmpty) {
    addImage(imageUrl: product.displayImageUrl ?? product.imageUrl);
  }

  return images;
}

String? _resolveColorMediaUrl(ProductModel product, String code) {
  for (final media in product.media) {
    if (_normalizeCode(media.variantGroupCode) != 'color') continue;
    if (_sameCode(media.variantOptionCode, code) &&
        media.imageUrl.trim().isNotEmpty) {
      return media.imageUrl.trim();
    }
  }
  return null;
}

String? _resolveInitialColorCode({
  String? selectedColorCode,
  required List<ProductSummaryColorData> colors,
  required List<ProductSummaryGalleryImageData> galleryImages,
}) {
  final normalizedRequested = _normalizeCode(selectedColorCode);
  if (normalizedRequested != null) {
    for (final color in colors) {
      if (_sameCode(color.code, normalizedRequested) && color.available) {
        return color.code;
      }
    }
  }
  for (final image in galleryImages) {
    if (image.colorCode != null && image.colorCode!.trim().isNotEmpty) {
      return image.colorCode;
    }
  }
  for (final color in colors) {
    if (color.available) return color.code;
  }
  return colors.isNotEmpty ? colors.first.code : null;
}

String? _resolveInitialSizeCode({
  required String? selectedColorCode,
  String? selectedSizeCode,
  required List<ProductSummarySizeData> sizes,
}) {
  if (sizes.isEmpty) return null;
  final normalizedRequested = _normalizeCode(selectedSizeCode);
  final available = _filterSizesForColor(
    sizes,
    selectedColorCode: selectedColorCode,
  );
  if (normalizedRequested != null) {
    for (final size in available) {
      if (_sameCode(size.code, normalizedRequested) && size.available) {
        return size.code;
      }
    }
  }
  for (final size in available) {
    if (size.available) return size.code;
  }
  return available.isNotEmpty ? available.first.code : sizes.first.code;
}

List<ProductSummarySizeData> _filterSizesForColor(
  List<ProductSummarySizeData> sizes, {
  required String? selectedColorCode,
}) {
  if (sizes.isEmpty) return const [];
  final normalizedColor = _normalizeCode(selectedColorCode);
  if (normalizedColor == null) {
    return sizes.where((size) => size.available).toList(growable: false);
  }
  final filtered = sizes
      .where((size) {
        if (!size.available) return false;
        if (size.availableColorCodes.isEmpty) return true;
        return size.availableColorCodes.any(
          (colorCode) => _sameCode(colorCode, normalizedColor),
        );
      })
      .toList(growable: false);
  return filtered.isNotEmpty
      ? filtered
      : sizes.where((size) => size.available).toList(growable: false);
}

List<String> _normalizeDetailLines(List<String> lines) {
  return lines
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

class ProductSummaryCardAppearance {
  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;
  final Color bodyColor;
  final Color chipBackgroundColor;
  final Color chipBorderColor;
  final Color chipTextColor;
  final Color accentColor;
  final Color successColor;
  final Color warningColor;
  final Color dangerColor;
  final BorderRadius borderRadius;

  const ProductSummaryCardAppearance({
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
    required this.bodyColor,
    required this.chipBackgroundColor,
    required this.chipBorderColor,
    required this.chipTextColor,
    required this.accentColor,
    required this.successColor,
    required this.warningColor,
    required this.dangerColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  factory ProductSummaryCardAppearance.fromContext(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    return ProductSummaryCardAppearance(
      backgroundColor: tokens.cardPrimary.withValues(alpha: 0.72),
      borderColor: tokens.borderSubtle.withValues(alpha: 0.4),
      titleColor: tokens.textPrimary,
      bodyColor: tokens.textMuted,
      chipBackgroundColor: Colors.white.withValues(alpha: 0.06),
      chipBorderColor: tokens.borderSubtle.withValues(alpha: 0.24),
      chipTextColor: tokens.textMuted,
      accentColor: visual.accentCyan,
      successColor: tokens.success,
      warningColor: Colors.orange,
      dangerColor: tokens.danger,
    );
  }
}

class ProductSummaryCard extends StatefulWidget {
  final ProductSummaryCardData data;
  final ProductSummaryCardAppearance? appearance;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showDescription;
  final bool showImage;
  final bool compact;
  final int maxAttributeBadges;
  final int maxVariantBadges;
  final int maxStatusBadges;
  final bool showDetailedSpecifications;
  final double? imageSize;
  final double? heroAspectRatio;
  final bool interactiveGallery;
  final bool showVariantControls;
  final String? selectedColorCode;
  final String? selectedSizeCode;
  final List<String> detailedSpecificationLines;
  final ValueChanged<ProductSummaryCardSelection>? onSelectionChanged;

  const ProductSummaryCard({
    super.key,
    required this.data,
    this.appearance,
    this.onTap,
    this.trailing,
    this.showDescription = true,
    this.showImage = true,
    this.compact = true,
    this.maxAttributeBadges = 3,
    this.maxVariantBadges = 4,
    this.maxStatusBadges = 3,
    this.showDetailedSpecifications = false,
    this.imageSize,
    this.heroAspectRatio,
    this.interactiveGallery = false,
    this.showVariantControls = true,
    this.selectedColorCode,
    this.selectedSizeCode,
    this.detailedSpecificationLines = const [],
    this.onSelectionChanged,
  });

  factory ProductSummaryCard.fromProduct(
    ProductModel product, {
    Key? key,
    ProductSummaryCardAppearance? appearance,
    VoidCallback? onTap,
    Widget? trailing,
    bool showDescription = true,
    bool showImage = true,
    bool compact = true,
    int maxAttributeBadges = 3,
    int maxVariantBadges = 4,
    int maxStatusBadges = 3,
    bool showDetailedSpecifications = false,
    double? imageSize,
    double? heroAspectRatio,
    bool interactiveGallery = false,
    bool showVariantControls = true,
    String? selectedColorCode,
    String? selectedSizeCode,
    bool strictVariantSelection = false,
    String? colorGroupLabelAr,
    String? colorGroupLabelEn,
    String? sizeGroupLabelAr,
    String? sizeGroupLabelEn,
    List<String> detailedSpecificationLines = const [],
    ValueChanged<ProductSummaryCardSelection>? onSelectionChanged,
    Locale? locale,
  }) {
    return ProductSummaryCard(
      key: key,
      data: ProductSummaryCardData.fromProduct(
        product,
        locale: locale,
        selectedColorCode: selectedColorCode,
        selectedSizeCode: selectedSizeCode,
        strictVariantSelection: strictVariantSelection,
        colorGroupLabelAr: colorGroupLabelAr,
        colorGroupLabelEn: colorGroupLabelEn,
        sizeGroupLabelAr: sizeGroupLabelAr,
        sizeGroupLabelEn: sizeGroupLabelEn,
        detailedSpecificationLines: detailedSpecificationLines,
      ),
      appearance: appearance,
      onTap: onTap,
      trailing: trailing,
      showDescription: showDescription,
      showImage: showImage,
      compact: compact,
      maxAttributeBadges: maxAttributeBadges,
      maxVariantBadges: maxVariantBadges,
      maxStatusBadges: maxStatusBadges,
      showDetailedSpecifications: showDetailedSpecifications,
      imageSize: imageSize,
      heroAspectRatio: heroAspectRatio,
      interactiveGallery: interactiveGallery,
      showVariantControls: showVariantControls,
      selectedColorCode: selectedColorCode,
      selectedSizeCode: selectedSizeCode,
      detailedSpecificationLines: detailedSpecificationLines,
      onSelectionChanged: onSelectionChanged,
    );
  }

  @override
  State<ProductSummaryCard> createState() => _ProductSummaryCardState();
}

class _ProductSummaryCardState extends State<ProductSummaryCard> {
  String? _selectedColorCode;
  String? _selectedSizeCode;
  int _galleryIndex = 0;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _selectedColorCode =
        widget.selectedColorCode ?? widget.data.selectedColorCode;
    _selectedSizeCode = widget.selectedSizeCode ?? widget.data.selectedSizeCode;
    _galleryIndex = widget.data.resolveGalleryIndex(
      colorCode: _selectedColorCode,
      fallbackIndex: 0,
    );
    _pageController =
        widget.interactiveGallery && widget.data.galleryImages.length > 1
        ? PageController(initialPage: _galleryIndex)
        : null;
  }

  @override
  void didUpdateWidget(covariant ProductSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSignature = _gallerySignature(oldWidget.data);
    final newSignature = _gallerySignature(widget.data);
    if (oldSignature != newSignature ||
        oldWidget.interactiveGallery != widget.interactiveGallery) {
      _galleryIndex = widget.data.resolveGalleryIndex(
        colorCode:
            _selectedColorCode ??
            widget.selectedColorCode ??
            widget.data.selectedColorCode,
        fallbackIndex: _galleryIndex,
      );
      _pageController?.dispose();
      _pageController =
          widget.interactiveGallery && widget.data.galleryImages.length > 1
          ? PageController(initialPage: _galleryIndex)
          : null;
    }
    if (widget.selectedColorCode != oldWidget.selectedColorCode) {
      _selectedColorCode =
          widget.selectedColorCode ?? widget.data.selectedColorCode;
      _galleryIndex = widget.data.resolveGalleryIndex(
        colorCode: _selectedColorCode,
        fallbackIndex: _galleryIndex,
      );
      _jumpToCurrentPage();
    }
    if (widget.selectedSizeCode != oldWidget.selectedSizeCode) {
      _selectedSizeCode =
          widget.selectedSizeCode ?? widget.data.selectedSizeCode;
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _jumpToCurrentPage() {
    if (!widget.interactiveGallery) return;
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final current = controller.page?.round();
    if (current == _galleryIndex) return;
    controller.jumpToPage(_galleryIndex);
  }

  ProductSummaryCardSelection _currentSelection({
    String? selectedColorCode,
    String? selectedSizeCode,
  }) {
    return widget.data.resolveSelection(
      selectedColorCode: selectedColorCode ?? _selectedColorCode,
      selectedSizeCode: selectedSizeCode ?? _selectedSizeCode,
      galleryIndex: _galleryIndex,
    );
  }

  /// The price to show right now for the live in-card selection: a full
  /// combination override wins, then a per-option special price (size before
  /// color), else the parent-provided priceText (base / forced override).
  String get _currentPriceText {
    final selection = _currentSelection();
    if (selection.variantId != null) {
      for (final v in widget.data.variants) {
        if (v.id == selection.variantId) {
          final combo = v.discountedPriceOverride ?? v.priceOverride;
          if (combo != null) return formatIqd(combo);
          break;
        }
      }
    }
    for (final s in widget.data.sizes) {
      if (_sameCode(s.code, _selectedSizeCode) && s.priceOverride != null) {
        return formatIqd(s.priceOverride!);
      }
    }
    for (final c in widget.data.colors) {
      if (_sameCode(c.code, _selectedColorCode) && c.priceOverride != null) {
        return formatIqd(c.priceOverride!);
      }
    }
    return widget.data.priceText;
  }

  void _emitSelection() {
    final callback = widget.onSelectionChanged;
    if (callback == null) return;
    callback(_currentSelection());
  }

  String _gallerySignature(ProductSummaryCardData data) {
    final gallery = data.galleryImages
        .map(
          (item) =>
              '${item.imageUrl ?? item.imageFile?.name ?? ''}:${item.colorCode ?? ''}:${item.isPrimary ? 1 : 0}:${item.sortOrder}',
        )
        .join('|');
    final colors = data.colors
        .map((item) => '${item.code}:${item.imageUrl ?? ''}:${item.hex ?? ''}')
        .join('|');
    final sizes = data.sizes
        .map((item) => '${item.code}:${item.available ? 1 : 0}')
        .join('|');
    return [
      data.title,
      data.imageUrl ?? '',
      data.imageFile?.name ?? '',
      gallery,
      colors,
      sizes,
    ].join('||');
  }

  void _selectColor(ProductSummaryColorData color) {
    if (!widget.showVariantControls || !color.available) return;
    final nextSizes = widget.data.availableSizesForColor(color.code);
    final nextSize = nextSizes.isNotEmpty
        ? nextSizes.firstWhere(
            (size) => size.available,
            orElse: () => nextSizes.first,
          )
        : null;
    setState(() {
      _selectedColorCode = color.code;
      _selectedSizeCode = nextSize?.code;
      _galleryIndex = widget.data.resolveGalleryIndex(
        colorCode: color.code,
        fallbackIndex: _galleryIndex,
      );
    });
    _jumpToCurrentPage();
    _emitSelection();
  }

  void _selectSize(ProductSummarySizeData size) {
    if (!widget.showVariantControls || !size.available) return;
    setState(() {
      _selectedSizeCode = size.code;
    });
    _emitSelection();
  }

  void _handlePageChanged(int index) {
    if (_galleryIndex == index) return;
    setState(() {
      _galleryIndex = index;
      final image = widget.data.galleryImages[index];
      if (image.colorCode?.trim().isNotEmpty == true) {
        _selectedColorCode = image.colorCode;
        final color = widget.data.colors.firstWhere(
          (item) => _sameCode(item.code, image.colorCode),
          orElse: () => widget.data.colors.first,
        );
        final eligibleSizes = widget.data.availableSizesForColor(color.code);
        if (_selectedSizeCode == null ||
            eligibleSizes.every(
              (size) => !_sameCode(size.code, _selectedSizeCode),
            )) {
          _selectedSizeCode = eligibleSizes.isNotEmpty
              ? eligibleSizes.first.code
              : null;
        }
      }
    });
    _emitSelection();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedAppearance =
        widget.appearance ?? ProductSummaryCardAppearance.fromContext(context);
    final currentSelection = _currentSelection();
    final variantLocale = Localizations.localeOf(context);
    final colorGroupLabel = _localizedText(
      variantLocale,
      ar: widget.data.colorGroupLabelAr,
      en: widget.data.colorGroupLabelEn,
    );
    final sizeGroupLabel = _localizedText(
      variantLocale,
      ar: widget.data.sizeGroupLabelAr,
      en: widget.data.sizeGroupLabelEn,
    );
    final heroAspectRatio =
        widget.heroAspectRatio ?? (widget.compact ? 1.45 : 1.12);
    final showGallery = widget.showImage;
    final currentImage = widget.data.resolveGalleryImage(
      colorCode: currentSelection.colorCode,
      fallbackIndex: _galleryIndex,
    );
    final visibleSizes = widget.showVariantControls
        ? widget.data.availableSizesForColor(currentSelection.colorCode)
        : const <ProductSummarySizeData>[];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: resolvedAppearance.borderRadius,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 12 : 16,
            vertical: widget.compact ? 12 : 14,
          ),
          decoration: BoxDecoration(
            borderRadius: resolvedAppearance.borderRadius,
            color: resolvedAppearance.backgroundColor,
            border: Border.all(color: resolvedAppearance.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showGallery) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(widget.compact ? 14 : 16),
                  child: AspectRatio(
                    aspectRatio: heroAspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.interactiveGallery &&
                            widget.data.galleryImages.length > 1)
                          PageView.builder(
                            controller: _pageController,
                            onPageChanged: _handlePageChanged,
                            itemCount: widget.data.galleryImages.length,
                            itemBuilder: (context, index) {
                              return _buildGalleryImage(
                                resolvedAppearance,
                                widget.data.galleryImages[index],
                              );
                            },
                          )
                        else
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: KeyedSubtree(
                              key: ValueKey(
                                '${currentImage?.imageUrl ?? widget.data.imageUrl ?? 'placeholder'}|${currentImage?.imageFile?.name ?? widget.data.imageFile?.name ?? ''}|$_galleryIndex|${_selectedColorCode ?? ''}',
                              ),
                              child: _buildGalleryImage(
                                resolvedAppearance,
                                currentImage ??
                                    ProductSummaryGalleryImageData(
                                      imageUrl: widget.data.imageUrl,
                                      imageFile: widget.data.imageFile,
                                      colorCode: null,
                                      colorLabel: null,
                                      colorHex: null,
                                      isPrimary: true,
                                      sortOrder: 0,
                                    ),
                              ),
                            ),
                          ),
                        if (widget.data.galleryImages.length > 1)
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 10,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                widget.data.galleryImages.length,
                                (index) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  width: _galleryIndex == index ? 20 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _galleryIndex == index
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: widget.compact ? 10 : 12),
              ],
              if (widget.data.categoryLabel?.trim().isNotEmpty == true) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    key: const ValueKey('product-summary-category'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: resolvedAppearance.chipBackgroundColor,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: resolvedAppearance.chipBorderColor,
                      ),
                    ),
                    child: Text(
                      widget.data.categoryLabel!,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 11,
                        color: resolvedAppearance.chipTextColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                widget.data.title,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: resolvedAppearance.titleColor,
                  fontSize: widget.compact ? 15 : 16.5,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (widget.showDescription &&
                  widget.data.description?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  widget.data.description!.trim(),
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  maxLines: widget.compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: resolvedAppearance.bodyColor,
                    fontSize: widget.compact ? 12 : 13,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                textDirection: TextDirection.rtl,
                children: [
                  Flexible(
                    child: Text(
                      _currentPriceText,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: resolvedAppearance.titleColor,
                        fontWeight: FontWeight.w800,
                        fontSize: widget.compact ? 14 : 16,
                      ),
                    ),
                  ),
                  if (widget.data.originalPriceText?.trim().isNotEmpty ==
                      true) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.data.originalPriceText!.trim(),
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: resolvedAppearance.bodyColor,
                          fontSize: widget.compact ? 11.5 : 12.5,
                        ),
                      ),
                    ),
                  ],
                  if (widget.data.discountBadge != null) ...[
                    const SizedBox(width: 6),
                    _buildBadge(resolvedAppearance, widget.data.discountBadge!),
                  ],
                  if (widget.data.availabilityBadge != null) ...[
                    const SizedBox(width: 6),
                    _buildBadge(
                      resolvedAppearance,
                      widget.data.availabilityBadge!,
                    ),
                  ],
                ],
              ),
              if (_limited(
                widget.data.attributeBadges,
                widget.maxAttributeBadges,
              ).isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children:
                      _limited(
                            widget.data.attributeBadges,
                            widget.maxAttributeBadges,
                          )
                          .map(
                            (badge) => _buildBadge(resolvedAppearance, badge),
                          )
                          .toList(growable: false),
                ),
              ],
              if (widget.showDetailedSpecifications &&
                  (widget.data.specificationBadges.isNotEmpty ||
                      widget.data.detailedSpecificationLines.isNotEmpty)) ...[
                const SizedBox(height: 10),
                Text(
                  _localizedText(
                    variantLocale,
                    ar: 'المواصفات الكاملة',
                    en: 'Full specifications',
                  ),
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: resolvedAppearance.bodyColor,
                    fontWeight: FontWeight.w700,
                    fontSize: widget.compact ? 12 : 13,
                  ),
                ),
                const SizedBox(height: 6),
                if (widget.data.detailedSpecificationLines.isNotEmpty) ...[
                  ...widget.data.detailedSpecificationLines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        textDirection: TextDirection.rtl,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.circle, size: 7),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              line,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: resolvedAppearance.bodyColor,
                                fontSize: widget.compact ? 11.5 : 12.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (widget.data.specificationBadges.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: widget.data.specificationBadges
                        .map((badge) => _buildBadge(resolvedAppearance, badge))
                        .toList(growable: false),
                  ),
              ],
              if (widget.showVariantControls &&
                  widget.data.colors.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  colorGroupLabel,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: resolvedAppearance.bodyColor,
                    fontWeight: FontWeight.w700,
                    fontSize: widget.compact ? 12 : 13,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: widget.data.colors
                      .map((color) {
                        final selected = _sameCode(
                          color.code,
                          currentSelection.colorCode,
                        );
                        return _buildColorChip(
                          appearance: resolvedAppearance,
                          color: color,
                          selected: selected,
                        );
                      })
                      .toList(growable: false),
                ),
                if (widget.data.strictVariantSelection &&
                    currentSelection.colorCode == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _localizedText(
                      variantLocale,
                      ar: 'اختر $colorGroupLabel',
                      en: 'Choose $colorGroupLabel',
                    ),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: resolvedAppearance.warningColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
              if (widget.showVariantControls && visibleSizes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  sizeGroupLabel,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: resolvedAppearance.bodyColor,
                    fontWeight: FontWeight.w700,
                    fontSize: widget.compact ? 12 : 13,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: visibleSizes
                      .map((size) {
                        final selected = _sameCode(
                          size.code,
                          currentSelection.sizeCode,
                        );
                        return _buildSizeChip(
                          appearance: resolvedAppearance,
                          size: size,
                          selected: selected,
                        );
                      })
                      .toList(growable: false),
                ),
                if (widget.data.strictVariantSelection &&
                    currentSelection.sizeCode == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _localizedText(
                      variantLocale,
                      ar: 'اختر $sizeGroupLabel',
                      en: 'Choose $sizeGroupLabel',
                    ),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: resolvedAppearance.warningColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
              if (_limited(
                widget.data.variantBadges,
                widget.maxVariantBadges,
              ).isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children:
                      _limited(
                            widget.data.variantBadges,
                            widget.maxVariantBadges,
                          )
                          .map(
                            (badge) => _buildBadge(resolvedAppearance, badge),
                          )
                          .toList(growable: false),
                ),
              ],
              if (_limited(
                widget.data.statusBadges,
                widget.maxStatusBadges,
              ).isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children:
                      _limited(widget.data.statusBadges, widget.maxStatusBadges)
                          .map(
                            (badge) => _buildBadge(resolvedAppearance, badge),
                          )
                          .toList(growable: false),
                ),
              ],
              if (widget.trailing != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: widget.trailing!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGalleryImage(
    ProductSummaryCardAppearance appearance,
    ProductSummaryGalleryImageData image,
  ) {
    final fallback = Container(
      color: Colors.white.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: appearance.bodyColor, size: 44),
    );

    Widget imageWidget;
    if (image.imageFile?.hasBytes == true) {
      imageWidget = Image.memory(image.imageFile!.bytes!, fit: BoxFit.cover);
    } else if (image.imageUrl?.trim().isNotEmpty == true) {
      imageWidget = CachedAppImage(
        imageUrl: image.imageUrl!.trim(),
        cacheIdentity: 'product_summary_${image.imageUrl.hashCode}',
        fit: BoxFit.cover,
        errorWidget: (context, error, stackTrace) => fallback,
      );
    } else {
      imageWidget = fallback;
    }

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.04),
      child: imageWidget,
    );
  }

  Widget _buildColorChip({
    required ProductSummaryCardAppearance appearance,
    required ProductSummaryColorData color,
    required bool selected,
  }) {
    final swatch = _parseVariantSwatch(color.hex) ?? appearance.accentColor;
    return InkWell(
      onTap: color.available ? () => _selectColor(color) : null,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? appearance.accentColor.withValues(alpha: 0.12)
              : appearance.chipBackgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? appearance.accentColor
                : appearance.chipBorderColor,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.rtl,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: swatch,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: color.imageUrl?.trim().isNotEmpty == true
                  ? ClipOval(
                      child: CachedAppImage(
                        imageUrl: color.imageUrl!.trim(),
                        cacheIdentity: 'product_summary_color_${color.code}',
                        fit: BoxFit.cover,
                        errorWidget: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                color.available
                    ? color.label
                    : '${color.label} · ${_localizedText(Localizations.localeOf(context), ar: 'غير متوفر', en: 'Unavailable')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? appearance.titleColor
                      : appearance.chipTextColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeChip({
    required ProductSummaryCardAppearance appearance,
    required ProductSummarySizeData size,
    required bool selected,
  }) {
    return InkWell(
      onTap: size.available ? () => _selectSize(size) : null,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? appearance.accentColor.withValues(alpha: 0.12)
              : appearance.chipBackgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? appearance.accentColor
                : appearance.chipBorderColor,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          size.available
              ? size.label
              : '${size.label} · ${_localizedText(Localizations.localeOf(context), ar: 'غير متوفر', en: 'Unavailable')}',
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: selected ? appearance.titleColor : appearance.chipTextColor,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(
    ProductSummaryCardAppearance appearance,
    ProductSummaryBadgeData badge,
  ) {
    final colors = _badgeColors(appearance, badge.kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: appearance.chipBorderColor),
      ),
      child: Text(
        badge.text,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontSize: 11,
          color: colors.text,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  List<ProductSummaryBadgeData> _limited(
    List<ProductSummaryBadgeData> items,
    int max,
  ) {
    if (max <= 0 || items.isEmpty) return const [];
    return items.take(max).toList(growable: false);
  }

  ({Color background, Color text}) _badgeColors(
    ProductSummaryCardAppearance appearance,
    ProductSummaryBadgeKind kind,
  ) {
    switch (kind) {
      case ProductSummaryBadgeKind.discount:
        return (
          background: appearance.warningColor.withValues(alpha: 0.18),
          text: appearance.warningColor,
        );
      case ProductSummaryBadgeKind.success:
        return (
          background: appearance.successColor.withValues(alpha: 0.16),
          text: appearance.successColor,
        );
      case ProductSummaryBadgeKind.warning:
        return (
          background: appearance.warningColor.withValues(alpha: 0.16),
          text: appearance.warningColor,
        );
      case ProductSummaryBadgeKind.danger:
        return (
          background: appearance.dangerColor.withValues(alpha: 0.16),
          text: appearance.dangerColor,
        );
      case ProductSummaryBadgeKind.variant:
        return (
          background: appearance.accentColor.withValues(alpha: 0.12),
          text: appearance.accentColor,
        );
      case ProductSummaryBadgeKind.status:
      case ProductSummaryBadgeKind.attribute:
        return (
          background: appearance.chipBackgroundColor,
          text: appearance.chipTextColor,
        );
    }
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
