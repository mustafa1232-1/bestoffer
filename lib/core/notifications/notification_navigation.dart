import 'package:flutter/material.dart';

import '../../features/admin/ui/admin_dashboard_screen.dart';
import '../../features/auth/state/auth_controller.dart';
import '../../features/notifications/models/app_notification_model.dart';
import '../../features/notifications/ui/notifications_screen.dart';
import '../../features/orders/ui/customer_orders_screen.dart';
import '../../features/owner/ui/owner_dashboard_screen.dart';
import '../../features/social/ui/basmaya_feed_screen.dart';
import '../../features/social/ui/social_call_screen.dart';
import '../../features/social/ui/social_chat_threads_screen.dart';
import '../../features/taxi/ui/taxi_call_screen.dart';
import '../../features/taxi/ui/taxi_captain_dashboard_screen.dart';
import '../../pages/map_page.dart';
import 'local_notification_service.dart';

class NotificationNavigation {
  static NotificationTapPayload payloadFromModel(AppNotificationModel model) {
    final payload = model.payload;
    return NotificationTapPayload(
      orderId:
          model.orderId ??
          _parseInt(payload?['orderId']) ??
          _parseInt(payload?['order_id']),
      rideId:
          model.rideId ??
          _parseInt(payload?['rideId']) ??
          _parseInt(payload?['ride_id']),
      postId: _parseInt(payload?['postId']) ?? _parseInt(payload?['post_id']),
      storyId:
          model.storyId ??
          _parseInt(payload?['storyId']) ??
          _parseInt(payload?['story_id']),
      threadId:
          _parseInt(payload?['threadId']) ?? _parseInt(payload?['thread_id']),
      sessionId:
          _parseInt(payload?['sessionId']) ?? _parseInt(payload?['session_id']),
      notificationId: model.id,
      type: model.type,
      target: model.target ?? payload?['target']?.toString(),
    );
  }

  static Future<void> open({
    required NavigatorState navigator,
    required AuthState auth,
    required NotificationTapPayload payload,
  }) async {
    final route = _resolveRoute(auth: auth, payload: payload);
    if (route == null) return;
    await navigator.push(route);
  }

  static String resolveTarget({String? rawTarget, String? type, int? orderId}) {
    final direct = (rawTarget ?? '').trim().toLowerCase();
    if (direct.isNotEmpty) return direct;

    final normalizedType = (type ?? '').trim().toLowerCase();
    if (normalizedType.isEmpty) {
      return orderId == null ? 'notifications' : 'order_tracking';
    }

    if (normalizedType == 'taxi.call.incoming') return 'taxi_call';
    if (normalizedType.startsWith('taxi.')) return 'taxi_live';
    if (normalizedType.startsWith('social.call.')) return 'social_call';
    if (normalizedType.startsWith('social.chat.')) return 'social_chat';
    if (normalizedType.startsWith('social.')) return 'social_feed';
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
    if (normalizedType.contains('settlement')) return 'admin_settlements';
    if (normalizedType.startsWith('owner_')) return 'owner_orders';
    if (normalizedType.startsWith('delivery_')) return 'delivery_orders';
    if (normalizedType.contains('order')) return 'order_tracking';

    return orderId == null ? 'notifications' : 'order_tracking';
  }

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
    final storyId = payload.storyId;
    final threadId = payload.threadId;
    final sessionId = payload.sessionId;
    final isCustomer = !auth.isBackoffice && !auth.isOwner && !auth.isDelivery;

    if (isCustomer) {
      if (target == 'social_chat') {
        if (threadId != null && threadId > 0) {
          return MaterialPageRoute(
            builder: (_) => SocialChatThreadsScreen(initialThreadId: threadId),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const SocialChatThreadsScreen(),
        );
      }
      if (target == 'social_call') {
        if (threadId != null && threadId > 0) {
          return MaterialPageRoute(
            builder: (_) => SocialCallScreen(
              threadId: threadId,
              isCaller: false,
              initialSessionId: sessionId,
            ),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const SocialChatThreadsScreen(),
        );
      }
      if (target == 'social_feed') {
        return MaterialPageRoute(
          builder: (_) =>
              BasmayaFeedScreen(initialPostId: postId, initialStoryId: storyId),
        );
      }
      if (target == 'taxi_call' && rideId != null && rideId > 0) {
        return MaterialPageRoute(
          builder: (_) => TaxiCallScreen(rideId: rideId, isCaller: false),
        );
      }
      if (target == 'taxi_live') {
        return MaterialPageRoute(builder: (_) => const MapPage());
      }
      if (target == 'order_tracking' || orderId != null) {
        return MaterialPageRoute(
          builder: (_) => CustomerOrdersScreen(initialOrderId: orderId),
        );
      }
      return MaterialPageRoute(builder: (_) => const NotificationsScreen());
    }

    if (auth.isBackoffice) {
      if (target == 'admin_merchants_pending') {
        return MaterialPageRoute(
          builder: (_) => const AdminDashboardScreen(
            initialSection: AdminDashboardSection.pendingApprovals,
          ),
        );
      }
      if (target == 'admin_settlements') {
        return MaterialPageRoute(
          builder: (_) => const AdminDashboardScreen(
            initialSection: AdminDashboardSection.pendingSettlements,
          ),
        );
      }
      if (target == 'order_tracking' && orderId != null) {
        return MaterialPageRoute(
          builder: (_) => CustomerOrdersScreen(initialOrderId: orderId),
        );
      }
      return MaterialPageRoute(builder: (_) => const AdminDashboardScreen());
    }

    if (auth.isOwner) {
      if (target == 'owner_orders' || target == 'order_tracking') {
        return MaterialPageRoute(
          builder: (_) =>
              const OwnerDashboardScreen(initialTab: OwnerDashboardTab.orders),
        );
      }
      return MaterialPageRoute(builder: (_) => const OwnerDashboardScreen());
    }

    if (auth.isDelivery) {
      if (target == 'taxi_call' && rideId != null && rideId > 0) {
        return MaterialPageRoute(
          builder: (_) => TaxiCallScreen(rideId: rideId, isCaller: false),
        );
      }
      if (target == 'delivery_orders' ||
          target == 'taxi_live' ||
          target == 'taxi_call') {
        return MaterialPageRoute(
          builder: (_) => const TaxiCaptainDashboardScreen(),
        );
      }
      return MaterialPageRoute(builder: (_) => const NotificationsScreen());
    }

    return MaterialPageRoute(builder: (_) => const NotificationsScreen());
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    final parsed = int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
