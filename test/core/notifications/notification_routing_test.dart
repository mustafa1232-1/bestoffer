import 'dart:io';

import 'package:maslaki/core/platform/app_flavor.dart';
import 'package:maslaki/core/notifications/notification_navigation.dart';
import 'package:maslaki/features/notifications/models/app_notification_model.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

AuthState _serviceProviderAuth() {
  return AuthState(
    user: UserModel(
      id: 1,
      fullName: 'Service Provider',
      phone: '0770000000',
      role: 'service_provider',
      block: 'A',
      buildingNumber: '101',
      apartment: '1',
      imageUrl: null,
      workTitle: null,
      workCompany: null,
      preferredLocale: 'ar',
      isSuperAdmin: false,
    ),
    token: 'token',
  );
}

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

    test('Taxi offer notifications resolve to the live taxi target', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'taxi_offer_received',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'customer',
        rawTarget: target,
        type: 'taxi_offer_received',
      );
      expect(target, 'taxi_live');
      expect(module, 'taxi');
    });

    test('Taxi ride requested notifications resolve to new taxi requests', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'taxi_ride_requested',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'taxi_captain',
        rawTarget: target,
        type: 'taxi_ride_requested',
      );
      expect(target, 'taxi_trips_new');
      expect(module, 'taxi');
    });

    test('Taxi ride requested dotted alias resolves to new taxi requests', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'taxi.ride.requested',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'taxi_captain',
        rawTarget: target,
        type: 'taxi.ride.requested',
      );
      expect(target, 'taxi_trips_new');
      expect(module, 'taxi');
    });

    test('Taxi competition notifications resolve to competitions target', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'taxi.competition.progress',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'taxi_captain',
        rawTarget: target,
        type: 'taxi.competition.progress',
      );
      expect(target, 'taxi_competitions');
      expect(module, 'taxi');
    });

    test('Taxi chat notifications resolve to live taxi target', () {
      final target = NotificationNavigation.resolveTarget(
        rawTarget: null,
        type: 'taxi_chat_message',
        orderId: null,
      );
      final module = NotificationNavigation.resolveModule(
        rawModule: null,
        roleScope: 'taxi_captain',
        rawTarget: target,
        type: 'taxi_chat_message',
      );
      expect(target, 'taxi_live');
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

    test('Taxi notification tap payload preserves offer identifiers', () {
      const model = AppNotificationModel(
        id: 501,
        orderId: null,
        rideId: null,
        storyId: null,
        reelId: null,
        merchantId: null,
        target: 'taxi_live',
        type: 'taxi_offer_received',
        title: 'Offer received',
        body: 'Captain sent an offer',
        payload: <String, dynamic>{
          'rideId': 41,
          'offerId': 12,
          'bidId': 12,
          'captainId': 77,
          'customerUserId': 9,
          'target': 'taxi_live',
          'targetModule': 'taxi',
        },
        isRead: false,
        createdAt: null,
        readAt: null,
      );

      final payload = NotificationNavigation.payloadFromModel(model);
      expect(payload.rideId, 41);
      expect(payload.offerId, 12);
      expect(payload.bidId, 12);
      expect(payload.captainId, 77);
      expect(payload.customerUserId, 9);
      expect(payload.target, 'taxi_live');
    });

    test(
      'Car listing notifications resolve to direct customer detail target',
      () {
        final target = NotificationNavigation.resolveTarget(
          rawTarget: null,
          type: 'car_listing',
          orderId: null,
        );
        final module = NotificationNavigation.resolveModule(
          rawModule: null,
          roleScope: 'customer',
          rawTarget: target,
          type: 'car_listing',
        );
        expect(target, 'car_listing');
        expect(module, 'customer');
      },
    );

    test(
      'Real estate listing notifications resolve to direct customer detail target',
      () {
        final target = NotificationNavigation.resolveTarget(
          rawTarget: null,
          type: 'real_estate_listing',
          orderId: null,
        );
        final module = NotificationNavigation.resolveModule(
          rawModule: null,
          roleScope: 'customer',
          rawTarget: target,
          type: 'real_estate_listing',
        );
        expect(target, 'real_estate_listing');
        expect(module, 'customer');
      },
    );

    test(
      'Notification payload fallback parses listingId for marketplace deep links',
      () {
        const model = AppNotificationModel(
          id: 502,
          orderId: null,
          rideId: null,
          storyId: null,
          reelId: null,
          merchantId: null,
          target: 'car_listing',
          type: 'car_listing',
          title: 'Car listing',
          body: 'Open the listing',
          payload: <String, dynamic>{
            'listingId': 88,
            'target': 'car_listing',
            'targetModule': 'customer',
          },
          isRead: false,
          createdAt: null,
          readAt: null,
        );

        final payload = NotificationNavigation.payloadFromModel(model);
        expect(payload.entityId, 88);
        expect(payload.target, 'car_listing');
      },
    );

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

    test(
      'Services request notifications resolve to request details target',
      () {
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
      },
    );

    test(
      'Service offering moderation notifications resolve to the admin review queue target',
      () {
        final target = NotificationNavigation.resolveTarget(
          rawTarget: null,
          type: 'services.offering.pending_review',
          orderId: null,
        );
        expect(target, 'admin_services_offerings_pending');
      },
    );

    test(
      'Pharmacy cart proposed notifications resolve to pharmacy conversation',
      () {
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
      },
    );

    test(
      'Pharmacy order created store notifications preserve direct owner target',
      () {
        const model = AppNotificationModel(
          id: 503,
          orderId: null,
          rideId: null,
          storyId: null,
          reelId: null,
          merchantId: null,
          target: 'owner_order_details',
          type: 'pharmacy.order.created.store',
          title: 'Order created',
          body: 'Pharmacy order created',
          payload: <String, dynamic>{
            'target': 'owner_order_details',
            'orderId': 731,
            'conversationId': 44,
            'merchantId': 9,
          },
          isRead: false,
          createdAt: null,
          readAt: null,
        );

        final payload = NotificationNavigation.payloadFromModel(model);
        expect(payload.target, 'owner_order_details');
        expect(payload.orderId, 731);

        final target = NotificationNavigation.resolveTarget(
          rawTarget: payload.target,
          type: model.type,
          orderId: payload.orderId,
        );
        final module = NotificationNavigation.resolveModule(
          rawModule: null,
          roleScope: 'owner',
          rawTarget: payload.target,
          type: model.type,
        );
        expect(target, 'owner_order_details');
        expect(module, 'merchant');
      },
    );

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

    test(
      'Service provider auth is allowed on user flavor and owner order notifications open details',
      () {
        final auth = _serviceProviderAuth();
        expect(
          NotificationNavigation.isFlavorAllowedForAuth(AppFlavor.user, auth),
          true,
        );

        final target = NotificationNavigation.resolveTarget(
          rawTarget: 'merchant_order_details',
          type: 'owner_new_order',
          orderId: 19,
        );
        final module = NotificationNavigation.resolveModule(
          rawModule: null,
          roleScope: 'merchant',
          rawTarget: target,
          type: 'owner_new_order',
        );
        expect(target, 'merchant_order_details');
        expect(module, 'merchant');
      },
    );

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

    test('Admin ops alert types resolve to notification center target', () {
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
    });

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
      expect(pushContent.contains('getNotificationAppLaunchDetails()'), isTrue);
      // Unified tap handling in the split user runtime.
      expect(mainContent.contains('runtimeLocalNotificationsProvider'), isTrue);
      expect(mainContent.contains('runtimePushNotificationsProvider'), isTrue);
      expect(mainContent.contains('_handleRuntimeNotificationTap'), isTrue);
    });
  });
}
