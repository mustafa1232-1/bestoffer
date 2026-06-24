import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/notifications/notification_navigation.dart';

void main() {
  group('isRestrictedForDelivery', () {
    test('blocks social / community surfaces', () {
      expect(
        NotificationNavigation.isRestrictedForDelivery(
          'social',
          'social_community',
        ),
        isTrue,
      );
      expect(
        NotificationNavigation.isRestrictedForDelivery('', 'social_profile'),
        isTrue,
      );
      expect(
        NotificationNavigation.isRestrictedForDelivery('', 'social_reel'),
        isTrue,
      );
      expect(
        NotificationNavigation.isRestrictedForDelivery('', 'community'),
        isTrue,
      );
    });

    test('blocks customer surfaces', () {
      expect(
        NotificationNavigation.isRestrictedForDelivery(
          'customer',
          'customer_orders_current',
        ),
        isTrue,
      );
      expect(
        NotificationNavigation.isRestrictedForDelivery('', 'customer_home'),
        isTrue,
      );
    });

    test('allows courier surfaces and order tracking', () {
      expect(
        NotificationNavigation.isRestrictedForDelivery(
          'courier',
          'courier_orders_current',
        ),
        isFalse,
      );
      // An assigned courier is allowed to open live tracking.
      expect(
        NotificationNavigation.isRestrictedForDelivery(
          'customer',
          'order_tracking',
        ),
        isFalse,
      );
      expect(
        NotificationNavigation.isRestrictedForDelivery('taxi', 'taxi_live'),
        isFalse,
      );
    });
  });
}
