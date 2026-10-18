import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/calls/incoming_call_service.dart';
import 'package:maslaki/core/notifications/local_notification_service.dart';
import 'package:maslaki/core/notifications/notification_navigation.dart';
import 'package:maslaki/core/notifications/push_notification_service.dart';
import 'package:maslaki/core/platform/app_flavor.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/notifications/models/app_notification_model.dart';

/// Pins the notification routing table (docs/notifications_routing_map.md):
/// every notification type opens its exact screen + entity for each role.
AuthState _auth(String role, {bool superAdmin = false}) {
  return AuthState(
    user: UserModel(
      id: 900,
      fullName: 'Role $role',
      phone: '0770000900',
      role: role,
      block: 'A',
      buildingNumber: '1',
      apartment: '1',
      imageUrl: null,
      workTitle: null,
      workCompany: null,
      preferredLocale: 'ar',
      isSuperAdmin: superAdmin,
    ),
    token: 'token',
  );
}

NotificationTapPayload _payload({
  required String type,
  String? target,
  String? appSurface,
  String? roleScope,
  String? targetModule,
  int? orderId,
  int? rideId,
  int? threadId,
  int? sessionId,
  int? requestId,
  int? postId,
  int? entityId,
  String? targetEntity,
  bool requiresAction = false,
}) {
  return NotificationTapPayload(
    type: type,
    target: target,
    appSurface: appSurface,
    roleScope: roleScope,
    targetModule: targetModule,
    orderId: orderId,
    rideId: rideId,
    threadId: threadId,
    sessionId: sessionId,
    requestId: requestId,
    postId: postId,
    entityId: entityId,
    targetEntity: targetEntity,
    requiresAction: requiresAction,
  );
}

void _expectRoute(
  AuthState auth,
  NotificationTapPayload payload,
  NotificationScreen screen, {
  int? id,
}) {
  final destination = NotificationNavigation.resolveDestination(
    auth: auth,
    payload: payload,
  );
  expect(destination, isNotNull, reason: '${payload.type} → null');
  expect(
    destination!.screen,
    screen,
    reason: '${auth.user?.role}: ${payload.type}/${payload.target}',
  );
  if (id != null) {
    expect(destination.id, id, reason: '${payload.type} entity id');
  }
}

