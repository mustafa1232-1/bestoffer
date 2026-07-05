import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/orders/models/order_model.dart';
import 'package:maslaki/features/owner/printing/receipt_builder.dart';
import 'package:maslaki/features/owner/printing/models/receipt_print_data.dart';

Map<String, dynamic> _orderJson() {
  return {
    'id': 99,
    'merchant_id': 3,
    'customer_user_id': 11,
    'merchant_name': 'Test Merchant',
    'status': 'delivered',
    'customer_full_name': 'Test Customer',
    'customer_phone': '0770000000',
    'customer_city': 'Basmaya',
    'customer_block': 'A1',
    'customer_building_number': '12',
    'customer_apartment': '3',
    'subtotal': 10000,
    'gross_subtotal': 10000,
    'product_discount_total': 0,
    'service_fee': 500,
    'delivery_fee': 1000,
    'coupon_discount_total': 250,
    'total_amount': 11250,
    'items': [
      {
        'id': 1,
        'order_id': 99,
        'product_name': 'Burger',
        'quantity': 1,
        'base_unit_price': 10000,
        'unit_price': 10000,
        'line_total': 10000,
      },
    ],
  };
}

void main() {
  test('ReceiptPrintData and thermal builder preserve stored service fee', () {
    final order = OrderModel.fromJson(_orderJson());
    final data = ReceiptPrintData.fromOrder(
      order: order,
      assignmentMode: 'app_courier',
      appName: 'MASLAKI',
      cashierName: 'Cashier 1',
    );

    expect(data.totals.serviceFee, 500);

    final document = const ReceiptBuilder().build(
      data: data,
      options: const ReceiptBuildOptions(
        useArabicLabels: false,
        asciiSafe: true,
        lineWidth: 32,
      ),
    );

    final serviceLine = document.lines.firstWhere(
      (line) => line.contains('Service Fee'),
    );
    expect(serviceLine, contains('500'));
    expect(serviceLine, contains('IQD'));
  });
}
