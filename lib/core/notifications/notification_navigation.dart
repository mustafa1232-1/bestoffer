import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../calls/in_app_call_overlay_coordinator.dart';
import '../platform/app_flavor.dart';
import '../platform/app_platform_capabilities.dart';
import '../../features/accountant/ui/accountant_dashboard_screen.dart';
import '../../features/admin/ui/admin_ad_board_screen.dart';
import '../../features/admin/ui/admin_approvals_hub_screen.dart';
import '../../features/admin/ui/admin_emergency_requests_screen.dart';
import '../../features/admin/ui/admin_navigation_pages.dart';
import '../../features/admin/ui/admin_merchant_approvals_screen.dart';
import '../../features/admin/ui/admin_receivables_screen.dart';
import '../../features/admin/ui/admin_services_hub_screen.dart';
import '../../features/admin/ui/admin_social_reports_screen.dart';
import '../../features/admin/ui/admin_support_tickets_screen.dart';
import '../../features/admin/ui/admin_taxi_captain_requests_screen.dart';
import '../../features/admin/ui/admin_taxi_cash_payments_screen.dart';
import '../../features/admin/ui/admin_taxi_governance_screen.dart';
import '../../features/admin/ui/monitoring_detail_screen.dart';
import '../../features/admin/ui/monitoring_operations_list_screen.dart';
import '../../features/admin/ui/monitoring_taxi_rides_screen.dart';
import '../../features/auth/state/auth_controller.dart';
import '../../features/delivery/ui/courier_pages.dart';
import '../../features/delivery/ui/delivery_reports_screens.dart';
import '../../features/delivery/ui/delivery_restricted_screen.dart';
import '../../features/hr/ui/hr_dashboard_screen.dart';
import '../../features/hr/ui/hr_employee_portal_screen.dart';
import '../../features/jobs/ui/job_applications_screen.dart';
import '../../features/jobs/ui/job_my_applications_screen.dart';
import '../../features/notifications/models/app_notification_model.dart';
import '../../features/notifications/ui/notifications_screen.dart';
import '../../features/orders/ui/customer_order_pages.dart';
import '../../features/orders/ui/customer_orders_screen.dart';
import '../../features/owner/ui/merchant_navigation_pages.dart';
import '../../features/owner/ui/owner_dashboard_screen.dart';
import '../../features/paid_upgrades/ui/admin_paid_upgrade_requests_screen.dart';
import '../../features/paid_upgrades/ui/paid_upgrades_home_screen.dart';
import '../../features/pharmacy/ui/pharmacy_conversation_screen.dart';
import '../../features/customer/ui/customer_car_listing_details_screen.dart';
import '../../features/customer/ui/customer_cars_marketplace_screen.dart';
import '../../features/real_estate/ui/real_estate_listing_details_screen.dart';
import '../../features/real_estate/ui/admin_real_estate_pending_screen.dart';
import '../../features/real_estate/ui/real_estate_marketplace_screen.dart';
import '../../features/real_estate/ui/real_estate_workspace_screen.dart';
import '../../features/services/ui/service_offering_details_screen.dart';
import '../../features/services/ui/service_my_requests_screen.dart';
import '../../features/services/ui/service_provider_profile_screen.dart';
import '../../features/services/ui/service_request_details_screen.dart';
import '../../features/services/ui/emergency_request_tracking_screen.dart';
import '../../features/services/ui/service_provider_shell.dart';
import '../../features/services/ui/service_provider_workspace_screen.dart';
import '../../features/services/ui/services_marketplace_screen.dart';
import '../../features/social/ui/social_call_screen.dart';
import '../../features/social/ui/social_community_screen.dart';
import '../../features/social/ui/social_post_details_screen.dart';
import '../../features/social/ui/social_profile_screen.dart';
import '../../features/social/ui/social_reported_posts_screen.dart';
import '../../features/social/ui/social_residence_change_screen.dart';
import '../../features/social/ui/social_restrictions_screen.dart';
import '../../features/social/ui/social_shell_screen.dart';
import '../../features/social/ui/social_story_viewer_screen.dart';
import '../../features/support/ui/support_tickets_screen.dart';
import '../../features/taxi/ui/taxi_pages.dart';
import '../../features/taxi/ui/taxi_shared_ride_tracking_screen.dart';
import '../../features/tracking/ui/delivery_live_tracking_screen.dart';
import '../../features/tracking/ui/taxi_live_tracking_screen.dart';
import '../../features/admin/ui/admin_residence_change_requests_screen.dart';
import '../../features/admin/ui/admin_social_restrictions_screen.dart';

import 'package:maslaki/features/ai_dev_support/screens/incident_details_screen.dart';

import '../../pages/map_page.dart';
import '../sections/section_access_guard.dart';
import '../sections/section_availability_models.dart';
import '../sections/section_availability_targets.dart';
import '../sections/section_unavailable_screen.dart';
import 'local_notification_service.dart';
import 'notification_type_registry.dart';

/// Every screen a notification can open. One entry per real destination;
/// see docs/notifications_routing_map.md for the type → screen table per role.
enum NotificationScreen {
  notifications,
  sectionUnavailable,
  customerOrdersCurrent,
  customerOrdersCompleted,
  customerOrdersCancelled,
  customerNotifications,
  customerOrderTracking,
  customerOrders,
  supportTicketDetails,
  supportTickets,
  taxiMap,
  taxiLiveTracking,
  taxiSharedRide,
  jobsMyApplications,
  socialCommunity,
  socialReportedPosts,
  socialChat,
  socialActivity,
  socialHome,
  socialCall,
  socialReels,
  socialStory,
  socialPost,
  socialProfile,
  residenceChange,
  socialRestrictions,
  paidUpgrades,
  realEstateMarketplace,
  realEstateWorkspace,
  realEstateListing,
  carListing,
  carsMarketplace,
  servicesMarketplace,
  customerEmergencyRequest,
  serviceProviderWorkspace,
  serviceRequestDetails,
  serviceMyRequests,
  serviceProviderProfile,
  serviceOfferingDetails,
  pharmacyConversation,
  customerPharmacyConversations,
  taxiTripDetails,
  taxiTripsNew,
  taxiCompetitions,
  taxiCaptainNotifications,
  taxiCaptainDashboard,
  taxiTripsCurrent,
  taxiTripsCompleted,
  taxiTripsCancelled,
  taxiEarnings,
  taxiReports,
  jobApplications,
  hrEmployeePortal,
  hrDashboard,
  accountantDashboard,
  adminOrderDetails,
  adminOrdersMonitoring,
  adminTaxiRideDetails,
  adminTaxiRides,
  adminCarListing,
  adminRealEstateListing,
  adminDashboard,
  adminApprovalsHub,
  adminSettlements,
  adminReceivables,
  adminCompetitions,
  adminSupportTicketDetails,
  adminSupportTickets,
  adminSupportOrComplaints,
  adminAdBoard,
  adminMaintenance,
  adminSettings,
  adminNotificationCenter,
  adminNotificationsOperations,
  adminDeviceReliability,
  adminCrashCenter,
  adminAuditSecurity,
  adminFeatureFlags,
  adminPermissionsMatrix,
  adminAiDevIncident,
  adminAiDevSupport,
  adminMerchantApprovals,
  adminEmergencyRequest,
  adminEmergencyRequests,
  adminServicesHub,
  adminTaxiCashPayments,
  adminTaxiProfileEdits,
  adminTaxiGovernance,
  adminSocialReports,
  adminResidenceRequests,
  adminSocialRestrictions,
  adminPaidUpgradeRequests,
  adminRealEstatePending,
  adminReports,
  adminRequestsInbox,
  merchantDashboard,
  merchantOrderDetails,
  merchantOrdersCurrent,
  merchantOrdersCompleted,
  merchantOrdersCancelled,
  merchantReceivables,
  merchantPaymentRequests,
  merchantCouriers,
  merchantReports,
  merchantNotifications,
  merchantSettings,
  ownerDashboard,
  ownerOrdersTab,
  ownerPharmacyConversation,
  ownerPharmacyConversations,
  deliveryRestricted,
  courierOrderDetails,
  courierDashboard,
  courierOrdersNew,
  courierOrdersCurrent,
  courierOrdersCompleted,
  courierOrdersCancelled,
  courierCompetitions,
  courierEarnings,
  courierReports,
  courierReconciliation,
  courierNotifications,
  courierSettings,
}

/// Result of [NotificationNavigation.resolveDestination]: the screen plus the
/// entity it is about (order/ride/thread/ticket/... id).
@immutable
class NotificationDestination {
  final NotificationScreen screen;
  final int? id;
  final Object? extra;

  const NotificationDestination(this.screen, {this.id, this.extra});

  @override
  String toString() =>
      'NotificationDestination(${screen.name}${id == null ? '' : ', id: $id'})';
}

