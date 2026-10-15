import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/notifications/local_notification_service.dart';
import 'package:maslaki/core/notifications/push_notification_service.dart';
import 'package:maslaki/core/platform/app_flavor.dart';

void main() {
  group('notification surface isolation', () {
    test('delivery notifications are rejected by the customer app', () {
      const payload = NotificationTapPayload(
        type: 'delivery_grouped_assigned',
        appSurface: 'delivery',
      );

      expect(
        notificationPayloadMatchesAppFlavor(payload, AppFlavor.user),
        isFalse,
      );
      expect(
        notificationPayloadMatchesAppFlavor(payload, AppFlavor.delivery),
        isTrue,
      );
    });

    test('unknown audience is rejected instead of being shown everywhere', () {
      const payload = NotificationTapPayload(type: 'delivery_order_assigned');

      expect(
        notificationPayloadMatchesAppFlavor(payload, AppFlavor.user),
        isFalse,
      );
      expect(
        notificationPayloadMatchesAppFlavor(payload, AppFlavor.delivery),
        isFalse,
      );
    });

    test('company alerts remain available in the admin-enabled user surface', () {
      const payload = NotificationTapPayload(appSurface: 'company');

      expect(
        notificationPayloadMatchesAppFlavor(payload, AppFlavor.user),
        isTrue,
      );
      expect(
        notificationPayloadMatchesAppFlavor(payload, AppFlavor.delivery),
        isFalse,
      );
    });
  });
}
