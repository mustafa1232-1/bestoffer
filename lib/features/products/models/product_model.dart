import 'dart:convert';

import '../../../core/utils/parsers.dart';

class ProductAttributeModel {
  final String code;
  final String? labelAr;
  final String? labelEn;
  final String valueText;
  final String? valueUnit;
  final bool showInCard;
  final bool showInDetails;
  final int sortOrder;
  final Map<String, dynamic> metadata;

  const ProductAttributeModel({
    required this.code,
    required this.labelAr,
    required this.labelEn,
    required this.valueText,
    required this.valueUnit,
    required this.showInCard,
    required this.showInDetails,
    required this.sortOrder,
    required this.metadata,
  });

  factory ProductAttributeModel.fromJson(Map<String, dynamic> j) {
    return ProductAttributeModel(
      code: parseString(j['code'] ?? j['attribute_code'] ?? j['attributeCode']),
      labelAr: parseNullableString(j['label_ar'] ?? j['labelAr']),
      labelEn: parseNullableString(j['label_en'] ?? j['labelEn']),
      valueText: parseString(j['value_text'] ?? j['valueText']),
      valueUnit: parseNullableString(j['value_unit'] ?? j['valueUnit']),
      showInCard: parseBool(j['show_in_card'] ?? j['showInCard']),
      showInDetails: j['show_in_details'] == null
          ? true
          : parseBool(j['show_in_details'] ?? j['showInDetails']),
      sortOrder: parseInt(j['sort_order'] ?? j['sortOrder'], fallback: 0),
      metadata: _toMap(j['metadata_json'] ?? j['metadata']),
    );
  }

  String get title {
    return (labelAr?.trim().isNotEmpty == true ? labelAr : labelEn)?.trim() ??
        code;
  }
}

class ProductVariantOptionModel {
  final int optionId;
  final String code;
  final String? labelAr;
  final String? labelEn;
  final String? swatchHex;
  final double priceDelta;
  final String? imageUrl;
  final bool isAvailable;
  final int sortOrder;
  final Map<String, dynamic> metadata;

  const ProductVariantOptionModel({
    required this.optionId,
    required this.code,
    required this.labelAr,
    required this.labelEn,
    required this.swatchHex,
    required this.priceDelta,
    required this.imageUrl,
    required this.isAvailable,
    required this.sortOrder,
    required this.metadata,
  });

  factory ProductVariantOptionModel.fromJson(Map<String, dynamic> j) {
    return ProductVariantOptionModel(
      optionId: parseInt(j['option_id'] ?? j['optionId'], fallback: 0),
      code: parseString(j['code'] ?? j['option_code'] ?? j['optionCode']),
      labelAr: parseNullableString(j['label_ar'] ?? j['labelAr']),
      labelEn: parseNullableString(j['label_en'] ?? j['labelEn']),
      swatchHex: parseNullableString(j['swatch_hex'] ?? j['swatchHex']),
      priceDelta: parseDouble(j['price_delta'] ?? j['priceDelta']),
      imageUrl: parseNullableString(
        j['image_url'] ??
            j['imageUrl'] ??
            j['color_image_url'] ??
            j['colorImageUrl'],
      ),
      isAvailable: j['is_available'] == null
          ? true
          : parseBool(j['is_available'] ?? j['isAvailable']),
      sortOrder: parseInt(j['sort_order'] ?? j['sortOrder'], fallback: 0),
      metadata: _toMap(j['metadata_json'] ?? j['metadata']),
    );
  }

  String get title {
    return (labelAr?.trim().isNotEmpty == true ? labelAr : labelEn)?.trim() ??
        code;
  }
}

class ProductVariantGroupModel {
  final int groupId;
  final String code;
  final String? labelAr;
  final String? labelEn;
  final String displayMode;
  final String selectionMode;
  final bool required;
  final int sortOrder;
  final Map<String, dynamic> metadata;
  final List<ProductVariantOptionModel> options;

  const ProductVariantGroupModel({
    required this.groupId,
    required this.code,
    required this.labelAr,
    required this.labelEn,
    required this.displayMode,
    required this.selectionMode,
    required this.required,
    required this.sortOrder,
    required this.metadata,
    required this.options,
  });

