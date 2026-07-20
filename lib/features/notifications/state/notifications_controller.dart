import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/notifications/active_chat_context_registry.dart';
import '../../../core/notifications/attention_alert_service.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/platform/app_platform_capabilities.dart';
import '../../../core/network/session_invalidation.dart';
import '../../../core/realtime/maslaki_realtime_service.dart';
import '../../auth/state/auth_controller.dart';
import '../../delivery/state/delivery_controller.dart';
import '../../owner/state/owner_controller.dart';
import '../../orders/state/orders_controller.dart';
import '../data/notifications_api.dart';
import '../models/app_notification_model.dart';

final notificationsApiProvider = Provider<NotificationsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return NotificationsApi(
    dio,
    realtime: ref.read(maslakiRealtimeServiceProvider),
  );
});

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
      return NotificationsController(ref);
    });

enum NotificationInboxMode { all, general, socialActivity }

enum NotificationBucket { general, socialActivity, socialMessages }

enum NotificationsRealtimeStatus {
  offline,
  connecting,
  connected,
  reconnecting,
}

const Duration _kNotificationsFallbackPollInterval = Duration(seconds: 30);
const int _kNotificationsConnectedUnreadRefreshEveryTicks = 2;
const int _kNotificationsConnectedListRefreshEveryTicks = 4;

/// حالة صندوق الإشعارات داخل التطبيق.
///
/// تحتوي على القائمة الحالية، عداد غير المقروء، وحالة اتصال realtime حتى
/// تستطيع الواجهة عرض inbox موحد دون معرفة تفاصيل SSE أو polling.
class NotificationsState {
  final bool loading;
  final bool marking;
  final int unreadCount;
  final List<AppNotificationModel> notifications;
  final NotificationsRealtimeStatus realtimeStatus;
  final DateTime? realtimeUpdatedAt;
  final int reconnectAttempt;
  final String? error;

  const NotificationsState({
    this.loading = false,
    this.marking = false,
    this.unreadCount = 0,
    this.notifications = const [],
    this.realtimeStatus = NotificationsRealtimeStatus.offline,
    this.realtimeUpdatedAt,
    this.reconnectAttempt = 0,
    this.error,
  });

  NotificationsState copyWith({
    bool? loading,
    bool? marking,
    int? unreadCount,
    List<AppNotificationModel>? notifications,
    NotificationsRealtimeStatus? realtimeStatus,
    DateTime? realtimeUpdatedAt,
    int? reconnectAttempt,
    String? error,
  }) {
    return NotificationsState(
      loading: loading ?? this.loading,
      marking: marking ?? this.marking,
      unreadCount: unreadCount ?? this.unreadCount,
      notifications: notifications ?? this.notifications,
      realtimeStatus: realtimeStatus ?? this.realtimeStatus,
      realtimeUpdatedAt: realtimeUpdatedAt ?? this.realtimeUpdatedAt,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      error: error,
    );
  }
}

/// المتحكم المركزي لصندوق الإشعارات والربط الحي مع SSE وfallback polling.
///
/// Critical notes:
/// - هذا الملف هو source of truth للإشعارات داخل Flutter.
/// - أي desync بين badge والقائمة وعداد غير المقروء يبدأ تشخيصه من هنا.
class NotificationsController extends StateNotifier<NotificationsState> {
  final Ref ref;
  static const Duration _kUnreadRefreshThrottle = Duration(seconds: 2);
  static const Duration _kListRefreshThrottle = Duration(seconds: 3);
  Timer? _fallbackPollTimer;
  Timer? _reconnectTimer;
  Timer? _roleRefreshTimer;
  StreamSubscription<NotificationLiveEvent>? _liveSub;
  bool _realtimeStarted = false;
  bool _realtimeRequestedByUi = false;
  int? _lastEventId;
  int _reconnectAttempt = 0;
  int _fallbackTick = 0;
  bool _unauthorizedHandled = false;
  final Set<int> _recentRealtimeEventIds = <int>{};
  final List<int> _recentRealtimeEventOrder = <int>[];
  DateTime? _lastUnreadRefreshAt;
  DateTime? _lastListRefreshAt;
  Future<void>? _unreadRefreshInFlight;
  late final VoidCallback _sessionRecoveryListener;
  bool _recoveryResyncInFlight = false;

