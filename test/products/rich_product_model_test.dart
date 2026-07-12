import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/products/models/product_model.dart';

void main() {
  test('parses variant combinations, stock, attributes, and media', () {
    final product = ProductModel.fromJson({
      'id': 10,
      'merchantId': 2,
      'categoryId': 7,
      'name': 'ØªÙŠØ´ÙŠØ±Øª Ù‚Ø·Ù†',
      'price': 20000,
      'isAvailable': true,
      'sortOrder': 0,
      'attributes': [
        {
          'code': 'material',
          'labelAr': 'Ø§Ù„Ø®Ø§Ù…Ø©',
          'valueText': 'Ù‚Ø·Ù† 100%',
          'showInCard': true,
        },
      ],
      'variantGroups': [
        {
          'code': 'color',
          'labelAr': 'Ø§Ù„Ù„ÙˆÙ†',
          'options': [
            {
              'code': 'black',
              'labelAr': 'Ø£Ø³ÙˆØ¯',
              'swatchHex': '#000000',
              'colorImageUrl': '/uploads/black.jpg',
            },
          ],
        },
        {
          'code': 'size',
          'labelAr': 'Ø§Ù„Ù…Ù‚Ø§Ø³',
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

  test(
    'resolves variant by selections map despite divergent signature, case, and whitespace',
    () {
      // Reproduces the real "اعتماد الاختيارات stays disabled" bug: legacy /
      // mixed data where the pre-computed variant signature does NOT match the
      // reconstructed groupCode:optionCode string (different delimiter/order),
      // and the live option codes differ in case/whitespace. The button must
      // still resolve the correct variant.
      final product = ProductModel.fromJson({
        'id': 20,
        'merchantId': 2,
        'name': 'قميص',
        'price': 25000,
        'isAvailable': true,
        'sortOrder': 0,
        'variantGroups': [
          {
            'code': 'color',
            'labelAr': 'اللون',
            'options': [
              {'code': 'نيلي', 'labelAr': 'نيلي'},
            ],
          },
          {
            'code': 'size',
            'labelAr': 'المقاس',
            'options': [
              {'code': 'XL', 'labelAr': 'XL'},
            ],
          },
        ],
        'variants': [
          {
            'id': 77,
            // Intentionally divergent signature format (reversed order + labels)
            // so any string-based signature comparison would fail.
            'signature': 'SIZE=XL;COLOR=Navy',
            'selections': [
              {'groupCode': 'color', 'optionCode': 'نيلي '},
              {'groupCode': 'size', 'optionCode': ' xl'},
            ],
            'stockQuantity': 3,
            'isAvailable': true,
          },
        ],
      });

      // Exact selection as produced by the picker (group.code -> option.code).
      final resolved = product.variantForSelections({
        'color': 'نيلي',
        'size': 'XL',
      });
      expect(resolved, isNotNull);
      expect(resolved!.id, 77);
      expect(product.canOrderVariant(resolved), isTrue);

      // A partial selection must NOT resolve (keeps the confirm button disabled).
      expect(product.variantForSelections({'color': 'نيلي'}), isNull);
    },
  );

  test('legacy product without inventory remains orderable', () {
    final product = ProductModel.fromJson({
      'id': 11,
      'merchantId': 2,
      'name': 'Ù…Ù†ØªØ¬ Ø¨Ø³ÙŠØ·',
      'price': 1000,
      'isAvailable': true,
      'sortOrder': 0,
    });
    expect(product.stockQuantity, isNull);
    expect(product.variants, isEmpty);
    expect(product.isInStock, isTrue);
  });

  test('untracked products remain orderable with zero or null stock', () {
    final zeroStock = ProductModel.fromJson({
      'id': 12,
      'merchantId': 2,
      'name': 'Ù…Ù†ØªØ¬ ØºÙŠØ± Ù…ØªØªØ¨Ø¹',
      'price': 1000,
      'isAvailable': true,
      'trackStock': false,
      'stockMode': 'untracked',
      'stockQuantity': 0,
      'sortOrder': 0,
    });
    final nullStock = ProductModel.fromJson({
      'id': 13,
      'merchantId': 2,
      'name': 'Ù…Ù†ØªØ¬ Ø¨Ø¯ÙˆÙ† Ù…Ø®Ø²ÙˆÙ†',
      'price': 1000,
      'isAvailable': true,
      'trackStock': false,
      'stockMode': 'untracked',
      'stockQuantity': null,
      'sortOrder': 0,
    });

    expect(zeroStock.isStockTracked, isFalse);
    expect(zeroStock.stockQuantity, 0);
    expect(zeroStock.isInStock, isTrue);
    expect(nullStock.isStockTracked, isFalse);
    expect(nullStock.stockQuantity, isNull);
    expect(nullStock.isInStock, isTrue);
  });

  test('tracked products with zero stock are not orderable', () {
    final product = ProductModel.fromJson({
      'id': 14,
      'merchantId': 2,
      'name': 'Ù…Ù†ØªØ¬ Ù…ØªØªØ¨Ø¹',
      'price': 1000,
      'isAvailable': true,
      'trackStock': true,
      'stockMode': 'tracked',
      'stockQuantity': 0,
      'sortOrder': 0,
    });

    expect(product.isStockTracked, isTrue);
    expect(product.isInStock, isFalse);
    expect(product.canBeOrdered, isFalse);
  });
}
