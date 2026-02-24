import '../../../core/utils/parsers.dart';

class OrderItemModel {
  final int id;
  final int orderId;
  final int? productId;
  final String productName;
  final double unitPrice;
  final int quantity;
  final double lineTotal;

  const OrderItemModel({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> j) {
    return OrderItemModel(
      id: parseInt(j['id']),
      orderId: parseInt(j['order_id'] ?? j['orderId']),
      productId: j['product_id'] == null ? null : parseInt(j['product_id']),
      productName: parseString(j['product_name'] ?? j['productName']),
      unitPrice: parseDouble(j['unit_price'] ?? j['unitPrice']),
      quantity: parseInt(j['quantity']),
      lineTotal: parseDouble(j['line_total'] ?? j['lineTotal']),
    );
  }
}
