import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:maslaki/core/utils/report_printing.dart';

Map<String, dynamic> _orderRow({
  double? serviceFee,
  Map<String, dynamic>? snapshot,
  double totalAmount = 11250,
  int couponDiscountTotal = 250,
}) {
  return {
    'id': 42,
    'status': 'delivered',
    'merchant_name': 'Test Merchant',
    'customer_full_name': 'Test Customer',
    'customer_phone': '0770000000',
    'customer_city': 'Basmaya',
    'customer_block': 'A1',
    'customer_building_number': '12',
    'customer_apartment': '3',
    'subtotal': 10000,
    'service_fee': ?serviceFee,
    'delivery_fee': 1000,
    'coupon_discount_total': couponDiscountTotal,
    'total_amount': totalAmount,
    'financial_config_snapshot_json': ?snapshot,
    'created_at': '2026-07-05T09:00:00.000Z',
    'approved_at': '2026-07-05T09:10:00.000Z',
    'prepared_at': '2026-07-05T09:20:00.000Z',
    'picked_up_at': '2026-07-05T09:30:00.000Z',
    'delivered_at': '2026-07-05T09:40:00.000Z',
    'customer_confirmed_at': '2026-07-05T09:45:00.000Z',
    'items': [
      {
        'product_name': 'Item 1',
        'quantity': 1,
        'unit_price': 10000,
        'line_total': 10000,
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('orders report printing', () {
    test(
      'stored service fee wins even when coupon discount would make the total imply less',
      () {
        final rows = buildOrdersReportRows([
          _orderRow(serviceFee: 500, totalAmount: 11250),
        ]);

        expect(rows, hasLength(1));
        expect(rows.single.serviceFee, 500);
        expect(rows.single.totalAmount, 11250);
      },
    );

    test('old rows without service_fee fall back to snapshot value', () {
      final rows = buildOrdersReportRows([
        _orderRow(
          serviceFee: null,
          totalAmount: 11250,
          snapshot: {'serviceFeeAmount': 500},
        ),
      ]);

      expect(rows.single.serviceFee, 500);
    });

    test(
      'very old rows without service_fee use the legacy total math fallback',
      () {
        final rows = buildOrdersReportRows([
          _orderRow(serviceFee: null, totalAmount: 11500, snapshot: null),
        ]);

        expect(rows.single.serviceFee, 500);
      },
    );

    test(
      'PDF and Excel exports build from the same stored service fee data',
      () async {
        final orders = [_orderRow(serviceFee: 500, totalAmount: 11250)];
        final theme = pw.ThemeData.withFont(
          base: pw.Font.ttf(
            await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'),
          ),
          bold: pw.Font.ttf(
            await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'),
          ),
        );

        final pdfBytes = await buildOrdersReceiptReportPdfBytes(
          title: 'Owner final report',
          orders: orders,
          theme: theme,
        );
        expect(pdfBytes, isNotEmpty);

        final excelBytes = await buildOrdersReportExcelBytes(
          title: 'Owner final report',
          orders: orders,
        );
        expect(excelBytes, isNotEmpty);

        final workbook = Excel.decodeBytes(excelBytes);
        final ordersSheet = workbook.tables['Orders'];
        expect(ordersSheet, isNotNull);

        final serviceFeeCell = ordersSheet!
            .cell(CellIndex.indexByString('H2'))
            .value;
        expect(serviceFeeCell, const IntCellValue(500));
      },
    );
  });
}