/// يحول الإشعار المخزن أو القادم من push/local notification إلى شاشة فعلية
/// داخل التطبيق بحسب الدور ونوع الحدث والـ payload المتاح.
///
/// Critical notes:
/// - هذا الملف هو طبقة التوافق بين backend notification taxonomy والواجهات.
/// - أي route جديد مرتبط بالإشعارات يجب إضافته هنا وفي registry المرتبط.
///
/// Maintenance notes:
/// - إذا ضغط المستخدم إشعاراً ووصل إلى شاشة خاطئة، ابدأ من:
///   payloadFromModel -> resolveTarget -> resolveDestination -> buildRoute.
class NotificationNavigation {
  /// يبني payload موحداً من نموذج الإشعار المخزن في inbox.
  static NotificationTapPayload payloadFromModel(AppNotificationModel model) {
    final payload = model.payload;
    return NotificationTapPayload(
      requestId:
          _parseInt(payload?['requestId']) ??
          _parseInt(payload?['request_id']) ??
          _parseInt(payload?['ticketId']) ??
          _parseInt(payload?['ticket_id']),
      orderId:
          model.orderId ??
          _parseInt(payload?['orderId']) ??
          _parseInt(payload?['order_id']),
      rideId:
          model.rideId ??
          _parseInt(payload?['rideId']) ??
          _parseInt(payload?['ride_id']),
      offerId:
          _parseInt(payload?['offerId']) ?? _parseInt(payload?['offer_id']),
      bidId: _parseInt(payload?['bidId']) ?? _parseInt(payload?['bid_id']),
      postId: _parseInt(payload?['postId']) ?? _parseInt(payload?['post_id']),
      reelId:
          model.reelId ??
          _parseInt(payload?['reelId']) ??
          _parseInt(payload?['reel_id']),
      storyId:
          model.storyId ??
          _parseInt(payload?['storyId']) ??
          _parseInt(payload?['story_id']),
      threadId:
          _parseInt(payload?['threadId']) ?? _parseInt(payload?['thread_id']),
      sessionId:
          _parseInt(payload?['sessionId']) ?? _parseInt(payload?['session_id']),
      jobId: _parseInt(payload?['jobId']) ?? _parseInt(payload?['job_id']),
      applicationId:
          _parseInt(payload?['applicationId']) ??
          _parseInt(payload?['application_id']),
      senderUserId:
          _parseInt(payload?['senderUserId']) ??
          _parseInt(payload?['sender_user_id']) ??
          _parseInt(payload?['actorUserId']) ??
          _parseInt(payload?['actor_user_id']),
      captainId:
          _parseInt(payload?['captainId']) ?? _parseInt(payload?['captain_id']),
      customerUserId:
          _parseInt(payload?['customerUserId']) ??
          _parseInt(payload?['customer_user_id']),
      notificationId: model.id,
      type: model.type,
      target: model.target ?? payload?['target']?.toString(),
      targetModule:
          payload?['targetModule']?.toString() ??
          payload?['target_module']?.toString(),
      roleScope:
          payload?['roleScope']?.toString() ??
          payload?['role_scope']?.toString(),
      appSurface:
          payload?['appSurface']?.toString() ??
          payload?['app_surface']?.toString(),
      action:
          payload?['action']?.toString() ??
          payload?['target_action']?.toString(),
      targetEntity:
          payload?['targetEntity']?.toString() ??
          payload?['target_entity']?.toString(),
      entityId:
          _parseInt(payload?['entityId']) ??
          _parseInt(payload?['entity_id']) ??
          _parseInt(payload?['ticketId']) ??
          _parseInt(payload?['ticket_id']) ??
          _parseInt(payload?['listingId']) ??
          _parseInt(payload?['listing_id']),
      scopeType:
          payload?['scopeType']?.toString() ??
          payload?['scope_type']?.toString(),
      scopeCode:
          payload?['scopeCode']?.toString() ??
          payload?['scope_code']?.toString(),
      remoteDisplayName:
          payload?['remoteDisplayName']?.toString() ??
          payload?['remote_display_name']?.toString(),
      restrictionId:
          _parseInt(payload?['restrictionId']) ??
          _parseInt(payload?['restriction_id']),
      capabilityKey:
          payload?['capabilityKey']?.toString() ??
          payload?['capability_key']?.toString(),
      restrictionReason: payload?['reason']?.toString(),
      restrictionStartsAt:
          payload?['startsAt']?.toString() ?? payload?['starts_at']?.toString(),
      restrictionEndsAt:
          payload?['endsAt']?.toString() ?? payload?['ends_at']?.toString(),
      requiresAction:
          payload?['requiresAction'] == true ||
          '${payload?['requiresAction']}'.toLowerCase() == 'true' ||
          '${payload?['requiresAction']}' == '1',
    );
  }

  /// يفتح route الإشعار إذا أمكن حله للمستخدم والدور الحاليين.
  static Future<void> open({
    required NavigatorState navigator,
    required AuthState auth,
    required NotificationTapPayload payload,
  }) async {
    if (!isPayloadAllowedForFlavor(payload, AppFlavorContext.current)) {
      if (kDebugMode) {
        debugPrint(
          '[notification-router] ignored cross-surface tap intended=${payload.appSurface} current=${AppFlavorContext.current.key}',
        );
      }
      return;
    }
    if (!isFlavorAllowedForAuth(AppFlavorContext.current, auth)) {
      return;
    }
    if (auth.isCompanyPortal) {
      return;
    }
    final destination = resolveDestination(auth: auth, payload: payload);
    if (destination == null) return;
    final route = buildRoute(destination, payload);

    final target = resolveTarget(
      rawTarget: payload.target,
      type: payload.type,
      orderId: payload.orderId,
    );
    final threadId = payload.threadId;
    if (destination.screen == NotificationScreen.socialCall &&
        target == 'social_call' &&
        appInAppCallsEnabled &&
        threadId != null &&
        threadId > 0) {
      final key = InAppCallOverlayCoordinator.socialKey(
        threadId: threadId,
        sessionId: payload.sessionId,
      );
      if (!InAppCallOverlayCoordinator.tryOpen(key)) return;
      try {
        await navigator.push(route);
      } finally {
        InAppCallOverlayCoordinator.close(key);
      }
      return;
    }

    await navigator.push(route);
  }

  static bool isPayloadAllowedForFlavor(
    NotificationTapPayload payload,
    AppFlavor flavor,
  ) {
    final raw = (payload.appSurface ?? '').trim().toLowerCase();
    if (raw.isEmpty) return true;
    final intended = switch (raw) {
      'customer' => 'user',
      'owner' || 'merchant' => 'store',
      'courier' => 'delivery',
      'taxi_captain' || 'captain' => 'taxi',
      _ => raw,
    };
    final current = flavor == AppFlavor.taxiCaptain ? 'taxi' : flavor.key;
    if (flavor == AppFlavor.user && intended == 'company') return true;
    return intended == current;
  }

