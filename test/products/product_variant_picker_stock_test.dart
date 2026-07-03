import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/products/models/product_model.dart';
import 'package:maslaki/features/products/ui/product_variant_picker_sheet.dart';

ProductModel _productWithVariantStock(int stock) {
  return ProductModel.fromJson({
    'id': 9,
    'merchantId': 2,
    'name': 'mm',
    'price': 75000,
    'is_available': true,
    'variantGroups': [
      {
        'code': 'color',
        'labelAr': 'اللون',
        'displayMode': 'swatches',
        'selectionMode': 'single',
        'required': true,
        'options': [
          {
            'optionId': 11,
            'code': 'purpel',
            'labelAr': 'purpel',
            'swatchHex': '#800080',
          },
        ],
      },
      {
        'code': 'size',
        'labelAr': 'المقاس',
        'selectionMode': 'single',
        'required': true,
        'options': [
          {'optionId': 21, 'code': 'xl', 'labelAr': 'xl'},
        ],
      },
    ],
    'variants': [
      {
        'id': 101,
        'selections': [
          {'groupCode': 'color', 'optionCode': 'purpel'},
          {'groupCode': 'size', 'optionCode': 'xl'},
        ],
        'stockQuantity': stock,
        'isAvailable': true,
      },
    ],
  });
}

Future<void> _openPicker(WidgetTester tester, ProductModel product) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () =>
                  showProductVariantPickerSheet(context, product: product),
              child: const Text('افتح الخيارات'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('افتح الخيارات'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('confirm is enabled when the selected variant has stock', (
    tester,
  ) async {
    await _openPicker(tester, _productWithVariantStock(5));

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(confirm.onPressed, isNotNull);
    expect(
      find.text('This color/size is currently unavailable'),
      findsNothing,
    );
  });

  testWidgets('confirm is disabled with a clear message when stock is zero', (
    tester,
  ) async {
    await _openPicker(tester, _productWithVariantStock(0));

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(confirm.onPressed, isNull);
    expect(
      find.text('This color/size is currently unavailable'),
      findsOneWidget,
    );
  });

  test('availability badge source reflects real variant stock', () {
    expect(_productWithVariantStock(0).isInStock, isFalse);
    expect(_productWithVariantStock(5).isInStock, isTrue);
  });
}
