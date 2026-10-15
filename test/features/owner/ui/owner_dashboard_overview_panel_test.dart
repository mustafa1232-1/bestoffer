import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/owner/models/owner_merchant_model.dart';
import 'package:maslaki/features/owner/state/owner_controller.dart';
import 'package:maslaki/features/owner/ui/widgets/owner_dashboard_overview_panel.dart';
import 'package:maslaki/features/orders/models/order_model.dart';

OwnerMerchantModel _merchant() {
  return OwnerMerchantModel.fromJson({
    'id': 9,
    'name': 'Maslaki Store',
    'type': 'market',
    'activity_type': 'market',
    'is_open': true,
    'is_approved': true,
    'approval_status': 'approved',
    'supports_chat': true,
    'supports_attachments': true,
    'supports_pharmacy_workflow': false,
  });
}

OwnerState _state() {
  return OwnerState(
    merchant: _merchant(),
    analytics: {
      'day': {'orders_count': 3, 'delivery_fees': 3000},
      'month': {'orders_count': 10, 'delivery_fees': 10000},
      'year': {'orders_count': 24, 'delivery_fees': 24000},
    },
    settlementSummary: {'outstandingAmount': 125000, 'ordersCount': 7},
    merchantDashboardV2: {
      'kpis': {
        'totalOrders': 24,
        'completedOrders': 18,
        'cancelledOrders': 2,
        'activeOrders': 4,
        'grossSales': 240000,
        'avgOrderValue': 10000,
      },
    },
    merchantTopProductsV2: [
      {'product_name': 'Rice', 'qty_sold': 30, 'gross_amount': 30000},
      {'product_name': 'Tea', 'qty_sold': 18, 'gross_amount': 18000},
    ],
    merchantTopCategoriesV2: [
      {'category_name': 'Grocery', 'qty_sold': 48, 'gross_amount': 48000},
    ],
  );
}

OrderModel _reportOrder({
  int id = 101,
  String status = 'completed',
  num subtotal = 10000,
  num serviceFee = 500,
  num deliveryFee = 1000,
  num couponDiscountTotal = 250,
  num totalAmount = 11250,
}) {
  return OrderModel.fromJson({
    'id': id,
    'merchant_id': 9,
    'customer_user_id': 7001,
    'merchant_name': 'Maslaki Store',
    'customer_full_name': 'Test Customer',
    'customer_phone': '07700000000',
    'customer_city': 'Baghdad',
    'customer_block': 'A',
    'customer_building_number': '12',
    'customer_apartment': '3',
    'status': status,
    'subtotal': subtotal,
    'service_fee': serviceFee,
    'delivery_fee': deliveryFee,
    'coupon_discount_total': couponDiscountTotal,
    'total_amount': totalAmount,
    'items': const [],
  });
}

void main() {
  test('owner period report summary keeps stored service fee', () {
    final summary = buildOwnerPeriodReportSummary([_reportOrder()]);

    expect(summary.ordersCount, 1);
    expect(summary.subtotal, 10000);
    expect(summary.serviceFee, 500);
    expect(summary.deliveryFee, 1000);
    expect(summary.couponDiscount, 250);
    expect(summary.grossSales, 10000);
    expect(summary.completedOrders, 1);
    expect(summary.cancelledOrders, 0);
    expect(summary.activeOrders, 0);
    expect(summary.summaryLines.join(' '), contains('رسوم الخدمة المخزنة'));
  });

  test('owner period report summary excludes cancelled orders from sales', () {
    final summary = buildOwnerPeriodReportSummary([
      _reportOrder(),
      _reportOrder(
        id: 102,
        status: 'cancelled',
        subtotal: 8000,
        serviceFee: 500,
        deliveryFee: 1000,
        couponDiscountTotal: 0,
        totalAmount: 9500,
      ),
    ]);

    expect(summary.ordersCount, 2);
    expect(summary.completedOrders, 1);
    expect(summary.cancelledOrders, 1);
    expect(summary.subtotal, 10000);
    expect(summary.serviceFee, 500);
    expect(summary.deliveryFee, 1000);
    expect(summary.grossSales, 10000);
    expect(summary.avgOrderValue, 10000);
  });

  testWidgets('owner dashboard overview renders key actions and period cards', (
    tester,
  ) async {
    String? openedPeriod;
    String? openedTitle;
    var currentOrdersTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OwnerDashboardOverviewPanel(
              state: _state(),
              saving: false,
              onOpenPeriodReport:
                  ({required String period, required String title}) async {
                    openedPeriod = period;
                    openedTitle = title;
                  },
              onOpenCurrentOrders: () {
                currentOrdersTapped = true;
              },
              onOpenCatalog: () {},
              onOpenAddProduct: () {},
              onOpenKpis: () {},
              onOpenReceivables: () {},
              onOpenCouriers: () {},
              onOpenHr: () {},
              onOpenPrinterSettings: () {},
              onRequestSettlement: () async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('أهم الأرقام'), findsOneWidget);
    expect(find.text('تقارير الفترات'), findsOneWidget);
    expect(find.text('قيمة المنتجات'), findsWidgets);
    expect(find.text('المستحقات الحالية'), findsWidgets);

    await tester.ensureVisible(find.text('تفاصيل الأسبوع'));
    await tester.tap(find.text('تفاصيل الأسبوع'));
    await tester.pumpAndSettle();
    expect(openedPeriod, 'week');
    expect(openedTitle, 'تفاصيل الأسبوع');

    await tester.scrollUntilVisible(find.text('الطلبات').last, 200);
    await tester.tap(find.text('الطلبات').last);
    await tester.pumpAndSettle();
    expect(currentOrdersTapped, true);
  });
}
