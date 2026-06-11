import 'dart:io';

import 'package:maslaki/core/notifications/notification_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Notification routing resolver', () {
    test('Courier notifications resolve to courier module only', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'courier_order_offer',
        orderId: 44,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'courier',
        rawTarget: target,
        type: 'courier_order_offer',
      );
      expect(target, anyOf('courier_orders_new', 'courier_orders_current'));
      expect(module, 'courier');
    });

    test('Taxi notifications resolve to taxi module only', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'taxi_trip_offer',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'taxi_captain',
        rawTarget: target,
        type: 'taxi_trip_offer',
      );
      expect(target, 'taxi_trips_new');
      expect(module, 'taxi');
    });

    test('Taxi trip details type resolves to taxi_trip_details', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'taxi.ride.details',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'taxi_captain',
        rawTarget: target,
        type: 'taxi.ride.details',
      );
      expect(target, 'taxi_trip_details');
      expect(module, 'taxi');
    });

    test('Taxi completed type resolves to completed trips target', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'taxi.completed',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'taxi_captain',
        rawTarget: target,
        type: 'taxi.completed',
      );
      expect(target, 'taxi_trips_completed');
      expect(module, 'taxi');
    });

    test('Merchant payment notifications resolve to merchant receivables', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'merchant_payment_confirmed',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'owner',
        rawTarget: target,
        type: 'merchant_payment_confirmed',
      );
      expect(target, 'merchant_receivables');
      expect(module, 'merchant');
    });

    test('Services request notifications resolve to request details target', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'services.request.created',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: 'customer',
        roleScope: 'customer',
        rawTarget: target,
        type: 'services.request.created',
      );
      expect(target, 'service_request_details');
      expect(module, 'customer');
    });

    test('Pharmacy cart proposed notifications resolve to pharmacy conversation', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'pharmacy.cart.proposed',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'customer',
        rawTarget: target,
        type: 'pharmacy.cart.proposed',
      );
      expect(target, 'pharmacy_conversation');
      expect(module, 'customer');
    });

    test('Owner pharmacy notifications resolve to merchant module', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'pharmacy.order.created',
        orderId: 17,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'owner',
        rawTarget: null,
        type: 'pharmacy.order.created',
      );
      expect(target, 'order_tracking');
      expect(module, 'merchant');
    });

    test('Admin payment notifications resolve to admin payment requests', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'admin_payment_request',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'admin',
        rawTarget: target,
        type: 'admin_payment_request',
      );
      expect(target, 'admin_payment_requests');
      expect(module, 'admin');
    });

    test(
      'Admin ops alert types resolve to notification center target',
      () {
        final target = NotificationNavigation.resolveTarget(
          rawTarget: null,
          type: 'admin.ops.alert.critical',
          orderId: null,
        );
        final module = NotificationNavigation.resolveModule(
          rawModule: null,
          roleScope: 'admin',
          rawTarget: target,
          type: 'admin.ops.alert.critical',
        );
        expect(target, 'admin_ops_notification_center');
        expect(module, 'admin');
      },
    );

    test('Admin ops crash types resolve to crash center target', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'admin.ops.crash.detected',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'admin',
        rawTarget: target,
        type: 'admin.ops.crash.detected',
      );
      expect(target, 'admin_ops_crash_center');
      expect(module, 'admin');
    });

    test('Customer order updates resolve to order tracking', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'customer_order_update',
        orderId: 91,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'customer',
        rawTarget: target,
        type: 'customer_order_update',
      );
      expect(target, 'order_tracking');
      expect(module, 'customer');
    });

    test(
      'Social post notifications resolve to social module and post target',
      () {
        final target = NotificationNavigation.resolveTarget(
          rawTarget: null,
          type: 'social.post.created',
          orderId: null,
        );
        final module = NotificationNavigation.resolveModule(
          rawModule: null,
          roleScope: 'customer',
          rawTarget: target,
          type: 'social.post.created',
        );
        expect(target, 'social_post');
        expect(module, 'customer');
      },
    );

    test('Social chat notifications resolve to social chat target', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'social.chat.message',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'customer',
        rawTarget: target,
        type: 'social.chat.message',
      );
      expect(target, 'social_chat');
      expect(module, 'customer');
    });

    test('Social reel notifications resolve to reels target', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'social.reel.comment',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'customer',
        rawTarget: target,
        type: 'social.reel.comment',
      );
      expect(target, 'social_reel');
      expect(module, 'customer');
    });
  });

  group('Notification lifecycle wiring', () {
    test('Foreground/background/terminated entry points are wired', () {
      final pushFile = File(
        'packages/core_notifications/lib/core_notifications.dart',
      );
      final userRuntimeFile = File(
        'packages/app_user_runtime/lib/app_user_runtime.dart',
      );

      expect(pushFile.existsSync(), isTrue);
      expect(userRuntimeFile.existsSync(), isTrue);

      final pushContent = pushFile.readAsStringSync();
      final mainContent = userRuntimeFile.readAsStringSync();

      // Terminated (FCM) and background-open.
      expect(pushContent.contains('getInitialMessage()'), isTrue);
      expect(pushContent.contains('onMessageOpenedApp.listen'), isTrue);
      // Foreground.
      expect(pushContent.contains('onMessage.listen'), isTrue);
      // Terminated (local notifications launch).
      expect(
        pushContent.contains('getNotificationAppLaunchDetails()'),
        isTrue,
      );
      // Unified tap handling in the split user runtime.
      expect(
        mainContent.contains('runtimeLocalNotificationsProvider'),
        isTrue,
      );
      expect(mainContent.contains('runtimePushNotificationsProvider'), isTrue);
      expect(mainContent.contains('_handleRuntimeNotificationTap'), isTrue);
    });
  });
}