  /// يستنتج target screen من الحقول الصريحة أو من notification type.
  ///
  /// السبب:
  /// - backend قد يرسل target مباشر أو type فقط، وهذه الدالة توحد القرار
  ///   حتى تبقى navigations القديمة والجديدة متوافقة.
  static String resolveTarget({String? rawTarget, String? type, int? orderId}) {
    final direct = (rawTarget ?? '').trim().toLowerCase();
    if (direct.isNotEmpty) return direct;

    final normalizedType = (type ?? '').trim().toLowerCase();
    if (normalizedType == 'taxi_trip_details' ||
        normalizedType == 'taxi.ride.details' ||
        normalizedType == 'taxi.ride.detail' ||
        normalizedType == 'taxi_ride_details' ||
        normalizedType.contains('taxi_trip_details')) {
      return 'taxi_trip_details';
    }
    if (normalizedType == 'taxi.ride.requested' ||
        normalizedType == 'taxi_ride.requested' ||
        normalizedType == 'taxi_ride_requested' ||
        normalizedType == 'taxi_new_request' ||
        normalizedType.startsWith('taxi.ride.requested')) {
      return 'taxi_trips_new';
    }
    if ((normalizedType.startsWith('taxi.') ||
            normalizedType.startsWith('taxi_')) &&
        (normalizedType.contains('competition') ||
            normalizedType.contains('contest') ||
            normalizedType.contains('loyalty'))) {
      return 'taxi_competitions';
    }
    if (normalizedType.contains('taxi_trip_cancelled') ||
        normalizedType.contains('taxi.cancel')) {
      return 'taxi_trips_cancelled';
    }
    if (normalizedType.contains('taxi_trip_completed') ||
        normalizedType.contains('taxi.completed')) {
      return 'taxi_trips_completed';
    }
    if (normalizedType.contains('taxi_earning') ||
        normalizedType.contains('taxi.earning') ||
        normalizedType.contains('taxi_payout') ||
        normalizedType.contains('taxi_report')) {
      return normalizedType.contains('report')
          ? 'taxi_reports'
          : 'taxi_earnings';
    }
    if (normalizedType.startsWith('admin.ops.')) {
      if (normalizedType.contains('ai_dev_support')) {
        return 'admin_ai_dev_support';
      }
      if (normalizedType.contains('notification') ||
          normalizedType.contains('alert')) {
        return 'admin_ops_notification_center';
      }
      if (normalizedType.contains('crash') ||
          normalizedType.contains('error')) {
        return 'admin_ops_crash_center';
      }
      if (normalizedType.contains('feature_flag')) {
        return 'admin_ops_feature_flags';
      }
      if (normalizedType.contains('permission')) {
        return 'admin_ops_permissions_matrix';
      }
      if (normalizedType.contains('device')) {
        return 'admin_ops_device_reliability';
      }
      return 'admin_ops_notification_center';
    }

    final registrySpec = NotificationTypeRegistry.resolve(
      type: normalizedType,
      target: direct,
      targetModule: '',
      roleScope: '',
    );
    if (registrySpec.targetScreen != 'notifications' &&
        registrySpec.targetScreen.isNotEmpty) {
      return registrySpec.targetScreen;
    }
    if (normalizedType.isEmpty) {
      return orderId == null ? 'notifications' : 'order_tracking';
    }

    if (normalizedType == 'taxi.ride.shared') return 'taxi_shared_ride';
    if (normalizedType.startsWith('residence.change.')) {
      return 'residence_change_request';
    }
    if (normalizedType.startsWith('social.capability.')) {
      return normalizedType.contains('restricted')
          ? 'social_restriction_notice'
          : 'social_profile';
    }
    if (normalizedType.startsWith('paid_upgrade.')) {
      return 'paid_upgrades_home';
    }
    if (normalizedType.startsWith('real_estate.')) {
      if (normalizedType.contains('pending_admin_review')) {
        return 'admin_real_estate_pending';
      }
      if (normalizedType.contains('approved') ||
          normalizedType.contains('rejected') ||
          normalizedType.contains('hidden_due_subscription_expiry')) {
        return 'real_estate_workspace';
      }
      return 'real_estate_marketplace';
    }
    if (normalizedType.startsWith('pharmacy.')) {
      if (normalizedType.contains('order.created')) {
        return 'order_tracking';
      }
      return 'pharmacy_conversation';
    }
    if (normalizedType.startsWith('services.')) {
      if (normalizedType.contains('provider.status')) {
        return 'services_provider_workspace';
      }
      if (normalizedType.contains('provider.pending_approval')) {
        return 'admin_services_providers_pending';
      }
      if (normalizedType.contains('offering.pending_review')) {
        return 'admin_services_offerings_pending';
      }
      if (normalizedType.contains('request')) {
        return 'service_request_details';
      }
      return 'services_marketplace';
    }
    if (normalizedType.startsWith('social.community.') ||
        normalizedType.startsWith('social_community.')) {
      return 'social_community';
    }
    if (normalizedType.startsWith('taxi.')) return 'taxi_live';
    if (normalizedType.startsWith('social.call.')) return 'social_call';
    if (normalizedType.startsWith('social.chat.')) return 'social_chat';
    if (normalizedType.startsWith('social.story.')) return 'social_story';
    if (normalizedType.startsWith('social.post.')) return 'social_post';
    if (normalizedType.startsWith('social.reel.')) return 'social_reel';
    if (normalizedType.startsWith('social.relation.')) return 'social_profile';
    if (normalizedType.startsWith('social.report.')) {
      return 'admin_social_reports';
    }
    if (normalizedType.startsWith('social.')) return 'social_activity';
    if (normalizedType.startsWith('jobs.')) {
      if (normalizedType.contains('application.status_updated') ||
          normalizedType.contains('offer_accepted')) {
        return 'jobs_my_applications';
      }
      return 'jobs_applications';
    }
    if (normalizedType.startsWith('hr.')) return 'hr_dashboard';
    if (normalizedType.startsWith('accountant.')) return 'accountant_dashboard';
    if (normalizedType.startsWith('employee.')) return 'employee_portal';
    if (normalizedType.contains('admin_delivery_pending')) {
      return 'admin_merchants_pending';
    }
    if (normalizedType.contains('pending_approval') &&
        normalizedType.contains('admin')) {
      return 'admin_merchants_pending';
    }
    if (normalizedType.contains('admin_pending_merchant')) {
      return 'admin_merchants_pending';
    }
    if (normalizedType == 'taxi.captain.subscription.cash_payment_requested') {
      return 'admin_taxi_payments_pending';
    }
    if (normalizedType == 'taxi.captain.profile_edit.requested') {
      return 'admin_taxi_profile_edits_pending';
    }
    if (normalizedType.contains('taxi.governance') ||
        normalizedType.contains('taxi.coupon') ||
        normalizedType.contains('taxi.contest') ||
        normalizedType.contains('taxi.complaint') ||
        normalizedType.contains('taxi.warning')) {
      return 'admin_taxi_governance';
    }
    if (normalizedType.contains('settlement')) return 'admin_settlements';
    if (normalizedType.startsWith('owner_payment_request') ||
        normalizedType.contains('merchant_receivable')) {
      return 'merchant_receivables';
    }
    if (normalizedType.startsWith('owner.payroll')) return 'owner_dashboard';
    if (normalizedType.startsWith('owner.')) return 'owner_dashboard';
    if (normalizedType.startsWith('owner_')) return 'owner_orders';
    if (normalizedType.startsWith('delivery.')) return 'delivery_dashboard';
    if (normalizedType.startsWith('delivery_')) return 'delivery_orders';
    if (normalizedType.contains('delivery_order_available') ||
        normalizedType.contains('delivery_order_offer')) {
      return 'courier_orders_current';
    }
    if (normalizedType.contains('delivery_order_ready_for_pickup') ||
        normalizedType.contains('ready_for_pickup')) {
      return 'courier_orders_current';
    }
    if (normalizedType.contains('delivery_order_assigned') ||
        normalizedType.contains('owner_delivery_assigned')) {
      return 'courier_orders_current';
    }
    if (normalizedType.startsWith('courier.') ||
        normalizedType.startsWith('courier_') ||
        normalizedType.contains('courier_order') ||
        normalizedType.contains('delivery_order_offer')) {
      if (normalizedType.contains('offer') ||
          normalizedType.contains('requested')) {
        return 'courier_orders_current';
      }
      if (normalizedType.contains('completed') ||
          normalizedType.contains('received') ||
          normalizedType.contains('delivered')) {
        return 'courier_orders_completed';
      }
      if (normalizedType.contains('cancelled') ||
          normalizedType.contains('rejected')) {
        return 'courier_orders_cancelled';
      }
      if (normalizedType.contains('competition')) {
        return 'courier_competitions';
      }
      if (normalizedType.contains('earning') ||
          normalizedType.contains('payout') ||
          normalizedType.contains('report')) {
        return 'courier_reports';
      }
      return 'courier_orders_current';
    }
    if (normalizedType.startsWith('merchant.') ||
        normalizedType.startsWith('merchant_')) {
      if (normalizedType.contains('receivable') ||
          normalizedType.contains('payment')) {
        return 'merchant_receivables';
      }
      if (normalizedType.contains('courier')) return 'merchant_couriers';
      if (normalizedType.contains('report') || normalizedType.contains('kpi')) {
        return 'merchant_reports';
      }
      if (normalizedType.contains('order')) return 'merchant_orders_current';
      return 'merchant_dashboard';
    }
    if (normalizedType.startsWith('admin.')) {
      if (normalizedType.contains('ops.ai_dev_support')) {
        return 'admin_ai_dev_support';
      }
      if (normalizedType.contains('ops.notification') ||
          normalizedType.contains('ops.alert')) {
        return 'admin_ops_notification_center';
      }
      if (normalizedType.contains('ops.crash') ||
          normalizedType.contains('ops.error')) {
        return 'admin_ops_crash_center';
      }
      if (normalizedType.contains('ops.feature_flag')) {
        return 'admin_ops_feature_flags';
      }
      if (normalizedType.contains('ops.permission')) {
        return 'admin_ops_permissions_matrix';
      }
      if (normalizedType.contains('payment') ||
          normalizedType.contains('settlement') ||
          normalizedType.contains('receivable')) {
        return 'admin_payment_requests';
      }
      if (normalizedType.contains('competition')) return 'admin_competitions';
      if (normalizedType.contains('approval') ||
          normalizedType.contains('pending')) {
        return 'admin_requests_inbox';
      }
      if (normalizedType.contains('report') ||
          normalizedType.contains('abuse')) {
        return 'admin_support';
      }
      return 'admin_dashboard';
    }
    if (normalizedType == 'taxi_trip_offer' ||
        normalizedType.contains('taxi_trip_offer')) {
      return 'taxi_trips_new';
    }
    if (normalizedType.contains('order')) return 'order_tracking';

    return orderId == null ? 'notifications' : 'order_tracking';
  }

  static String resolveModule({
    String? rawModule,
    String? roleScope,
    String? rawTarget,
    String? type,
  }) {
    final module = (rawModule ?? '').trim().toLowerCase();
    if (module.isNotEmpty) return module;

    final registrySpec = NotificationTypeRegistry.resolve(
      type: (type ?? '').trim().toLowerCase(),
      target: (rawTarget ?? '').trim().toLowerCase(),
      targetModule: module,
      roleScope: (roleScope ?? '').trim().toLowerCase(),
    );
    if (registrySpec.targetModule.isNotEmpty &&
        registrySpec.targetModule != 'customer') {
      return registrySpec.targetModule;
    }

    final scopedRole = (roleScope ?? '').trim().toLowerCase();
    if (scopedRole == 'courier' || scopedRole == 'delivery') return 'courier';
    if (scopedRole == 'taxi_captain' || scopedRole == 'taxi') return 'taxi';
    if (scopedRole == 'owner' || scopedRole == 'merchant') return 'merchant';
    if (scopedRole == 'admin' || scopedRole == 'deputy_admin') return 'admin';
    if (scopedRole == 'hr') return 'hr';
    if (scopedRole == 'accountant') return 'accountant';
    if (scopedRole == 'user' || scopedRole == 'customer') return 'customer';

    final target = (rawTarget ?? '').trim().toLowerCase();
    if (target.startsWith('delivery_')) return 'courier';
    if (target.startsWith('courier_')) return 'courier';
    if (target.startsWith('merchant_')) return 'merchant';
    if (target.startsWith('customer_')) return 'customer';
    if (target == 'car_listing' || target == 'real_estate_listing') {
      return 'customer';
    }
    if (target.startsWith('taxi_') || target == 'taxi_live') {
      return 'taxi';
    }
    if (target.startsWith('owner_') || target == 'owner_dashboard') {
      return 'merchant';
    }
    if (target.startsWith('admin_')) return 'admin';
    if (target.startsWith('pharmacy_')) {
      if (scopedRole == 'owner' || scopedRole == 'merchant') {
        return 'merchant';
      }
      return 'customer';
    }
    if (target.startsWith('service_') || target.startsWith('services_')) {
      return target.startsWith('admin_services_') ? 'admin' : 'customer';
    }
    if (target.startsWith('jobs_')) return 'jobs';
    if (target.startsWith('social_')) return 'social';
    if (target == 'hr_dashboard' || target == 'employee_portal') return 'hr';
    if (target == 'accountant_dashboard') return 'accountant';
    if (target == 'order_tracking') return 'customer';

    final normalizedType = (type ?? '').trim().toLowerCase();
    if (normalizedType.startsWith('delivery') ||
        normalizedType.contains('courier')) {
      return 'courier';
    }
    if (normalizedType.startsWith('taxi.')) return 'taxi';
    if (normalizedType.startsWith('owner.')) return 'merchant';
    if (normalizedType.startsWith('admin.')) return 'admin';
    if (normalizedType.startsWith('pharmacy.')) {
      if (scopedRole == 'owner' || scopedRole == 'merchant') {
        return 'merchant';
      }
      return 'customer';
    }
    if (normalizedType == 'car_listing' ||
        normalizedType.startsWith('car.listing.')) {
      return 'customer';
    }
    if (normalizedType == 'real_estate_listing' ||
        normalizedType.startsWith('real_estate_listing.')) {
      return 'customer';
    }
    if (normalizedType.startsWith('services.')) return 'customer';
    if (normalizedType.startsWith('jobs.')) return 'jobs';
    if (normalizedType.startsWith('social.')) return 'social';
    if (normalizedType.startsWith('hr.')) return 'hr';
    if (normalizedType.startsWith('accountant.')) return 'accountant';

    return '';
  }

