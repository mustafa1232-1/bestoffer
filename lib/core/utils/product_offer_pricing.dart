import '../../features/products/models/product_model.dart';

class ProductOfferPricingResult {
  final double baseUnitPrice;
  final double unitPrice;
  final int quantity;
  final int freeUnits;
  final double grossLineTotal;
  final double lineDiscountTotal;
  final double lineTotal;
  final String? offerLabel;
  final String? offerType;

  const ProductOfferPricingResult({
    required this.baseUnitPrice,
    required this.unitPrice,
    required this.quantity,
    required this.freeUnits,
    required this.grossLineTotal,
    required this.lineDiscountTotal,
    required this.lineTotal,
    required this.offerLabel,
    required this.offerType,
  });
}

double _roundMoney(double value) => double.parse(value.toStringAsFixed(2));

/// The effective per-unit price for a cart item's variant selection: a full
/// size+color combination override wins, then a per-option special price (size
/// before color, then any group). Returns null when nothing special is set.
double? variantSelectionUnitPriceOverride(
  ProductModel product, {
  int? variantId,
  List<Map<String, dynamic>> selections = const [],
}) {
  // 1) A full size+color combination override wins. Resolve the combination by
  //    its id, or by matching the selected options.
  ProductVariantModel? variant;
  if (variantId != null) {
    for (final v in product.variants) {
      if (v.id == variantId) {
        variant = v;
        break;
      }
    }
  }
  variant ??= selections.isEmpty
      ? null
      : product.variantForSelectionEntries(selections);
  if (variant != null) {
    final combo = variant.discountedPriceOverride ?? variant.priceOverride;
    if (combo != null) return combo;
  }
  double? optionOverride(String groupCode) {
    for (final entry in selections) {
      final gc = '${entry['groupCode'] ?? entry['group_code'] ?? ''}'
          .trim()
          .toLowerCase();
      if (gc != groupCode) continue;
      final oc = '${entry['optionCode'] ?? entry['option_code'] ?? ''}'
          .trim()
          .toLowerCase();
      for (final group in product.variantGroups) {
        if (group.code.trim().toLowerCase() != groupCode) continue;
        for (final option in group.options) {
          if (option.code.trim().toLowerCase() == oc &&
              option.priceOverride != null) {
            return option.priceOverride;
          }
        }
      }
    }
    return null;
  }

  final sizePrice = optionOverride('size');
  if (sizePrice != null) return sizePrice;
  final colorPrice = optionOverride('color');
  if (colorPrice != null) return colorPrice;
  for (final entry in selections) {
    final gc = '${entry['groupCode'] ?? entry['group_code'] ?? ''}'
        .trim()
        .toLowerCase();
    final anyPrice = optionOverride(gc);
    if (anyPrice != null) return anyPrice;
  }
  return null;
}

ProductOfferPricingResult computeProductOfferPricing(
  ProductModel product, {
  int quantity = 1,
  double? unitPriceOverride,
}) {
  final qty = quantity < 1 ? 1 : quantity;
  final hasOverride = unitPriceOverride != null && unitPriceOverride > 0;
  final baseUnitPrice = hasOverride ? unitPriceOverride : product.price;
  final grossLineTotal = _roundMoney(baseUnitPrice * qty);
  final offerType = product.activeOfferType;

  if (offerType == 'buy_x_get_y') {
    final buyQty = product.activeOfferBuyQuantity ?? 0;
    final getQty = product.activeOfferGetQuantity ?? 0;
    final bundleSize = buyQty + getQty;
    final freeUnits = bundleSize > 0 ? (qty ~/ bundleSize) * getQty : 0;
    final lineDiscountTotal = _roundMoney(baseUnitPrice * freeUnits);
    final lineTotal = _roundMoney(grossLineTotal - lineDiscountTotal);
    final unitPrice = _roundMoney(lineTotal / qty);
    return ProductOfferPricingResult(
      baseUnitPrice: baseUnitPrice,
      unitPrice: unitPrice,
      quantity: qty,
      freeUnits: freeUnits,
      grossLineTotal: grossLineTotal,
      lineDiscountTotal: lineDiscountTotal,
      lineTotal: lineTotal,
      offerLabel: product.offerLabel,
      offerType: offerType,
    );
  }

  // A variant override is already the final price for that option — don't layer
  // the product-level discount on top of it.
  final discountedUnitPrice = hasOverride ? null : product.discountedPrice;
  final unitPrice = discountedUnitPrice != null && discountedUnitPrice > 0
      ? discountedUnitPrice
      : baseUnitPrice;
  final lineTotal = _roundMoney(unitPrice * qty);
  final lineDiscountTotal = _roundMoney(grossLineTotal - lineTotal);
  return ProductOfferPricingResult(
    baseUnitPrice: baseUnitPrice,
    unitPrice: unitPrice,
    quantity: qty,
    freeUnits: 0,
    grossLineTotal: grossLineTotal,
    lineDiscountTotal: lineDiscountTotal,
    lineTotal: lineTotal,
    offerLabel: product.offerLabel,
    offerType: offerType,
  );
}
