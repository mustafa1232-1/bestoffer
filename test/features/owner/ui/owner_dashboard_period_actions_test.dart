import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/owner/models/owner_merchant_model.dart';
import 'package:maslaki/features/owner/state/owner_controller.dart';
import 'package:maslaki/features/owner/ui/widgets/owner_dashboard_overview_panel.dart';

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
    merchantTopProductsV2: const [
      {'product_name': 'Rice', 'qty_sold': 30, 'gross_amount': 30000},
      {'product_name': 'Tea', 'qty_sold': 18, 'gross_amount': 18000},
    ],
    merchantTopCategoriesV2: const [
      {'category_name': 'Grocery', 'qty_sold': 48, 'gross_amount': 48000},
    ],
  );
}

void main() {
  testWidgets(
    'owner dashboard KPI and period cards open the selected report window',
    (tester) async {
      final reportCalls = <Map<String, String>>[];
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
                      reportCalls.add({'period': period, 'title': title});
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

      expect(find.text('إجمالي المبيعات'), findsWidgets);
      expect(find.text('تقارير الفترات'), findsOneWidget);

      await tester.tap(find.text('إجمالي المبيعات').first);
      await tester.pumpAndSettle();
      expect(reportCalls.last['period'], 'all');
      expect(reportCalls.last['title'], 'الإجمالي');

      final periodCases = <MapEntry<String, String>>[
        const MapEntry('تفاصيل اليوم', 'day'),
        const MapEntry('تفاصيل الأسبوع', 'week'),
        const MapEntry('تفاصيل الشهر', 'month'),
      ];
      for (final entry in periodCases) {
        await tester.ensureVisible(find.text(entry.key));
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(reportCalls.last['period'], entry.value);
        expect(reportCalls.last['title'], entry.key);
      }

      await tester.ensureVisible(find.text('الطلبات').last);
      await tester.tap(find.text('الطلبات').last);
      await tester.pumpAndSettle();
      expect(currentOrdersTapped, isTrue);
    },
  );
}
