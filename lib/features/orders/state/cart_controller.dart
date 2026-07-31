import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/pricing.dart';
import '../../../core/utils/product_offer_pricing.dart';
import '../../products/models/product_model.dart';
import '../models/cart_item_model.dart';

enum CartAddStatus { added, storeLimitExceeded }

final cartControllerProvider = StateNotifierProvider<CartController, CartState>(
  (ref) {
    return CartController();
  },
);

class CartStoreSection {
  final int merchantId;
  final String merchantName;
  final List<CartItemModel> items;

  const CartStoreSection({
    required this.merchantId,
    required this.merchantName,
    required this.items,
  });

  double get grossSubtotal {
    return items.fold(0, (sum, item) {
      final pricing = computeProductOfferPricing(
        item.product,
        quantity: item.quantity,
        unitPriceOverride: variantSelectionUnitPriceOverride(
          item.product,
          variantId: item.selectedVariantId,
          selections: item.selectedVariantSelections,
        ),
      );
      return sum + pricing.grossLineTotal;
    });
  }

  double get productDiscountTotal {
    return items.fold(0, (sum, item) {
      final pricing = computeProductOfferPricing(
        item.product,
        quantity: item.quantity,
        unitPriceOverride: variantSelectionUnitPriceOverride(
          item.product,
          variantId: item.selectedVariantId,
          selections: item.selectedVariantSelections,
        ),
      );
      return sum + pricing.lineDiscountTotal;
    });
  }

  double get subtotal {
    return items.fold(0, (sum, item) {
      final pricing = computeProductOfferPricing(
        item.product,
        quantity: item.quantity,
        unitPriceOverride: variantSelectionUnitPriceOverride(
          item.product,
          variantId: item.selectedVariantId,
          selections: item.selectedVariantSelections,
        ),
      );
      return sum + pricing.lineTotal;
    });
  }

  double get serviceFee => calcEstimatedServiceFee(subtotal);

  double get deliveryFee {
    if (items.isEmpty) return 0;
    final hasFreeDelivery = items.any((item) => item.product.freeDelivery);
    if (hasFreeDelivery) return 0;
    return deliveryFeeIqd.toDouble();
  }

  double get total => subtotal + serviceFee + deliveryFee;
}

class CartState {
  final List<CartItemModel> items;
  final String? draftNote;

  const CartState({this.items = const [], this.draftNote});

  Set<int> get storeIds => items.map((item) => item.merchantId).toSet();

  int get storesCount => storeIds.length;

  bool get isMultiStore => storesCount > 1;

  bool get reachedMaxStores => storesCount >= 3;

  int? get merchantId => storesCount == 1 ? items.first.merchantId : null;

  String? get merchantName =>
      storesCount == 1 ? items.first.merchantName : null;

  List<CartStoreSection> get storeSections {
    final grouped = <int, List<CartItemModel>>{};
    final names = <int, String>{};
    for (final item in items) {
      grouped.putIfAbsent(item.merchantId, () => <CartItemModel>[]).add(item);
      names[item.merchantId] = item.merchantName;
    }
    final sections = grouped.entries
        .map(
          (entry) => CartStoreSection(
            merchantId: entry.key,
            merchantName: names[entry.key] ?? 'متجر',
            items: entry.value,
          ),
        )
        .toList();
    sections.sort((a, b) => a.merchantName.compareTo(b.merchantName));
    return sections;
  }

  double get grossSubtotal {
    return storeSections.fold(0, (sum, section) => sum + section.grossSubtotal);
  }

  double get productDiscountTotal {
    return storeSections.fold(
      0,
      (sum, section) => sum + section.productDiscountTotal,
    );
  }

  double get subtotal {
    return storeSections.fold(0, (sum, section) => sum + section.subtotal);
  }

  double get serviceFee {
    return storeSections.fold(0, (sum, section) => sum + section.serviceFee);
  }

  double get deliveryFee {
    return storeSections.fold(0, (sum, section) => sum + section.deliveryFee);
  }

  double get total => subtotal + serviceFee + deliveryFee;

  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);

  CartState copyWith({List<CartItemModel>? items, String? draftNote}) {
    return CartState(
      items: items ?? this.items,
      draftNote: draftNote ?? this.draftNote,
    );
  }
}

class CartController extends StateNotifier<CartState> {
  CartController() : super(const CartState());

