import '../../products/models/product_model.dart';

class CartItemModel {
  final ProductModel product;
  final int quantity;
  final int merchantId;
  final String merchantName;
  final List<Map<String, dynamic>> selectedModifiers;

  const CartItemModel({
    required this.product,
    required this.quantity,
    required this.merchantId,
    required this.merchantName,
    this.selectedModifiers = const [],
  });

  CartItemModel copyWith({
    int? quantity,
    List<Map<String, dynamic>>? selectedModifiers,
  }) {
    return CartItemModel(
      product: product,
      quantity: quantity ?? this.quantity,
      merchantId: merchantId,
      merchantName: merchantName,
      selectedModifiers: selectedModifiers ?? this.selectedModifiers,
    );
  }
}
