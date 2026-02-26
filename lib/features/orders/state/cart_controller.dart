import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/pricing.dart';
import '../../products/models/product_model.dart';
import '../models/cart_item_model.dart';

final cartControllerProvider = StateNotifierProvider<CartController, CartState>(
  (ref) {
    return CartController();
  },
);

class CartState {
  final int? merchantId;
  final String? merchantName;
  final List<CartItemModel> items;
  final String? draftNote;

  const CartState({
    this.merchantId,
    this.merchantName,
    this.items = const [],
    this.draftNote,
  });

  double get subtotal {
    return items.fold(0, (sum, item) {
      final price = item.product.discountedPrice ?? item.product.price;
      return sum + (price * item.quantity);
    });
  }

  double get serviceFee => calcServiceFee(subtotal);

  double get deliveryFee {
    if (items.isEmpty) return 0;
    final hasFreeDelivery = items.any((item) => item.product.freeDelivery);
    if (hasFreeDelivery) return 0;
    return deliveryFeeIqd.toDouble();
  }

  double get total => subtotal + serviceFee + deliveryFee;

  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);

  CartState copyWith({
    int? merchantId,
    String? merchantName,
    List<CartItemModel>? items,
    String? draftNote,
  }) {
    return CartState(
      merchantId: merchantId ?? this.merchantId,
      merchantName: merchantName ?? this.merchantName,
      items: items ?? this.items,
      draftNote: draftNote ?? this.draftNote,
    );
  }
}

class CartController extends StateNotifier<CartState> {
  CartController() : super(const CartState());

  void addItem({
    required ProductModel product,
    required int merchantId,
    required String merchantName,
  }) {
    if (state.merchantId != null && state.merchantId != merchantId) {
      state = const CartState();
    }

    final index = state.items.indexWhere((i) => i.product.id == product.id);
    final nextItems = [...state.items];

    if (index >= 0) {
      final current = nextItems[index];
      nextItems[index] = current.copyWith(quantity: current.quantity + 1);
    } else {
      nextItems.add(CartItemModel(product: product, quantity: 1));
    }

    state = CartState(
      merchantId: merchantId,
      merchantName: merchantName,
      items: nextItems,
      draftNote: state.draftNote,
    );
  }

  void decrementItem(int productId) {
    final index = state.items.indexWhere((i) => i.product.id == productId);
    if (index < 0) return;

    final nextItems = [...state.items];
    final current = nextItems[index];
    if (current.quantity <= 1) {
      nextItems.removeAt(index);
    } else {
      nextItems[index] = current.copyWith(quantity: current.quantity - 1);
    }

    if (nextItems.isEmpty) {
      state = const CartState();
    } else {
      state = state.copyWith(items: nextItems);
    }
  }

  void removeItem(int productId) {
    final nextItems = state.items
        .where((i) => i.product.id != productId)
        .toList();
    if (nextItems.isEmpty) {
      state = const CartState();
    } else {
      state = state.copyWith(items: nextItems);
    }
  }

  void clear() {
    state = const CartState();
  }

  void setDraftNote(String value) {
    final normalized = value.trim().isEmpty ? null : value;
    if ((state.draftNote ?? '') == (normalized ?? '')) return;
    state = CartState(
      merchantId: state.merchantId,
      merchantName: state.merchantName,
      items: state.items,
      draftNote: normalized,
    );
  }
}
