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

ProductOfferPricingResult computeProductOfferPricing(
  ProductModel product, {
  int quantity = 1,
}) {
  final qty = quantity < 1 ? 1 : quantity;
  final baseUnitPrice = product.price;
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

  final discountedUnitPrice = product.discountedPrice;
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