  /// True when a notification target belongs to a customer/community/social
  /// surface that must never open inside the delivery app. Order tracking is
  /// intentionally NOT restricted — an assigned courier is allowed to track.
  static bool isRestrictedForDelivery(String targetModule, String target) {
    final module = targetModule.trim().toLowerCase();
    final t = target.trim().toLowerCase();
    if (module == 'social') return true;
    if (t.startsWith('social_')) return true;
    if (t.startsWith('customer_')) return true;
    const restricted = <String>{
      'social_community',
      'social_profile',
      'social_feed',
      'social_reel',
      'social_story',
      'social_post',
      'social_activity',
      'social_chat',
      'community',
    };
    return restricted.contains(t);
  }

  /// Resolves the exact screen a notification opens for the signed-in role.
  ///
  /// Pure (no widgets): the routing table in docs/notifications_routing_map.md
  /// mirrors this function and test/core/notifications/
  /// notification_destination_table_test.dart pins it per role.
  static NotificationDestination? resolveDestination({
    required AuthState auth,
    required NotificationTapPayload payload,
  }) {
    final target = resolveTarget(
      rawTarget: payload.target,
      type: payload.type,
      orderId: payload.orderId,
    );
    final normalizedType = (payload.type ?? '').trim().toLowerCase();
    final rideId = payload.rideId;
    final orderId = payload.orderId;
    final postId = payload.postId;
    final reelId = payload.reelId;
    final storyId = payload.storyId;
    final jobId = payload.jobId;
    final applicationId = payload.applicationId;
    final threadId = payload.threadId;
    final entityId = payload.entityId;
    final ticketId = _supportTicketId(payload);
    final scopeType = (payload.scopeType ?? '').trim().toLowerCase();
    final scopeCode = (payload.scopeCode ?? '').trim().toUpperCase();
    final roleScope = (payload.roleScope ?? '').trim().toLowerCase();
    final targetModule = resolveModule(
      rawModule: payload.targetModule,
      roleScope: payload.roleScope,
      rawTarget: payload.target,
      type: payload.type,
    );
    final isHr = auth.isHr;
    final isAccountant = auth.isAccountant;
    // Captains have their own branch below; they are never routed as customers.
    final isCustomer =
        !auth.isAdminDashboardUser &&
        !auth.isBackoffice &&
        !auth.isOwner &&
        !auth.isDelivery &&
        !auth.isTaxiCaptain &&
        !isHr &&
        !isAccountant;
    final isSupportNotification =
        target == 'support_ticket' ||
        target == 'admin_support_ticket' ||
        normalizedType.startsWith('support.') ||
        normalizedType == 'admin_support_ticket_created';
    // A finished/missed call has no live session to join: open the chat.
    final isTerminalCall =
        normalizedType == 'social.call.missed' ||
        normalizedType == 'social.call.declined' ||
        normalizedType == 'social.call.ended';

    if (kDebugMode) {
      _debugLogResolution(
        role: auth.user?.role ?? '',
        isDelivery: auth.isDelivery,
        isTaxiCaptain: auth.isTaxiCaptain,
        type: payload.type,
        target: target,
        module: targetModule,
        roleScope: roleScope,
      );
    }

    if (!_isScopeAllowedForRole(
      auth: auth,
      roleScope: roleScope,
      targetModule: targetModule,
    )) {
      // Hard isolation: a courier must never be routed into a customer/social
      // surface. Show an explicit dead-end instead of a silent redirect.
      if (auth.isDelivery && isRestrictedForDelivery(targetModule, target)) {
        return const NotificationDestination(
          NotificationScreen.deliveryRestricted,
        );
      }
      return _fallbackDestinationForRole(auth, preferredModule: targetModule);
    }

    final courierScoped =
        targetModule == 'courier' ||
        roleScope == 'courier' ||
        roleScope == 'delivery' ||
        target.startsWith('courier_') ||
        target.startsWith('delivery_') ||
        normalizedType.contains('courier') ||
        normalizedType.contains('delivery_order');
    final taxiScoped =
        targetModule == 'taxi' ||
        roleScope == 'taxi' ||
        roleScope == 'taxi_captain' ||
        target.startsWith('taxi_') ||
        target == 'taxi_live' ||
        normalizedType.startsWith('taxi.');
    final taxiOfferNotification =
        target == 'taxi_offer_received' ||
        target == 'taxi_counter_offer_received' ||
        target == 'taxi_offer_rejected' ||
        target == 'taxi_ride_unavailable';
    final taxiAssignmentNotification =
        target == 'taxi_offer_accepted' ||
        target == 'taxi_ride_assigned' ||
        target == 'taxi_captain_arrived' ||
        target == 'taxi_ride_started';
    final taxiTerminalNotification =
        target == 'taxi_ride_completed' || target == 'taxi_ride_canceled';
    final taxiChatNotification = target == 'taxi_chat_message';
    final taxiRequestNotification =
        target == 'taxi_ride_requested' ||
        target == 'taxi_new_request' ||
        target == 'taxi_trips_new';

    NotificationDestination to(
      NotificationScreen screen, {
      int? id,
      Object? extra,
    }) => NotificationDestination(screen, id: id, extra: extra);

    if (isCustomer) {
      final unavailable = _resolveUnavailableSection(
        target: target,
        targetModule: targetModule,
        payload: payload,
      );
      if (unavailable != null) return unavailable;
      if (target == 'customer_orders_current') {
        return to(NotificationScreen.customerOrdersCurrent);
      }
      if (target == 'customer_orders_completed') {
        return to(NotificationScreen.customerOrdersCompleted);
      }
      if (target == 'customer_orders_cancelled') {
        return to(NotificationScreen.customerOrdersCancelled);
      }
      if (target == 'customer_notifications') {
        return to(NotificationScreen.customerNotifications);
      }
      if (isSupportNotification) {
        if (ticketId != null) {
          return to(NotificationScreen.supportTicketDetails, id: ticketId);
        }
        return to(NotificationScreen.supportTickets);
      }
      if (taxiOfferNotification || taxiChatNotification) {
        // Offers are accepted from the live ride request on the map.
        return to(NotificationScreen.taxiMap);
      }
      if (taxiAssignmentNotification ||
          taxiTerminalNotification ||
          target == 'taxi_live') {
        if (rideId != null && rideId > 0) {
          return to(NotificationScreen.taxiLiveTracking, id: rideId);
        }
        return to(NotificationScreen.taxiMap);
      }
      if (taxiRequestNotification) {
        return to(NotificationScreen.taxiMap);
      }
      if (target == 'taxi_shared_ride' && rideId != null && rideId > 0) {
        return to(NotificationScreen.taxiSharedRide, id: rideId);
      }
      if (target == 'jobs_my_applications' || target == 'jobs_applications') {
        return to(
          NotificationScreen.jobsMyApplications,
          extra: _initialMyApplicationsTab(payload),
        );
      }
      if (target == 'social_community' &&
          scopeType.isNotEmpty &&
          scopeCode.isNotEmpty) {
        return to(
          NotificationScreen.socialCommunity,
          extra: (scopeType: scopeType, scopeCode: scopeCode),
        );
      }
      if (target == 'social_reported_posts') {
        return to(NotificationScreen.socialReportedPosts);
      }
      if (target == 'social_chat' ||
          (target == 'social_call' && isTerminalCall)) {
        return to(NotificationScreen.socialChat, id: threadId);
      }
      if (target == 'social_activity') {
        return to(NotificationScreen.socialActivity);
      }
      if (target == 'social_call') {
        if (appInAppCallsEnabled && threadId != null && threadId > 0) {
          return to(NotificationScreen.socialCall, id: threadId);
        }
        return to(NotificationScreen.socialChat, id: threadId);
      }
      if (target == 'social_reel' || (reelId != null && reelId > 0)) {
        return to(NotificationScreen.socialReels, id: reelId);
      }
      if (target == 'social_story' && storyId != null && storyId > 0) {
        return to(NotificationScreen.socialStory, id: storyId);
      }
      if (target == 'social_post') {
        if (postId != null && postId > 0) {
          return to(NotificationScreen.socialPost, id: postId);
        }
        if (reelId != null && reelId > 0) {
          return to(NotificationScreen.socialReels, id: reelId);
        }
      }
      if (target == 'social_feed') {
        if (postId != null && postId > 0) {
          return to(NotificationScreen.socialPost, id: postId);
        }
        if (storyId != null && storyId > 0) {
          return to(NotificationScreen.socialStory, id: storyId);
        }
        return to(NotificationScreen.socialActivity);
      }
      if (target == 'social_profile') {
        final userId =
            payload.entityId ?? payload.senderUserId ?? auth.user?.id;
        if (userId != null && userId > 0) {
          return to(NotificationScreen.socialProfile, id: userId);
        }
        if (postId != null && postId > 0) {
          return to(NotificationScreen.socialPost, id: postId);
        }
        return to(NotificationScreen.socialHome);
      }
      if (target == 'residence_change_request') {
        return to(NotificationScreen.residenceChange);
      }
      // Result of a user's profile core-data change request → their profile.
      if (target == 'profile_core_change_request' || target == 'profile') {
        final selfId = payload.entityId ?? auth.user?.id;
        if (selfId != null && selfId > 0) {
          return to(NotificationScreen.socialProfile, id: selfId);
        }
      }
      if (target == 'social_restriction_notice' ||
          target == 'social_restrictions') {
        return to(NotificationScreen.socialRestrictions);
      }
      if (target == 'paid_upgrades_home') {
        return to(NotificationScreen.paidUpgrades);
      }
      if (target == 'real_estate_marketplace') {
        return to(NotificationScreen.realEstateMarketplace);
      }
      if (target == 'real_estate_workspace') {
        return to(NotificationScreen.realEstateWorkspace);
      }
      if (target == 'real_estate_listing') {
        if (entityId != null && entityId > 0) {
          return to(NotificationScreen.realEstateListing, id: entityId);
        }
        return to(NotificationScreen.realEstateMarketplace);
      }
      if (target == 'car_listing') {
        if (entityId != null && entityId > 0) {
          return to(NotificationScreen.carListing, id: entityId);
        }
        return to(NotificationScreen.carsMarketplace);
      }
      if (target == 'services_marketplace') {
        return to(NotificationScreen.servicesMarketplace);
      }
      if (target == 'customer_emergency_request') {
        final requestId = payload.requestId ?? entityId;
        if ((requestId ?? 0) > 0) {
          return to(NotificationScreen.customerEmergencyRequest, id: requestId);
        }
      }
      if (target == 'services_provider_workspace') {
        return to(NotificationScreen.serviceProviderWorkspace);
      }
      if (target == 'services_provider_requests' ||
          target == 'service_request_details') {
        final requestId = payload.requestId ?? entityId;
        if ((requestId ?? 0) > 0) {
          return to(NotificationScreen.serviceRequestDetails, id: requestId);
        }
        return to(
          auth.isServiceProvider
              ? NotificationScreen.serviceProviderWorkspace
              : NotificationScreen.serviceMyRequests,
        );
      }
      if ((target == 'service_provider_profile' ||
              target == 'service_provider_details') &&
          (entityId ?? 0) > 0) {
        return to(NotificationScreen.serviceProviderProfile, id: entityId);
      }
      if ((target == 'service_offering_details' ||
              target == 'service_offering') &&
          (entityId ?? 0) > 0) {
        return to(NotificationScreen.serviceOfferingDetails, id: entityId);
      }
      if (target == 'pharmacy_conversation') {
        if ((entityId ?? 0) > 0) {
          return to(NotificationScreen.pharmacyConversation, id: entityId);
        }
        return to(NotificationScreen.customerPharmacyConversations);
      }
      if (target == 'order_tracking' || orderId != null) {
        if (orderId != null && orderId > 0) {
          return to(NotificationScreen.customerOrderTracking, id: orderId);
        }
        return to(NotificationScreen.customerOrders);
      }
      return to(NotificationScreen.notifications);
    }

    if (auth.isTaxiCaptain &&
        !courierScoped &&
        (taxiScoped || !auth.isDelivery)) {
      // A new ride request opens that specific ride so the captain can accept it.
      if (taxiRequestNotification) {
        if (rideId != null && rideId > 0) {
          return to(NotificationScreen.taxiTripDetails, id: rideId);
        }
        return to(NotificationScreen.taxiTripsNew);
      }
      if (target == 'taxi_competitions') {
        return to(NotificationScreen.taxiCompetitions);
      }
      if (target == 'taxi_notifications') {
        return to(NotificationScreen.taxiCaptainNotifications);
      }
      if (taxiOfferNotification || taxiChatNotification) {
        if (rideId != null && rideId > 0) {
          return to(NotificationScreen.taxiTripDetails, id: rideId);
        }
        return to(NotificationScreen.taxiCaptainDashboard);
      }
      if (taxiAssignmentNotification ||
          taxiTerminalNotification ||
          target == 'taxi_trips_current' ||
          target == 'taxi_live' ||
          target == 'taxi_trip_details') {
        if (rideId != null && rideId > 0) {
          return to(NotificationScreen.taxiTripDetails, id: rideId);
        }
        return to(NotificationScreen.taxiTripsCurrent);
      }
      if (target == 'taxi_trips_completed') {
        return to(NotificationScreen.taxiTripsCompleted);
      }
      if (target == 'taxi_trips_cancelled') {
        return to(NotificationScreen.taxiTripsCancelled);
      }
      if (target == 'taxi_earnings') {
        return to(NotificationScreen.taxiEarnings);
      }
      if (target == 'taxi_reports') {
        return to(NotificationScreen.taxiReports);
      }
      if (rideId != null && rideId > 0) {
        return to(NotificationScreen.taxiTripDetails, id: rideId);
      }
      return to(NotificationScreen.taxiCaptainDashboard);
    }

    if (isHr) {
      if (target == 'jobs_applications') {
        return to(
          NotificationScreen.jobApplications,
          id: jobId,
          extra: _jobInitialSearch(payload, applicationId),
        );
      }
      if (target == 'employee_portal') {
        return to(NotificationScreen.hrEmployeePortal);
      }
      return to(NotificationScreen.hrDashboard);
    }

    if (isAccountant) {
      if (target == 'employee_portal') {
        return to(NotificationScreen.hrEmployeePortal);
      }
      return to(NotificationScreen.accountantDashboard);
    }

    if (auth.isBackoffice || auth.isStaff) {
      if (target == 'admin_order_details' ||
          target == 'admin_orders' ||
          target == 'admin_orders_monitoring' ||
          (target == 'order_tracking' && orderId != null)) {
        if (orderId != null && orderId > 0) {
          return to(NotificationScreen.adminOrderDetails, id: orderId);
        }
        return to(NotificationScreen.adminOrdersMonitoring);
      }
      if (target == 'admin_taxi_ride_details' ||
          target == 'admin_taxi_rides' ||
          target == 'admin_taxi_rides_monitoring') {
        if (rideId != null && rideId > 0) {
          return to(NotificationScreen.adminTaxiRideDetails, id: rideId);
        }
        return to(NotificationScreen.adminTaxiRides);
      }
      if (target == 'admin_marketplace_contacts') {
        final entity = (payload.targetEntity ?? '').trim().toLowerCase();
        if (entityId != null && entityId > 0) {
          if (entity == 'car_listing') {
            return to(NotificationScreen.adminCarListing, id: entityId);
          }
          if (entity == 'real_estate_listing') {
            return to(NotificationScreen.adminRealEstateListing, id: entityId);
          }
        }
        return to(NotificationScreen.adminDashboard);
      }
      // Tickets (incl. Mimo escalations) open the ticket itself, never a list.
      if (isSupportNotification) {
        if (ticketId != null) {
          return to(NotificationScreen.adminSupportTicketDetails, id: ticketId);
        }
        return to(NotificationScreen.adminSupportTickets);
      }
      if (target == 'admin_requests_inbox' ||
          target == 'admin_approval_requests' ||
          target == 'admin_profile_change_requests' ||
          target.startsWith('admin_request_') ||
          target.contains('approval')) {
        return to(NotificationScreen.adminApprovalsHub);
      }
      if (target == 'admin_payment_requests' ||
          target.startsWith('admin_payment_') ||
          target.contains('settlement')) {
        return to(NotificationScreen.adminSettlements);
      }
      if (target == 'admin_receivables') {
        return to(NotificationScreen.adminReceivables);
      }
      if (target == 'admin_competitions') {
        return to(NotificationScreen.adminCompetitions);
      }
      if (target == 'admin_support' ||
          target == 'admin_complaints' ||
          target == 'order_revision') {
        return to(NotificationScreen.adminSupportOrComplaints);
      }
      if (target == 'admin_ad_board') {
        return to(NotificationScreen.adminAdBoard);
      }
      if (target == 'admin_maintenance') {
        return to(NotificationScreen.adminMaintenance);
      }
      if (target == 'admin_settings') {
        return to(NotificationScreen.adminSettings);
      }
      if (target == 'admin_ops_notification_center' ||
          target == 'admin_notification_center') {
        return to(NotificationScreen.adminNotificationCenter);
      }
      if (target == 'admin_ops_notifications_operations' ||
          target == 'admin_notifications_operations') {
        return to(NotificationScreen.adminNotificationsOperations);
      }
      if (target == 'admin_ops_device_reliability' ||
          target == 'admin_device_reliability') {
        return to(NotificationScreen.adminDeviceReliability);
      }
      if (target == 'admin_ops_crash_center' ||
          target == 'admin_crash_error_center') {
        return to(NotificationScreen.adminCrashCenter);
      }
      if (target == 'admin_ops_audit_security' ||
          target == 'admin_audit_security_center') {
        return to(NotificationScreen.adminAuditSecurity);
      }
      if (target == 'admin_ops_feature_flags' ||
          target == 'admin_feature_flags_center') {
        return to(NotificationScreen.adminFeatureFlags);
      }
      if (target == 'admin_ops_permissions_matrix' ||
          target == 'admin_permissions_matrix') {
        return to(NotificationScreen.adminPermissionsMatrix);
      }
      if (target == 'admin_ai_dev_support' ||
          target == 'admin_ai_dev_support_incident_details') {
        if ((entityId ?? 0) > 0) {
          return to(NotificationScreen.adminAiDevIncident, id: entityId);
        }
        return to(NotificationScreen.adminAiDevSupport);
      }
      if (target == 'admin_merchants_pending') {
        return to(NotificationScreen.adminMerchantApprovals);
      }
      if (target == 'admin_services_providers_pending' ||
          target == 'admin_services_requests' ||
          target == 'admin_services_reports') {
        return to(NotificationScreen.adminApprovalsHub);
      }
      if (target == 'admin_emergency_request') {
        final requestId = payload.requestId ?? entityId;
        if ((requestId ?? 0) > 0) {
          return to(NotificationScreen.adminEmergencyRequest, id: requestId);
        }
        return to(NotificationScreen.adminEmergencyRequests);
      }
      if (target == 'admin_services_offerings_pending') {
        return to(NotificationScreen.adminServicesHub);
      }
      if (target == 'admin_settlements') {
        return to(NotificationScreen.adminSettlements);
      }
      if (target == 'admin_taxi_payments_pending') {
        return to(NotificationScreen.adminTaxiCashPayments);
      }
      if (target == 'admin_taxi_profile_edits_pending') {
        return to(NotificationScreen.adminTaxiProfileEdits);
      }
      if (target == 'admin_taxi_governance') {
        return to(NotificationScreen.adminTaxiGovernance);
      }
      if (target == 'admin_social_reports' ||
          target == 'social_reported_posts') {
        return to(NotificationScreen.adminSocialReports);
      }
      if (target == 'admin_residence_requests') {
        return to(NotificationScreen.adminResidenceRequests);
      }
      if (target == 'admin_social_restrictions' ||
          target == 'social_restrictions') {
        return to(
          NotificationScreen.adminSocialRestrictions,
          id: payload.entityId ?? payload.senderUserId,
        );
      }
      if (target == 'admin_paid_upgrade_requests') {
        return to(NotificationScreen.adminPaidUpgradeRequests);
      }
      if (target == 'admin_real_estate_pending') {
        return to(NotificationScreen.adminRealEstatePending);
      }
      if (target == 'admin_reports' ||
          target == 'admin_financial_reports' ||
          target == 'admin_sales_report' ||
          target == 'admin_collections_report' ||
          target == 'admin_receivables_report') {
        return to(NotificationScreen.adminReports);
      }
      if (target == 'jobs_applications' || target == 'jobs_my_applications') {
        return to(
          NotificationScreen.jobApplications,
          id: jobId,
          extra: _jobInitialSearch(payload, applicationId),
        );
      }
      if (orderId != null && orderId > 0) {
        return to(NotificationScreen.adminOrderDetails, id: orderId);
      }
      if (rideId != null && rideId > 0) {
        return to(NotificationScreen.adminTaxiRideDetails, id: rideId);
      }
      return to(NotificationScreen.notifications);
    }

    if (auth.isOwner) {
      if (isSupportNotification) {
        if (ticketId != null) {
          return to(NotificationScreen.supportTicketDetails, id: ticketId);
        }
        return to(NotificationScreen.supportTickets);
      }
      if (target == 'merchant_dashboard') {
        return to(NotificationScreen.merchantDashboard);
      }
      if ((target == 'merchant_orders_current' ||
              target == 'owner_orders' ||
              target == 'merchant_order_details' ||
              target == 'owner_order_details' ||
              target == 'order_tracking' ||
              target == 'order_revision') &&
          orderId != null &&
          orderId > 0) {
        return to(NotificationScreen.merchantOrderDetails, id: orderId);
      }
      if (target == 'merchant_orders_current' || target == 'owner_orders') {
        return to(NotificationScreen.merchantOrdersCurrent);
      }
      if (target == 'merchant_orders_completed') {
        return to(NotificationScreen.merchantOrdersCompleted);
      }
      if (target == 'merchant_orders_cancelled') {
        return to(NotificationScreen.merchantOrdersCancelled);
      }
      if (target == 'merchant_receivables' ||
          target == 'merchant_payment' ||
          target == 'merchant_settlement' ||
          target == 'owner_settlements') {
        return to(NotificationScreen.merchantReceivables);
      }
      if (target == 'merchant_payment_requests') {
        return to(NotificationScreen.merchantPaymentRequests);
      }
      if (target == 'merchant_couriers') {
        return to(NotificationScreen.merchantCouriers);
      }
      if (target == 'merchant_reports') {
        return to(NotificationScreen.merchantReports);
      }
      if (target == 'merchant_notifications') {
        return to(NotificationScreen.merchantNotifications);
      }
      if (target == 'merchant_settings') {
        return to(NotificationScreen.merchantSettings);
      }
      if (target == 'owner_dashboard') {
        return to(NotificationScreen.ownerDashboard);
      }
      if (target == 'pharmacy_conversation') {
        if ((entityId ?? 0) > 0) {
          return to(NotificationScreen.ownerPharmacyConversation, id: entityId);
        }
        return to(NotificationScreen.ownerPharmacyConversations);
      }
      if (target == 'owner_orders' || target == 'order_tracking') {
        return to(NotificationScreen.ownerOrdersTab);
      }
      if (target == 'jobs_applications') {
        return to(
          NotificationScreen.jobApplications,
          id: jobId,
          extra: _jobInitialSearch(payload, applicationId),
        );
      }
      if (target == 'hr_dashboard') {
        return to(NotificationScreen.hrDashboard);
      }
      if (target == 'accountant_dashboard') {
        return to(NotificationScreen.accountantDashboard);
      }
      if (target == 'employee_portal') {
        return to(NotificationScreen.hrEmployeePortal);
      }
      if (orderId != null && orderId > 0) {
        return to(NotificationScreen.merchantOrderDetails, id: orderId);
      }
      return to(NotificationScreen.merchantNotifications);
    }

    if (auth.isDelivery && (!taxiScoped || courierScoped)) {
      if (targetModule == 'taxi' || roleScope == 'taxi_captain') {
        return to(NotificationScreen.courierNotifications);
      }
      if (isSupportNotification) {
        if (ticketId != null) {
          return to(NotificationScreen.supportTicketDetails, id: ticketId);
        }
        return to(NotificationScreen.supportTickets);
      }
      final normalizedAction = (payload.action ?? '').trim().toLowerCase();
      // An assignment (even an urgent one) is already the courier's order;
      // only open offers go to the "new orders" list.
      final isOfferNotification =
          (payload.requiresAction && !normalizedType.contains('assigned')) ||
          normalizedAction.contains('offer') ||
          normalizedAction.contains('requested') ||
          normalizedType.contains('delivery_order_available') ||
          normalizedType.contains('delivery_order_offer');
      final hasOrderId = orderId != null && orderId > 0;
      if (target == 'courier_dashboard' || target == 'delivery_dashboard') {
        if (hasOrderId && !isOfferNotification) {
          return to(NotificationScreen.courierOrderDetails, id: orderId);
        }
        return to(NotificationScreen.courierDashboard);
      }
      if (target == 'courier_orders_new' ||
          target == 'delivery_order_offer' ||
          target == 'courier_order_offer') {
        return to(NotificationScreen.courierOrdersNew);
      }
      if (target == 'courier_orders_current' ||
          target == 'delivery_orders' ||
          target == 'delivery_dashboard_orders') {
        if (isOfferNotification) {
          return to(NotificationScreen.courierOrdersNew);
        }
        if (hasOrderId) {
          return to(NotificationScreen.courierOrderDetails, id: orderId);
        }
        return to(NotificationScreen.courierOrdersCurrent);
      }
      if (target == 'courier_orders_completed') {
        if (hasOrderId) {
          return to(NotificationScreen.courierOrderDetails, id: orderId);
        }
        return to(NotificationScreen.courierOrdersCompleted);
      }
      if (target == 'courier_orders_cancelled') {
        if (hasOrderId) {
          return to(NotificationScreen.courierOrderDetails, id: orderId);
        }
        return to(NotificationScreen.courierOrdersCancelled);
      }
      if (target == 'courier_competitions') {
        return to(NotificationScreen.courierCompetitions);
      }
      if (target == 'courier_earnings') {
        return to(NotificationScreen.courierEarnings);
      }
      if (target == 'courier_reports') {
        return to(NotificationScreen.courierReports);
      }
      if (target == 'courier_reconciliation') {
        return to(NotificationScreen.courierReconciliation);
      }
      if (target == 'courier_notifications') {
        return to(NotificationScreen.courierNotifications);
      }
      if (target == 'courier_settings') {
        return to(NotificationScreen.courierSettings);
      }
      if (hasOrderId) {
        return to(NotificationScreen.courierOrderDetails, id: orderId);
      }
      return to(NotificationScreen.courierNotifications);
    }

    return _fallbackDestinationForRole(auth, preferredModule: targetModule);
  }

