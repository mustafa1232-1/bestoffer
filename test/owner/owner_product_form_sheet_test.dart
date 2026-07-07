import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/owner/ui/owner_product_form_sheet.dart';
import 'package:maslaki/features/products/models/product_category_model.dart';
import 'package:maslaki/features/products/models/product_model.dart';

void main() {
  const clothes = ProductCategoryModel(
    id: 7,
    merchantId: 2,
    name: 'cloths',
    catalogType: 'clothes',
    sortOrder: 0,
    availableProductsCount: 0,
    createdAt: null,
    updatedAt: null,
  );

  const electronics = ProductCategoryModel(
    id: 8,
    merchantId: 2,
    name: 'Chargers',
    catalogType: 'electronics',
    sortOrder: 1,
    availableProductsCount: 0,
    createdAt: null,
    updatedAt: null,
  );

  ProductModel invalidProduct() {
    return ProductModel.fromJson({
      'id': 12,
      'merchantId': 2,
      'categoryId': 8,
      'categoryName': 'Chargers',
      'name': 'USB Charger',
      'price': 12000,
      'sortOrder': 0,
      'isAvailable': true,
      'freeDelivery': false,
    });
  }

  testWidgets('actual owner product form exposes rich clothes sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProductFormSheet(
            categories: [clothes],
            merchantActivityType: 'fashion_clothing',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إضافة منتج'), findsOneWidget);
    expect(find.text(clothes.displayName), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsWidgets);
    expect(find.byType(SwitchListTile), findsAtLeastNWidgets(2));
  });

  testWidgets(
    'owner product form filters categories by store type and blocks invalid save',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Center(
                  child: FilledButton(
                    onPressed: () {
                      showModalBottomSheet<ProductFormData>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ProductFormSheet(
                          product: invalidProduct(),
                          categories: const [clothes, electronics],
                          merchantActivityType: 'fashion_clothing',
                        ),
                      );
                    },
                    child: const Text('open-product-form'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-product-form'));
      await tester.pump(const Duration(milliseconds: 400));

      final categoryField = find.byType(DropdownButtonFormField<int>).first;
      await tester.scrollUntilVisible(
        categoryField,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(categoryField);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(clothes.displayName), findsWidgets);
      expect(find.text('Chargers'), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await tester.pump(const Duration(milliseconds: 200));

      final availabilitySwitch = find.byKey(
        const ValueKey('product-form-availability-switch'),
      );
      await tester.scrollUntilVisible(
        availabilitySwitch,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(availabilitySwitch);
      await tester.pump(const Duration(milliseconds: 200));

      final reasonField = find.byKey(
        const ValueKey('product-form-unavailable-reason'),
      );
      final untilField = find.byKey(
        const ValueKey('product-form-unavailable-until'),
      );
      expect(reasonField, findsOneWidget);
      expect(untilField, findsOneWidget);
      await tester.enterText(reasonField, 'Maintenance');
      await tester.enterText(untilField, '2026-07-07T12:00:00.000Z');

      final submitButton = find.byKey(const ValueKey('product-form-submit'));
      await tester.scrollUntilVisible(
        submitButton,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(submitButton);
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining(
          'Selected category does not match this store type',
        ),
        findsOneWidget,
      );
    },
  );

  test('cloths remains backward compatible and has clothes catalog type', () {
    final parsed = ProductCategoryModel.fromJson({
      'id': 1,
      'merchantId': 2,
      'name': 'cloths',
      'sortOrder': 0,
    });
    expect(parsed.catalogType, 'clothes');
    expect(parsed.displayName, clothes.displayName);
  });
}