  factory ProductVariantGroupModel.fromJson(Map<String, dynamic> j) {
    final rawOptions = _toList(j['options']);
    return ProductVariantGroupModel(
      groupId: parseInt(j['group_id'] ?? j['groupId'], fallback: 0),
      code: parseString(j['code'] ?? j['group_code'] ?? j['groupCode']),
      labelAr: parseNullableString(j['label_ar'] ?? j['labelAr']),
      labelEn: parseNullableString(j['label_en'] ?? j['labelEn']),
      displayMode: parseString(
        j['display_mode'] ?? j['displayMode'],
        fallback: 'chips',
      ),
      selectionMode: parseString(
        j['selection_mode'] ?? j['selectionMode'],
        fallback: 'single',
      ),
      required: j['required'] == null ? true : parseBool(j['required']),
      sortOrder: parseInt(j['sort_order'] ?? j['sortOrder'], fallback: 0),
      metadata: _toMap(j['metadata_json'] ?? j['metadata']),
      options: rawOptions
          .map(
            (entry) => ProductVariantOptionModel.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  String get title {
    return (labelAr?.trim().isNotEmpty == true ? labelAr : labelEn)?.trim() ??
        code;
  }
}

class ProductVariantModel {
  final int? id;
  final String signature;
  final List<Map<String, String>> selections;
  final String? sku;
  final String? barcode;
  final String? material;
  final double? priceOverride;
  final double? discountedPriceOverride;
  final int stockQuantity;
  final String? imageUrl;
  final bool isAvailable;
  final String? unavailableReason;
  final DateTime? unavailableUntil;
  final int sortOrder;
  final Map<String, dynamic> metadata;

  const ProductVariantModel({
    this.id,
    required this.signature,
    required this.selections,
    this.sku,
    this.barcode,
    this.material,
    this.priceOverride,
    this.discountedPriceOverride,
    required this.stockQuantity,
    this.imageUrl,
    required this.isAvailable,
    this.unavailableReason,
    this.unavailableUntil,
    required this.sortOrder,
    required this.metadata,
  });

  factory ProductVariantModel.fromJson(Map<String, dynamic> j) {
    final selections = _toList(j['selections'] ?? j['selections_json'])
        .whereType<Map>()
        .map(
          (entry) => <String, String>{
            'groupCode': parseString(entry['groupCode'] ?? entry['group_code']),
            'optionCode': parseString(
              entry['optionCode'] ?? entry['option_code'],
            ),
          },
        )
        .where(
          (entry) =>
              entry['groupCode']!.isNotEmpty && entry['optionCode']!.isNotEmpty,
        )
        .toList(growable: false);
    final signatureParts =
        selections
            .map((entry) => '${entry['groupCode']}:${entry['optionCode']}')
            .toList()
          ..sort();
    return ProductVariantModel(
      id: j['id'] == null ? null : parseInt(j['id']),
      signature: parseString(
        j['signature'],
        fallback: signatureParts.join('|'),
      ),
      selections: selections,
      sku: parseNullableString(j['sku']),
      barcode: parseNullableString(j['barcode']),
      material: parseNullableString(j['material']),
      priceOverride: _parseNullableDouble(
        j['price_override'] ?? j['priceOverride'],
      ),
      discountedPriceOverride: _parseNullableDouble(
        j['discounted_price_override'] ?? j['discountedPriceOverride'],
      ),
      stockQuantity: parseInt(j['stock_quantity'] ?? j['stockQuantity']),
      imageUrl: parseNullableString(j['image_url'] ?? j['imageUrl']),
      isAvailable: j['is_available'] == null
          ? parseBool(j['isAvailable'] ?? true)
          : parseBool(j['is_available']),
      unavailableReason: parseNullableString(
        j['unavailable_reason'] ?? j['unavailableReason'],
      ),
      unavailableUntil: _parseNullableDateTime(
        j['unavailable_until'] ?? j['unavailableUntil'],
      ),
      sortOrder: parseInt(j['sort_order'] ?? j['sortOrder']),
      metadata: _toMap(j['metadata_json'] ?? j['metadata']),
    );
  }

  bool get inStock => isAvailable && stockQuantity > 0;
}

class ProductMediaModel {
  final int? id;
  final String imageUrl;
  final String? altText;
  final bool isPrimary;
  final int sortOrder;
  final String? variantGroupCode;
  final String? variantOptionCode;
  final Map<String, dynamic> metadata;

  const ProductMediaModel({
    required this.id,
    required this.imageUrl,
    required this.altText,
    required this.isPrimary,
    required this.sortOrder,
    required this.variantGroupCode,
    required this.variantOptionCode,
    required this.metadata,
  });

  factory ProductMediaModel.fromJson(Map<String, dynamic> j) {
    return ProductMediaModel(
      id: j['id'] == null ? null : parseInt(j['id']),
      imageUrl: parseString(j['image_url'] ?? j['imageUrl']),
      altText: parseNullableString(j['alt_text'] ?? j['altText']),
      isPrimary: j['is_primary'] == null
          ? false
          : parseBool(j['is_primary'] ?? j['isPrimary']),
      sortOrder: parseInt(j['sort_order'] ?? j['sortOrder'], fallback: 0),
      variantGroupCode: parseNullableString(
        j['variant_group_code'] ?? j['variantGroupCode'],
      ),
      variantOptionCode: parseNullableString(
        j['variant_option_code'] ?? j['variantOptionCode'],
      ),
      metadata: _toMap(j['metadata_json'] ?? j['metadata']),
    );
  }
}

class ProductModel {
  final int id;
  final int merchantId;
  final int? categoryId;
  final String? categoryName;
  final int? categorySortOrder;
  final String name;
  final String? description;
  final double price;
  final double? discountedPrice;
  final String? imageUrl;
  final bool freeDelivery;
  final String? offerLabel;
  final bool requiresPrescription;
  final bool requiresReview;
  final int? activeOfferId;
  final String? activeOfferType;
  final String? activeOfferTitle;
  final double? activeOfferDiscountValue;
  final int? activeOfferBuyQuantity;
  final int? activeOfferGetQuantity;
  final bool isAvailable;
  final String? unavailableReason;
  final DateTime? unavailableUntil;
  final bool trackStock;
  final String? stockMode;
  final int sortOrder;
  final List<ProductAttributeModel> attributes;
  final List<ProductAttributeModel> summaryAttributes;
  final List<ProductVariantGroupModel> variantGroups;
  final List<ProductVariantModel> variants;
  final List<ProductMediaModel> media;
  final ProductMediaModel? primaryMedia;
  final Map<String, dynamic>? metadata;
  final bool hasVariants;
  final int? stockQuantity;

  const ProductModel({
    required this.id,
    required this.merchantId,
    this.categoryId,
    this.categoryName,
    this.categorySortOrder,
    required this.name,
    this.description,
    required this.price,
    this.discountedPrice,
    this.imageUrl,
    required this.freeDelivery,
    this.offerLabel,
    this.requiresPrescription = false,
    this.requiresReview = false,
    this.activeOfferId,
    this.activeOfferType,
    this.activeOfferTitle,
    this.activeOfferDiscountValue,
    this.activeOfferBuyQuantity,
    this.activeOfferGetQuantity,
    required this.isAvailable,
    this.unavailableReason,
    this.unavailableUntil,
    this.trackStock = false,
    this.stockMode,
    required this.sortOrder,
    this.attributes = const [],
    this.summaryAttributes = const [],
    this.variantGroups = const [],
    this.variants = const [],
    this.media = const [],
    this.primaryMedia,
    this.metadata,
    this.hasVariants = false,
    this.stockQuantity,
  });

  factory ProductModel.fromJson(Map<String, dynamic> j) {
    final attributes = _parseAttributes(j);
    final summaryAttributes = _parseSummaryAttributes(j, attributes);
    final variantGroups = _parseVariantGroups(j);
    final variants = _parseVariants(j);
    final media = _parseMedia(j);
    final primaryMedia = _parsePrimaryMedia(j, media);
    final imageUrl =
        parseNullableString(j['image_url'] ?? j['imageUrl']) ??
        primaryMedia?.imageUrl;
    final metadata = _toMap(
      j['metadata_json'] ?? j['metadataJson'] ?? j['metadata'],
    );

    return ProductModel(
      id: parseInt(j['id']),
      merchantId: parseInt(j['merchant_id'] ?? j['merchantId']),
      categoryId: _parseNullableInt(j['category_id'] ?? j['categoryId']),
      categoryName: parseNullableString(
        j['category_name'] ?? j['categoryName'],
      ),
      categorySortOrder: _parseNullableInt(
        j['category_sort_order'] ?? j['categorySortOrder'],
      ),
      name: parseString(j['name']),
      description: parseNullableString(j['description']),
      price: parseDouble(j['price']),
      discountedPrice: _parseNullableDouble(
        j['discounted_price'] ?? j['discountedPrice'],
      ),
      imageUrl: imageUrl,
      freeDelivery: j['free_delivery'] ?? j['freeDelivery'] ?? false,
      offerLabel: parseNullableString(j['offer_label'] ?? j['offerLabel']),
      requiresPrescription: parseBool(
        j['requires_prescription'] ?? j['requiresPrescription'],
      ),
      requiresReview: parseBool(j['requires_review'] ?? j['requiresReview']),
      activeOfferId: _parseNullableInt(
        j['active_offer_id'] ?? j['activeOfferId'],
      ),
      activeOfferType: parseNullableString(
        j['active_offer_type'] ?? j['activeOfferType'],
      ),
      activeOfferTitle: parseNullableString(
        j['active_offer_title'] ?? j['activeOfferTitle'],
      ),
      activeOfferDiscountValue: _parseNullableDouble(
        j['active_offer_discount_value'] ?? j['activeOfferDiscountValue'],
      ),
      activeOfferBuyQuantity: _parseNullableInt(
        j['active_offer_buy_quantity'] ?? j['activeOfferBuyQuantity'],
      ),
      activeOfferGetQuantity: _parseNullableInt(
        j['active_offer_get_quantity'] ?? j['activeOfferGetQuantity'],
      ),
      isAvailable: j['is_available'] == null
          ? parseBool(j['isAvailable'] ?? true)
          : parseBool(j['is_available']),
      unavailableReason: parseNullableString(
        j['unavailable_reason'] ?? j['unavailableReason'],
      ),
      unavailableUntil: _parseNullableDateTime(
        j['unavailable_until'] ?? j['unavailableUntil'],
      ),
      trackStock: parseBool(
        j['track_stock'] ??
            j['trackStock'] ??
            j['inventory_enabled'] ??
            j['inventoryEnabled'] ??
            false,
      ),
      stockMode: parseNullableString(j['stock_mode'] ?? j['stockMode']),
      sortOrder: parseInt(j['sort_order'] ?? j['sortOrder']),
      attributes: attributes,
      summaryAttributes: summaryAttributes,
      variantGroups: variantGroups,
      variants: variants,
      media: media,
      primaryMedia: primaryMedia,
      metadata: metadata,
      hasVariants:
          (j['has_variants'] ?? j['hasVariants'] ?? variantGroups.isNotEmpty) ==
              true ||
          variantGroups.isNotEmpty,
      stockQuantity:
          (j['stock_quantity'] ??
                  j['stockQuantity'] ??
                  j['inventory_quantity'] ??
                  j['inventoryQuantity']) ==
              null
          ? null
          : parseInt(
              j['stock_quantity'] ??
                  j['stockQuantity'] ??
                  j['inventory_quantity'] ??
                  j['inventoryQuantity'],
            ),
    );
  }

  bool get hasActiveOffer => activeOfferId != null;

  bool get requiresPharmacyConversation =>
      requiresPrescription || requiresReview;

  bool get isBuyXGetYOffer => activeOfferType == 'buy_x_get_y';

  bool get hasDiscount =>
      discountedPrice != null &&
      discountedPrice! > 0 &&
      discountedPrice! < price;

  int? get discountPercent {
    if (!hasDiscount || price <= 0) return null;
    return ((1 - (discountedPrice! / price)) * 100).round();
  }

  String? get displayImageUrl => primaryMedia?.imageUrl ?? imageUrl;

  bool get _isTrackedStock {
    final mode = stockMode?.trim().toLowerCase();
    if (mode == 'tracked') return true;
    if (mode == 'untracked') return false;
    return trackStock;
  }

  bool get isStockTracked => _isTrackedStock;

  bool canOrderVariant(ProductVariantModel variant) {
    if (!isAvailable || !variant.isAvailable) return false;
    if (!isStockTracked) return true;
    return variant.stockQuantity > 0;
  }

  ProductVariantModel? variantForSelections(Map<String, String> selections) {
    if (variants.isEmpty) return null;
    final parts =
        selections.entries
            .map(
              (entry) =>
                  '${entry.key.toLowerCase()}:${entry.value.toLowerCase()}',
            )
            .toList()
          ..sort();
    final signature = parts.join('|');
    for (final variant in variants) {
      if (variant.signature.toLowerCase() == signature) return variant;
    }
    return null;
  }

  ProductVariantModel? variantForSelectionEntries(
    List<Map<String, dynamic>> selections,
  ) {
    if (selections.isEmpty) return null;
    final normalized = <String, String>{};
    for (final entry in selections) {
      final groupCode = parseNullableString(
        entry['groupCode'] ?? entry['group_code'] ?? entry['group'],
      )?.trim().toLowerCase();
      final optionCode = parseNullableString(
        entry['optionCode'] ?? entry['option_code'] ?? entry['option'],
      )?.trim().toLowerCase();
      if (groupCode == null || groupCode.isEmpty) continue;
      if (optionCode == null || optionCode.isEmpty) continue;
      normalized[groupCode] = optionCode;
    }
    if (normalized.isEmpty) return null;
    return variantForSelections(normalized);
  }

  bool get isInStock {
    return canBeOrdered;
  }

  bool get isOrderable => canBeOrdered;

  bool get canBeOrdered {
    if (!isAvailable) return false;
    if (variants.isNotEmpty) {
      return variants.any((variant) => canOrderVariant(variant));
    }
    if (!isStockTracked) return true;
    return stockQuantity != null && stockQuantity! > 0;
  }
}

List<ProductAttributeModel> _parseAttributes(Map<String, dynamic> j) {
  final raw = _toList(j['attributes']).isNotEmpty
      ? _toList(j['attributes'])
      : _toList(j['richAttributes']);
  return raw
      .map(
        (entry) => ProductAttributeModel.fromJson(
          Map<String, dynamic>.from(entry as Map),
        ),
      )
      .toList(growable: false);
}

List<ProductAttributeModel> _parseSummaryAttributes(
  Map<String, dynamic> j,
  List<ProductAttributeModel> attributes,
) {
  final raw =
      j['summary_attributes'] ?? j['summaryAttributes'] ?? j['highlights'];
  if (raw is List) {
    return raw
        .map(
          (entry) => ProductAttributeModel.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .where((attr) => attr.showInCard)
        .toList(growable: false);
  }
  return attributes.where((attr) => attr.showInCard).toList(growable: false);
}

List<ProductVariantGroupModel> _parseVariantGroups(Map<String, dynamic> j) {
  final raw = _toList(j['variant_groups']).isNotEmpty
      ? _toList(j['variant_groups'])
      : _toList(j['variantGroups']);
  return raw
      .map(
        (entry) => ProductVariantGroupModel.fromJson(
          Map<String, dynamic>.from(entry as Map),
        ),
      )
      .toList(growable: false);
}

List<ProductVariantModel> _parseVariants(Map<String, dynamic> j) {
  return _toList(j['variants'])
      .whereType<Map>()
      .map(
        (entry) =>
            ProductVariantModel.fromJson(Map<String, dynamic>.from(entry)),
      )
      .toList(growable: false);
}

List<ProductMediaModel> _parseMedia(Map<String, dynamic> j) {
  final raw = _toList(j['media']);
  return raw
      .map(
        (entry) =>
            ProductMediaModel.fromJson(Map<String, dynamic>.from(entry as Map)),
      )
      .toList(growable: false);
}

ProductMediaModel? _parsePrimaryMedia(
  Map<String, dynamic> j,
  List<ProductMediaModel> media,
) {
  final primaryRaw = j['primary_media'] ?? j['primaryMedia'];
  if (primaryRaw is Map) {
    return ProductMediaModel.fromJson(Map<String, dynamic>.from(primaryRaw));
  }
  for (final entry in media) {
    if (entry.isPrimary) return entry;
  }
  return media.isNotEmpty ? media.first : null;
}

Map<String, dynamic> _toMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

int? _parseNullableInt(dynamic value) {
  if (value == null) return null;
  final parsed = parseInt(value, fallback: 0);
  if (parsed <= 0) return null;
  return parsed;
}

double? _parseNullableDouble(dynamic value) {
  if (value == null) return null;
  final parsed = parseDouble(value);
  if (parsed == 0 && value != 0 && value != '0' && value != 0.0) {
    return null;
  }
  return parsed;
}

List<dynamic> _toList(dynamic value) {
  if (value is List) return value;
  final parsed = _parseJsonMaybe(value, null);
  if (parsed is List) return parsed;
  return const [];
}

dynamic _parseJsonMaybe(dynamic value, [dynamic fallback]) {
  if (value == null || value == '') return fallback;
  if (value is Map || value is List) return value;
  if (value is! String) return fallback;
  try {
    return jsonDecode(value);
  } catch (_) {
    return fallback;
  }
}

DateTime? _parseNullableDateTime(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