  /// Builds the Flutter route for a resolved [NotificationDestination].
  static Route<void> buildRoute(
    NotificationDestination destination,
    NotificationTapPayload payload,
  ) {
    final id = destination.id;
    final requiredId = id ?? 0;
    MaterialPageRoute<void> page(Widget child) =>
        MaterialPageRoute<void>(builder: (_) => child);

    return switch (destination.screen) {
      NotificationScreen.notifications => page(const NotificationsScreen()),
      NotificationScreen.sectionUnavailable => page(
        SectionUnavailableScreen(
          entry: destination.extra! as SectionAvailabilityEntry,
        ),
      ),
      NotificationScreen.customerOrdersCurrent => page(
        const CustomerOrdersCurrentPage(),
      ),
      NotificationScreen.customerOrdersCompleted => page(
        const CustomerOrdersCompletedPage(),
      ),
      NotificationScreen.customerOrdersCancelled => page(
        const CustomerOrdersCancelledPage(),
      ),
      NotificationScreen.customerNotifications => page(
        const CustomerNotificationsPage(),
      ),
      NotificationScreen.customerOrderTracking => page(
        DeliveryLiveTrackingScreen(orderId: requiredId),
      ),
      NotificationScreen.customerOrders => page(
        CustomerOrdersScreen(initialOrderId: id),
      ),
      NotificationScreen.supportTicketDetails => page(
        SupportTicketDetailsScreen(ticketId: requiredId),
      ),
      NotificationScreen.supportTickets => page(const SupportTicketsScreen()),
      NotificationScreen.taxiMap => page(const MapPage()),
      NotificationScreen.taxiLiveTracking => page(
        TaxiLiveTrackingScreen(rideId: requiredId),
      ),
      NotificationScreen.taxiSharedRide => page(
        TaxiSharedRideTrackingScreen(rideId: requiredId),
      ),
      NotificationScreen.jobsMyApplications => page(
        JobMyApplicationsScreen(initialTab: destination.extra as int? ?? 0),
      ),
      NotificationScreen.socialCommunity => () {
        final scope =
            destination.extra! as ({String scopeType, String scopeCode});
        return page(
          SocialCommunityScreen(
            scopeType: scope.scopeType,
            scopeCode: scope.scopeCode,
          ),
        );
      }(),
      NotificationScreen.socialReportedPosts => page(
        const SocialReportedPostsScreen(),
      ),
      NotificationScreen.socialChat => page(
        SocialShellScreen(
          initialTab: SocialShellTab.messages,
          initialThreadId: id,
        ),
      ),
      NotificationScreen.socialActivity => page(
        const SocialShellScreen(initialTab: SocialShellTab.activity),
      ),
      NotificationScreen.socialHome => page(
        const SocialShellScreen(initialTab: SocialShellTab.home),
      ),
      NotificationScreen.socialCall => page(
        SocialCallScreen(
          threadId: requiredId,
          isCaller: false,
          initialSessionId: payload.sessionId,
          remoteDisplayName: payload.remoteDisplayName,
          initialAction: payload.quickActionId,
          notificationId: payload.notificationId,
        ),
      ),
      NotificationScreen.socialReels => page(
        SocialShellScreen(initialTab: SocialShellTab.reels, initialReelId: id),
      ),
      NotificationScreen.socialStory => page(
        SocialStoryViewerScreen(storyId: requiredId),
      ),
      NotificationScreen.socialPost => page(
        SocialPostDetailsScreen(postId: requiredId),
      ),
      NotificationScreen.socialProfile => page(
        SocialProfileScreen(userId: requiredId),
      ),
      NotificationScreen.residenceChange => page(
        const SocialResidenceChangeScreen(),
      ),
      NotificationScreen.socialRestrictions => page(
        SocialRestrictionsScreen(
          initialRestrictionId: payload.restrictionId,
          initialCapabilityKey: payload.capabilityKey,
          initialReason: payload.restrictionReason,
          initialStartsAt: payload.restrictionStartsAt,
          initialEndsAt: payload.restrictionEndsAt,
        ),
      ),
      NotificationScreen.paidUpgrades => page(const PaidUpgradesHomeScreen()),
      NotificationScreen.realEstateMarketplace => page(
        const RealEstateMarketplaceScreen(),
      ),
      NotificationScreen.realEstateWorkspace => page(
        const RealEstateWorkspaceScreen(),
      ),
      NotificationScreen.realEstateListing => page(
        RealEstateListingDetailsScreen(listingId: requiredId),
      ),
      NotificationScreen.carListing => page(
        CustomerCarListingDetailsScreen(listingId: requiredId),
      ),
      NotificationScreen.carsMarketplace => page(
        const CustomerCarsMarketplaceScreen(),
      ),
      NotificationScreen.servicesMarketplace => page(
        const ServicesMarketplaceScreen(),
      ),
      NotificationScreen.customerEmergencyRequest => page(
        EmergencyRequestTrackingScreen(requestId: requiredId),
      ),
      NotificationScreen.serviceProviderWorkspace => page(
        const ServiceProviderShell(child: ServiceProviderWorkspaceScreen()),
      ),
      NotificationScreen.serviceRequestDetails => page(
        ServiceRequestDetailsScreen(requestId: requiredId),
      ),
      NotificationScreen.serviceMyRequests => page(
        const ServiceMyRequestsScreen(),
      ),
      NotificationScreen.serviceProviderProfile => page(
        ServiceProviderProfileScreen(providerId: requiredId),
      ),
      NotificationScreen.serviceOfferingDetails => page(
        ServiceOfferingDetailsScreen(offeringId: requiredId),
      ),
      NotificationScreen.pharmacyConversation => page(
        PharmacyConversationScreen(conversationId: id),
      ),
      NotificationScreen.customerPharmacyConversations => page(
        const CustomerPharmacyConversationsScreen(),
      ),
      NotificationScreen.taxiTripDetails => page(
        TaxiTripDetailsPage(rideId: id),
      ),
      NotificationScreen.taxiTripsNew => page(const TaxiTripsNewPage()),
      NotificationScreen.taxiCompetitions => page(
        const TaxiCaptainCompetitionsPage(),
      ),
      NotificationScreen.taxiCaptainNotifications => page(
        const TaxiCaptainNotificationsPage(),
      ),
      NotificationScreen.taxiCaptainDashboard => page(
        const TaxiCaptainDashboardPage(),
      ),
      NotificationScreen.taxiTripsCurrent => page(const TaxiTripsCurrentPage()),
      NotificationScreen.taxiTripsCompleted => page(
        const TaxiTripsCompletedPage(),
      ),
      NotificationScreen.taxiTripsCancelled => page(
        const TaxiTripsCancelledPage(),
      ),
      NotificationScreen.taxiEarnings => page(const TaxiEarningsPage()),
      NotificationScreen.taxiReports => page(const TaxiReportsPage()),
      NotificationScreen.jobApplications => page(
        JobApplicationsScreen(
          initialJobId: id,
          initialSearch: destination.extra as String? ?? '',
        ),
      ),
      NotificationScreen.hrEmployeePortal => page(
        const HrEmployeePortalScreen(),
      ),
      NotificationScreen.hrDashboard => page(const HrDashboardScreen()),
      NotificationScreen.accountantDashboard => page(
        const AccountantDashboardScreen(),
      ),
      NotificationScreen.adminOrderDetails => page(
        MonitoringDetailScreen(
          mode: MonitoringDetailMode.order,
          id: requiredId,
          title: 'Order #$requiredId',
        ),
      ),
      NotificationScreen.adminOrdersMonitoring => page(
        const MonitoringOperationsListScreen(
          mode: MonitoringOperationsMode.orders,
        ),
      ),
      NotificationScreen.adminTaxiRideDetails => page(
        MonitoringDetailScreen(
          mode: MonitoringDetailMode.taxiRide,
          id: requiredId,
          title: 'Ride #$requiredId',
        ),
      ),
      NotificationScreen.adminTaxiRides => page(
        const MonitoringTaxiRidesScreen(),
      ),
      NotificationScreen.adminCarListing => page(
        MonitoringDetailScreen(
          mode: MonitoringDetailMode.carListing,
          id: requiredId,
          title: 'Car listing #$requiredId',
        ),
      ),
      NotificationScreen.adminRealEstateListing => page(
        MonitoringDetailScreen(
          mode: MonitoringDetailMode.realEstateListing,
          id: requiredId,
          title: 'Real estate #$requiredId',
        ),
      ),
      NotificationScreen.adminDashboard => page(const AdminDashboardPage()),
      NotificationScreen.adminApprovalsHub => page(
        const AdminApprovalsHubScreen(),
      ),
      NotificationScreen.adminSettlements => page(
        const AdminReceivablesScreen(),
      ),
      NotificationScreen.adminReceivables => page(const AdminReceivablesPage()),
      NotificationScreen.adminCompetitions => page(
        const AdminCompetitionsPage(),
      ),
      NotificationScreen.adminSupportTicketDetails => page(
        AdminSupportTicketDetailsScreen(ticketId: requiredId),
      ),
      NotificationScreen.adminSupportTickets => page(
        const AdminSupportTicketsScreen(),
      ),
      NotificationScreen.adminSupportOrComplaints => page(
        const AdminSupportOrComplaintsPage(),
      ),
      NotificationScreen.adminAdBoard => page(const AdminAdBoardScreen()),
      NotificationScreen.adminMaintenance => page(const AdminMaintenancePage()),
      NotificationScreen.adminSettings => page(const AdminSettingsPage()),
      NotificationScreen.adminNotificationCenter => page(
        const AdminNotificationCenterPage(),
      ),
      NotificationScreen.adminNotificationsOperations => page(
        const AdminNotificationsOperationsPage(),
      ),
      NotificationScreen.adminDeviceReliability => page(
        const AdminDeviceReliabilityPage(),
      ),
      NotificationScreen.adminCrashCenter => page(
        const AdminCrashErrorCenterPage(),
      ),
      NotificationScreen.adminAuditSecurity => page(
        const AdminAuditSecurityCenterPage(),
      ),
      NotificationScreen.adminFeatureFlags => page(
        const AdminFeatureFlagsCenterPage(),
      ),
      NotificationScreen.adminPermissionsMatrix => page(
        const AdminPermissionsMatrixPage(),
      ),
      NotificationScreen.adminAiDevIncident => page(
        IncidentDetailsScreen(incidentId: requiredId),
      ),
      NotificationScreen.adminAiDevSupport => page(
        const AdminAiDevSupportPage(),
      ),
      NotificationScreen.adminMerchantApprovals => page(
        const AdminMerchantApprovalsScreen(),
      ),
      NotificationScreen.adminEmergencyRequest => page(
        EmergencyRequestTrackingScreen(requestId: requiredId, adminMode: true),
      ),
      NotificationScreen.adminEmergencyRequests => page(
        const AdminEmergencyRequestsScreen(),
      ),
      NotificationScreen.adminServicesHub => page(
        const AdminServicesHubScreen(),
      ),
      NotificationScreen.adminTaxiCashPayments => page(
        const AdminTaxiCashPaymentsScreen(),
      ),
      NotificationScreen.adminTaxiProfileEdits => page(
        const AdminTaxiCaptainRequestsScreen(initialTabIndex: 1),
      ),
      NotificationScreen.adminTaxiGovernance => page(
        const AdminTaxiGovernanceScreen(),
      ),
      NotificationScreen.adminSocialReports => page(
        const AdminSocialReportsScreen(),
      ),
      NotificationScreen.adminResidenceRequests => page(
        const AdminResidenceChangeRequestsScreen(),
      ),
      NotificationScreen.adminSocialRestrictions => page(
        AdminSocialRestrictionsScreen(initialUserId: id),
      ),
      NotificationScreen.adminPaidUpgradeRequests => page(
        const AdminPaidUpgradeRequestsScreen(),
      ),
      NotificationScreen.adminRealEstatePending => page(
        const AdminRealEstatePendingScreen(),
      ),
      NotificationScreen.adminReports => page(const AdminReportsPage()),
      NotificationScreen.adminRequestsInbox => page(
        const AdminRequestsInboxPage(),
      ),
      NotificationScreen.merchantDashboard => page(
        const MerchantDashboardPage(),
      ),
      NotificationScreen.merchantOrderDetails => page(
        MerchantOrderDetailsPage(orderId: requiredId),
      ),
      NotificationScreen.merchantOrdersCurrent => page(
        const MerchantOrdersCurrentPage(),
      ),
      NotificationScreen.merchantOrdersCompleted => page(
        const MerchantOrdersCompletedPage(),
      ),
      NotificationScreen.merchantOrdersCancelled => page(
        const MerchantOrdersCancelledPage(),
      ),
      NotificationScreen.merchantReceivables => page(
        const MerchantReceivablesPage(),
      ),
      NotificationScreen.merchantPaymentRequests => page(
        const MerchantPaymentRequestsPage(),
      ),
      NotificationScreen.merchantCouriers => page(const MerchantCouriersPage()),
      NotificationScreen.merchantReports => page(const MerchantReportsPage()),
      NotificationScreen.merchantNotifications => page(
        const MerchantNotificationsPage(),
      ),
      NotificationScreen.merchantSettings => page(const MerchantSettingsPage()),
      NotificationScreen.ownerDashboard => page(const OwnerDashboardScreen()),
      NotificationScreen.ownerOrdersTab => page(
        const OwnerDashboardScreen(initialTab: OwnerDashboardTab.orders),
      ),
      NotificationScreen.ownerPharmacyConversation => page(
        PharmacyConversationScreen(conversationId: id, ownerMode: true),
      ),
      NotificationScreen.ownerPharmacyConversations => page(
        const OwnerPharmacyConversationsScreen(),
      ),
      NotificationScreen.deliveryRestricted => page(
        const DeliveryRestrictedScreen(),
      ),
      NotificationScreen.courierOrderDetails => page(
        CourierOrderDetailsPage(orderId: requiredId),
      ),
      NotificationScreen.courierDashboard => page(const CourierDashboardPage()),
      NotificationScreen.courierOrdersNew => page(const CourierOrdersNewPage()),
      NotificationScreen.courierOrdersCurrent => page(
        const CourierOrdersCurrentPage(),
      ),
      NotificationScreen.courierOrdersCompleted => page(
        const CourierOrdersCompletedPage(),
      ),
      NotificationScreen.courierOrdersCancelled => page(
        const CourierOrdersCancelledPage(),
      ),
      NotificationScreen.courierCompetitions => page(
        const CourierCompetitionsPage(),
      ),
      NotificationScreen.courierEarnings => page(const CourierEarningsPage()),
      NotificationScreen.courierReports => page(const CourierReportsPage()),
      NotificationScreen.courierReconciliation => page(
        const DeliveryReconciliationScreen(),
      ),
      NotificationScreen.courierNotifications => page(
        const CourierNotificationsPage(),
      ),
      NotificationScreen.courierSettings => page(const CourierSettingsPage()),
    };
  }

