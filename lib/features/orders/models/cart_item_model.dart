import '../../products/models/product_model.dart';

class CartItemModel {
  final ProductModel product;
  final int quantity;
  final int merchantId;
  final String merchantName;
  final List<Map<String, dynamic>> selectedModifiers;
  final List<Map<String, dynamic>> selectedVariantSelections;

  const CartItemModel({
    required this.product,
    required this.quantity,
    required this.merchantId,
    required this.merchantName,
    this.selectedModifiers = const [],
    this.selectedVariantSelections = const [],
  });

  CartItemModel copyWith({
    int? quantity,
    List<Map<String, dynamic>>? selectedModifiers,
    List<Map<String, dynamic>>? selectedVariantSelections,
  }) {
    return CartItemModel(
      product: product,
      quantity: quantity ?? this.quantity,
      merchantId: merchantId,
      merchantName: merchantName,
      selectedModifiers: selectedModifiers ?? this.selectedModifiers,
      selectedVariantSelections:
          selectedVariantSelections ?? this.selectedVariantSelections,
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
