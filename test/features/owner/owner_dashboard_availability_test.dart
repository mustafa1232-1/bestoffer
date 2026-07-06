import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/owner/ui/owner_dashboard_screen.dart';
import 'package:maslaki/features/products/models/product_model.dart';
import 'package:maslaki/features/products/ui/product_summary_card.dart';

ProductModel _product({
  required int id,
  required bool isAvailable,
  String? unavailableReason,
  String? unavailableUntil,
}) {
  return ProductModel.fromJson({
    'id': id,
    'merchantId': 9,
    'name': 'Product $id',
    'price': 12000,
    'isAvailable': isAvailable,
    'unavailableReason': unavailableReason,
    'unavailableUntil': unavailableUntil,
    'stockQuantity': 0,
    'trackStock': false,
    'stockMode': 'untracked',
  });
}

void main() {
  test('owner availability filter keeps only matching product rows', () {
    final products = [
      _product(id: 1, isAvailable: true),
      _product(id: 2, isAvailable: false, unavailableReason: 'Paused'),
      _product(id: 3, isAvailable: false, unavailableReason: 'Until tomorrow'),
    ];

    expect(
      filterOwnerProductsByAvailability(
        products,
        OwnerProductAvailabilityFilter.all,
      ).map((product) => product.id),
      [1, 2, 3],
    );
    expect(
      filterOwnerProductsByAvailability(
        products,
        OwnerProductAvailabilityFilter.available,
      ).map((product) => product.id),
      [1],
    );
    expect(
      filterOwnerProductsByAvailability(
        products,
        OwnerProductAvailabilityFilter.unavailable,
      ).map((product) => product.id),
      [2, 3],
    );
  });

  test('unavailable product badge surfaces the unavailable state', () {
    final product = _product(
      id: 7,
      isAvailable: false,
      unavailableReason: 'Maintenance',
      unavailableUntil: '2026-07-07T12:00:00.000Z',
    );

    final card = ProductSummaryCardData.fromProduct(product);
    expect(card.availabilityBadge, isNotNull);
    expect(card.availabilityBadge!.text, anyOf('غير متاح', 'Unavailable'));
    expect(card.availabilityBadge!.kind, ProductSummaryBadgeKind.danger);
  });
}
