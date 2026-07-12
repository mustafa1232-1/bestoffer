class NotificationRouteSpec {
  final String targetModule;
  final String targetScreen;
  final String fallbackScreen;
  final Set<String> allowedRoleScopes;
  final Set<String> expectedPayloadKeys;

  const NotificationRouteSpec({
    required this.targetModule,
    required this.targetScreen,
    required this.fallbackScreen,
    this.allowedRoleScopes = const <String>{},
    this.expectedPayloadKeys = const <String>{},
  });
}

class NotificationTypeRegistry {
  static NotificationRouteSpec resolve({
    required String type,
    required String target,
    required String targetModule,
    required String roleScope,
  }) {
    final normalizedType = type.trim().toLowerCase();
    final normalizedTarget = target.trim().toLowerCase();
    final normalizedModule = targetModule.trim().toLowerCase();
    final normalizedRole = roleScope.trim().toLowerCase();

    if (normalizedType == 'delivery_order_available' ||
        normalizedType == 'delivery_order_offer' ||
        normalizedType == 'courier_order_offer') {
      return const NotificationRouteSpec(
        targetModule: 'courier',
        targetScreen: 'courier_orders_current',
        fallbackScreen: 'courier_notifications',
        allowedRoleScopes: {'courier', 'delivery'},
        expectedPayloadKeys: {'orderId', 'merchantId'},
      );
    }

    if (normalizedType == 'delivery_order_ready_for_pickup' ||
        normalizedType == 'delivery_order_assigned' ||
        normalizedType.startsWith('courier.') ||
        normalizedType.startsWith('courier_')) {
      if (normalizedType.contains('competition')) {
        return const NotificationRouteSpec(
          targetModule: 'courier',
          targetScreen: 'courier_competitions',
          fallbackScreen: 'courier_notifications',
          allowedRoleScopes: {'courier', 'delivery'},
        );
      }
      return const NotificationRouteSpec(
        targetModule: 'courier',
        targetScreen: 'courier_orders_current',
        fallbackScreen: 'courier_notifications',
        allowedRoleScopes: {'courier', 'delivery'},
        expectedPayloadKeys: {'orderId'},
      );
    }

    if (normalizedType == 'taxi_ride_requested' ||
        normalizedType == 'taxi_trip_offer' ||
        normalizedType == 'taxi.request.new' ||
        normalizedType.startsWith('taxi.request.') ||
        normalizedType.startsWith('taxi_ride_requested') ||
        normalizedType.startsWith('taxi_trip_offer') ||
        normalizedType.startsWith('taxi.trip.offer')) {
      return const NotificationRouteSpec(
        targetModule: 'taxi',
        targetScreen: 'taxi_trips_new',
        fallbackScreen: 'taxi_notifications',
        allowedRoleScopes: {'taxi_captain', 'taxi'},
        expectedPayloadKeys: {'rideId'},
      );
    }

    if (normalizedType == 'taxi_offer_received' ||
        normalizedType == 'taxi_counter_offer_received' ||
        normalizedType == 'taxi_offer_accepted' ||
        normalizedType == 'taxi_offer_rejected' ||
        normalizedType == 'taxi_ride_assigned' ||
        normalizedType == 'taxi_ride_unavailable' ||
        normalizedType == 'taxi_captain_arrived' ||
        normalizedType == 'taxi_ride_started' ||
        normalizedType == 'taxi_ride_completed' ||
        normalizedType == 'taxi_ride_canceled' ||
        normalizedType == 'taxi_chat_message' ||
        normalizedType.startsWith('taxi.offer.') ||
        normalizedType.startsWith('taxi.ride.')) {
      return const NotificationRouteSpec(
        targetModule: 'taxi',
        targetScreen: 'taxi_live',
        fallbackScreen: 'taxi_notifications',
        allowedRoleScopes: {'user', 'customer', 'taxi_captain', 'taxi'},
        expectedPayloadKeys: {'rideId'},
      );
    }

    if (normalizedType == 'car_listing' ||
        normalizedType.startsWith('car.listing.')) {
      return const NotificationRouteSpec(
        targetModule: 'customer',
        targetScreen: 'car_listing',
        fallbackScreen: 'customer_notifications',
        allowedRoleScopes: {'user', 'customer'},
        expectedPayloadKeys: {'listingId'},
      );
    }

    if (normalizedType == 'real_estate_listing' ||
        normalizedType.startsWith('real_estate_listing.')) {
      return const NotificationRouteSpec(
        targetModule: 'customer',
        targetScreen: 'real_estate_listing',
        fallbackScreen: 'customer_notifications',
        allowedRoleScopes: {'user', 'customer'},
        expectedPayloadKeys: {'listingId'},
      );
    }

    if (normalizedType.contains('merchant_payment') ||
        normalizedType.startsWith('owner_payment_request') ||
        normalizedType.contains('merchant_settlement') ||
        normalizedType.contains('merchant_receivable')) {
      return const NotificationRouteSpec(
        targetModule: 'merchant',
        targetScreen: 'merchant_receivables',
        fallbackScreen: 'merchant_notifications',
        allowedRoleScopes: {'owner', 'merchant'},
      );
    }

    if (normalizedType.contains('admin_payment') ||
        normalizedType.startsWith('admin_merchant_payment') ||
        normalizedType.contains('admin_settlement') ||
        normalizedType.contains('admin_receivable')) {
      return const NotificationRouteSpec(
        targetModule: 'admin',
        targetScreen: 'admin_payment_requests',
        fallbackScreen: 'admin_requests_inbox',
        allowedRoleScopes: {'admin', 'deputy_admin'},
      );
    }

    if (normalizedType.startsWith('taxi.') ||
        normalizedType.startsWith('taxi_')) {
      return const NotificationRouteSpec(
        targetModule: 'taxi',
        targetScreen: 'taxi_trips_current',
        fallbackScreen: 'taxi_notifications',
        allowedRoleScopes: {'taxi_captain', 'taxi'},
      );
    }

    if (normalizedType.startsWith('merchant.') ||
        normalizedType.startsWith('merchant_') ||
        normalizedType.startsWith('owner.')) {
      return const NotificationRouteSpec(
        targetModule: 'merchant',
        targetScreen: 'merchant_orders_current',
        fallbackScreen: 'merchant_notifications',
        allowedRoleScopes: {'owner', 'merchant'},
      );
    }

    if (normalizedType.startsWith('admin.') ||
        normalizedType.startsWith('admin_')) {
      if (normalizedType.contains('competition')) {
        return const NotificationRouteSpec(
          targetModule: 'admin',
          targetScreen: 'admin_competitions',
          fallbackScreen: 'admin_requests_inbox',
          allowedRoleScopes: {'admin', 'deputy_admin'},
        );
      }
      return const NotificationRouteSpec(
        targetModule: 'admin',
        targetScreen: 'admin_requests_inbox',
        fallbackScreen: 'admin_requests_inbox',
        allowedRoleScopes: {'admin', 'deputy_admin'},
      );
    }

    if (normalizedType == 'order_status_update' ||
        normalizedType.contains('customer_order') ||
        normalizedType.contains('delivery_arrived')) {
      return const NotificationRouteSpec(
        targetModule: 'customer',
        targetScreen: 'order_tracking',
        fallbackScreen: 'customer_notifications',
        allowedRoleScopes: {'user', 'customer'},
      );
    }

    if (normalizedModule == 'courier' ||
        normalizedTarget.startsWith('courier_') ||
        normalizedRole == 'courier' ||
        normalizedRole == 'delivery') {
      return const NotificationRouteSpec(
        targetModule: 'courier',
        targetScreen: 'courier_orders_current',
        fallbackScreen: 'courier_notifications',
        allowedRoleScopes: {'courier', 'delivery'},
      );
    }

    if (normalizedModule == 'taxi' ||
        normalizedTarget.startsWith('taxi_') ||
        normalizedRole == 'taxi' ||
        normalizedRole == 'taxi_captain') {
      return const NotificationRouteSpec(
        targetModule: 'taxi',
        targetScreen: 'taxi_trips_current',
        fallbackScreen: 'taxi_notifications',
        allowedRoleScopes: {'taxi', 'taxi_captain'},
      );
    }

    if (normalizedModule == 'merchant' ||
        normalizedTarget.startsWith('merchant_') ||
        normalizedRole == 'owner' ||
        normalizedRole == 'merchant') {
      return const NotificationRouteSpec(
        targetModule: 'merchant',
        targetScreen: 'merchant_dashboard',
        fallbackScreen: 'merchant_notifications',
        allowedRoleScopes: {'owner', 'merchant'},
      );
    }

    if (normalizedModule == 'admin' || normalizedTarget.startsWith('admin_')) {
      return const NotificationRouteSpec(
        targetModule: 'admin',
        targetScreen: 'admin_dashboard',
        fallbackScreen: 'admin_requests_inbox',
        allowedRoleScopes: {'admin', 'deputy_admin'},
      );
    }

    return const NotificationRouteSpec(
      targetModule: 'customer',
      targetScreen: 'notifications',
      fallbackScreen: 'notifications',
    );
  }
}