  NotificationsController(this.ref) : super(const NotificationsState()) {
    _sessionRecoveryListener = _handleSessionRecovery;
    SessionRecoveryBus.instance.addListener(_sessionRecoveryListener);
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      final prevToken = previous?.token?.trim() ?? '';
      final nextToken = next.token?.trim() ?? '';
      final hadSession = prevToken.isNotEmpty;
      final hasSession = nextToken.isNotEmpty;

      if (!hasSession) {
        _unauthorizedHandled = false;
        _realtimeRequestedByUi = false;
        if (_realtimeStarted) {
          stopRealtime();
        }
        state = state.copyWith(
          unreadCount: 0,
          notifications: const [],
          error: null,
          realtimeStatus: NotificationsRealtimeStatus.offline,
          reconnectAttempt: 0,
        );
        return;
      }

      if (!hadSession && hasSession) {
        _unauthorizedHandled = false;
        if (_realtimeRequestedByUi) {
          startRealtime();
        }
      }
    });
  }

  /// Re-syncs notifications after a silent session recovery.
  ///
  /// Recovery is not a logout: the list and the unread badge must survive it,
  /// and realtime must come back rather than stay offline.
  void _handleSessionRecovery() {
    if (!mounted) return;
    // Let the next 401 be handled again and allow an immediate reconnect.
    _unauthorizedHandled = false;
    _reconnectAttempt = 0;
    // Duplicate recovery ticks must not stack reconnects or refresh bursts.
    if (_recoveryResyncInFlight) return;
    _recoveryResyncInFlight = true;
    if (_realtimeRequestedByUi) {
      // stopRealtime clears the started flag so startRealtime re-subscribes
      // with a freshly minted token instead of returning early.
      stopRealtime();
      startRealtime();
    }
    unawaited(
      refreshUnreadCount().whenComplete(() => _recoveryResyncInFlight = false),
    );
  }

  /// يجلب عدد الإشعارات غير المقروءة فقط دون إعادة تحميل القائمة كاملة.
  Future<void> refreshUnreadCount() async {
    if (!_hasActiveSession()) return;
    final now = DateTime.now();
    final shouldThrottle =
        _lastUnreadRefreshAt != null &&
        now.difference(_lastUnreadRefreshAt!) < _kUnreadRefreshThrottle;
    if (shouldThrottle && _unreadRefreshInFlight != null) {
      await _unreadRefreshInFlight;
      return;
    }
    if (shouldThrottle) return;

    final future = () async {
      _lastUnreadRefreshAt = DateTime.now();
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final count = await ref.read(notificationsApiProvider).unreadCount();
          state = state.copyWith(unreadCount: count);
          return;
        } on DioException catch (e) {
          if (attempt == 0 && _isTransientFetchError(e)) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            continue;
          }
          if (_isUnauthorized(e)) {
            _handleUnauthorized();
          }
          return;
        } catch (_) {
          // Keep silent for background refresh.
          return;
        }
      }
    }();
    _unreadRefreshInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_unreadRefreshInFlight, future)) {
        _unreadRefreshInFlight = null;
      }
    }
  }

  /// يحمل قائمة الإشعارات من API مع دعم وضع `silent` للخلفية.
  ///
  /// Maintenance notes:
  /// - عند بقاء قائمة قديمة رغم وصول أحداث حية، افحص هذه الدالة مع
  ///   `_handleRealtimeEvent` و`NotificationsApi.list`.
  Future<void> loadNotifications({
    bool unreadOnly = false,
    bool silent = false,
  }) async {
    if (!_hasActiveSession()) {
      if (!silent) {
        state = state.copyWith(loading: false, error: null);
      }
      return;
    }

    final now = DateTime.now();
    final shouldThrottle =
        !unreadOnly &&
        _lastListRefreshAt != null &&
        now.difference(_lastListRefreshAt!) < _kListRefreshThrottle;
    if (shouldThrottle) return;
    _lastListRefreshAt = now;

    if (!silent) {
      state = state.copyWith(loading: true, error: null);
    }

    try {
      List<dynamic> raw = const <dynamic>[];
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          raw = await ref
              .read(notificationsApiProvider)
              .list(unreadOnly: unreadOnly, limit: 100);
          break;
        } on DioException catch (e) {
          if (attempt == 0 && _isTransientFetchError(e)) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            continue;
          }
          if (_isUnauthorized(e)) {
            _handleUnauthorized();
            return;
          }
          rethrow;
        }
      }
      final list = raw
          .map(
            (e) => AppNotificationModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      final listUnreadCount = list.where((n) => !n.isRead).length;
      final nextUnreadCount = state.unreadCount < listUnreadCount
          ? listUnreadCount
          : state.unreadCount;

      state = state.copyWith(
        loading: silent ? state.loading : false,
        notifications: list,
        unreadCount: nextUnreadCount,
      );
    } on DioException catch (e) {
      if (_isUnauthorized(e)) {
        _handleUnauthorized();
        return;
      }
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

  /// يطبق optimistic read على عنصر واحد ثم يثبتها عبر API.
  Future<void> markRead(int notificationId) async {
    if (!_hasActiveSession()) return;
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

  /// يعلّم كل الإشعارات كمقروءة مع الحفاظ على fallback rollback عند الفشل.
  Future<void> markAllRead() async {
    if (!_hasActiveSession()) return;
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

  Future<void> markSocialChatNotificationsRead({int? threadId}) async {
    if (!_hasActiveSession()) return;
    final targets = state.notifications
        .where((n) => _isUnreadSocialChatNotification(n, threadId: threadId))
        .toList(growable: false);
    if (targets.isEmpty) return;

    final targetIds = targets.map((n) => n.id).toSet();
    final now = DateTime.now();
    final optimistic = state.notifications
        .map(
          (n) => targetIds.contains(n.id)
              ? n.copyWith(isRead: true, readAt: now)
              : n,
        )
        .toList(growable: false);
    state = state.copyWith(
      notifications: optimistic,
      unreadCount: optimistic.where((n) => !n.isRead).length,
      error: null,
    );

    await Future.wait(
      targets.map((n) async {
        try {
          await ref.read(notificationsApiProvider).markRead(n.id);
        } catch (_) {
          // Keep optimistic state; background refresh will reconcile if needed.
        }
      }),
    );
  }

  Future<void> markSocialCommunityNotificationsRead({
    required String scopeType,
    required String scopeCode,
  }) async {
    if (!_hasActiveSession()) return;
    final targets = state.notifications
        .where(
          (n) => _isUnreadSocialCommunityNotification(
            n,
            scopeType: scopeType,
            scopeCode: scopeCode,
          ),
        )
        .toList(growable: false);
    if (targets.isEmpty) return;

    final targetIds = targets.map((n) => n.id).toSet();
    final now = DateTime.now();
    final optimistic = state.notifications
        .map(
          (n) => targetIds.contains(n.id)
              ? n.copyWith(isRead: true, readAt: now)
              : n,
        )
        .toList(growable: false);
    state = state.copyWith(
      notifications: optimistic,
      unreadCount: optimistic.where((n) => !n.isRead).length,
      error: null,
    );

    await Future.wait(
      targets.map((n) async {
        try {
          await ref.read(notificationsApiProvider).markRead(n.id);
        } catch (_) {
          // Keep optimistic state; background refresh will reconcile if needed.
        }
      }),
    );
  }

  /// يبدأ SSE للإشعارات ويشغّل fallback polling عند الحاجة.
  ///
  /// Critical notes:
  /// - لا يجب استدعاؤها دون جلسة فعالة.
  /// - إعادة الاتصال المنضبطة هنا مهمة لمنع تعدد الاشتراكات أو تضاعف
  ///   events في الواجهة.
  void startRealtime() {
    _realtimeRequestedByUi = true;
    if (_realtimeStarted) return;
    if (!_hasActiveSession()) {
      _setRealtimeStatus(
        NotificationsRealtimeStatus.offline,
        reconnectAttempt: 0,
      );
      return;
    }

    _unauthorizedHandled = false;
    _realtimeStarted = true;
    _fallbackTick = 0;
    _setRealtimeStatus(NotificationsRealtimeStatus.connecting);

    unawaited(refreshUnreadCount());
    unawaited(loadNotifications(silent: true));
    _fallbackPollTimer = Timer.periodic(_kNotificationsFallbackPollInterval, (
      _,
    ) {
      if (!_hasActiveSession()) {
        stopRealtime();
        return;
      }
      _fallbackTick += 1;
      final connected =
          state.realtimeStatus == NotificationsRealtimeStatus.connected;
      final shouldRefreshUnread =
          !connected ||
          _fallbackTick % _kNotificationsConnectedUnreadRefreshEveryTicks == 0;
      final shouldSyncList =
          !connected ||
          _fallbackTick % _kNotificationsConnectedListRefreshEveryTicks == 0;
      if (shouldRefreshUnread) {
        unawaited(refreshUnreadCount());
      }
      if (shouldSyncList) {
        unawaited(loadNotifications(silent: true));
      }
    });

    _connectLiveStream();
  }

  /// يوقف كل مصادر realtime/polling ويفرغ الموارد المرتبطة بالجلسة.
  void stopRealtime() {
    _realtimeStarted = false;
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _roleRefreshTimer?.cancel();
    _roleRefreshTimer = null;
    _liveSub?.cancel();
    _liveSub = null;
    _reconnectAttempt = 0;
    _fallbackTick = 0;
    _resetRealtimeCursor();
    _setRealtimeStatus(
      NotificationsRealtimeStatus.offline,
      reconnectAttempt: 0,
    );
  }

  void _connectLiveStream() {
    if (!_hasActiveSession()) {
      stopRealtime();
      return;
    }

    _setRealtimeStatus(
      _reconnectAttempt > 0
          ? NotificationsRealtimeStatus.reconnecting
          : NotificationsRealtimeStatus.connecting,
      reconnectAttempt: _reconnectAttempt,
    );
    _liveSub?.cancel();
    _liveSub = ref
        .read(notificationsApiProvider)
        .streamEvents(lastEventId: _lastEventId, channel: 'notifications')
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
    _setRealtimeStatus(
      NotificationsRealtimeStatus.reconnecting,
      reconnectAttempt: _reconnectAttempt,
    );
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
    _setRealtimeStatus(
      NotificationsRealtimeStatus.connected,
      reconnectAttempt: 0,
      touchedAt: DateTime.now(),
    );

    if (event.event == 'connected') {
      _reconnectAttempt = 0;
      unawaited(refreshUnreadCount());
      unawaited(loadNotifications(silent: true));
      return;
    }

    if (event.event == 'replayed') {
      _reconnectAttempt = 0;
      unawaited(refreshUnreadCount());
      unawaited(loadNotifications(silent: true));
      return;
    }

    if (event.event == 'resync_required') {
      _reconnectAttempt = 0;
      _resetRealtimeCursor(
        lastEventId: _readEventId(event.data['latestEventId']),
      );
      unawaited(refreshUnreadCount());
      unawaited(loadNotifications(silent: true));
      _scheduleRoleRefresh(force: true);
      return;
    }

    if (event.event == 'heartbeat') return;
    if (!_acceptRealtimeEvent(event.eventId)) return;

    if (event.event == 'notification') {
      final rawNotification = event.data['notification'];
      if (rawNotification is Map) {
        final model = AppNotificationModel.fromJson(
          Map<String, dynamic>.from(rawNotification),
        );
        final shouldSuppress = _shouldSuppressInActiveChat(model);
        final effectiveModel = shouldSuppress && !model.isRead
            ? model.copyWith(isRead: true, readAt: DateTime.now())
            : model;

        if (!shouldSuppress &&
            !appSupportsPushMessaging &&
            appSupportsLocalNotifications) {
          unawaited(
            ref.read(localNotificationsProvider).showFromModel(effectiveModel),
          );
        }
        if (!shouldSuppress &&
            _notificationRequiresAction(effectiveModel) &&
            (!appSupportsLocalNotifications || appIsDesktop)) {
          unawaited(ref.read(attentionAlertServiceProvider).play());
        }

        final withoutCurrent = state.notifications
            .where((n) => n.id != effectiveModel.id)
            .toList();
        final nextList = [effectiveModel, ...withoutCurrent];

        state = state.copyWith(
          notifications: nextList,
          unreadCount: nextList.where((n) => !n.isRead).length,
        );

        if (shouldSuppress && model.id > 0 && !model.isRead) {
          unawaited(ref.read(notificationsApiProvider).markRead(model.id));
        }

        final orderId =
            effectiveModel.orderId ?? effectiveModel.payload?['orderId'];
        if (orderId != null) {
          _scheduleRoleRefresh();
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

  bool _acceptRealtimeEvent(int? eventId) {
    if (eventId == null || eventId <= 0) return true;
    if (_recentRealtimeEventIds.contains(eventId)) return false;
    if (_lastEventId != null && eventId <= _lastEventId!) return false;

    _lastEventId = eventId;
    _recentRealtimeEventIds.add(eventId);
    _recentRealtimeEventOrder.add(eventId);

    const maxRememberedIds = 240;
    while (_recentRealtimeEventOrder.length > maxRememberedIds) {
      final removed = _recentRealtimeEventOrder.removeAt(0);
      _recentRealtimeEventIds.remove(removed);
    }

    return true;
  }

  int? _readEventId(dynamic value) {
    if (value == null) return null;
    final parsed = int.tryParse('$value');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  void _resetRealtimeCursor({int? lastEventId}) {
    _recentRealtimeEventIds.clear();
    _recentRealtimeEventOrder.clear();
    _lastEventId = (lastEventId != null && lastEventId > 0)
        ? lastEventId
        : null;
  }

  void _scheduleRoleRefresh({bool force = false}) {
    if (_roleRefreshTimer?.isActive == true && !force) return;
    _roleRefreshTimer?.cancel();
    _roleRefreshTimer = Timer(
      force
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 450),
      () {
        final auth = ref.read(authControllerProvider);
        if (auth.isTaxiCaptain) {
          // Taxi captains have a dedicated module; avoid forcing courier refresh.
          return;
        }
        final role = auth.user?.role ?? '';
        switch (role) {
          case 'owner':
            unawaited(
              ref
                  .read(ownerControllerProvider.notifier)
                  .refreshOrders(includeHistory: false),
            );
            break;
          case 'delivery':
            unawaited(
              ref
                  .read(deliveryControllerProvider.notifier)
                  .refreshCurrentOrders(),
            );
            break;
          case 'user':
          default:
            unawaited(
              ref
                  .read(ordersControllerProvider.notifier)
                  .loadMyOrders(silent: true),
            );
            break;
        }
      },
    );
  }

  bool _notificationRequiresAction(AppNotificationModel notification) {
    final payload = notification.payload;
    if (payload == null) return false;
    final raw = payload['requiresAction'];
    if (raw == true) return true;
    final normalized = '$raw'.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  bool _isUnreadSocialChatNotification(
    AppNotificationModel notification, {
    int? threadId,
  }) {
    if (notification.isRead) return false;
    final target = (notification.target ?? '').trim().toLowerCase();
    final type = notification.type.trim().toLowerCase();
    final isChat =
        target == 'social_chat' ||
        type.startsWith('social.chat.') ||
        type.startsWith('social_chat.') ||
        type == 'social_chat_message';
    if (!isChat) return false;
    if (threadId == null || threadId <= 0) return true;
    final notificationThreadId = _extractThreadId(notification);
    return notificationThreadId == threadId;
  }

  bool _isUnreadSocialCommunityNotification(
    AppNotificationModel notification, {
    required String scopeType,
    required String scopeCode,
  }) {
    if (notification.isRead) return false;
    final target = (notification.target ?? '').trim().toLowerCase();
    final type = notification.type.trim().toLowerCase();
    final isCommunity =
        target == 'social_community' ||
        type.startsWith('social.community.') ||
        type.startsWith('social_community.');
    if (!isCommunity) return false;

    final nType = _extractScopeType(notification);
    final nCode = _extractScopeCode(notification);
    final expectedType = scopeType.trim().toLowerCase();
    final expectedCode = scopeCode.trim().toUpperCase();
    return nType == expectedType && nCode == expectedCode;
  }

  int? _extractThreadId(AppNotificationModel notification) {
    final payload = notification.payload;
    if (payload == null) return null;
    final raw = payload['threadId'] ?? payload['thread_id'];
    final parsed = int.tryParse('$raw');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String? _extractScopeType(AppNotificationModel notification) {
    final payload = notification.payload;
    if (payload == null) return null;
    final raw = payload['scopeType'] ?? payload['scope_type'];
    final safe = '$raw'.trim().toLowerCase();
    return safe.isEmpty ? null : safe;
  }

  String? _extractScopeCode(AppNotificationModel notification) {
    final payload = notification.payload;
    if (payload == null) return null;
    final raw = payload['scopeCode'] ?? payload['scope_code'];
    final safe = '$raw'.trim().toUpperCase();
    return safe.isEmpty ? null : safe;
  }

  bool _shouldSuppressInActiveChat(AppNotificationModel notification) {
    final payload = notification.payload ?? const <String, dynamic>{};
    final threadId = _extractThreadId(notification);
    return ActiveChatContextRegistry.matchesPayload(
      target: notification.target ?? payload['target']?.toString(),
      type: notification.type,
      threadId: threadId,
      scopeType:
          payload['scopeType']?.toString() ?? payload['scope_type']?.toString(),
      scopeCode:
          payload['scopeCode']?.toString() ?? payload['scope_code']?.toString(),
    );
  }

  void _setRealtimeStatus(
    NotificationsRealtimeStatus status, {
    int? reconnectAttempt,
    DateTime? touchedAt,
  }) {
    state = state.copyWith(
      realtimeStatus: status,
      reconnectAttempt: reconnectAttempt ?? state.reconnectAttempt,
      realtimeUpdatedAt: touchedAt ?? state.realtimeUpdatedAt,
    );
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

  bool _isTransientFetchError(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401 || statusCode == 403 || statusCode == 408) {
        return true;
      }
      final data = error.response?.data;
      if (data is Map) {
        final message = '${data['message'] ?? data['error'] ?? ''}'
            .trim()
            .toUpperCase();
        return message.contains('INVALID_TOKEN') ||
            message.contains('TOKEN_EXPIRED') ||
            message.contains('UNAUTHORIZED') ||
            message.contains('SESSION');
      }
    }
    return false;
  }

  String? _currentAccessToken() {
    final token = ref.read(authControllerProvider).token;
    final clean = token?.trim();
    if (clean == null || clean.isEmpty) return null;
    return clean;
  }

  bool _hasActiveSession() {
    return _currentAccessToken() != null;
  }

  /// يعزل قناة الإشعارات عند 401 بدون إسقاط جلسة التطبيق كاملة.
  void _handleUnauthorized() {
    if (_unauthorizedHandled) return;
    _unauthorizedHandled = true;
    stopRealtime();
    state = state.copyWith(
      error: 'تعذر مزامنة الإشعارات حاليا. سيتم إيقاف التحديث الحي مؤقتا.',
      realtimeStatus: NotificationsRealtimeStatus.offline,
      reconnectAttempt: 0,
    );
  }

  @override
  /// ينظف جميع الـ timers والاشتراكات لتفادي memory leaks أو events متأخرة.
  void dispose() {
    SessionRecoveryBus.instance.removeListener(_sessionRecoveryListener);
    stopRealtime();
    super.dispose();
  }
}

bool isSocialMessageNotification(AppNotificationModel notification) {
  final target = (notification.target ?? '').trim().toLowerCase();
  final type = notification.type.trim().toLowerCase();
  return target == 'social_chat' ||
      target == 'social_call' ||
      type.startsWith('social.chat.') ||
      type.startsWith('social.call.') ||
      type.startsWith('social_chat.') ||
      type.startsWith('social_call.') ||
      type == 'social_chat_message';
}

bool isSocialActivityNotification(AppNotificationModel notification) {
  if (notification.isRead && notification.payload == null) {
    // Fall through to type-based checks below for legacy payload-light rows.
  }
  if (isSocialMessageNotification(notification)) return false;
  final target = (notification.target ?? '').trim().toLowerCase();
  final type = notification.type.trim().toLowerCase();
  if (target == 'social_feed' ||
      target == 'social_post' ||
      target == 'social_reel' ||
      target == 'social_story' ||
      target == 'social_profile' ||
      target == 'social_restriction_notice' ||
      target == 'social_restrictions') {
    return true;
  }
  if (!type.startsWith('social.')) return false;
  if (type.startsWith('social.community.') ||
      type.startsWith('social.report.') ||
      type.startsWith('social.capability.')) {
    return false;
  }
  return true;
}

bool isGeneralAppNotification(AppNotificationModel notification) {
  return !isSocialMessageNotification(notification) &&
      !isSocialActivityNotification(notification);
}

NotificationBucket resolveNotificationBucket(
  AppNotificationModel notification,
) {
  if (isSocialMessageNotification(notification)) {
    return NotificationBucket.socialMessages;
  }
  if (isSocialActivityNotification(notification)) {
    return NotificationBucket.socialActivity;
  }
  return NotificationBucket.general;
}

final generalNotificationsProvider = Provider<List<AppNotificationModel>>((
  ref,
) {
  final notifications = ref
      .watch(notificationsControllerProvider)
      .notifications;
  return notifications.where(isGeneralAppNotification).toList(growable: false);
});

final socialActivityNotificationsProvider =
    Provider<List<AppNotificationModel>>((ref) {
      final notifications = ref
          .watch(notificationsControllerProvider)
          .notifications;
      return notifications
          .where(isSocialActivityNotification)
          .toList(growable: false);
    });

final socialMessageNotificationsProvider = Provider<List<AppNotificationModel>>(
  (ref) {
    final notifications = ref
        .watch(notificationsControllerProvider)
        .notifications;
    return notifications
        .where(isSocialMessageNotification)
        .toList(growable: false);
  },
);

int _unreadCountOf(Iterable<AppNotificationModel> notifications) =>
    notifications.where((notification) => !notification.isRead).length;

final generalUnreadCountProvider = Provider<int>((ref) {
  return _unreadCountOf(ref.watch(generalNotificationsProvider));
});

final socialActivityUnreadCountProvider = Provider<int>((ref) {
  return _unreadCountOf(ref.watch(socialActivityNotificationsProvider));
});

final socialMessagesUnreadCountProvider = Provider<int>((ref) {
  return _unreadCountOf(ref.watch(socialMessageNotificationsProvider));
});
