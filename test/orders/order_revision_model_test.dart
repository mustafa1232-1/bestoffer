import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/orders/models/order_revision_model.dart';

void main() {
  test('order revision model parses totals, approvals, and waiting states', () {
    final revision = OrderRevisionModel.fromJson({
      'id': 7,
      'order_id': 22,
      'support_ticket_id': 4,
      'version_number': 2,
      'base_order_version': 1,
      'status': 'AWAITING_BOTH',
      'reason': 'customer correction',
      'price_difference': '1500',
      'original_totals_json': {'totalAmount': 2000},
      'proposed_totals_json': {'totalAmount': 3500},
      'original_items_json': [
        {'productId': 10, 'productName': 'Rice', 'quantity': 2},
      ],
      'proposed_items_json': [
        {'productId': 10, 'productName': 'Rice', 'quantity': 3},
        {'productId': 11, 'productName': 'Tea', 'quantity': 1},
      ],
      'approvals_required_json': ['CUSTOMER', 'MERCHANT'],
      'payment_effect_json': {'direction': 'customer_owes'},
    });

    expect(revision.orderId, 22);
    expect(revision.isWaitingForCustomer, isTrue);
    expect(revision.isWaitingForMerchant, isTrue);
    expect(revision.proposedItems.length, 2);
    expect(revision.proposedTotals.totalAmount, 3500);
    expect(revision.approvalsRequired, ['CUSTOMER', 'MERCHANT']);
  });
}
