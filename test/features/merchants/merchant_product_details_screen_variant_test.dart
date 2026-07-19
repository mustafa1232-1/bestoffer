import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/merchants/models/merchant_model.dart';
import 'package:maslaki/features/merchants/ui/merchant_product_details_screen.dart';
import 'package:maslaki/features/products/models/product_model.dart';
import 'package:maslaki/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('ar'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: child,
    ),
  );
}

MerchantModel _restaurantMerchant() {
  return MerchantModel(
    id: 77,
    name: 'Sanadrilla',
    type: 'restaurant',
    activityType: 'restaurant',
    isOpen: true,
    hasDiscountOffer: false,
    hasFreeDeliveryOffer: false,
    supportsChat: true,
  );
}

ProductModel _variantProduct() {
  return ProductModel.fromJson({
    'id': 501,
    'merchantId': 77,
    'categoryId': 9,
    'categoryName': 'restaurant',
    'name': 'تقاوي',
    'description': 'تقاوي على الفحم برياني',
    'price': 25000,
    'isAvailable': true,
    'isInStock': true,
    'sortOrder': 0,
    'attributes': [
      {
        'code': 'meal_size',
        'label_ar': 'الحجم',
        'label_en': 'Size',
        'value_text': 'صغير / وسط / كبير',
        'show_in_card': true,
        'show_in_details': true,
      },
      {
        'code': 'spice_level',
        'label_ar': 'التتبيل',
        'label_en': 'Seasoning',
        'value_text': 'حار متوسط',
        'show_in_card': true,
        'show_in_details': true,
      },
      {
        'code': 'serving_style',
        'label_ar': 'التقديم',
        'label_en': 'Serving',
        'value_text': 'صحن كبير',
        'show_in_card': false,
        'show_in_details': true,
      },
    ],
    'variant_groups': [
      {
        'group_id': 1,
        'code': 'color',
        'label_ar': 'اللون',
        'label_en': 'Color',
        'display_mode': 'chips',
        'selection_mode': 'single',
        'required': true,
        'sort_order': 0,
        'options': [
          {
            'option_id': 11,
            'code': 'hot',
            'label_ar': 'حار',
            'label_en': 'Hot',
            'is_available': true,
            'sort_order': 0,
          },
          {
            'option_id': 12,
            'code': 'normal',
            'label_ar': 'عادي',
            'label_en': 'Normal',
            'is_available': true,
            'sort_order': 1,
          },
        ],
      },
      {
        'group_id': 2,
        'code': 'size',
        'label_ar': 'المقاس',
        'label_en': 'Size',
        'display_mode': 'chips',
        'selection_mode': 'single',
        'required': true,
        'sort_order': 1,
        'options': [
          {
            'option_id': 21,
            'code': 'small',
            'label_ar': 'صغير',
            'label_en': 'Small',
            'is_available': true,
            'sort_order': 0,
          },
          {
            'option_id': 22,
            'code': 'medium',
            'label_ar': 'وسط',
            'label_en': 'Medium',
            'is_available': true,
            'sort_order': 1,
          },
        ],
      },
    ],
    'variants': [
      {
        'id': 9001,
        'signature': 'color:hot|size:small',
        'selections': [
          {'groupCode': 'color', 'optionCode': 'hot'},
          {'groupCode': 'size', 'optionCode': 'small'},
        ],
        'stock_quantity': 4,
        'is_available': true,
      },
      {
        'id': 9002,
        'signature': 'color:hot|size:medium',
        'selections': [
          {'groupCode': 'color', 'optionCode': 'hot'},
          {'groupCode': 'size', 'optionCode': 'medium'},
        ],
        'stock_quantity': 2,
        'is_available': true,
      },
      {
        'id': 9003,
        'signature': 'color:normal|size:small',
        'selections': [
          {'groupCode': 'color', 'optionCode': 'normal'},
          {'groupCode': 'size', 'optionCode': 'small'},
        ],
        'stock_quantity': 1,
        'is_available': true,
      },
    ],
  });
}

void main() {
  testWidgets('restaurant variant labels enable add-to-cart after selection', (
    tester,
  ) async {
    final merchant = _restaurantMerchant();
    final product = _variantProduct();
    var addCount = 0;

    await tester.pumpWidget(
      _wrap(
        MerchantProductDetailsScreen(
          merchant: merchant,
          product: product,
          similarProducts: const [],
          canOrder: true,
          unavailableLabel: 'غير متوفر',
          onAddToCart: (
            productArg,
            quantityArg, {
            List<Map<String, dynamic>> selectedVariantSelections = const [],
            int? selectedVariantId,
          }) async {
            expect(productArg.id, product.id);
            expect(quantityArg, 1);
            addCount += 1;
            expect(selectedVariantId, isNotNull);
            expect(selectedVariantSelections, isNotEmpty);
          },
          onOpenProduct: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('درجة التتبيل'), findsOneWidget);
    expect(find.text('الحجم'), findsOneWidget);
    expect(find.text('اختر درجة التتبيل والحجم أولاً'), findsOneWidget);
    expect(find.text('المواصفات الكاملة'), findsOneWidget);
    expect(find.textContaining('الحجم: صغير / وسط / كبير'), findsWidgets);
    expect(find.textContaining('التتبيل: حار متوسط'), findsWidgets);

    await tester.scrollUntilVisible(find.text('حار').first, 300);
    await tester.tap(find.text('حار').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('صغير').first, 300);
    await tester.tap(find.text('صغير').first);
    await tester.pumpAndSettle();

    expect(find.text('إضافة إلى السلة'), findsWidgets);

    await tester.tap(find.text('إضافة إلى السلة').first);
    await tester.pumpAndSettle();

    expect(addCount, 1);
  });
}