void main() {
  group('Customer app routing table', () {
    final customer = _auth('user');

    test('order updates open that order', () {
      _expectRoute(
        customer,
        _payload(
          type: 'customer_order_status',
          target: 'order_tracking',
          appSurface: 'user',
          roleScope: 'customer',
          orderId: 123,
        ),
        NotificationScreen.customerOrderTracking,
        id: 123,
      );
      _expectRoute(
        customer,
        _payload(type: 'customer_order_delivered', orderId: 77),
        NotificationScreen.customerOrderTracking,
        id: 77,
      );
    });

    test('a message opens that conversation', () {
      _expectRoute(
        customer,
        _payload(
          type: 'social.chat.message',
          target: 'social_chat',
          appSurface: 'user',
          threadId: 5,
        ),
        NotificationScreen.socialChat,
        id: 5,
      );
    });

    test(
      'an incoming call opens the live call; a missed call opens the chat',
      () {
        _expectRoute(
          customer,
          _payload(
            type: 'social.call.incoming',
            target: 'social_call',
            threadId: 5,
            sessionId: 77,
          ),
          NotificationScreen.socialCall,
          id: 5,
        );
        for (final target in ['social_chat', 'social_call']) {
          _expectRoute(
            customer,
            _payload(
              type: 'social.call.missed',
              target: target,
              threadId: 5,
              sessionId: 77,
            ),
            NotificationScreen.socialChat,
            id: 5,
          );
        }
      },
    );

    test('a support ticket opens that ticket', () {
      _expectRoute(
        customer,
        _payload(
          type: 'support.ticket.agent_reply',
          target: 'support_ticket',
          requestId: 9,
          entityId: 9,
          targetEntity: 'support_ticket',
        ),
        NotificationScreen.supportTicketDetails,
        id: 9,
      );
    });

    test('a ride opens that ride (assigned, arrived, completed)', () {
      for (final target in [
        'taxi_ride_assigned',
        'taxi_captain_arrived',
        'taxi_ride_completed',
        'taxi_live',
      ]) {
        _expectRoute(
          customer,
          // Backend audience enrichment always tags customer rows.
          _payload(
            type: 'taxi.ride.update',
            target: target,
            roleScope: 'customer',
            targetModule: 'customer',
            rideId: 33,
          ),
          NotificationScreen.taxiLiveTracking,
          id: 33,
        );
      }
    });

    test('social content opens the post', () {
      _expectRoute(
        customer,
        _payload(type: 'social.post.like', target: 'social_post', postId: 4),
        NotificationScreen.socialPost,
        id: 4,
      );
    });
  });

  group('Store app routing table', () {
    final owner = _auth('owner');

    test('new / updated orders open that order', () {
      for (final type in [
        'owner_new_order',
        'owner_delivery_assigned',
        'owner_order_picked_up',
      ]) {
        _expectRoute(
          owner,
          _payload(
            type: type,
            target: 'owner_orders',
            appSurface: 'store',
            roleScope: 'merchant',
            orderId: 123,
          ),
          NotificationScreen.merchantOrderDetails,
          id: 123,
        );
      }
      _expectRoute(
        owner,
        _payload(
          type: 'merchant_review_created',
          target: 'merchant_order_details',
          orderId: 50,
        ),
        NotificationScreen.merchantOrderDetails,
        id: 50,
      );
    });

    test('payouts and tickets open their own screens', () {
      _expectRoute(
        owner,
        _payload(type: 'owner_payment_request_approved'),
        NotificationScreen.merchantReceivables,
      );
      _expectRoute(
        owner,
        _payload(
          type: 'support.ticket.resolved',
          target: 'support_ticket',
          roleScope: 'merchant',
          requestId: 12,
        ),
        NotificationScreen.supportTicketDetails,
        id: 12,
      );
    });
  });

  group('Delivery app routing table', () {
    final courier = _auth('delivery');

    test('assigned orders open that order; offers open new orders', () {
      _expectRoute(
        courier,
        _payload(
          type: 'delivery_order_assigned',
          target: 'courier_orders_current',
          roleScope: 'courier',
          orderId: 44,
        ),
        NotificationScreen.courierOrderDetails,
        id: 44,
      );
      _expectRoute(
        courier,
        _payload(
          type: 'delivery_order_available',
          target: 'courier_orders_current',
          roleScope: 'courier',
          orderId: 44,
          requiresAction: true,
        ),
        NotificationScreen.courierOrdersNew,
      );
      _expectRoute(
        courier,
        _payload(
          type: 'delivery_grouped_assigned',
          target: 'courier_orders_current',
          roleScope: 'courier',
          requiresAction: true,
        ),
        NotificationScreen.courierOrdersCurrent,
      );
      _expectRoute(
        courier,
        _payload(
          type: 'delivery_order_invoice_updated',
          target: 'delivery_order_detail',
          roleScope: 'courier',
          orderId: 61,
        ),
        NotificationScreen.courierOrderDetails,
        id: 61,
      );
    });

    test('customer/social surfaces never open inside the courier app', () {
      final destination = NotificationNavigation.resolveDestination(
        auth: courier,
        payload: _payload(
          type: 'social.chat.message',
          target: 'social_chat',
          roleScope: 'customer',
          threadId: 5,
        ),
      );
      expect(destination!.screen, NotificationScreen.deliveryRestricted);
    });
  });

  group('Captain app routing table', () {
    final captain = _auth('taxi_captain');

    test('a ride request / ride chat opens that ride', () {
      _expectRoute(
        captain,
        _payload(
          type: 'taxi.ride.requested',
          target: 'taxi_ride_requested',
          rideId: 33,
          requiresAction: true,
        ),
        NotificationScreen.taxiTripDetails,
        id: 33,
      );
      _expectRoute(
        captain,
        _payload(
          type: 'taxi.chat.message',
          target: 'taxi_chat_message',
          rideId: 34,
        ),
        NotificationScreen.taxiTripDetails,
        id: 34,
      );
    });
  });

  group('Admin / super admin routing table', () {
    final admin = _auth('admin');
    final superAdmin = _auth('user', superAdmin: true);

    test('tickets and Mimo escalations open the ticket itself', () {
      for (final auth in [admin, superAdmin]) {
        for (final type in [
          'admin_support_ticket_created',
          'support.mimo.escalation',
          'support.ticket.customer_reply',
        ]) {
          _expectRoute(
            auth,
            _payload(
              type: type,
              target: 'admin_support_ticket',
              appSurface: 'company',
              roleScope: 'admin',
              requestId: 1042,
              entityId: 1042,
              targetEntity: 'support_ticket',
            ),
            NotificationScreen.adminSupportTicketDetails,
            id: 1042,
          );
        }
      }
    });

    test('orders, rides, approvals, reports and incidents open their page', () {
      _expectRoute(
        admin,
        _payload(
          type: 'admin_order_created',
          target: 'admin_order_details',
          orderId: 5,
        ),
        NotificationScreen.adminOrderDetails,
        id: 5,
      );
      _expectRoute(
        admin,
        _payload(
          type: 'admin_taxi_ride_requested',
          target: 'admin_taxi_ride_details',
          rideId: 6,
        ),
        NotificationScreen.adminTaxiRideDetails,
        id: 6,
      );
      _expectRoute(
        admin,
        _payload(
          type: 'admin_pending_merchant',
          target: 'admin_merchants_pending',
        ),
        NotificationScreen.adminMerchantApprovals,
      );
      _expectRoute(
        admin,
        _payload(
          type: 'social.report.story.created',
          target: 'admin_social_reports',
        ),
        NotificationScreen.adminSocialReports,
      );
      _expectRoute(
        admin,
        _payload(
          type: 'admin.ops.ai_dev_support.incident',
          target: 'admin_ai_dev_support_incident_details',
          entityId: 3,
        ),
        NotificationScreen.adminAiDevIncident,
        id: 3,
      );
    });
  });

  group('HR routing table', () {
    test('HR requests open the HR dashboard', () {
      _expectRoute(
        _auth('hr'),
        _payload(
          type: 'hr.leave.request_created',
          target: 'hr_dashboard',
          roleScope: 'hr',
          targetModule: 'hr',
        ),
        NotificationScreen.hrDashboard,
      );
    });
  });

  group('Role isolation', () {
    test('each app only opens notifications for its own surface', () {
      final cases = <String, AppFlavor>{
        'user': AppFlavor.user,
        'store': AppFlavor.store,
        'delivery': AppFlavor.delivery,
        'taxi': AppFlavor.taxiCaptain,
        'company': AppFlavor.company,
      };
      for (final surface in cases.keys) {
        for (final entry in cases.entries) {
          final payload = _payload(type: 'x', appSurface: surface);
          final allowed = NotificationNavigation.isPayloadAllowedForFlavor(
            payload,
            entry.value,
          );
          final pushAllowed = notificationPayloadMatchesAppFlavor(
            payload,
            entry.value,
          );
          final expected =
              surface == entry.key ||
              // A super admin signed into the user app keeps admin alerts.
              (entry.value == AppFlavor.user && surface == 'company');
          expect(allowed, expected, reason: '$surface in ${entry.value}');
          expect(pushAllowed, expected, reason: '$surface push ${entry.value}');
        }
      }
    });

    test('closed apps resolve their flavor from the package name', () {
      expect(appFlavorForPackageName('com.maslaki.user'), AppFlavor.user);
      expect(appFlavorForPackageName('com.maslaki.store'), AppFlavor.store);
      expect(appFlavorForPackageName('com.maslaki.pharmacy'), AppFlavor.store);
      expect(
        appFlavorForPackageName('com.maslaki.delivery'),
        AppFlavor.delivery,
      );
      expect(
        appFlavorForPackageName('com.maslaki.captain'),
        AppFlavor.taxiCaptain,
      );
      expect(appFlavorForPackageName('com.maslaki.company'), AppFlavor.company);
      expect(appFlavorForPackageName(''), isNull);
    });
  });

  group('In-app list uses the same table', () {
    test('a stored notification row resolves to its exact page', () {
      final model = AppNotificationModel.fromJson({
        'id': 31,
        'order_id': null,
        'type': 'support.mimo.escalation',
        'title': '🚨 تذكرة دعم عاجلة: الطلب وصل تالف',
        'body': 'ST-1042',
        'payload': {
          'ticketId': 1042,
          'entityId': 1042,
          'targetEntity': 'support_ticket',
          'target': 'admin_support_ticket',
          'appSurface': 'company',
          'roleScope': 'admin',
        },
        'is_read': false,
      });
      final payload = NotificationNavigation.payloadFromModel(model);
      _expectRoute(
        _auth('admin'),
        payload,
        NotificationScreen.adminSupportTicketDetails,
        id: 1042,
      );
    });
  });

  group('Incoming call push contract', () {
    test('call UUID matches the backend format', () {
      expect(callUuidForSession(77), '5a17ca11-0000-4000-8000-00000000004d');
      expect(sessionIdFromCallUuid(callUuidForSession(123456789)), 123456789);
      expect(sessionIdFromCallUuid('not-a-call'), isNull);
    });

    test('invite data parses into the native call params', () {
      final invite = IncomingCallInvite.fromPushData({
        'type': 'social.call.incoming',
        'threadId': '5',
        'sessionId': '77',
        'callerName': 'علي',
        'callActionToken': 'tok',
        'callUuid': callUuidForSession(77),
        'callExpiresAt': DateTime.now()
            .add(const Duration(seconds: 30))
            .toIso8601String(),
      });
      expect(invite, isNotNull);
      expect(invite!.threadId, 5);
      expect(invite.sessionId, 77);
      expect(invite.isExpired(), isFalse);
      final params = IncomingCallService.buildParams(invite);
      expect(params.id, callUuidForSession(77));
      expect(params.nameCaller, 'علي');
      expect(params.android?.textAccept, 'رد');
      expect(params.android?.textDecline, 'رفض');
      expect(params.extra?['callActionToken'], 'tok');
      expect(
        '${params.extra?['declineUrl']}',
        endsWith('/api/feed/chats/calls/decline'),
      );
      expect(
        IncomingCallInvite.fromPushData({
          'type': 'social.call.missed',
          'threadId': '5',
          'sessionId': '77',
        }),
        isNull,
      );
    });
  });
}
