import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/delivery/data/delivery_api.dart';
import 'package:maslaki/features/delivery/state/delivery_controller.dart';
import 'package:maslaki/features/delivery/ui/courier_pages.dart';
import 'package:maslaki/features/delivery/ui/delivery_dashboard_screen.dart';
import 'package:maslaki/features/delivery/ui/delivery_order_detail_screen.dart';
import 'package:maslaki/features/orders/models/order_model.dart';
import 'package:maslaki/features/orders/models/order_revision_model.dart';
import 'package:maslaki/features/orders/ui/widgets/order_item_widgets.dart';
import 'package:maslaki/l10n/app_localizations.dart';

/// Fake API that returns a canonical delivery order-detail payload, matching
/// the shape produced by the backend `GET /api/delivery/orders/:orderId`.
class _FakeDeliveryApi extends DeliveryApi {
  _FakeDeliveryApi(this.detail) : super(Dio());

  final Map<String, dynamic> detail;

  @override
  Future<Map<String, dynamic>> orderDetailV2(int orderId) async => detail;

  @override
  Future<List<OrderRevisionModel>> listOrderRevisions(int orderId) async {
    return const <OrderRevisionModel>[];
  }
}

Map<String, dynamic> _cannedDetail() {
  final item = {
    'id': 1,
    'order_id': 7,
    'product_name': 'Test Product',
    'quantity': 2,
    'unit_price': 5000,
    'line_total': 10000,
  };
  return {
    'order': {
      'id': 7,
      'merchant_id': 3,
      'customer_user_id': 11,
      'merchant_name': 'Test Merchant',
      'status': 'on_the_way',
      'customer_full_name': 'Test Customer',
      'customer_phone': '0770000000',
      'customer_city': 'Basmaya',
      'customer_block': 'A1',
      'customer_building_number': '12',
      'customer_apartment': '3',
      'subtotal': 10000,
      'gross_subtotal': 10000,
      'service_fee': 1500,
      'delivery_fee': 3000,
      'product_discount_total': 0,
      'coupon_discount_total': 0,
      'total_amount': 14500,
      'payment_method': 'cash',
      'orderState': 'ready',
      'courierState': 'on_the_way',
      'items': [item],
    },
    'items': [item],
    'merchant': {'id': 3, 'name': 'Test Merchant', 'phone': '0780000000'},
    'customer': {'userId': 11, 'fullName': 'Test Customer', 'phone': '0770'},
    'invoice': {
      'grossSubtotal': 10000,
      'productDiscountTotal': 0,
      'subtotal': 10000,
      'serviceFee': 1500,
      'deliveryFee': 3000,
      'couponDiscountTotal': 0,
      'totalAmount': 14500,
      'paymentMethod': 'cash',
    },
    'timeline': const [],
    'allowedActions': const ['arrived'],
  };
}

Widget _wrap(Widget child, DeliveryApi api) {
  return ProviderScope(
    overrides: [deliveryApiProvider.overrideWithValue(api)],
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.dark(),
      home: child,
    ),
  );
}

Future<void> _settleLoad(WidgetTester tester) async {
  // The detail screen shows a CircularProgressIndicator while loading, so we
  // cannot pumpAndSettle (it never settles). Pump a few frames instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('delivery order detail shows items, fees and final total', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const DeliveryOrderDetailScreen(orderId: 7),
        _FakeDeliveryApi(_cannedDetail()),
      ),
    );
    await _settleLoad(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(OrderItemsSummaryList), findsOneWidget);
    expect(find.text('Test Product'), findsOneWidget);
    expect(find.byType(OrderItemPriceBreakdownRow), findsOneWidget);
  });

  testWidgets('CourierOrderDetailsPage routes to the detail screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const CourierOrderDetailsPage(orderId: 7),
        _FakeDeliveryApi(_cannedDetail()),
      ),
    );
    await _settleLoad(tester);

    expect(find.byType(DeliveryOrderDetailScreen), findsOneWidget);
  });

  testWidgets('CourierOrderDetailsPage with null id does not open detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const CourierOrderDetailsPage(orderId: null),
        _FakeDeliveryApi(_cannedDetail()),
      ),
    );
    await tester.pump();

    expect(find.byType(DeliveryOrderDetailScreen), findsNothing);
  });

  testWidgets('tapping an order card opens the detail screen', (tester) async {
    final order = OrderModel.fromJson({
      'id': 7,
      'merchant_id': 3,
      'customer_user_id': 11,
      'merchant_name': 'Test Merchant',
      'status': 'on_the_way',
      'customer_full_name': 'Test Customer',
      'customer_phone': '0770000000',
      'customer_city': 'Basmaya',
      'customer_block': 'A1',
      'customer_building_number': '12',
      'customer_apartment': '3',
      'subtotal': 10000,
      'service_fee': 1500,
      'delivery_fee': 3000,
      'total_amount': 14500,
      'delivery_user_id': null,
      'items': const <dynamic>[],
    });

    await tester.pumpWidget(
      _wrap(
        Scaffold(body: DeliveryCurrentOrderCard(order: order)),
        _FakeDeliveryApi(_cannedDetail()),
      ),
    );
    await tester.pump();

    // The card must not assert a misleading "0 items" when the list payload
    // carried no items — it surfaces a "View details" hint instead.
    expect(
      find.text('Tap "View details" to see items and the full invoice'),
      findsOneWidget,
    );

    // Tapping the card body (the merchant line) opens the full detail screen.
    await tester.tap(find.textContaining('Test Merchant'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DeliveryOrderDetailScreen), findsOneWidget);
  });

  testWidgets('view details button opens the detail screen', (tester) async {
    final order = OrderModel.fromJson({
      'id': 7,
      'merchant_id': 3,
      'customer_user_id': 11,
      'merchant_name': 'Test Merchant',
      'status': 'on_the_way',
      'customer_full_name': 'Test Customer',
      'customer_phone': '0770000000',
      'customer_city': 'Basmaya',
      'customer_block': 'A1',
      'customer_building_number': '12',
      'customer_apartment': '3',
      'subtotal': 10000,
      'service_fee': 1500,
      'delivery_fee': 3000,
      'total_amount': 14500,
      'delivery_user_id': null,
      'items': const <dynamic>[],
    });

    await tester.pumpWidget(
      _wrap(
        Scaffold(body: DeliveryCurrentOrderCard(order: order)),
        _FakeDeliveryApi(_cannedDetail()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('View details & invoice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DeliveryOrderDetailScreen), findsOneWidget);
  });
}
