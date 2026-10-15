import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/orders/ui/widgets/customer_active_order_banner_logic.dart';

void main() {
  test('a delivered order immediately leaves the active banner', () {
    expect(shouldShowCustomerActiveOrderBanner(status: 'delivered'), isFalse);
  });

  test('active orders stay visible and terminal orders are hidden', () {
    for (final status in ['pending', 'preparing', 'on_the_way']) {
      expect(shouldShowCustomerActiveOrderBanner(status: status), isTrue);
    }
    for (final status in [
      'completed',
      'received',
      'cancelled',
      'failed_delivery',
    ]) {
      expect(shouldShowCustomerActiveOrderBanner(status: status), isFalse);
    }
  });
}
