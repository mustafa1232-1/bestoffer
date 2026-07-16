import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/merchants/ui/merchant_products_screen.dart';
import 'package:maslaki/features/products/models/product_model.dart';

ProductModel _product({
  required int id,
  required String name,
  required bool isAvailable,
  required int stockQuantity,
  double? discountedPrice,
  bool hasVariants = false,
  bool trackStock = false,
  String? stockMode,
}) {
  return ProductModel.fromJson({
    'id': id,
    'merchantId': 2,
    'name': name,
    'price': 10000,
    'discountedPrice': ?discountedPrice,
    'isAvailable': isAvailable,
    'stockQuantity': stockQuantity,
    'trackStock': trackStock,
    'stockMode': stockMode ?? (trackStock ? 'tracked' : 'untracked'),
    if (hasVariants)
      'variantGroups': [
        {
          'code': 'color',
          'labelAr': 'اللون',
          'selectionMode': 'single',
          'required': true,
          'options': [
            {'code': 'red', 'labelAr': 'أحمر', 'isAvailable': true},
          ],
        },
      ],
    if (hasVariants)
      'variants': [
        {
          'id': id * 100,
          'signature': 'color:red',
          'selections': [
            {'groupCode': 'color', 'optionCode': 'red'},
          ],
          'stockQuantity': stockQuantity,
          'isAvailable': true,
        },
      ],
  });
}

void main() {
  test(
    'discount highlights keep untracked zero-stock products and skip tracked zero-stock and unavailable products',
    () {
      final products = [
        _product(
          id: 1,
          name: 'Untracked zero stock discount',
          isAvailable: true,
          stockQuantity: 0,
          trackStock: false,
          stockMode: 'untracked',
          discountedPrice: 8000,
        ),
        _product(
          id: 2,
          name: 'Tracked zero stock discount',
          isAvailable: true,
          stockQuantity: 0,
          trackStock: true,
          stockMode: 'tracked',
          discountedPrice: 8000,
        ),
        _product(
          id: 3,
          name: 'Unavailable discount',
          isAvailable: false,
          stockQuantity: 4,
          trackStock: false,
          stockMode: 'untracked',
          discountedPrice: 8000,
        ),
        _product(
          id: 4,
          name: 'Tracked available discount',
          isAvailable: true,
          stockQuantity: 4,
          trackStock: true,
          stockMode: 'tracked',
          discountedPrice: 8000,
        ),
      ];

      final filtered = filterMerchantDiscountHighlights(products);

      expect(filtered.map((product) => product.id), [1, 4]);
    },
  );

  test('discount highlights skip unavailable and zero-stock products', () {
    final products = [
      _product(
        id: 1,
        name: 'Available discount',
        isAvailable: true,
        trackStock: true,
        stockMode: 'tracked',
        stockQuantity: 4,
        discountedPrice: 8000,
      ),
      _product(
        id: 2,
        name: 'Out of stock discount',
        isAvailable: true,
        trackStock: true,
        stockMode: 'tracked',
        stockQuantity: 0,
        discountedPrice: 8000,
      ),
      _product(
        id: 3,
        name: 'Unavailable discount',
        isAvailable: false,
        trackStock: true,
        stockMode: 'tracked',
        stockQuantity: 4,
        discountedPrice: 8000,
      ),
    ];

    final filtered = filterMerchantDiscountHighlights(products);

    expect(filtered.map((product) => product.id), [1]);
  });
}
