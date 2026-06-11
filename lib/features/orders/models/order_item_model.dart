import '../../../core/utils/parsers.dart';

class OrderItemModel {
  final int id;
  final int orderId;
  final int? productId;
  final String productName;
  final double baseUnitPrice;
  final double unitPrice;
  final int quantity;
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
    required this.lineDiscountTotal,
    required this.lineTotal,
    required this.pricingBreakdown,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> j) {
    final pricingRaw = j['pricing_breakdown_json'] ?? j['pricingBreakdown'];
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
      lineDiscountTotal: parseDouble(
        j['line_discount_total'] ?? j['lineDiscountTotal'],
      ),
      lineTotal: parseDouble(j['line_total'] ?? j['lineTotal']),
      pricingBreakdown: pricingRaw is Map
          ? Map<String, dynamic>.from(pricingRaw)
          : null,
    );
  }
}
