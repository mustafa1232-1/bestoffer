import '../../products/models/product_model.dart';

class CartItemModel {
  final ProductModel product;
  final int quantity;

  const CartItemModel({required this.product, required this.quantity});

  CartItemModel copyWith({int? quantity}) {
    return CartItemModel(product: product, quantity: quantity ?? this.quantity);
  }
}
