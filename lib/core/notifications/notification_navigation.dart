import 'package:flutter/material.dart';

import '../platform/app_platform_capabilities.dart';
import '../../features/accountant/ui/accountant_dashboard_screen.dart';
import '../../features/admin/ui/admin_ad_board_screen.dart';
import '../../features/admin/ui/admin_approvals_hub_screen.dart';
import '../../features/admin/ui/admin_navigation_pages.dart';
import '../../features/admin/ui/admin_merchant_approvals_screen.dart';
import '../../features/admin/ui/admin_receivables_screen.dart';
import '../../features/admin/ui/admin_social_reports_screen.dart';
import '../../features/admin/ui/admin_taxi_captain_requests_screen.dart';
import '../../features/admin/ui/admin_taxi_cash_payments_screen.dart';
import '../../features/admin/ui/admin_taxi_governance_screen.dart';
import '../../features/auth/state/auth_controller.dart';
import '../../features/delivery/ui/courier_pages.dart';
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
import '../../features/real_estate/ui/admin_real_estate_pending_screen.dart';
import '../../features/real_estate/ui/real_estate_marketplace_screen.dart';
import '../../features/real_estate/ui/real_estate_workspace_screen.dart';
import '../../features/services/ui/service_offering_details_screen.dart';
import '../../features/services/ui/service_my_requests_screen.dart';
import '../../features/services/ui/service_provider_profile_screen.dart';
import '../../features/services/ui/service_request_details_screen.dart';
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
import '../../features/taxi/ui/taxi_pages.dart';
import '../../features/taxi/ui/taxi_shared_ride_tracking_screen.dart';
import '../../features/tracking/ui/delivery_live_tracking_screen.dart';
import '../../features/tracking/ui/taxi_live_tracking_screen.dart';
import '../../features/admin/ui/admin_residence_change_requests_screen.dart';
import '../../features/admin/ui/admin_social_restrictions_screen.dart';
import 'package:maslaki/features/ai_dev_support/screens/incident_details_screen.dart';
import '../../pages/map_page.dart';
import '../sections/section_access_guard.dart';
import '../sections/section_availability_targets.dart';
import '../sections/section_unavailable_screen.dart';
import 'local_notification_service.dart';
import 'notification_type_registry.dart';

