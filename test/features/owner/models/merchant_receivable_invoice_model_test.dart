import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/owner/models/merchant_receivable_invoice_model.dart';

void main() {
  test(
    'MerchantReceivableInvoiceModel reads stored service fee amount directly',
    () {
      final model = MerchantReceivableInvoiceModel.fromJson({
        'id': 7,
        'order_id': 42,
        'invoice_number': 'INV-42',
        'issued_at': '2026-07-05T10:00:00.000Z',
        'order_status': 'delivered',
        'subtotal': 10000,
        'commission_amount': 1200,
        'service_fee_amount': 500,
        'app_delivery_fee_amount': 1000,
        'store_delivery_fee_amount': 0,
        'app_receivable_amount': 12500,
        'store_net_amount': 9300,
        'paid_amount': 9300,
        'outstanding_amount': 0,
        'invoice_status': 'paid',
      });

      expect(model.id, 7);
      expect(model.orderId, 42);
      expect(model.serviceFeeAmount, 500);
      expect(model.invoiceStatus, 'paid');
    },
  );
}
