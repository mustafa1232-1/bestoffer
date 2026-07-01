import '../../../core/utils/parsers.dart';

class OrderItemModel {
  final int id;
  final int orderId;
  final int? productId;
  final String productName;
  final double baseUnitPrice;
  final double unitPrice;
  final int quantity;
  final List<Map<String, dynamic>> selectedModifiers;
  final Map<String, dynamic>? selectedVariant;
  final List<Map<String, dynamic>> selectedVariantSelections;
  final List<Map<String, dynamic>> selectedVariantOptions;
  final double variantPriceDeltaTotal;
  final double lineDiscountTotal;
  final double lineTotal;
  final Map<String, dynamic>? pricingBreakdown;

  const OrderItemModel({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.baseUnitPrice,
    required this.unitPrice,
    required this.quantity,
    required this.selectedModifiers,
    required this.selectedVariant,
    required this.selectedVariantSelections,
    required this.selectedVariantOptions,
    required this.variantPriceDeltaTotal,
    required this.lineDiscountTotal,
    required this.lineTotal,
    required this.pricingBreakdown,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> j) {
    final pricingRaw = j['pricing_breakdown_json'] ?? j['pricingBreakdown'];
    final selectedModifiers = _asMapList(
      j['selected_modifiers_json'] ?? j['selectedModifiers'],
    );
    final selectedVariantRaw =
        j['selected_variant_json'] ?? j['selectedVariant'];
    final selectedVariantSelections = _asMapList(
      j['selected_variant_options_json'] ??
          j['selectedVariantOptions'] ??
          j['selectedVariantSelections'] ??
          (selectedVariantRaw is Map ? selectedVariantRaw['selections'] : null),
    );
    final selectedVariant = selectedVariantRaw is Map
        ? Map<String, dynamic>.from(selectedVariantRaw)
        : null;

    return OrderItemModel(
      id: parseInt(j['id']),
      orderId: parseInt(j['order_id'] ?? j['orderId']),
      productId: j['product_id'] == null ? null : parseInt(j['product_id']),
      productName: parseString(j['product_name'] ?? j['productName']),
      baseUnitPrice: parseDouble(
        j['base_unit_price'] ?? j['baseUnitPrice'] ?? j['unit_price'],
      ),
      unitPrice: parseDouble(j['unit_price'] ?? j['unitPrice']),
      quantity: parseInt(j['quantity']),
      selectedModifiers: selectedModifiers,
      selectedVariant: selectedVariant,
      selectedVariantSelections: selectedVariantSelections,
      selectedVariantOptions: selectedVariantSelections,
      variantPriceDeltaTotal: parseDouble(
        j['variant_price_delta_total'] ?? j['variantPriceDeltaTotal'],
      ),
      lineDiscountTotal: parseDouble(
        j['line_discount_total'] ?? j['lineDiscountTotal'],
      ),
      lineTotal: parseDouble(j['line_total'] ?? j['lineTotal']),
      pricingBreakdown: pricingRaw is Map
          ? Map<String, dynamic>.from(pricingRaw)
          : null,
    );
  }

  bool get hasVariantSelections => selectedVariantSelections.isNotEmpty;

  String get variantSelectionsLabel {
    if (selectedVariantSelections.isEmpty) return '';
    return selectedVariantSelections.map((entry) {
      final group = '${entry['groupLabel'] ?? entry['groupCode'] ?? ''}'.trim();
      final option =
          '${entry['optionLabel'] ?? entry['optionCode'] ?? ''}'.trim();
      if (group.isEmpty) return option;
      if (option.isEmpty) return group;
      return '$group: $option';
    }).join(' • ');
  }
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }
  if (value is Map) {
    return [Map<String, dynamic>.from(value)];
  }
  return const <Map<String, dynamic>>[];
}