/// يحول الإشعار المخزن أو القادم من push/local notification إلى شاشة فعلية
/// داخل التطبيق بحسب الدور ونوع الحدث والـ payload المتاح.
///
/// Critical notes:
/// - هذا الملف هو طبقة التوافق بين backend notification taxonomy والواجهات.
/// - أي route جديد مرتبط بالإشعارات يجب إضافته هنا وفي registry المرتبط.
///
/// Maintenance notes:
/// - إذا ضغط المستخدم إشعاراً ووصل إلى شاشة خاطئة، ابدأ من:
///   payloadFromModel -> resolveTarget -> _resolveRoute.
class NotificationNavigation {
  /// يبني payload موحداً من نموذج الإشعار المخزن في inbox.
  static NotificationTapPayload payloadFromModel(AppNotificationModel model) {
    final payload = model.payload;
    return NotificationTapPayload(
      requestId:
          _parseInt(payload?['requestId']) ?? _parseInt(payload?['request_id']),
      orderId:
          model.orderId ??
          _parseInt(payload?['orderId']) ??
          _parseInt(payload?['order_id']),
      rideId:
          model.rideId ??
          _parseInt(payload?['rideId']) ??
          _parseInt(payload?['ride_id']),
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
      notificationId: model.id,
      type: model.type,
      target: model.target ?? payload?['target']?.toString(),
      targetModule:
          payload?['targetModule']?.toString() ??
          payload?['target_module']?.toString(),
      roleScope:
          payload?['roleScope']?.toString() ??
          payload?['role_scope']?.toString(),
      action:
          payload?['action']?.toString() ??
          payload?['target_action']?.toString(),
      targetEntity:
          payload?['targetEntity']?.toString() ??
          payload?['target_entity']?.toString(),
      entityId:
          _parseInt(payload?['entityId']) ?? _parseInt(payload?['entity_id']),
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
    final route = _resolveRoute(auth: auth, payload: payload);
    if (route == null) return;
    await navigator.push(route);
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
      return 'courier_orders_new';
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
        return 'courier_orders_new';
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

  /// يحول target النهائي إلى Route Flutter صالح اعتماداً على دور المستخدم
  /// والكيانات المرجعية الموجودة في payload.
  static Route<void>? _resolveRoute({
    required AuthState auth,
    required NotificationTapPayload payload,
  }) {
    final target = resolveTarget(
      rawTarget: payload.target,
      type: payload.type,
      orderId: payload.orderId,
    );
    final rideId = payload.rideId;
    final orderId = payload.orderId;
    final postId = payload.postId;
    final reelId = payload.reelId;
    final storyId = payload.storyId;
    final jobId = payload.jobId;
    final applicationId = payload.applicationId;
    final threadId = payload.threadId;
    final sessionId = payload.sessionId;
    final entityId = payload.entityId;
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
    final isCustomer =
        !auth.isBackoffice &&
        !auth.isOwner &&
        !auth.isDelivery &&
        !isHr &&
        !isAccountant;

    _debugLogResolution(
      role: auth.user?.role ?? '',
      isDelivery: auth.isDelivery,
      isTaxiCaptain: auth.isTaxiCaptain,
      type: payload.type,
      target: target,
      module: targetModule,
      roleScope: roleScope,
    );

    if (!_isScopeAllowedForRole(
      auth: auth,
      roleScope: roleScope,
      targetModule: targetModule,
    )) {
      // Hard isolation: a courier must never be routed into a customer/social
      // surface. Show an explicit dead-end instead of a silent redirect.
      if (auth.isDelivery && isRestrictedForDelivery(targetModule, target)) {
        return MaterialPageRoute(
          builder: (_) => const DeliveryRestrictedScreen(),
        );
      }
      return _fallbackRouteForRole(auth, preferredModule: targetModule);
    }

    final courierScoped =
        targetModule == 'courier' ||
        roleScope == 'courier' ||
        roleScope == 'delivery' ||
        target.startsWith('courier_') ||
        target.startsWith('delivery_') ||
        (payload.type ?? '').toLowerCase().contains('courier') ||
        (payload.type ?? '').toLowerCase().contains('delivery_order');
    final taxiScoped =
        targetModule == 'taxi' ||
        roleScope == 'taxi' ||
        roleScope == 'taxi_captain' ||
        target.startsWith('taxi_') ||
        target == 'taxi_live' ||
        (payload.type ?? '').toLowerCase().startsWith('taxi.');

    if (isCustomer) {
      final unavailableSectionRoute = _resolveUnavailableSectionRoute(
        target: target,
        targetModule: targetModule,
        payload: payload,
      );
      if (unavailableSectionRoute != null) {
        return unavailableSectionRoute;
      }
      if (target == 'customer_orders_current') {
        return MaterialPageRoute(
          builder: (_) => const CustomerOrdersCurrentPage(),
        );
      }
      if (target == 'customer_orders_completed') {
        return MaterialPageRoute(
          builder: (_) => const CustomerOrdersCompletedPage(),
        );
      }
      if (target == 'customer_orders_cancelled') {
        return MaterialPageRoute(
          builder: (_) => const CustomerOrdersCancelledPage(),
        );
      }
      if (target == 'customer_notifications') {
        return MaterialPageRoute(
          builder: (_) => const CustomerNotificationsPage(),
        );
      }
      if (target == 'jobs_my_applications') {
        return MaterialPageRoute(
          builder: (_) => JobMyApplicationsScreen(
            initialTab: _initialMyApplicationsTab(payload),
          ),
        );
      }
      if (target == 'jobs_applications') {
        return MaterialPageRoute(
          builder: (_) => JobMyApplicationsScreen(
            initialTab: _initialMyApplicationsTab(payload),
          ),
        );
      }
      if (target == 'social_community' &&
          scopeType.isNotEmpty &&
          scopeCode.isNotEmpty) {
        return MaterialPageRoute(
          builder: (_) =>
              SocialCommunityScreen(scopeType: scopeType, scopeCode: scopeCode),
        );
      }
      if (target == 'social_reported_posts') {
        return MaterialPageRoute(
          builder: (_) => const SocialReportedPostsScreen(),
        );
      }
      if (target == 'social_chat') {
        return MaterialPageRoute(
          builder: (_) => SocialShellScreen(
            initialTab: SocialShellTab.messages,
            initialThreadId: threadId,
          ),
        );
      }
      if (target == 'social_activity') {
        return MaterialPageRoute(
          builder: (_) =>
              const SocialShellScreen(initialTab: SocialShellTab.activity),
        );
      }
      if (target == 'social_call') {
        if (appInAppCallsEnabled && threadId != null && threadId > 0) {
          return MaterialPageRoute(
            builder: (_) => SocialCallScreen(
              threadId: threadId,
              isCaller: false,
              initialSessionId: sessionId,
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => SocialShellScreen(
            initialTab: SocialShellTab.messages,
            initialThreadId: threadId,
          ),
        );
      }
      if (target == 'social_reel' || (reelId != null && reelId > 0)) {
        return MaterialPageRoute(
          builder: (_) => SocialShellScreen(
            initialTab: SocialShellTab.reels,
            initialReelId: reelId,
          ),
        );
      }
      if (target == 'social_story' && storyId != null && storyId > 0) {
        return MaterialPageRoute(
          builder: (_) => SocialStoryViewerScreen(storyId: storyId),
        );
      }
      if (target == 'social_post') {
        if (postId != null && postId > 0) {
          return MaterialPageRoute(
            builder: (_) => SocialPostDetailsScreen(postId: postId),
          );
        }
        if (reelId != null && reelId > 0) {
          return MaterialPageRoute(
            builder: (_) => SocialShellScreen(
              initialTab: SocialShellTab.reels,
              initialReelId: reelId,
            ),
          );
        }
      }
      if (target == 'social_feed') {
        if (postId != null && postId > 0) {
          return MaterialPageRoute(
            builder: (_) => SocialPostDetailsScreen(postId: postId),
          );
        }
        if (storyId != null && storyId > 0) {
          return MaterialPageRoute(
            builder: (_) => SocialStoryViewerScreen(storyId: storyId),
          );
        }
        return MaterialPageRoute(
          builder: (_) =>
              const SocialShellScreen(initialTab: SocialShellTab.activity),
        );
      }
      if (target == 'social_profile') {
        final userId =
            payload.entityId ?? payload.senderUserId ?? auth.user?.id;
        if (userId != null && userId > 0) {
          return MaterialPageRoute(
            builder: (_) => SocialProfileScreen(userId: userId),
          );
        }
        if (postId != null && postId > 0) {
          return MaterialPageRoute(
            builder: (_) => SocialPostDetailsScreen(postId: postId),
          );
        }
        return MaterialPageRoute(
          builder: (_) =>
              const SocialShellScreen(initialTab: SocialShellTab.home),
        );
      }
      if (target == 'residence_change_request') {
        return MaterialPageRoute(
          builder: (_) => const SocialResidenceChangeScreen(),
        );
      }
      // Result of a user's profile core-data change request → their profile.
      if (target == 'profile_core_change_request' || target == 'profile') {
        final selfId = payload.entityId ?? auth.user?.id;
        if (selfId != null && selfId > 0) {
          return MaterialPageRoute(
            builder: (_) => SocialProfileScreen(userId: selfId),
          );
        }
      }
      if (target == 'social_restriction_notice' ||
          target == 'social_restrictions') {
        return MaterialPageRoute(
          builder: (_) => SocialRestrictionsScreen(
            initialRestrictionId: payload.restrictionId,
            initialCapabilityKey: payload.capabilityKey,
            initialReason: payload.restrictionReason,
            initialStartsAt: payload.restrictionStartsAt,
            initialEndsAt: payload.restrictionEndsAt,
          ),
        );
      }
      if (target == 'paid_upgrades_home') {
        return MaterialPageRoute(
          builder: (_) => const PaidUpgradesHomeScreen(),
        );
      }
      if (target == 'real_estate_marketplace') {
        return MaterialPageRoute(
          builder: (_) => const RealEstateMarketplaceScreen(),
        );
      }
      if (target == 'real_estate_workspace') {
        return MaterialPageRoute(
          builder: (_) => const RealEstateWorkspaceScreen(),
        );
      }
      if (target == 'services_marketplace') {
        return MaterialPageRoute(
          builder: (_) => const ServicesMarketplaceScreen(),
        );
      }
      if (target == 'services_provider_workspace') {
        return MaterialPageRoute(
          builder: (_) => const ServiceProviderWorkspaceScreen(),
        );
      }
      if (target == 'services_provider_requests' ||
          target == 'service_request_details') {
        final requestId = payload.requestId ?? entityId;
        if ((requestId ?? 0) > 0) {
          return MaterialPageRoute(
            builder: (_) => ServiceRequestDetailsScreen(requestId: requestId!),
          );
        }
        return MaterialPageRoute(
          builder: (_) => auth.isServiceProvider
              ? const ServiceProviderWorkspaceScreen()
              : const ServiceMyRequestsScreen(),
        );
      }
      if ((target == 'service_provider_profile' ||
              target == 'service_provider_details') &&
          (entityId ?? 0) > 0) {
        return MaterialPageRoute(
          builder: (_) => ServiceProviderProfileScreen(providerId: entityId!),
        );
      }
      if ((target == 'service_offering_details' ||
              target == 'service_offering') &&
          (entityId ?? 0) > 0) {
        return MaterialPageRoute(
          builder: (_) => ServiceOfferingDetailsScreen(offeringId: entityId!),
        );
      }
      if (target == 'pharmacy_conversation') {
        final conversationId = entityId;
        if ((conversationId ?? 0) > 0) {
          return MaterialPageRoute(
            builder: (_) =>
                PharmacyConversationScreen(conversationId: conversationId),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const CustomerPharmacyConversationsScreen(),
        );
      }
      if (target == 'taxi_live') {
        if (rideId != null && rideId > 0) {
          return MaterialPageRoute(
            builder: (_) => TaxiLiveTrackingScreen(rideId: rideId),
          );
        }
        return MaterialPageRoute(builder: (_) => const MapPage());
      }
      if (target == 'taxi_shared_ride' && rideId != null && rideId > 0) {
        return MaterialPageRoute(
          builder: (_) => TaxiSharedRideTrackingScreen(rideId: rideId),
        );
      }
      if (target == 'order_tracking' || orderId != null) {
        if (orderId != null && orderId > 0) {
          return MaterialPageRoute(
            builder: (_) => DeliveryLiveTrackingScreen(orderId: orderId),
          );
        }
        return MaterialPageRoute(
          builder: (_) => CustomerOrdersScreen(initialOrderId: orderId),
        );
      }
      return MaterialPageRoute(builder: (_) => const NotificationsScreen());
    }

    if (auth.isTaxiCaptain &&
        !courierScoped &&
        (taxiScoped || !auth.isDelivery)) {
      // A new ride request opens that specific ride so the captain can accept it.
      if (target == 'taxi_new_request') {
        if (rideId != null && rideId > 0) {
          return MaterialPageRoute(
            builder: (_) => TaxiTripDetailsPage(rideId: rideId),
          );
        }
        return MaterialPageRoute(builder: (_) => const TaxiTripsNewPage());
      }
      if (target == 'taxi_trips_new') {
        return MaterialPageRoute(builder: (_) => const TaxiTripsNewPage());
      }
      if (target == 'taxi_trip_details') {
        return MaterialPageRoute(
          builder: (_) => TaxiTripDetailsPage(rideId: rideId),
        );
      }
      if (target == 'taxi_trips_current' || target == 'taxi_live') {
        if (rideId != null && rideId > 0) {
          return MaterialPageRoute(
            builder: (_) => TaxiTripDetailsPage(rideId: rideId),
          );
        }
        return MaterialPageRoute(builder: (_) => const TaxiTripsCurrentPage());
      }
      if (target == 'taxi_trips_completed') {
        return MaterialPageRoute(
          builder: (_) => const TaxiTripsCompletedPage(),
        );
      }
      if (target == 'taxi_trips_cancelled') {
        return MaterialPageRoute(
          builder: (_) => const TaxiTripsCancelledPage(),
        );
      }
      if (target == 'taxi_earnings') {
        return MaterialPageRoute(builder: (_) => const TaxiEarningsPage());
      }
      if (target == 'taxi_reports') {
        return MaterialPageRoute(builder: (_) => const TaxiReportsPage());
      }
      if (target == 'taxi_notifications') {
        return MaterialPageRoute(builder: (_) => const TaxiNotificationsPage());
      }
      if (rideId != null && rideId > 0) {
        return MaterialPageRoute(
          builder: (_) => TaxiTripDetailsPage(rideId: rideId),
        );
      }
      return MaterialPageRoute(
        builder: (_) => const TaxiCaptainDashboardPage(),
      );
    }

    if (isHr) {
      if (target == 'jobs_applications') {
        return MaterialPageRoute(
          builder: (_) => JobApplicationsScreen(
            initialJobId: jobId,
            initialSearch: _jobInitialSearch(payload, applicationId),
          ),
        );
      }
      if (target == 'employee_portal') {
        return MaterialPageRoute(
          builder: (_) => const HrEmployeePortalScreen(),
        );
      }
      return MaterialPageRoute(builder: (_) => const HrDashboardScreen());
    }

    if (isAccountant) {
      if (target == 'employee_portal') {
        return MaterialPageRoute(
          builder: (_) => const HrEmployeePortalScreen(),
        );
      }
      return MaterialPageRoute(
        builder: (_) => const AccountantDashboardScreen(),
      );
    }

    if (auth.isBackoffice) {
      if (target == 'admin_requests_inbox' ||
          target == 'admin_approval_requests' ||
          target == 'admin_profile_change_requests' ||
          target.startsWith('admin_request_') ||
          target.contains('approval')) {
        return MaterialPageRoute(
          builder: (_) => const AdminApprovalsHubScreen(),
        );
      }
      if (target == 'admin_payment_requests' ||
          target.startsWith('admin_payment_') ||
          target.contains('settlement')) {
        return MaterialPageRoute(
          builder: (_) => const AdminReceivablesScreen(),
        );
      }
      if (target == 'admin_receivables') {
        return MaterialPageRoute(builder: (_) => const AdminReceivablesPage());
      }
      if (target == 'admin_competitions') {
        return MaterialPageRoute(builder: (_) => const AdminCompetitionsPage());
      }
      if (target == 'admin_support' || target == 'admin_complaints') {
        return MaterialPageRoute(
          builder: (_) => const AdminSupportOrComplaintsPage(),
        );
      }
      if (target == 'admin_ad_board') {
        return MaterialPageRoute(builder: (_) => const AdminAdBoardScreen());
      }
      if (target == 'admin_maintenance') {
        return MaterialPageRoute(builder: (_) => const AdminMaintenancePage());
      }
      if (target == 'admin_settings') {
        return MaterialPageRoute(builder: (_) => const AdminSettingsPage());
      }
      if (target == 'admin_ops_notification_center' ||
          target == 'admin_notification_center') {
        return MaterialPageRoute(
          builder: (_) => const AdminNotificationCenterPage(),
        );
      }
      if (target == 'admin_ops_notifications_operations' ||
          target == 'admin_notifications_operations') {
        return MaterialPageRoute(
          builder: (_) => const AdminNotificationsOperationsPage(),
        );
      }
      if (target == 'admin_ops_device_reliability' ||
          target == 'admin_device_reliability') {
        return MaterialPageRoute(
          builder: (_) => const AdminDeviceReliabilityPage(),
        );
      }
      if (target == 'admin_ops_crash_center' ||
          target == 'admin_crash_error_center') {
        return MaterialPageRoute(
          builder: (_) => const AdminCrashErrorCenterPage(),
        );
      }
      if (target == 'admin_ops_audit_security' ||
          target == 'admin_audit_security_center') {
        return MaterialPageRoute(
          builder: (_) => const AdminAuditSecurityCenterPage(),
        );
      }
      if (target == 'admin_ops_feature_flags' ||
          target == 'admin_feature_flags_center') {
        return MaterialPageRoute(
          builder: (_) => const AdminFeatureFlagsCenterPage(),
        );
      }
      if (target == 'admin_ops_permissions_matrix' ||
          target == 'admin_permissions_matrix') {
        return MaterialPageRoute(
          builder: (_) => const AdminPermissionsMatrixPage(),
        );
      }
      if (target == 'admin_ai_dev_support' ||
          target == 'admin_ai_dev_support_incident_details') {
        if (target == 'admin_ai_dev_support_incident_details' &&
            (entityId ?? 0) > 0) {
          return MaterialPageRoute(
            builder: (_) => IncidentDetailsScreen(incidentId: entityId!),
          );
        }
        return MaterialPageRoute(builder: (_) => const AdminAiDevSupportPage());
      }
      if (target == 'admin_merchants_pending') {
        return MaterialPageRoute(
          builder: (_) => const AdminMerchantApprovalsScreen(),
        );
      }
      if (target == 'admin_services_providers_pending' ||
          target == 'admin_services_offerings_pending' ||
          target == 'admin_services_requests' ||
          target == 'admin_services_reports') {
        return MaterialPageRoute(
          builder: (_) => const AdminApprovalsHubScreen(),
        );
      }
      if (target == 'admin_settlements') {
        return MaterialPageRoute(
          builder: (_) => const AdminReceivablesScreen(),
        );
      }
      if (target == 'admin_taxi_payments_pending') {
        return MaterialPageRoute(
          builder: (_) => const AdminTaxiCashPaymentsScreen(),
        );
      }
      if (target == 'admin_taxi_profile_edits_pending') {
        return MaterialPageRoute(
          builder: (_) =>
              const AdminTaxiCaptainRequestsScreen(initialTabIndex: 1),
        );
      }
      if (target == 'admin_taxi_governance') {
        return MaterialPageRoute(
          builder: (_) => const AdminTaxiGovernanceScreen(),
        );
      }
      if (target == 'admin_social_reports' ||
          target == 'social_reported_posts') {
        return MaterialPageRoute(
          builder: (_) => const AdminSocialReportsScreen(),
        );
      }
      if (target == 'admin_residence_requests') {
        return MaterialPageRoute(
          builder: (_) => const AdminResidenceChangeRequestsScreen(),
        );
      }
      if (target == 'admin_social_restrictions' ||
          target == 'social_restrictions') {
        final initialUserId = payload.entityId ?? payload.senderUserId;
        return MaterialPageRoute(
          builder: (_) =>
              AdminSocialRestrictionsScreen(initialUserId: initialUserId),
        );
      }
      if (target == 'admin_paid_upgrade_requests') {
        return MaterialPageRoute(
          builder: (_) => const AdminPaidUpgradeRequestsScreen(),
        );
      }
      if (target == 'admin_real_estate_pending') {
        return MaterialPageRoute(
          builder: (_) => const AdminRealEstatePendingScreen(),
        );
      }
      if (target == 'admin_reports' ||
          target == 'admin_financial_reports' ||
          target == 'admin_sales_report' ||
          target == 'admin_collections_report' ||
          target == 'admin_receivables_report') {
        return MaterialPageRoute(builder: (_) => const AdminReportsPage());
      }
      if (target == 'jobs_applications' || target == 'jobs_my_applications') {
        return MaterialPageRoute(
          builder: (_) => JobApplicationsScreen(
            initialJobId: jobId,
            initialSearch: _jobInitialSearch(payload, applicationId),
          ),
        );
      }
      if (target == 'order_tracking' && orderId != null) {
        return MaterialPageRoute(
          builder: (_) => CustomerOrdersScreen(initialOrderId: orderId),
        );
      }
      return MaterialPageRoute(builder: (_) => const AdminDashboardPage());
    }

    if (auth.isOwner) {
      if (target == 'merchant_dashboard') {
        return MaterialPageRoute(builder: (_) => const MerchantDashboardPage());
      }
      if (target == 'merchant_orders_current' || target == 'owner_orders') {
        return MaterialPageRoute(
          builder: (_) => const MerchantOrdersCurrentPage(),
        );
      }
      if ((target == 'merchant_order_details' || target == 'order_tracking') &&
          orderId != null &&
          orderId > 0) {
        return MaterialPageRoute(
          builder: (_) => MerchantOrderDetailsPage(orderId: orderId),
        );
      }
      if (target == 'merchant_orders_completed') {
        return MaterialPageRoute(
          builder: (_) => const MerchantOrdersCompletedPage(),
        );
      }
      if (target == 'merchant_orders_cancelled') {
        return MaterialPageRoute(
          builder: (_) => const MerchantOrdersCancelledPage(),
        );
      }
      if (target == 'merchant_receivables' ||
          target == 'merchant_payment' ||
          target == 'merchant_settlement' ||
          target == 'owner_settlements') {
        return MaterialPageRoute(
          builder: (_) => const MerchantReceivablesPage(),
        );
      }
      if (target == 'merchant_payment_requests') {
        return MaterialPageRoute(
          builder: (_) => const MerchantPaymentRequestsPage(),
        );
      }
      if (target == 'merchant_couriers') {
        return MaterialPageRoute(builder: (_) => const MerchantCouriersPage());
      }
      if (target == 'merchant_reports') {
        return MaterialPageRoute(builder: (_) => const MerchantReportsPage());
      }
      if (target == 'merchant_notifications') {
        return MaterialPageRoute(
          builder: (_) => const MerchantNotificationsPage(),
        );
      }
      if (target == 'merchant_settings') {
        return MaterialPageRoute(builder: (_) => const MerchantSettingsPage());
      }
      if (target == 'owner_dashboard') {
        return MaterialPageRoute(builder: (_) => const OwnerDashboardScreen());
      }
      if (target == 'pharmacy_conversation') {
        final conversationId = entityId;
        if ((conversationId ?? 0) > 0) {
          return MaterialPageRoute(
            builder: (_) => PharmacyConversationScreen(
              conversationId: conversationId,
              ownerMode: true,
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const OwnerPharmacyConversationsScreen(),
        );
      }
      if (target == 'owner_orders' || target == 'order_tracking') {
        return MaterialPageRoute(
          builder: (_) =>
              const OwnerDashboardScreen(initialTab: OwnerDashboardTab.orders),
        );
      }
      if (target == 'jobs_applications') {
        return MaterialPageRoute(
          builder: (_) => JobApplicationsScreen(
            initialJobId: jobId,
            initialSearch: _jobInitialSearch(payload, applicationId),
          ),
        );
      }
      if (target == 'hr_dashboard') {
        return MaterialPageRoute(builder: (_) => const HrDashboardScreen());
      }
      if (target == 'accountant_dashboard') {
        return MaterialPageRoute(
          builder: (_) => const AccountantDashboardScreen(),
        );
      }
      if (target == 'employee_portal') {
        return MaterialPageRoute(
          builder: (_) => const HrEmployeePortalScreen(),
        );
      }
      return MaterialPageRoute(builder: (_) => const OwnerDashboardScreen());
    }

    if (auth.isDelivery && (!taxiScoped || courierScoped)) {
      if (targetModule == 'taxi' || roleScope == 'taxi_captain') {
        return MaterialPageRoute(builder: (_) => const NotificationsScreen());
      }
      final normalizedAction = (payload.action ?? '').trim().toLowerCase();
      final normalizedType = (payload.type ?? '').trim().toLowerCase();
      final isOfferNotification =
          payload.requiresAction ||
          normalizedAction.contains('offer') ||
          normalizedAction.contains('requested') ||
          normalizedType.contains('delivery_order_available') ||
          normalizedType.contains('delivery_order_offer');
      final hasOrderId = orderId != null && orderId > 0;
      if (target == 'courier_dashboard' || target == 'delivery_dashboard') {
        if (hasOrderId && !isOfferNotification) {
          return MaterialPageRoute(
            builder: (_) => CourierOrderDetailsPage(orderId: orderId),
          );
        }
        return MaterialPageRoute(builder: (_) => const CourierDashboardPage());
      }
      if (target == 'courier_orders_new' ||
          target == 'delivery_order_offer' ||
          target == 'courier_order_offer') {
        return MaterialPageRoute(builder: (_) => const CourierOrdersNewPage());
      }
      if (target == 'courier_orders_current' ||
          target == 'delivery_orders' ||
          target == 'delivery_dashboard_orders') {
        if (isOfferNotification) {
          return MaterialPageRoute(
            builder: (_) => const CourierOrdersNewPage(),
          );
        }
        if (hasOrderId) {
          return MaterialPageRoute(
            builder: (_) => CourierOrderDetailsPage(orderId: orderId),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const CourierOrdersCurrentPage(),
        );
      }
      if (target == 'courier_orders_completed') {
        if (hasOrderId) {
          return MaterialPageRoute(
            builder: (_) => CourierOrderDetailsPage(orderId: orderId),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const CourierOrdersCompletedPage(),
        );
      }
      if (target == 'courier_orders_cancelled') {
        if (hasOrderId) {
          return MaterialPageRoute(
            builder: (_) => CourierOrderDetailsPage(orderId: orderId),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const CourierOrdersCancelledPage(),
        );
      }
      if (target == 'courier_competitions') {
        return MaterialPageRoute(
          builder: (_) => const CourierCompetitionsPage(),
        );
      }
      if (target == 'courier_earnings') {
        return MaterialPageRoute(builder: (_) => const CourierEarningsPage());
      }
      if (target == 'courier_reports') {
        return MaterialPageRoute(builder: (_) => const CourierReportsPage());
      }
      if (target == 'courier_notifications') {
        return MaterialPageRoute(
          builder: (_) => const CourierNotificationsPage(),
        );
      }
      if (target == 'courier_settings') {
        return MaterialPageRoute(builder: (_) => const CourierSettingsPage());
      }
      if (target == 'order_tracking' ||
          targetModule == 'courier' ||
          target.startsWith('courier_')) {
        if (!hasOrderId) {
          return MaterialPageRoute(
            builder: (_) => const CourierNotificationsPage(),
          );
        }
        return MaterialPageRoute(
          builder: (_) => CourierOrderDetailsPage(orderId: orderId),
        );
      }
      return MaterialPageRoute(builder: (_) => const NotificationsScreen());
    }

    return _fallbackRouteForRole(auth, preferredModule: targetModule);
  }

  static Route<void>? _resolveUnavailableSectionRoute({
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

    return MaterialPageRoute(
      builder: (_) => SectionUnavailableScreen(entry: entry),
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
      if (auth.isBackoffice) return module == 'admin';
      if (auth.isOwner) return module == 'merchant';
      if (auth.isHr) return module == 'hr';
      if (auth.isAccountant) return module == 'accountant';
      if (auth.isDelivery) return module == 'courier';
      if (auth.isTaxiCaptain) return module == 'taxi';
      return module == 'customer';
    }

    bool allowsScope(String scope) {
      if (scope.isEmpty) return true;
      if (scope == 'admin' || scope == 'deputy_admin') return auth.isBackoffice;
      if (scope == 'owner' || scope == 'merchant') return auth.isOwner;
      if (scope == 'courier' || scope == 'delivery') return auth.isDelivery;
      if (scope == 'taxi' || scope == 'taxi_captain') return auth.isTaxiCaptain;
      if (scope == 'hr') return auth.isHr;
      if (scope == 'accountant') return auth.isAccountant;
      if (scope == 'customer' || scope == 'user') {
        return !auth.isBackoffice &&
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

  static MaterialPageRoute<void> _fallbackRouteForRole(
    AuthState auth, {
    String preferredModule = '',
  }) {
    final module = preferredModule.trim().toLowerCase();
    if (module == 'courier' && auth.isDelivery) {
      return MaterialPageRoute(
        builder: (_) => const CourierNotificationsPage(),
      );
    }
    if (module == 'taxi' && auth.isTaxiCaptain) {
      return MaterialPageRoute(builder: (_) => const TaxiNotificationsPage());
    }
    if (module == 'merchant' && auth.isOwner) {
      return MaterialPageRoute(
        builder: (_) => const MerchantNotificationsPage(),
      );
    }
    if (module == 'admin' && auth.isBackoffice) {
      return MaterialPageRoute(builder: (_) => const AdminRequestsInboxPage());
    }
    if (auth.isBackoffice) {
      return MaterialPageRoute(builder: (_) => const AdminRequestsInboxPage());
    }
    if (auth.isOwner) {
      return MaterialPageRoute(
        builder: (_) => const MerchantNotificationsPage(),
      );
    }
    if (auth.isDelivery) {
      return MaterialPageRoute(
        builder: (_) => const CourierNotificationsPage(),
      );
    }
    if (auth.isTaxiCaptain) {
      return MaterialPageRoute(builder: (_) => const TaxiNotificationsPage());
    }
    return MaterialPageRoute(builder: (_) => const NotificationsScreen());
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