  static int? _supportTicketId(NotificationTapPayload payload) {
    final entity = (payload.targetEntity ?? '').trim().toLowerCase();
    final candidates = <int?>[
      if (entity.isEmpty || entity.contains('ticket')) payload.entityId,
      payload.requestId,
    ];
    for (final value in candidates) {
      if (value != null && value > 0) return value;
    }
    return null;
  }

  static NotificationDestination? _resolveUnavailableSection({
    required String target,
    required String targetModule,
    required NotificationTapPayload payload,
  }) {
    final sectionKey = resolveSectionKeyForNavigationTarget(
      target: target,
      targetModule: targetModule,
    );
    if (sectionKey == null) return null;
    final entry = resolveSectionAvailabilitySnapshot(sectionKey);
    if (entry.isOpen) return null;

    final allowExistingActiveAccess =
        entry.allowExistingActiveAccess &&
        <String>{
          'service_request_details',
          'services_provider_requests',
        }.contains(target) &&
        ((payload.requestId ?? payload.entityId) ?? 0) > 0;
    if (allowExistingActiveAccess) return null;

    return NotificationDestination(
      NotificationScreen.sectionUnavailable,
      extra: entry,
    );
  }

  static bool _isScopeAllowedForRole({
    required AuthState auth,
    required String roleScope,
    required String targetModule,
  }) {
    bool allowsModule(String module) {
      if (module.isEmpty) return true;
      if (module == 'social' || module == 'jobs') return true;
      if (auth.isBackoffice || auth.isStaff || auth.isAdminDashboardUser) {
        return module == 'admin';
      }
      if (auth.isOwner) return module == 'merchant';
      if (auth.isHr) return module == 'hr';
      if (auth.isAccountant) return module == 'accountant';
      if (auth.isDelivery) return module == 'courier';
      if (auth.isTaxiCaptain) return module == 'taxi';
      return module == 'customer';
    }

    bool allowsScope(String scope) {
      if (scope.isEmpty) return true;
      if (scope == 'admin' || scope == 'deputy_admin') {
        return auth.isBackoffice || auth.isStaff || auth.isAdminDashboardUser;
      }
      if (scope == 'owner' || scope == 'merchant') return auth.isOwner;
      if (scope == 'courier' || scope == 'delivery') return auth.isDelivery;
      if (scope == 'taxi' || scope == 'taxi_captain') return auth.isTaxiCaptain;
      if (scope == 'hr') return auth.isHr;
      if (scope == 'accountant') return auth.isAccountant;
      if (scope == 'customer' || scope == 'user') {
        return !auth.isAdminDashboardUser &&
            !auth.isBackoffice &&
            !auth.isOwner &&
            !auth.isDelivery &&
            !auth.isTaxiCaptain &&
            !auth.isHr &&
            !auth.isAccountant;
      }
      return true;
    }

    return allowsScope(roleScope) && allowsModule(targetModule);
  }

