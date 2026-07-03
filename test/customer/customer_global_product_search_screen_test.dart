import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maslaki/features/customer/ui/customer_global_product_search_screen.dart';
import 'package:maslaki/features/orders/data/orders_api.dart';
import 'package:maslaki/features/orders/state/cart_controller.dart';
import 'package:maslaki/features/orders/state/orders_controller.dart';
import 'package:maslaki/features/products/ui/product_summary_card.dart';

class _FakeOrdersApi extends OrdersApi {
  _FakeOrdersApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> searchProductsGlobal({
    required String query,
    String sort = 'best_offers',
    String? merchantType,
    bool onlyAvailable = false,
    bool onlyDiscounted = false,
    double? minPrice,
    double? maxPrice,
    double? minRating,
    String? city,
    String? block,
    int limit = 40,
    int offset = 0,
  }) async {
    return {
      'items': [
        {
          'productId': 99,
          'merchantId': 5,
          'merchant': {
            'id': 5,
            'name': 'متجر الألوان',
            'type': 'market',
            'rating': 4.8,
          },
          'categoryId': 7,
          'categoryName': 'cloths',
          'name': 'قميص أزرق',
          'price': 20000,
          'discountedPrice': 15000,
          'isAvailable': true,
          'isInStock': true,
          'sortOrder': 0,
          'imageUrl': '/main.jpg',
          'attributes': [
            {
              'code': 'material',
              'labelAr': 'الخامة',
              'valueText': 'Cotton',
              'showInCard': true,
            },
          ],
          'variantGroups': [
            {
              'code': 'color',
              'labelAr': 'اللون',
              'labelEn': 'Color',
              'displayMode': 'swatches',
              'selectionMode': 'single',
              'required': true,
              'options': [
                {
                  'code': 'red',
                  'labelAr': 'أحمر',
                  'labelEn': 'Red',
                  'swatchHex': '#FF0000',
                  'isAvailable': true,
                },
                {
                  'code': 'blue',
                  'labelAr': 'أزرق',
                  'labelEn': 'Blue',
                  'swatchHex': '#0000FF',
                  'isAvailable': true,
                },
              ],
            },
            {
              'code': 'size',
              'labelAr': 'المقاس',
              'labelEn': 'Size',
              'displayMode': 'chips',
              'selectionMode': 'single',
              'required': true,
              'options': [
                {
                  'code': 's',
                  'labelAr': 'S',
                  'labelEn': 'S',
                  'isAvailable': true,
                },
                {
                  'code': 'l',
                  'labelAr': 'L',
                  'labelEn': 'L',
                  'isAvailable': true,
                },
              ],
            },
          ],
          'variants': [
            {
              'id': 201,
              'signature': 'color:red|size:s',
              'selections': [
                {'groupCode': 'color', 'optionCode': 'red'},
                {'groupCode': 'size', 'optionCode': 's'},
              ],
              'stockQuantity': 5,
              'isAvailable': true,
            },
            {
              'id': 202,
              'signature': 'color:blue|size:l',
              'selections': [
                {'groupCode': 'color', 'optionCode': 'blue'},
                {'groupCode': 'size', 'optionCode': 'l'},
              ],
              'stockQuantity': 5,
              'isAvailable': true,
            },
          ],
          'media': [
            {
              'imageUrl': '/red.jpg',
              'variantGroupCode': 'color',
              'variantOptionCode': 'red',
              'isPrimary': true,
              'sortOrder': 0,
            },
            {
              'imageUrl': '/blue.jpg',
              'variantGroupCode': 'color',
              'variantOptionCode': 'blue',
              'isPrimary': false,
              'sortOrder': 1,
            },
          ],
        },
      ],
      'pagination': {'nextOffset': null},
    };
  }
}

void main() {
  testWidgets(
    'customer search uses the shared image-first card and seeds picker color',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [ordersApiProvider.overrideWithValue(_FakeOrdersApi())],
          child: const MaterialApp(home: CustomerGlobalProductSearchScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(TextField), 'قميص');
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(ProductSummaryCard), findsOneWidget);
      expect(find.text('Clothes / ملابس'), findsOneWidget);

      await tester.tap(find.text('أزرق'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('إضافة'));
      await tester.pump(const Duration(milliseconds: 400));

      final blueChip = tester.widget<ChoiceChip>(
        find
            .ancestor(of: find.text('أزرق'), matching: find.byType(ChoiceChip))
            .first,
      );
      expect(blueChip.selected, isTrue);
    },
  );

  testWidgets(
    'quick order opens cart from the selected shared card state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [ordersApiProvider.overrideWithValue(_FakeOrdersApi())],
          child: const MaterialApp(home: CustomerGlobalProductSearchScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(TextField), 'قميص');
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('أزرق'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('طلب سريع'));
      await tester.pump(const Duration(milliseconds: 800));

      final element = tester.element(
        find.byType(CustomerGlobalProductSearchScreen),
      );
      final container = ProviderScope.containerOf(element);
      final cart = container.read(cartControllerProvider);
      expect(cart.items, hasLength(1));
      expect(
        cart.items.first.selectedVariantSelections.any(
          (selection) => selection['optionCode'] == 'blue',
        ),
        isTrue,
      );
    },
  );
}
