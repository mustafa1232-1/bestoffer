import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../../orders/state/orders_controller.dart';
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
  Timer? _fallbackPollTimer;
  Timer? _reconnectTimer;
  StreamSubscription<NotificationLiveEvent>? _liveSub;
  bool _realtimeStarted = false;
  int? _lastEventId;
  int _reconnectAttempt = 0;

  NotificationsController(this.ref) : super(const NotificationsState()) {
    startRealtime();
  }

  Future<void> refreshUnreadCount() async {
    try {
      final count = await ref.read(notificationsApiProvider).unreadCount();
      state = state.copyWith(unreadCount: count);
    } on DioException catch (e) {
      if (_isUnauthorized(e)) {
        _handleUnauthorized();
      }
    } catch (_) {
      // Keep silent for background refresh.
    }
  }

  Future<void> loadNotifications({
    bool unreadOnly = false,
    bool silent = false,
  }) async {
    if (!silent) {
      state = state.copyWith(loading: true, error: null);
    }

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

      state = state.copyWith(
        loading: silent ? state.loading : false,
        notifications: list,
        unreadCount: list.where((n) => !n.isRead).length,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        loading: silent ? state.loading : false,
        error: _mapError(e),
      );
    } catch (e) {
      state = state.copyWith(
        loading: silent ? state.loading : false,
        error: mapAnyError(e, fallback: 'تعذر تحميل الإشعارات.'),
      );
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
    } catch (e) {
      state = state.copyWith(
        error: mapAnyError(e, fallback: 'تعذر تحديث الإشعار.'),
      );
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
    } catch (e) {
      state = state.copyWith(
        marking: false,
        error: mapAnyError(e, fallback: 'تعذر تعليم جميع الإشعارات كمقروءة.'),
      );
    }
  }

  void startRealtime() {
    if (_realtimeStarted) return;
    _realtimeStarted = true;

    unawaited(refreshUnreadCount());
    unawaited(loadNotifications(silent: true));
    _fallbackPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(refreshUnreadCount());
      unawaited(loadNotifications(silent: true));
    });

    _connectLiveStream();
  }

  void stopRealtime() {
    _realtimeStarted = false;
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _liveSub?.cancel();
    _liveSub = null;
    _reconnectAttempt = 0;
  }

  void _connectLiveStream() {
    _liveSub?.cancel();
    _liveSub = ref
        .read(notificationsApiProvider)
        .streamEvents(lastEventId: _lastEventId)
        .listen(
          _onLiveEvent,
          onError: (error) {
            if (_isUnauthorized(error)) {
              _handleUnauthorized();
              return;
            }
            _scheduleReconnect();
          },
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  void _scheduleReconnect() {
    if (!_realtimeStarted) return;
    if (_reconnectTimer?.isActive == true) return;

    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 6);
    final delaySeconds = switch (_reconnectAttempt) {
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 12,
      5 => 20,
      _ => 30,
    };

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_realtimeStarted) return;
      _connectLiveStream();
    });
  }

  void _onLiveEvent(NotificationLiveEvent event) {
    if (event.eventId != null && event.eventId! > 0) {
      _lastEventId = event.eventId;
    }

    if (event.event == 'connected') {
      _reconnectAttempt = 0;
      unawaited(loadNotifications(silent: true));
      return;
    }

    if (event.event == 'replayed') {
      _reconnectAttempt = 0;
      unawaited(loadNotifications(silent: true));
      return;
    }

    if (event.event == 'heartbeat') return;

    if (event.event == 'notification') {
      final rawNotification = event.data['notification'];
      if (rawNotification is Map) {
        final model = AppNotificationModel.fromJson(
          Map<String, dynamic>.from(rawNotification),
        );

        final withoutCurrent = state.notifications
            .where((n) => n.id != model.id)
            .toList();
        final nextList = [model, ...withoutCurrent];

        state = state.copyWith(
          notifications: nextList,
          unreadCount: nextList.where((n) => !n.isRead).length,
        );

        final orderId = model.orderId ?? model.payload?['orderId'];
        if (orderId != null) {
          unawaited(
            ref
                .read(ordersControllerProvider.notifier)
                .loadMyOrders(silent: true),
          );
        }
      } else {
        unawaited(refreshUnreadCount());
      }
      return;
    }

    if (event.event == 'notification_read') {
      final id = int.tryParse('${event.data['notificationId']}');
      if (id == null) return;

      final updated = state.notifications
          .map(
            (n) => n.id == id
                ? n.copyWith(isRead: true, readAt: DateTime.now())
                : n,
          )
          .toList();
      state = state.copyWith(
        notifications: updated,
        unreadCount: updated.where((n) => !n.isRead).length,
      );
      return;
    }

    if (event.event == 'notification_read_all') {
      state = state.copyWith(
        unreadCount: 0,
        notifications: state.notifications
            .map((n) => n.copyWith(isRead: true, readAt: DateTime.now()))
            .toList(),
      );
      return;
    }

    unawaited(refreshUnreadCount());
  }

  String _mapError(DioException e) {
    return mapDioError(
      e,
      fallback: 'تعذر الاتصال بالخادم أثناء تحميل الإشعارات.',
      appendRequestId: true,
    );
  }

  bool _isUnauthorized(Object error) {
    if (error is DioException) {
      return error.response?.statusCode == 401;
    }
    return false;
  }

  void _handleUnauthorized() {
    stopRealtime();
    state = state.copyWith(error: 'انتهت الجلسة. يرجى تسجيل الدخول مجددًا.');
  }

  @override
  void dispose() {
    stopRealtime();
    super.dispose();
  }
}
