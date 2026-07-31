import 'dart:convert';

import '../../../core/utils/parsers.dart';
import '../../../core/utils/product_offer_pricing.dart';
import 'cart_item_model.dart';
import 'order_item_model.dart';

class OrderItemPresentationEntry {
  final String label;
  final String value;
  final String? hex;

  const OrderItemPresentationEntry({
    required this.label,
    required this.value,
    this.hex,
  });

  bool get isEmpty => label.trim().isEmpty && value.trim().isEmpty;

  String get displayText {
    final left = label.trim();
    final right = value.trim();
    if (left.isEmpty) return right;
    if (right.isEmpty) return left;
    return '$left: $right';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'value': value,
        if (hex != null) 'hex': hex,
      };

  factory OrderItemPresentationEntry.fromAny(dynamic raw) {
    if (raw is String) {
      final text = raw.trim();
      return OrderItemPresentationEntry(label: text, value: text);
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final label = parseString(
        map['label'] ??
            map['labelAr'] ??
            map['label_ar'] ??
            map['groupLabel'] ??
            map['group_label'] ??
            map['optionLabel'] ??
            map['option_label'] ??
            map['title'] ??
            map['name'] ??
            map['code'] ??
            map['key'],
        fallback: '',
      );
      final value = parseString(
        map['value'] ??
            map['valueText'] ??
            map['value_text'] ??
            map['optionLabel'] ??
            map['option_label'] ??
            map['optionCode'] ??
            map['option_code'] ??
            map['code'] ??
            map['text'] ??
            map['description'],
        fallback: '',
      );
      final hex = parseNullableString(
        map['hex'] ?? map['swatchHex'] ?? map['swatch_hex'],
      );
      final normalizedLabel = label.isNotEmpty ? label : value;
      final normalizedValue = value.isNotEmpty ? value : label;
      if (normalizedLabel.isEmpty && normalizedValue.isEmpty) {
        return const OrderItemPresentationEntry(label: '', value: '');
      }
      return OrderItemPresentationEntry(
        label: normalizedLabel,
        value: normalizedValue,
        hex: hex,
      );
    }
    return const OrderItemPresentationEntry(label: '', value: '');
  }
}

class OrderItemPresentationModel {
  final Map<String, dynamic>? displaySnapshotJson;
  final int? productId;
  final String productName;
  final String? productImageUrl;
  final String? thumbnailUrl;
  final String? sku;
  final int? variantId;
  final String? variantName;
  final String? variantSku;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final String currency;
  final OrderItemPresentationEntry? selectedColor;
  final OrderItemPresentationEntry? selectedSize;
  final List<OrderItemPresentationEntry> specs;
  final List<OrderItemPresentationEntry> options;
  final List<OrderItemPresentationEntry> addons;
  final List<OrderItemPresentationEntry> removals;
  final String? userNote;
  final String? activityType;
  final int? storeId;
  final String? storeName;

  const OrderItemPresentationModel({
    required this.displaySnapshotJson,
    required this.productId,
    required this.productName,
    required this.productImageUrl,
    required this.thumbnailUrl,
    required this.sku,
    required this.variantId,
    required this.variantName,
    required this.variantSku,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.currency,
    required this.selectedColor,
    required this.selectedSize,
    required this.specs,
    required this.options,
    required this.addons,
    required this.removals,
    required this.userNote,
    required this.activityType,
    required this.storeId,
    required this.storeName,
  });

  String get displayTitle => productName;

  String? get displayImageUrl {
    final thumb = thumbnailUrl?.trim();
    if (thumb != null && thumb.isNotEmpty) return thumb;
    final image = productImageUrl?.trim();
    if (image != null && image.isNotEmpty) return image;
    return null;
  }

  bool get hasImage => displayImageUrl != null;

  bool get hasNote => userNote?.trim().isNotEmpty == true;

  bool get hasSpecs =>
      specs.isNotEmpty ||
      options.isNotEmpty ||
      addons.isNotEmpty ||
      removals.isNotEmpty ||
      selectedColor != null ||
      selectedSize != null;

  List<OrderItemPresentationEntry> get visibleSpecs {
    final merged = <OrderItemPresentationEntry>[];
    void addEntry(OrderItemPresentationEntry? entry) {
      if (entry == null || entry.isEmpty) return;
      final key =
          '${entry.label.trim().toLowerCase()}|${entry.value.trim().toLowerCase()}';
      if (merged.any(
        (existing) =>
            '${existing.label.trim().toLowerCase()}|${existing.value.trim().toLowerCase()}' ==
            key,
      )) {
        return;
      }
      merged.add(entry);
    }

    for (final entry in specs) {
      addEntry(entry);
    }
    addEntry(selectedColor);
    addEntry(selectedSize);
    return merged.toList(growable: false);
  }

