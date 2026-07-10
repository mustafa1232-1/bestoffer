import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/admin/data/admin_api.dart';
import 'package:maslaki/features/admin/state/admin_controller.dart';
import 'package:maslaki/features/admin/ui/admin_orders_overview_screen.dart';
import 'package:maslaki/features/orders/ui/widgets/order_item_widgets.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAdminApi extends AdminApi {
  _FakeAdminApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> ordersOverview({
    String status = 'all',
    String period = 'all',
    String? from,
    String? to,
    String? search,
    int limit = 60,
    int offset = 0,
  }) async {
    return {
      'summary': {
        'totalOrders': 1,
        'completedOrders': 0,
        'cancelledOrders': 0,
        'inProgressOrders': 1,
      },
      'items': [
        {
          'merchantId': 9,
          'merchantName': 'Test Store',
          'merchantType': 'fashion',
          'merchantPhone': '07700000000',
          'ownerUserId': 31,
          'ownerFullName': 'Store Owner',
          'ownerPhone': '07711111111',
          'ordersCount': 1,
          'lastOrderAt': '2026-07-10T08:00:00.000Z',
        },
      ],
      'total': 1,
      'limit': limit,
      'offset': offset,
    };
  }

  @override
  Future<Map<String, dynamic>> merchantOrdersOverview(
    int merchantId, {
    String status = 'all',
    String period = 'all',
    String? from,
    String? to,
    int limit = 80,
    int offset = 0,
  }) async {
    return {
      'merchantId': merchantId,
      'items': [
        {
          'id': 5001,
          'merchant_id': merchantId,
          'customer_user_id': 7001,
          'order_scope': 'single',
          'store_sequence': 1,
          'merchant_name': 'Test Store',
          'status': 'approved',
          'customer_full_name': 'Test Customer',
          'customer_phone': '07700000000',
          'customer_city': 'Baghdad',
          'customer_block': 'A',
          'customer_building_number': '12',
          'customer_apartment': '3',
          'gross_subtotal': 10000,
          'product_discount_total': 0,
          'subtotal': 10000,
          'service_fee': 500,
          'delivery_fee': 1000,
          'coupon_discount_total': 0,
          'total_amount': 11500,
          'delivery_user_id': 21,
          'is_merchant_delivery': false,
          'courier_source': 'app',
          'delivery_driver_type': 'app_driver',
          'archived_by_delivery': false,
          'items': [
            {
              'id': 1,
              'order_id': 5001,
              'product_id': 55,
              'product_name': 'Fashion Hoodie',
              'merchant_name': 'Test Store',
              'merchant_id': merchantId,
              'base_unit_price': 10000,
              'unit_price': 10000,
              'quantity': 1,
              'line_discount_total': 0,
              'line_total': 10000,
              'variant_price_delta_total': 0,
              'selected_variant_options_json': [
                {
                  'groupLabel': 'Color',
                  'optionLabel': 'Black',
                  'hex': '#000000',
                },
                {'groupLabel': 'Size', 'optionLabel': 'XL'},
              ],
              'display_snapshot_json': {
                'version': 1,
                'productId': 55,
                'productName': 'Fashion Hoodie',
                'productImageUrl': 'https://example.com/fashion-hoodie.jpg',
                'thumbnailUrl': 'https://example.com/fashion-hoodie-thumb.jpg',
                'sku': 'HOODIE-001',
                'variantId': 1012,
                'variantName': 'Black / XL',
                'variantSku': 'HOODIE-BLACK-XL',
                'quantity': 1,
                'unitPrice': 10000,
                'lineTotal': 10000,
                'currency': 'IQD',
                'selectedColor': {
                  'label': 'Color',
                  'value': 'Black',
                  'hex': '#000000',
                },
                'selectedSize': {'label': 'Size', 'value': 'XL'},
                'specs': [
                  {'label': 'Color', 'value': 'Black', 'hex': '#000000'},
                  {'label': 'Size', 'value': 'XL'},
                ],
                'options': [],
                'addons': [],
                'removals': [],
                'userNote': 'Leave at reception',
                'activityType': 'fashion_clothing',
                'storeId': merchantId,
                'storeName': 'Test Store',
              },
            },
          ],
        },
      ],
      'summary': const {},
      'total': 1,
      'limit': limit,
      'offset': offset,
    };
  }
}

void main() {
  testWidgets(
    'admin orders overview preserves item snapshot details in order detail',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminApiProvider.overrideWithValue(_FakeAdminApi())],
          child: const MaterialApp(
            locale: Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: AdminOrdersOverviewScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Test Store'), findsOneWidget);
      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();

      expect(find.text('Test Customer'), findsOneWidget);
      await tester.tap(find.text('Test Customer'));
      await tester.pumpAndSettle();

      expect(
        find.text('راجع المنتجات والمواصفات قبل الموافقة'),
        findsOneWidget,
      );
      expect(find.byType(OrderItemsSummaryList), findsOneWidget);
      expect(find.byType(OrderItemMiniCard), findsOneWidget);
      expect(find.byType(OrderItemThumbnail), findsOneWidget);
      expect(find.text('Color: Black'), findsOneWidget);
      expect(find.text('Size: XL'), findsOneWidget);
      expect(find.textContaining('Leave at reception'), findsOneWidget);
    },
  );
}