  CartAddStatus addItem({
    required ProductModel product,
    required int merchantId,
    required String merchantName,
    int quantity = 1,
    List<Map<String, dynamic>> selectedModifiers = const [],
    int? selectedVariantId,
    List<Map<String, dynamic>> selectedVariantSelections = const [],
  }) {
    final safeQuantity = quantity < 1 ? 1 : quantity;
    final storeIds = state.storeIds;
    final addingNewStore = !storeIds.contains(merchantId);
    if (addingNewStore && storeIds.length >= 3) {
      return CartAddStatus.storeLimitExceeded;
    }

    final keyModifiers = _normalizeModifiers(selectedModifiers);
    final keyVariant = _normalizeModifiers(selectedVariantSelections);
    final normalizedVariantId =
        selectedVariantId != null && selectedVariantId > 0
        ? selectedVariantId
        : null;
    final nextItems = [...state.items];
    final variantIndex = nextItems.indexWhere(
      (i) =>
          i.product.id == product.id &&
          i.merchantId == merchantId &&
          _modifierKey(i.selectedModifiers) == _modifierKey(keyModifiers) &&
          i.selectedVariantId == normalizedVariantId &&
          _modifierKey(i.selectedVariantSelections) == _modifierKey(keyVariant),
    );

    if (variantIndex >= 0) {
      final current = nextItems[variantIndex];
      nextItems[variantIndex] = current.copyWith(
        quantity: current.quantity + safeQuantity,
      );
    } else {
      nextItems.add(
        CartItemModel(
          product: product,
          quantity: safeQuantity,
          merchantId: merchantId,
          merchantName: merchantName,
          selectedModifiers: keyModifiers,
          selectedVariantId: normalizedVariantId,
          selectedVariantSelections: keyVariant,
        ),
      );
    }

    state = state.copyWith(items: nextItems);
    return CartAddStatus.added;
  }

  void decrementItem(
    int productId, {
    int? merchantId,
    List<Map<String, dynamic>> selectedModifiers = const [],
    int? selectedVariantId,
    List<Map<String, dynamic>> selectedVariantSelections = const [],
  }) {
    final keyModifiers = _normalizeModifiers(selectedModifiers);
    final keyVariant = _normalizeModifiers(selectedVariantSelections);
    final normalizedVariantId =
        selectedVariantId != null && selectedVariantId > 0
        ? selectedVariantId
        : null;
    final index = state.items.indexWhere(
      (i) =>
          i.product.id == productId &&
          (merchantId == null || i.merchantId == merchantId) &&
          _modifierKey(i.selectedModifiers) == _modifierKey(keyModifiers) &&
          i.selectedVariantId == normalizedVariantId &&
          _modifierKey(i.selectedVariantSelections) == _modifierKey(keyVariant),
    );
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

  void removeItem(
    int productId, {
    int? merchantId,
    List<Map<String, dynamic>> selectedModifiers = const [],
    int? selectedVariantId,
    List<Map<String, dynamic>> selectedVariantSelections = const [],
  }) {
    final keyModifiers = _normalizeModifiers(selectedModifiers);
    final keyVariant = _normalizeModifiers(selectedVariantSelections);
    final normalizedVariantId =
        selectedVariantId != null && selectedVariantId > 0
        ? selectedVariantId
        : null;
    final nextItems = state.items
        .where(
          (i) =>
              !(i.product.id == productId &&
                  (merchantId == null || i.merchantId == merchantId) &&
                  _modifierKey(i.selectedModifiers) ==
                      _modifierKey(keyModifiers) &&
                  i.selectedVariantId == normalizedVariantId &&
                  _modifierKey(i.selectedVariantSelections) ==
                      _modifierKey(keyVariant)),
        )
        .toList();
    if (nextItems.isEmpty) {
      state = const CartState();
    } else {
      state = state.copyWith(items: nextItems);
    }
  }

  void removeStore(int merchantId) {
    final nextItems = state.items
        .where((i) => i.merchantId != merchantId)
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
    if ((state.draftNote ?? "") == (normalized ?? "")) return;
    state = state.copyWith(draftNote: normalized);
  }

  List<Map<String, dynamic>> _normalizeModifiers(
    List<Map<String, dynamic>> modifiers,
  ) {
    return modifiers
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  String _modifierKey(List<Map<String, dynamic>> modifiers) {
    if (modifiers.isEmpty) return "";
    final normalized = modifiers.map((modifier) {
      final sorted = modifier.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return sorted.map((entry) => '${entry.key}:${entry.value}').join('|');
    }).toList()..sort();
    return normalized.join('||');
  }
}
