import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../data/notifications_api.dart';
import '../models/app_notification_model.dart';

final notificationsApiProvider = Provider<NotificationsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return NotificationsApi(dio);
});

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
      return NotificationsController(ref);
    });

class NotificationsState {
  final bool loading;
  final bool marking;
  final int unreadCount;
  final List<AppNotificationModel> notifications;
  final String? error;

  const NotificationsState({
    this.loading = false,
    this.marking = false,
    this.unreadCount = 0,
    this.notifications = const [],
    this.error,
  });

  NotificationsState copyWith({
    bool? loading,
    bool? marking,
    int? unreadCount,
    List<AppNotificationModel>? notifications,
    String? error,
  }) {
    return NotificationsState(
      loading: loading ?? this.loading,
      marking: marking ?? this.marking,
      unreadCount: unreadCount ?? this.unreadCount,
      notifications: notifications ?? this.notifications,
      error: error,
    );
  }
}

class NotificationsController extends StateNotifier<NotificationsState> {
  final Ref ref;

  NotificationsController(this.ref) : super(const NotificationsState());

  Future<void> refreshUnreadCount() async {
    try {
      final count = await ref.read(notificationsApiProvider).unreadCount();
      state = state.copyWith(unreadCount: count);
    } catch (_) {
      // ignore
    }
  }

  Future<void> loadNotifications({bool unreadOnly = false}) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final raw = await ref
          .read(notificationsApiProvider)
          .list(unreadOnly: unreadOnly, limit: 100);
      final list = raw
          .map(
            (e) => AppNotificationModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();

      final unread = list.where((n) => !n.isRead).length;

      state = state.copyWith(
        loading: false,
        notifications: list,
        unreadCount: unread,
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(loading: false, error: 'فشل تحميل الإشعارات');
    }
  }

  Future<void> markRead(int notificationId) async {
    final index = state.notifications.indexWhere((n) => n.id == notificationId);
    if (index < 0) return;
    final target = state.notifications[index];
    if (target.isRead) return;

    final updated = [...state.notifications];
    updated[index] = target.copyWith(isRead: true, readAt: DateTime.now());
    state = state.copyWith(
      notifications: updated,
      unreadCount: (state.unreadCount - 1).clamp(0, 9999).toInt(),
      error: null,
    );

    try {
      await ref.read(notificationsApiProvider).markRead(notificationId);
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
    } catch (_) {
      state = state.copyWith(error: 'فشل تحديث الإشعار');
    }
  }

  Future<void> markAllRead() async {
    state = state.copyWith(marking: true, error: null);
    try {
      await ref.read(notificationsApiProvider).markAllRead();
      state = state.copyWith(
        marking: false,
        unreadCount: 0,
        notifications: state.notifications
            .map((n) => n.copyWith(isRead: true, readAt: DateTime.now()))
            .toList(),
      );
    } on DioException catch (e) {
      state = state.copyWith(marking: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(marking: false, error: 'فشل تعليم الكل كمقروء');
    }
  }

  String _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    return 'حدث خطأ في الاتصال بالخادم';
  }
}