  static List<OrderItemPresentationEntry> _entryList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((item) => OrderItemPresentationEntry.fromAny(item))
          .where((entry) => !entry.isEmpty)
          .toList(growable: false);
    }
    if (raw is Map) {
      final entry = OrderItemPresentationEntry.fromAny(raw);
      return entry.isEmpty ? const <OrderItemPresentationEntry>[] : [entry];
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final entry = OrderItemPresentationEntry.fromAny(raw);
      return entry.isEmpty ? const <OrderItemPresentationEntry>[] : [entry];
    }
    return const <OrderItemPresentationEntry>[];
  }

  static OrderItemPresentationEntry? _entry(dynamic raw) {
    final entry = OrderItemPresentationEntry.fromAny(raw);
    return entry.isEmpty ? null : entry;
  }

  static Map<String, dynamic>? _snapshotFromRaw(Map<String, dynamic> raw) {
    final snapshotRaw = raw['display_snapshot_json'] ??
        raw['displaySnapshotJson'] ??
        raw['display_snapshot'] ??
        raw['displaySnapshot'];
    if (snapshotRaw is Map) return Map<String, dynamic>.from(snapshotRaw);
    if (snapshotRaw is String) {
      try {
        final parsed = jsonDecode(snapshotRaw);
        if (parsed is Map) return Map<String, dynamic>.from(parsed);
      } catch (_) {
        return null;
      }
    }
    if (raw['version'] != null && raw['productName'] != null) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  factory OrderItemPresentationModel.fromOrderItemModel(
    OrderItemModel item, {
    Map<String, dynamic>? orderContext,
  }) {
    return OrderItemPresentationModel.fromRawMap(
      <String, dynamic>{
        'id': item.id,
        'order_id': item.orderId,
        'product_id': item.productId,
        'product_name': item.productName,
        'base_unit_price': item.baseUnitPrice,
        'unit_price': item.unitPrice,
        'quantity': item.quantity,
        'selected_modifiers_json': item.selectedModifiers,
        'selected_variant_json': item.selectedVariant,
        'selected_variant_options_json': item.selectedVariantSelections,
        'variant_price_delta_total': item.variantPriceDeltaTotal,
        'line_discount_total': item.lineDiscountTotal,
        'line_total': item.lineTotal,
        'pricing_breakdown_json': item.pricingBreakdown,
        'display_snapshot_json': item.displaySnapshotJson,
      },
      orderContext: orderContext,
    );
  }

  factory OrderItemPresentationModel.fromCartItemModel(
    CartItemModel item, {
    Map<String, dynamic>? orderContext,
  }) {
    final pricing = computeProductOfferPricing(
      item.product,
      quantity: item.quantity,
      unitPriceOverride: variantSelectionUnitPriceOverride(
        item.product,
        variantId: item.selectedVariantId,
        selections: item.selectedVariantSelections,
      ),
    );
    final modifiersUnitTotal = item.selectedModifiers.fold<double>(
      0,
      (sum, modifier) =>
          sum + parseDouble(modifier['priceDelta'] ?? modifier['price']),
    );
    final unitPrice = pricing.unitPrice + modifiersUnitTotal;
    final lineTotal = pricing.lineTotal + (modifiersUnitTotal * item.quantity);
    final selectedVariantSelections = item.selectedVariantSelections;
    final color = _entry(
      selectedVariantSelections.firstWhere(
        (entry) {
          final group = parseString(entry['groupCode'] ?? entry['groupLabel']);
          return group.toLowerCase().contains('color') || group.contains('لون');
        },
        orElse: () => const <String, dynamic>{},
      ),
    );
    final size = _entry(
      selectedVariantSelections.firstWhere(
        (entry) {
          final group = parseString(entry['groupCode'] ?? entry['groupLabel']);
          return group.toLowerCase().contains('size') || group.contains('مقاس');
        },
        orElse: () => const <String, dynamic>{},
      ),
    );
    final specs = selectedVariantSelections
        .map((entry) => OrderItemPresentationEntry.fromAny(entry))
        .where((entry) => !entry.isEmpty)
        .toList(growable: false);
    final snapshot = <String, dynamic>{
      'version': 1,
      'productId': item.product.id,
      'productName': item.product.name,
      'productImageUrl': item.product.displayImageUrl ?? item.product.imageUrl,
      'thumbnailUrl': item.product.displayImageUrl ?? item.product.imageUrl,
      'sku': null,
      'variantId': item.selectedVariantId,
      'variantName': item.variantSelectionsLabel.isNotEmpty
          ? item.variantSelectionsLabel
          : null,
      'variantSku': null,
      'quantity': item.quantity,
      'unitPrice': unitPrice,
      'lineTotal': lineTotal,
      'currency': 'IQD',
      'selectedColor': color?.toJson(),
      'selectedSize': size?.toJson(),
      'specs': specs.map((entry) => entry.toJson()).toList(growable: false),
      'options': item.selectedModifiers
          .map((entry) => OrderItemPresentationEntry.fromAny(entry).toJson())
          .where((entry) => (entry['label'] as String?)?.isNotEmpty == true || (entry['value'] as String?)?.isNotEmpty == true)
          .toList(growable: false),
      'addons': const <dynamic>[],
      'removals': const <dynamic>[],
      'userNote': null,
      'activityType': null,
      'storeId': item.merchantId,
      'storeName': item.merchantName,
    };
    return OrderItemPresentationModel.fromRawMap(
      snapshot,
      orderContext: orderContext,
    );
  }

  factory OrderItemPresentationModel.fromRawMap(
    Map<String, dynamic> raw, {
    Map<String, dynamic>? orderContext,
  }) {
    final map = Map<String, dynamic>.from(raw);
    final snapshot = _snapshotFromRaw(map);
    final order = orderContext == null ? const <String, dynamic>{} : Map<String, dynamic>.from(orderContext);

    if (snapshot != null) {
      final normalizedSpecs = _entryList(snapshot['specs']);
      final selectedColor = _entry(snapshot['selectedColor']);
      final selectedSize = _entry(snapshot['selectedSize']);
      return OrderItemPresentationModel(
        displaySnapshotJson: snapshot,
        productId: parseNullableInt(snapshot['productId'] ?? snapshot['product_id']),
        productName: parseString(snapshot['productName'] ?? snapshot['product_name']),
        productImageUrl: parseNullableString(snapshot['productImageUrl'] ?? snapshot['product_image_url']),
        thumbnailUrl: parseNullableString(snapshot['thumbnailUrl'] ?? snapshot['thumbnail_url']) ??
            parseNullableString(snapshot['productImageUrl'] ?? snapshot['product_image_url']),
        sku: parseNullableString(snapshot['sku']),
        variantId: parseNullableInt(snapshot['variantId'] ?? snapshot['variant_id']),
        variantName: parseNullableString(snapshot['variantName'] ?? snapshot['variant_name']),
        variantSku: parseNullableString(snapshot['variantSku'] ?? snapshot['variant_sku']),
        quantity: parseInt(snapshot['quantity']),
        unitPrice: parseDouble(snapshot['unitPrice'] ?? snapshot['unit_price']),
        lineTotal: parseDouble(snapshot['lineTotal'] ?? snapshot['line_total']),
        currency: parseString(snapshot['currency'], fallback: 'IQD'),
        selectedColor: selectedColor,
        selectedSize: selectedSize,
        specs: normalizedSpecs,
        options: _entryList(snapshot['options']),
        addons: _entryList(snapshot['addons']),
        removals: _entryList(snapshot['removals']),
        userNote: parseNullableString(snapshot['userNote'] ?? snapshot['user_note']),
        activityType: parseNullableString(snapshot['activityType'] ?? snapshot['activity_type']),
        storeId: parseNullableInt(snapshot['storeId'] ?? snapshot['store_id']),
        storeName: parseNullableString(snapshot['storeName'] ?? snapshot['store_name']),
      );
    }

    final selectedVariant = map['selected_variant_json'] ?? map['selectedVariant'];
    final selectedVariantMap = selectedVariant is Map
        ? Map<String, dynamic>.from(selectedVariant)
        : const <String, dynamic>{};
    final selectedVariantSelections = _entryList(
      map['selected_variant_options_json'] ??
          map['selectedVariantOptions'] ??
          map['selectedVariantSelections'] ??
          selectedVariantMap['selections'],
    );
    final selectedModifiers = _entryList(
      map['selected_modifiers_json'] ?? map['selectedModifiers'],
    );
    final selectedColor = _entry(
      selectedVariantMap['colorLabel'] != null
          ? <String, dynamic>{
              'label': selectedVariantMap['colorLabel'],
              'value': selectedVariantMap['colorLabel'],
              'hex': selectedVariantMap['colorHex'],
            }
          : selectedVariantSelections.firstWhere(
              (entry) => entry.label.toLowerCase().contains('color') ||
                  entry.value.toLowerCase().contains('color') ||
                  entry.label.contains('لون') ||
                  entry.value.contains('لون'),
              orElse: () => const OrderItemPresentationEntry(label: '', value: ''),
            ),
    );
    final selectedSize = _entry(
      selectedVariantMap['sizeLabel'] != null
          ? <String, dynamic>{
              'label': selectedVariantMap['sizeLabel'],
              'value': selectedVariantMap['sizeLabel'],
            }
          : selectedVariantSelections.firstWhere(
              (entry) => entry.label.toLowerCase().contains('size') ||
                  entry.value.toLowerCase().contains('size') ||
                  entry.label.contains('مقاس') ||
                  entry.value.contains('مقاس'),
              orElse: () => const OrderItemPresentationEntry(label: '', value: ''),
            ),
    );
    final specs = selectedVariantSelections.isNotEmpty
        ? selectedVariantSelections
        : [selectedColor, selectedSize].whereType<OrderItemPresentationEntry>().toList(growable: false);
    final combinedOptions = <OrderItemPresentationEntry>[
      ..._entryList(map['options']),
      ...selectedModifiers,
    ];
    final resolvedStoreId = parseNullableInt(
      map['store_id'] ??
          map['storeId'] ??
          order['merchant_id'] ??
          order['merchantId'] ??
          order['store_id'] ??
          order['storeId'],
    );
    final resolvedStoreName = parseNullableString(
      map['store_name'] ??
          map['storeName'] ??
          order['merchant_name'] ??
          order['merchantName'] ??
          order['store_name'] ??
          order['storeName'],
    );
    final resolvedActivityType = parseNullableString(
      map['activity_type'] ??
          map['activityType'] ??
          order['merchant_activity_type'] ??
          order['merchantActivityType'] ??
          order['activity_type'] ??
          order['activityType'],
    );

    return OrderItemPresentationModel(
      displaySnapshotJson: snapshot ?? map,
      productId: parseNullableInt(
        map['product_id'] ?? map['productId'] ?? order['product_id'] ?? order['productId'],
      ),
      productName: parseString(
        map['product_name'] ?? map['productName'] ?? snapshot?['productName'] ?? snapshot?['product_name'],
        fallback: 'Product',
      ),
      productImageUrl: parseNullableString(
        map['product_image_url'] ??
            map['productImageUrl'] ??
            snapshot?['productImageUrl'] ??
            snapshot?['product_image_url'],
      ),
      thumbnailUrl: parseNullableString(
            map['thumbnail_url'] ??
                map['thumbnailUrl'] ??
                snapshot?['thumbnailUrl'] ??
                snapshot?['thumbnail_url'],
          ) ??
          parseNullableString(
            map['product_image_url'] ??
                map['productImageUrl'] ??
                snapshot?['productImageUrl'] ??
                snapshot?['product_image_url'],
          ),
      sku: parseNullableString(
        map['sku'] ?? map['productSku'] ?? selectedVariantMap['sku'],
      ),
      variantId: parseNullableInt(
        map['variant_id'] ??
            map['variantId'] ??
            selectedVariantMap['variantId'] ??
            selectedVariantMap['variant_id'],
      ),
      variantName: parseNullableString(
        map['variant_name'] ??
            map['variantName'] ??
            selectedVariantMap['variantName'] ??
            selectedVariantMap['signature'],
      ),
      variantSku: parseNullableString(
        map['variant_sku'] ?? map['variantSku'] ?? selectedVariantMap['sku'],
      ),
      quantity: parseInt(map['quantity'] ?? snapshot?['quantity']),
      unitPrice: parseDouble(
        map['unit_price'] ?? map['unitPrice'] ?? snapshot?['unitPrice'],
      ),
      lineTotal: parseDouble(
        map['line_total'] ?? map['lineTotal'] ?? snapshot?['lineTotal'],
      ),
      currency: parseString(
        map['currency'] ?? snapshot?['currency'],
        fallback: 'IQD',
      ),
      selectedColor: selectedColor,
      selectedSize: selectedSize,
      specs: specs,
      options: combinedOptions,
      addons: _entryList(map['addons'] ?? snapshot?['addons']),
      removals: _entryList(map['removals'] ?? snapshot?['removals']),
      userNote: parseNullableString(
        map['user_note'] ?? map['userNote'] ?? snapshot?['userNote'],
      ),
      activityType: resolvedActivityType,
      storeId: resolvedStoreId,
      storeName: resolvedStoreName,
    );
  }
}