  static bool isFlavorAllowedForAuth(AppFlavor flavor, AuthState auth) {
    switch (flavor) {
      case AppFlavor.user:
        return auth.isCustomer ||
            auth.isGuest ||
            auth.isServiceProvider ||
            auth.isAdminDashboardUser ||
            auth.isStaff;
      case AppFlavor.store:
        return auth.isOwner;
      case AppFlavor.delivery:
        return auth.isDelivery;
      case AppFlavor.taxiCaptain:
        return auth.isTaxiCaptain;
      case AppFlavor.company:
        return auth.isCompanyBackoffice ||
            auth.isCompanyPortal ||
            auth.isAccountant ||
            auth.isHr;
    }
  }

  static NotificationDestination _fallbackDestinationForRole(
    AuthState auth, {
    String preferredModule = '',
  }) {
    final module = preferredModule.trim().toLowerCase();
    if (module == 'courier' && auth.isDelivery) {
      return const NotificationDestination(
        NotificationScreen.courierNotifications,
      );
    }
    if (module == 'taxi' && auth.isTaxiCaptain) {
      return const NotificationDestination(
        NotificationScreen.taxiCaptainNotifications,
      );
    }
    if (module == 'merchant' && auth.isOwner) {
      return const NotificationDestination(
        NotificationScreen.merchantNotifications,
      );
    }
    if (auth.isBackoffice || auth.isStaff || auth.isAdminDashboardUser) {
      return const NotificationDestination(
        NotificationScreen.adminRequestsInbox,
      );
    }
    if (auth.isOwner) {
      return const NotificationDestination(
        NotificationScreen.merchantNotifications,
      );
    }
    if (auth.isDelivery) {
      return const NotificationDestination(
        NotificationScreen.courierNotifications,
      );
    }
    if (auth.isTaxiCaptain) {
      return const NotificationDestination(
        NotificationScreen.taxiCaptainNotifications,
      );
    }
    return const NotificationDestination(NotificationScreen.notifications);
  }

