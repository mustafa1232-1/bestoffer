import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/utils/order_status.dart';

void main() {
  group('order status copy', () {
    test('maps status labels consistently', () {
      expect(orderStatusLabel('pending'), isNotEmpty);
      expect(orderStatusLabel('ready_for_delivery'), isNotEmpty);
      expect(orderStatusLabel('unknown_state'), 'unknown_state');
    });

    test('owner hints stop when the courier completes delivery', () {
      expect(
        ownerOrderStatusHint(
          'approved',
          hasDeliveryAssigned: false,
          customerConfirmed: false,
        ),
        isNotNull,
      );
      expect(
        ownerOrderStatusHint(
          'approved',
          hasDeliveryAssigned: true,
          customerConfirmed: false,
        ),
        isNotNull,
      );
      expect(
        ownerOrderStatusHint(
          'delivered',
          hasDeliveryAssigned: true,
          customerConfirmed: true,
        ),
        isNull,
      );
    });

    test('delivery hints stop after the courier marks delivery complete', () {
      expect(
        deliveryOrderStatusHint('ready_for_delivery', customerConfirmed: false),
        isNotNull,
      );
      expect(
        deliveryOrderStatusHint('delivered', customerConfirmed: true),
        isNull,
      );
    });

    test('customer tracking hints stop when delivery is complete', () {
      expect(
        customerOrderTrackingHint(
          'pending',
          hasDeliveryAssigned: false,
          customerConfirmed: false,
        ),
        isNotNull,
      );
      expect(
        customerOrderTrackingHint(
          'approved',
          hasDeliveryAssigned: false,
          customerConfirmed: false,
        ),
        isNotNull,
      );
      expect(
        customerOrderTrackingHint(
          'approved',
          hasDeliveryAssigned: true,
          customerConfirmed: false,
        ),
        isNotNull,
      );
      expect(
        customerOrderTrackingHint(
          'delivered',
          hasDeliveryAssigned: true,
          customerConfirmed: false,
        ),
        isNull,
      );
    });
  });
}
