import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/owner/ui/owner_product_form_sheet.dart';
import 'package:maslaki/features/products/models/product_category_model.dart';
import 'package:maslaki/features/products/models/product_model.dart';
import 'package:maslaki/features/products/ui/product_summary_card.dart';

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

    final scrollable = find.byType(Scrollable).first;
    for (final label in const [
      'القماش / الخامة',
      'الماركة',
      'الألوان والمقاسات / Variants',
      'إضافة لون',
      'إضافة مقاس',
      'المواصفات التي تظهر للمستخدم خارج المنتج',
      'المواصفات الكاملة',
      'معاينة شكل المنتج للمستخدم',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        120,
        scrollable: scrollable,
      );
      expect(find.text(label), findsOneWidget);
    }

    await tester.scrollUntilVisible(
      find.byType(ProductSummaryCard),
      120,
      scrollable: scrollable,
    );
    expect(find.byType(ProductSummaryCard), findsWidgets);
  });

  testWidgets(
    'owner product form filters categories by store type and blocks invalid save',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductFormSheet(
              product: invalidProduct(),
              categories: [clothes, electronics],
              merchantActivityType: 'fashion_clothing',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();

      expect(find.text(clothes.displayName), findsWidgets);
      expect(find.text('Chargers'), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('معاينة شكل المنتج للمستخدم'),
        120,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pumpAndSettle();

      final submitButton = find.byType(FilledButton).last;
      expect(submitButton, findsOneWidget);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.byType(ProductFormSheet), findsOneWidget);
      expect(
        find.textContaining(
          'Selected category does not match this store type.',
        ),
        findsWidgets,
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
