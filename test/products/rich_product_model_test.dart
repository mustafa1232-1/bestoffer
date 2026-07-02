import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/products/models/product_model.dart';

void main() {
  test('parses variant combinations, stock, attributes, and media', () {
    final product = ProductModel.fromJson({
      'id': 10,
      'merchantId': 2,
      'categoryId': 7,
      'name': 'تيشيرت قطن',
      'price': 20000,
      'isAvailable': true,
      'sortOrder': 0,
      'attributes': [
        {
          'code': 'material',
          'labelAr': 'الخامة',
          'valueText': 'قطن 100%',
          'showInCard': true,
        },
      ],
      'variantGroups': [
        {
          'code': 'color',
          'labelAr': 'اللون',
          'options': [
            {
              'code': 'black',
              'labelAr': 'أسود',
              'swatchHex': '#000000',
              'colorImageUrl': '/uploads/black.jpg',
            },
          ],
        },
        {
          'code': 'size',
          'labelAr': 'المقاس',
          'options': [
            {'code': 'm', 'labelAr': 'M'},
          ],
        },
      ],
      'variants': [
        {
          'id': 55,
          'signature': 'color:black|size:m',
          'selections': [
            {'groupCode': 'color', 'optionCode': 'black'},
            {'groupCode': 'size', 'optionCode': 'm'},
          ],
          'sku': 'TS-BLK-M',
          'stockQuantity': 4,
          'imageUrl': '/uploads/black-m.jpg',
          'isAvailable': true,
        },
      ],
    });

    expect(product.summaryAttributes.single.valueText, 'قطن 100%');
    expect(
      product.variantGroups.first.options.first.imageUrl,
      '/uploads/black.jpg',
    );
    expect(product.variants.single.stockQuantity, 4);
    expect(product.isInStock, isTrue);
    expect(
      product.variantForSelections({'color': 'black', 'size': 'm'})?.id,
      55,
    );
  });

  test('legacy product without inventory remains orderable', () {
    final product = ProductModel.fromJson({
      'id': 11,
      'merchantId': 2,
      'name': 'منتج بسيط',
      'price': 1000,
      'isAvailable': true,
      'sortOrder': 0,
    });
    expect(product.stockQuantity, isNull);
    expect(product.variants, isEmpty);
    expect(product.isInStock, isTrue);
  });
}
