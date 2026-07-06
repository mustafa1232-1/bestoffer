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
}) {
  return ProductModel.fromJson({
    'id': id,
    'merchantId': 2,
    'name': name,
    'price': 10000,
    if (discountedPrice != null) 'discountedPrice': discountedPrice,
    'isAvailable': isAvailable,
    'stockQuantity': stockQuantity,
    if (hasVariants)
      'variantGroups': [
        {
          'code': 'color',
          'labelAr': 'اللون',
          'selectionMode': 'single',
          'required': true,
          'options': [
            {
              'code': 'red',
              'labelAr': 'أحمر',
              'isAvailable': true,
            },
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
  test('discount highlights skip unavailable and zero-stock products', () {
    final products = [
      _product(
        id: 1,
        name: 'Available discount',
        isAvailable: true,
        stockQuantity: 4,
        discountedPrice: 8000,
      ),
      _product(
        id: 2,
        name: 'Out of stock discount',
        isAvailable: true,
        stockQuantity: 0,
        discountedPrice: 8000,
      ),
      _product(
        id: 3,
        name: 'Unavailable discount',
        isAvailable: false,
        stockQuantity: 4,
        discountedPrice: 8000,
      ),
    ];

    final filtered = filterMerchantDiscountHighlights(products);

    expect(filtered.map((product) => product.id), [1]);
  });

  test('smart bundle candidates skip unavailable, zero-stock, and variant products', () {
    final products = [
      _product(
        id: 1,
        name: 'Available simple',
        isAvailable: true,
        stockQuantity: 2,
      ),
      _product(
        id: 2,
        name: 'Zero stock simple',
        isAvailable: true,
        stockQuantity: 0,
      ),
      _product(
        id: 3,
        name: 'Variant product',
        isAvailable: true,
        stockQuantity: 5,
        hasVariants: true,
      ),
      _product(
        id: 4,
        name: 'Unavailable simple',
        isAvailable: false,
        stockQuantity: 5,
      ),
    ];

    final filtered = filterMerchantSmartBundleCandidates(
      products,
      supportsPharmacyWorkflow: false,
    );

    expect(filtered.map((product) => product.id), [1]);
  });
}