  static int _initialMyApplicationsTab(NotificationTapPayload payload) {
    final status = _extractStatus(payload).toLowerCase();
    switch (status) {
      case 'shortlisted':
        return 1;
      case 'rejected':
        return 2;
      case 'hired':
        return 3;
      default:
        return 0;
    }
  }

  static String _jobInitialSearch(
    NotificationTapPayload payload,
    int? applicationId,
  ) {
    final status = _extractStatus(payload);
    if (applicationId != null && applicationId > 0) {
      return 'app:$applicationId ${status.isEmpty ? '' : status}'.trim();
    }
    if (payload.jobId != null && payload.jobId! > 0) {
      return 'job:${payload.jobId} ${status.isEmpty ? '' : status}'.trim();
    }
    return status;
  }

  static String _extractStatus(NotificationTapPayload payload) {
    final fromType = (payload.type ?? '').toLowerCase();
    if (fromType.contains('shortlisted')) return 'shortlisted';
    if (fromType.contains('rejected')) return 'rejected';
    if (fromType.contains('hired') || fromType.contains('offer_accepted')) {
      return 'hired';
    }
    return '';
  }

  static void _debugLogResolution({
    required String role,
    required bool isDelivery,
    required bool isTaxiCaptain,
    required String? type,
    required String target,
    required String module,
    required String roleScope,
  }) {
    debugPrint(
      '[notification-router] role=$role delivery=$isDelivery taxi=$isTaxiCaptain '
      'type=${type ?? ''} target=$target module=$module roleScope=$roleScope',
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    final parsed = int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
