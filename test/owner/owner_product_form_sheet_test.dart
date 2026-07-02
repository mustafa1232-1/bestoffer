import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/owner/ui/owner_product_form_sheet.dart';
import 'package:maslaki/features/products/models/product_category_model.dart';
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

  testWidgets('actual owner product form exposes rich clothes sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProductFormSheet(categories: [clothes])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إضافة منتج'), findsOneWidget);
    expect(find.text('Clothes / ملابس'), findsOneWidget);

    // The form body is a lazy ListView; scroll each section into view
    // before asserting on it.
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

  test('cloths remains backward compatible and has clothes catalog type', () {
    final parsed = ProductCategoryModel.fromJson({
      'id': 1,
      'merchantId': 2,
      'name': 'cloths',
      'sortOrder': 0,
    });
    expect(parsed.catalogType, 'clothes');
    expect(parsed.displayName, 'Clothes / ملابس');
  });
}
