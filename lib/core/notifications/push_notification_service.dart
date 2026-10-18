import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/state/auth_controller.dart';
import '../calls/incoming_call_service.dart';
import '../../features/notifications/data/notifications_api.dart';
import '../../features/orders/state/order_refresh_bus.dart';
import '../network/session_invalidation.dart';
import 'active_chat_context_registry.dart';
import '../platform/app_platform_capabilities.dart';
import '../platform/app_flavor.dart';
import '../storage/secure_storage.dart';
import 'firebase_runtime_options.dart';
import 'local_notification_service.dart';
import 'web_notification_service.dart';

const _tokenHeartbeatInterval = Duration(minutes: 15);
const _tokenForceResyncInterval = Duration(hours: 6);
const _appLocaleStorageKey = 'app_locale';
const _firebaseWebVapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

class PushTokenSessionContext {
  const PushTokenSessionContext({
    required this.userId,
    required this.sessionId,
    required this.appSurface,
  });

  final int userId;
  final int sessionId;
  final String appSurface;
}

String canonicalAppSurface(AppFlavor flavor) => switch (flavor) {
  AppFlavor.user => 'user',
  AppFlavor.store => 'store',
  AppFlavor.delivery => 'delivery',
  AppFlavor.taxiCaptain => 'taxi',
  AppFlavor.company => 'company',
};

String? normalizeNotificationAppSurface(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  return switch (normalized) {
    'user' || 'customer' => 'user',
    'store' || 'owner' || 'merchant' => 'store',
    'delivery' || 'courier' => 'delivery',
    'taxi' || 'taxi_captain' || 'captain' => 'taxi',
    'company' => 'company',
    _ => null,
  };
}

bool notificationPayloadMatchesAppFlavor(
  NotificationTapPayload payload,
  AppFlavor flavor,
) {
  final intended = normalizeNotificationAppSurface(payload.appSurface);
  if (flavor == AppFlavor.user && intended == 'company') return true;
  return intended != null && intended == canonicalAppSurface(flavor);
}

PushTokenSessionContext? resolvePushTokenSessionContext({
  required String accessToken,
  required int expectedUserId,
  required AppFlavor flavor,
}) {
  try {
    final claims = JwtDecoder.decode(accessToken);
    final userId = int.tryParse('${claims['sub'] ?? claims['id'] ?? ''}');
    final sessionId = int.tryParse('${claims['sid'] ?? ''}');
    final claimedSurface = normalizeNotificationAppSurface(
      claims['appSurface']?.toString(),
    );
    final expectedSurface = canonicalAppSurface(flavor);
    final acceptedSurface =
        flavor == AppFlavor.user && claimedSurface == 'company'
        ? 'company'
        : expectedSurface;
    if (userId == null ||
        userId <= 0 ||
        userId != expectedUserId ||
        sessionId == null ||
        sessionId <= 0 ||
        (claimedSurface != null && claimedSurface != acceptedSurface)) {
      return null;
    }
    return PushTokenSessionContext(
      userId: userId,
      sessionId: sessionId,
      appSurface: acceptedSurface,
    );
  } catch (_) {
    return null;
  }
}

void _pushDebugLog(String message) {
  if (kDebugMode) debugPrint('[push] $message');
}

/// Package name → app flavor. The FCM background isolate never runs the
/// flavor's `main`, so [AppFlavorContext.current] is still the `user` default
/// there; without this the store / delivery / captain / company apps dropped
/// every data-only push (ride requests, urgent assignments) while closed.
@visibleForTesting
AppFlavor? appFlavorForPackageName(String packageName) {
  final normalized = packageName.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  final suffix = normalized.split('.').last;
  return switch (suffix) {
    'user' => AppFlavor.user,
    'store' || 'pharmacy' => AppFlavor.store,
    'delivery' => AppFlavor.delivery,
    'captain' => AppFlavor.taxiCaptain,
    'company' => AppFlavor.company,
    _ => null,
  };
}

Future<AppFlavor> _resolveBackgroundAppFlavor() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final flavor = appFlavorForPackageName(info.packageName);
    if (flavor != null) {
      AppFlavorContext.setCurrent(flavor);
      return flavor;
    }
  } catch (_) {
    // Fall back to whatever the isolate already knows.
  }
  return AppFlavorContext.current;
}

bool _prefersEnglish(Map<String, dynamic> data) {
  final title = '${data['title'] ?? ''}';
  return title.isNotEmpty && !RegExp(r'[\u0600-\u06FF]').hasMatch(title);
}

/// Call invites ring through the native call UI; "call ended" dismisses it.
/// Returns true when [data] was a call event and has been fully handled.
Future<bool> handleCallPushData(
  Map<String, dynamic> data, {
  required AppFlavor flavor,
}) async {
  final isInvite = IncomingCallService.isCallInvite(data);
  final isEnded = IncomingCallService.isCallEnded(data);
  if (!isInvite && !isEnded) return false;
  // In-app calls live in the user app only.
  if (flavor != AppFlavor.user || !IncomingCallService.supported) return true;
  if (isEnded) {
    final sessionId = int.tryParse('${data['sessionId'] ?? ''}');
    final uuid = '${data['callUuid'] ?? ''}'.trim();
    if (uuid.isNotEmpty) {
      await IncomingCallService.endCall(uuid);
    } else {
      await IncomingCallService.endCallForSession(sessionId);
    }
    return true;
  }
  final invite = IncomingCallInvite.fromPushData(data);
  if (invite == null) return true;
  await IncomingCallService.showIncoming(
    invite,
    english: _prefersEnglish(data),
  );
  return true;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!appSupportsPushMessaging) return;
  try {
    if (Firebase.apps.isEmpty) {
      final runtimeOptions = FirebaseRuntimeOptions.currentPlatform();
      if (runtimeOptions != null) {
        await Firebase.initializeApp(options: runtimeOptions);
      } else {
        await Firebase.initializeApp();
      }
    }

    // For data-only pushes, render a local notification while app is backgrounded.
    if (message.notification == null && message.data.isNotEmpty) {
      final flavor = await _resolveBackgroundAppFlavor();
      final parsed = _parseRemoteMessagePayload(message);
      if (!notificationPayloadMatchesAppFlavor(parsed.$3, flavor)) {
        _pushDebugLog(
          'background payload ignored for surface=${parsed.$3.appSurface}',
        );
        return;
      }
      if (await handleCallPushData(message.data, flavor: flavor)) return;
      final local = LocalNotificationService();
      await local.initialize();

      await local.showRaw(
        title: parsed.$1,
        body: parsed.$2,
        orderId: parsed.$3.orderId,
        rideId: parsed.$3.rideId,
        offerId: parsed.$3.offerId,
        bidId: parsed.$3.bidId,
        jobId: parsed.$3.jobId,
        applicationId: parsed.$3.applicationId,
        postId: parsed.$3.postId,
        storyId: parsed.$3.storyId,
        threadId: parsed.$3.threadId,
        senderUserId: parsed.$3.senderUserId,
        captainId: parsed.$3.captainId,
        customerUserId: parsed.$3.customerUserId,
        sessionId: parsed.$3.sessionId,
        notificationId: parsed.$3.notificationId,
        type: parsed.$3.type,
        target: parsed.$3.target,
        targetModule: parsed.$3.targetModule,
        roleScope: parsed.$3.roleScope,
        appSurface: parsed.$3.appSurface,
        action: parsed.$3.action,
        targetEntity: parsed.$3.targetEntity,
        entityId: parsed.$3.entityId,
        scopeType: parsed.$3.scopeType,
        scopeCode: parsed.$3.scopeCode,
        remoteDisplayName: parsed.$3.remoteDisplayName,
        requiresAction: parsed.$3.requiresAction,
      );
    }
  } catch (e) {
    debugPrint('Background push handler failed: $e');
  }
}

final pushNotificationsProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService(
    api: NotificationsApi(ref.read(dioClientProvider).dio),
    local: ref.read(localNotificationsProvider),
    store: ref.read(secureStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class PushNotificationService {
  final NotificationsApi api;
  final LocalNotificationService local;
  final SecureStore store;
  late final VoidCallback _sessionRecoveryListener;

  PushNotificationService({
    required this.api,
    required this.local,
    required this.store,
  }) {
    _sessionRecoveryListener = () {
      // Recovery is not a logout: keep the bound user and re-register the push
      // token against the recovered session. Dropping the user id and killing
      // the heartbeat here left the device unreachable for push until the next
      // cold start.
      _tokenSyncInFlight = false;
      _lastSyncedToken = null;
      _lastSyncedAt = null;
      final userId = _activeUserId;
      if (userId != null) {
        unawaited(syncToken(userId: userId));
      }
    };
    SessionRecoveryBus.instance.addListener(_sessionRecoveryListener);
  }

  final List<NotificationTapPayload> _pendingTaps = [];
  // Buffer taps that arrive before a listener subscribes. Cold-start race:
  // getInitialMessage() fires during init, before the bootstrap subscribes to
  // tapStream, so a plain broadcast controller drops the tap and the app opens
  // without navigating. Pending taps are flushed when the first listener attaches.
  late final StreamController<NotificationTapPayload> _tapController =
      StreamController<NotificationTapPayload>.broadcast(
        onListen: _flushPendingTaps,
      );

  void _flushPendingTaps() {
    if (_pendingTaps.isEmpty) return;
    final pending = List<NotificationTapPayload>.of(_pendingTaps);
    _pendingTaps.clear();
    for (final payload in pending) {
      scheduleMicrotask(() {
        if (!_tapController.isClosed) _tapController.add(payload);
      });
    }
  }

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  StreamSubscription<Map<String, dynamic>>? _webNotificationClickSub;
  Timer? _tokenHeartbeatTimer;

  bool _initialized = false;
  bool _firebaseReady = false;
  String? _lastSyncedToken;
  DateTime? _lastSyncedAt;
  bool _tokenSyncInFlight = false;
  int? _activeUserId;
  String? _lastSyncedVoipToken;

  Stream<NotificationTapPayload> get tapStream => _tapController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!appSupportsPushMessaging) return;

    _firebaseReady = await _ensureFirebaseInitialized();
    if (!_firebaseReady) return;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _emitTapIfAllowed(_parseTapPayload(initialMessage), source: 'initial');
    }

    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _emitTapIfAllowed(_parseTapPayload(message), source: 'opened_app');
    });

    if (kIsWeb) {
      _webNotificationClickSub ??= WebNotificationService.instance.clickStream
          .listen(
            (payload) => _emitTapIfAllowed(
              _parseTapPayloadFromMap(payload),
              source: 'web_notification_click',
            ),
          );
    }

    _foregroundSub = FirebaseMessaging.onMessage.listen((message) async {
      final parsed = _parseRemoteMessagePayload(message);
      if (!notificationPayloadMatchesAppFlavor(
        parsed.$3,
        AppFlavorContext.current,
      )) {
        _pushDebugLog(
          'foreground payload ignored for surface=${parsed.$3.appSurface}',
        );
        return;
      }
      // Calls: the open app rings in-app (SSE + SocialCallScreen); never stack
      // a second ringing notification on top. "Call ended" clears CallKit.
      if (IncomingCallService.isCallEnded(message.data)) {
        await handleCallPushData(
          message.data,
          flavor: AppFlavorContext.current,
        );
        return;
      }
      final isCallInvite = IncomingCallService.isCallInvite(message.data);
      if (!isCallInvite && !_shouldSuppressForegroundNotification(parsed.$3)) {
        if (kIsWeb) {
          final urgent =
              parsed.$3.requiresAction ||
              _isUrgentRealtimePayload(parsed.$3) ||
              _isOperationalUrgentPayload(parsed.$3);
          await WebNotificationService.instance.showRaw(
            title: parsed.$1,
            body: parsed.$2,
            notificationId: parsed.$3.notificationId,
            type: parsed.$3.type,
            target: parsed.$3.target,
            requiresAction: parsed.$3.requiresAction,
            urgent: urgent,
            payload: _tapPayloadToWebMap(parsed.$3),
          );
        } else {
          await local.showRaw(
            title: parsed.$1,
            body: parsed.$2,
            orderId: parsed.$3.orderId,
            rideId: parsed.$3.rideId,
            offerId: parsed.$3.offerId,
            bidId: parsed.$3.bidId,
            jobId: parsed.$3.jobId,
            applicationId: parsed.$3.applicationId,
            postId: parsed.$3.postId,
            storyId: parsed.$3.storyId,
            threadId: parsed.$3.threadId,
            senderUserId: parsed.$3.senderUserId,
            captainId: parsed.$3.captainId,
            customerUserId: parsed.$3.customerUserId,
            sessionId: parsed.$3.sessionId,
            notificationId: parsed.$3.notificationId,
            type: parsed.$3.type,
            target: parsed.$3.target,
            targetModule: parsed.$3.targetModule,
            roleScope: parsed.$3.roleScope,
            appSurface: parsed.$3.appSurface,
            action: parsed.$3.action,
            targetEntity: parsed.$3.targetEntity,
            entityId: parsed.$3.entityId,
            scopeType: parsed.$3.scopeType,
            scopeCode: parsed.$3.scopeCode,
            remoteDisplayName: parsed.$3.remoteDisplayName,
            requiresAction: parsed.$3.requiresAction,
          );
        }
      }

      if (_isOrderRefreshPayload(parsed.$3)) {
        OrderRefreshBus.instance.notifyOrderChanged(
          orderId: parsed.$3.orderId,
          source: 'push_foreground',
        );
      }

      // Open urgent realtime overlays immediately while app is foregrounded.
      if (_isUrgentRealtimePayload(parsed.$3)) {
        _emitTapIfAllowed(parsed.$3, source: 'foreground_urgent');
      }
    });

    _tokenRefreshSub = messaging.onTokenRefresh.listen((token) {
      final userId = _activeUserId;
      if (userId != null) unawaited(_registerTokenSafe(token, userId));
    });

    _ensureHeartbeatTimer();
  }

  Future<bool> syncToken({required int userId}) async {
    _activeUserId = userId;
    await initialize();
    if (!appSupportsPushMessaging) return false;
    if (!_firebaseReady) return false;
    await requestPermissionIfNeeded();
    if (kIsWeb && !WebNotificationService.instance.permissionGranted) {
      return false;
    }
    if (_tokenSyncInFlight) return false;
    _tokenSyncInFlight = true;
    try {
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb && _firebaseWebVapidKey.trim().isNotEmpty
            ? _firebaseWebVapidKey.trim()
            : null,
      );
      if (token == null || token.isEmpty) return false;
      await _registerTokenWithRetry(token, userId);
      unawaited(_syncVoipToken(userId));
      _ensureHeartbeatTimer();
      return true;
    } finally {
      _tokenSyncInFlight = false;
    }
  }

  /// iOS: registers the PushKit token so closed iPhones ring via CallKit.
  Future<void> _syncVoipToken(int userId) async {
    if (AppFlavorContext.current != AppFlavor.user) return;
    final voipToken = await IncomingCallService.voipPushToken();
    if (voipToken == null || voipToken == _lastSyncedVoipToken) return;
    try {
      await _registerToken(voipToken, userId, platformOverride: 'ios_voip');
      _lastSyncedVoipToken = voipToken;
    } catch (e) {
      _pushDebugLog('voip token registration failed: $e');
    }
  }

  Future<void> unregisterCurrentToken() async {
    _activeUserId = null;
    final voipToken = _lastSyncedVoipToken;
    _lastSyncedVoipToken = null;
    if (voipToken != null) {
      try {
        await api.unregisterPushToken(token: voipToken);
      } catch (_) {
        // Best effort only.
      }
    }
    if (!appSupportsPushMessaging) return;
    if (!_firebaseReady) return;
    final accessToken = await store.readToken();
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb && _firebaseWebVapidKey.trim().isNotEmpty
          ? _firebaseWebVapidKey.trim()
          : null,
    );
    if (token == null || token.isEmpty) return;
    try {
      await api.unregisterPushToken(token: token);
    } catch (_) {
      // Best effort only.
    } finally {
      _lastSyncedToken = null;
      _lastSyncedAt = null;
    }
  }

  Future<void> requestPermissionIfNeeded({bool userInitiated = false}) async {
    await initialize();
    if (!appSupportsPushMessaging) return;
    if (!_firebaseReady) return;
    if (kIsWeb) {
      await WebNotificationService.instance.requestPermissionIfNeeded(
        userInitiated: userInitiated,
      );
      if (!WebNotificationService.instance.permissionGranted) return;
    }
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _registerToken(
    String token,
    int userId, {
    String? platformOverride,
  }) async {
    final clean = token.trim();
    if (clean.isEmpty) return;
    final now = DateTime.now();
    final recentlySynced =
        _lastSyncedAt != null &&
        now.difference(_lastSyncedAt!) < _tokenForceResyncInterval;
    if (platformOverride == null &&
        _lastSyncedToken == clean &&
        recentlySynced) {
      return;
    }

    // Avoid unauthenticated push-token registration requests.
    final accessToken = await store.readToken();
    if (accessToken == null || accessToken.isEmpty) {
      _pushDebugLog('token sync skipped: no authenticated access token');
      return;
    }
    final session = resolvePushTokenSessionContext(
      accessToken: accessToken,
      expectedUserId: userId,
      flavor: store.flavor,
    );
    if (session == null) {
      _pushDebugLog('token sync skipped: JWT user/session/surface mismatch');
      return;
    }

    final metadata = await Future.wait<Object?>([
      PackageInfo.fromPlatform(),
      DeviceInfoPlugin().deviceInfo,
    ]);
    final packageInfo = metadata[0] as PackageInfo;
    final deviceInfo = metadata[1] as BaseDeviceInfo;
    final deviceData = deviceInfo.data;
    final deviceModel =
        '${deviceData['model'] ?? deviceData['product'] ?? deviceData['name'] ?? _platformName()}'
            .trim();

    await api.registerPushToken(
      token: clean,
      userId: session.userId,
      sessionId: session.sessionId,
      appFlavor: session.appSurface,
      platform: platformOverride ?? _platformName(),
      appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
      deviceModel: deviceModel,
      localeCode: await _currentLocaleCode(),
    );
    if (platformOverride != null) return;
    _lastSyncedToken = clean;
    _lastSyncedAt = now;
    _pushDebugLog(
      'token synced user=${session.userId} session=${session.sessionId} surface=${session.appSurface}',
    );
  }

  Future<void> _registerTokenWithRetry(String token, int userId) async {
    const delays = <Duration>[
      Duration(milliseconds: 0),
      Duration(milliseconds: 700),
      Duration(milliseconds: 1700),
    ];
    Object? lastError;
    for (final delay in delays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      try {
        await _registerToken(token, userId);
        return;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) {
      throw lastError;
    }
  }

  void _ensureHeartbeatTimer() {
    if (!appSupportsPushMessaging || !_firebaseReady) return;
    if (_tokenHeartbeatTimer != null) return;
    _tokenHeartbeatTimer = Timer.periodic(_tokenHeartbeatInterval, (_) {
      final userId = _activeUserId;
      if (userId != null) unawaited(syncToken(userId: userId));
    });
  }

  Future<void> _registerTokenSafe(String token, int userId) async {
    try {
      await _registerTokenWithRetry(token, userId);
    } catch (e) {
      _pushDebugLog('token registration failed: $e');
    }
  }

  NotificationTapPayload _parseTapPayload(RemoteMessage message) {
    final payload = _parseRemoteMessagePayload(message).$3;
    return payload;
  }

  void _emitTapIfAllowed(
    NotificationTapPayload payload, {
    required String source,
  }) {
    if (!notificationPayloadMatchesAppFlavor(
      payload,
      AppFlavorContext.current,
    )) {
      _pushDebugLog(
        'tap ignored source=$source intended=${payload.appSurface} current=${canonicalAppSurface(AppFlavorContext.current)}',
      );
      return;
    }
    if (_tapController.hasListener) {
      _tapController.add(payload);
    } else {
      _pendingTaps.add(payload);
    }
  }

  static Future<bool> _ensureFirebaseInitialized() async {
    if (!appSupportsPushMessaging) return false;
    try {
      if (Firebase.apps.isNotEmpty) return true;
      final runtimeOptions = FirebaseRuntimeOptions.currentPlatform();
      if (runtimeOptions != null) {
        await Firebase.initializeApp(options: runtimeOptions);
      } else {
        await Firebase.initializeApp();
      }
      return true;
    } catch (e) {
      debugPrint('Push Firebase init failed: $e');
      return false;
    }
  }

  static String _platformName() {
    return appPlatformName;
  }

  Future<String> _currentLocaleCode() async {
    final stored = (await store.readString(_appLocaleStorageKey))?.trim();
    if (stored == 'en' || stored == 'ar') {
      return stored!;
    }
    final device = PlatformDispatcher.instance.locale.languageCode
        .toLowerCase();
    return device.startsWith('en') ? 'en' : 'ar';
  }

  void dispose() {
    SessionRecoveryBus.instance.removeListener(_sessionRecoveryListener);
    _tokenHeartbeatTimer?.cancel();
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _webNotificationClickSub?.cancel();
    _tapController.close();
  }
}

bool _shouldSuppressForegroundNotification(NotificationTapPayload payload) {
  return ActiveChatContextRegistry.matchesPayload(
    target: payload.target,
    type: payload.type,
    threadId: payload.threadId,
    scopeType: payload.scopeType,
    scopeCode: payload.scopeCode,
  );
}

bool _isOperationalUrgentPayload(NotificationTapPayload payload) {
  final value =
      '${payload.type ?? ''} ${payload.target ?? ''} ${payload.targetModule ?? ''} ${payload.roleScope ?? ''} ${payload.action ?? ''}'
          .toLowerCase();
  return value.contains('call') ||
      value.contains('urgent') ||
      value.contains('new_order') ||
      value.contains('order_assigned') ||
      value.contains('delivery_order_ready') ||
      value.contains('delivery_order_cancelled') ||
      value.contains('courier') ||
      value.contains('taxi_ride') ||
      value.contains('taxi_trips_new') ||
      value.contains('request_cancel');
}

bool _isOrderRefreshPayload(NotificationTapPayload payload) {
  final orderId = payload.orderId ?? payload.entityId;
  if (orderId != null && orderId > 0) return true;
  final target = (payload.target ?? '').trim().toLowerCase();
  final module = (payload.targetModule ?? '').trim().toLowerCase();
  final entity = (payload.targetEntity ?? '').trim().toLowerCase();
  final type = (payload.type ?? '').trim().toLowerCase();
  return target.contains('order') ||
      module == 'orders' ||
      module == 'merchant' ||
      module == 'courier' ||
      module == 'delivery' ||
      entity == 'order' ||
      type.contains('order') ||
      type.contains('delivery_assignment') ||
      type.contains('courier_assignment');
}

bool _isUrgentRealtimePayload(NotificationTapPayload payload) {
  if (!appInAppCallsEnabled) return false;
  final target = (payload.target ?? '').trim().toLowerCase();
  final callType = (payload.type ?? '').trim().toLowerCase();
  // Only a live invite opens the call screen; missed/ended calls never do.
  if (target == 'social_call' &&
      callType.startsWith('social.call.') &&
      callType != 'social.call.incoming') {
    return false;
  }
  if (target == 'social_call' ||
      target == 'courier_orders_current' ||
      target == 'delivery_order_offer' ||
      target == 'courier_order_offer' ||
      target == 'taxi_new_request' ||
      target == 'taxi_ride_requested' ||
      target == 'taxi_offer_received' ||
      target == 'taxi_counter_offer_received' ||
      target == 'taxi_offer_accepted' ||
      target == 'taxi_offer_rejected' ||
      target == 'taxi_ride_assigned' ||
      target == 'taxi_ride_unavailable' ||
      target == 'taxi_captain_arrived' ||
      target == 'taxi_ride_started' ||
      target == 'taxi_chat_message') {
    return true;
  }

  final type = (payload.type ?? '').trim().toLowerCase();
  return type == 'social.call.incoming' ||
      type == 'delivery_order_available' ||
      type == 'delivery_order_offer' ||
      type == 'courier_order_offer' ||
      type == 'delivery_order_assigned' ||
      type == 'delivery_order_removed' ||
      type == 'delivery_order_reassigned' ||
      type == 'delivery_assigned_by_owner' ||
      type == 'taxi.request.new' ||
      type == 'taxi.ride.requested' ||
      type == 'taxi.offer.received' ||
      type == 'taxi.counter_offer.received' ||
      type == 'taxi.offer.accepted' ||
      type == 'taxi.offer.rejected' ||
      type == 'taxi.ride.assigned' ||
      type == 'taxi.ride.unavailable' ||
      type == 'taxi.captain.arrived' ||
      type == 'taxi.ride.started' ||
      type == 'taxi.chat.message' ||
      type.startsWith('courier.') ||
      type.startsWith('taxi.request.');
}

(String, String, NotificationTapPayload) _parseRemoteMessagePayload(
  RemoteMessage message,
) {
  final title =
      message.notification?.title ??
      _asString(message.data['title']) ??
      'مَسْلَكِي';
  final body =
      message.notification?.body ??
      _asString(message.data['body']) ??
      'يوجد تحديث جديد';

  final payload = NotificationTapPayload(
    requestId: int.tryParse(
      '${message.data['requestId'] ?? message.data['request_id'] ?? message.data['ticketId'] ?? message.data['ticket_id'] ?? ''}',
    ),
    orderId: int.tryParse(
      '${message.data['orderId'] ?? message.data['order_id'] ?? ''}',
    ),
    rideId: int.tryParse(
      '${message.data['rideId'] ?? message.data['ride_id'] ?? ''}',
    ),
    offerId: int.tryParse(
      '${message.data['offerId'] ?? message.data['offer_id'] ?? ''}',
    ),
    bidId: int.tryParse(
      '${message.data['bidId'] ?? message.data['bid_id'] ?? ''}',
    ),
    jobId: int.tryParse(
      '${message.data['jobId'] ?? message.data['job_id'] ?? ''}',
    ),
    applicationId: int.tryParse(
      '${message.data['applicationId'] ?? message.data['application_id'] ?? ''}',
    ),
    postId: int.tryParse(
      '${message.data['postId'] ?? message.data['post_id'] ?? ''}',
    ),
    reelId: int.tryParse(
      '${message.data['reelId'] ?? message.data['reel_id'] ?? ''}',
    ),
    storyId: int.tryParse(
      '${message.data['storyId'] ?? message.data['story_id'] ?? ''}',
    ),
    threadId: int.tryParse(
      '${message.data['threadId'] ?? message.data['thread_id'] ?? ''}',
    ),
    senderUserId: int.tryParse(
      '${message.data['senderUserId'] ?? message.data['sender_user_id'] ?? message.data['actorUserId'] ?? message.data['actor_user_id'] ?? ''}',
    ),
    captainId: int.tryParse(
      '${message.data['captainId'] ?? message.data['captain_id'] ?? ''}',
    ),
    customerUserId: int.tryParse(
      '${message.data['customerUserId'] ?? message.data['customer_user_id'] ?? ''}',
    ),
    sessionId: int.tryParse(
      '${message.data['sessionId'] ?? message.data['session_id'] ?? ''}',
    ),
    notificationId: int.tryParse('${message.data['notificationId'] ?? ''}'),
    type:
        _asString(message.data['type']) ??
        _asString(message.data['notificationType']) ??
        _asString(message.messageType),
    target: _asString(message.data['target']),
    targetModule:
        _asString(message.data['targetModule']) ??
        _asString(message.data['target_module']),
    roleScope:
        _asString(message.data['roleScope']) ??
        _asString(message.data['role_scope']),
    appSurface:
        _asString(message.data['appSurface']) ??
        _asString(message.data['app_surface']),
    action:
        _asString(message.data['action']) ??
        _asString(message.data['target_action']),
    targetEntity:
        _asString(message.data['targetEntity']) ??
        _asString(message.data['target_entity']),
    entityId: int.tryParse(
      '${message.data['entityId'] ?? message.data['entity_id'] ?? message.data['ticketId'] ?? message.data['ticket_id'] ?? ''}',
    ),
    scopeType: _asString(message.data['scopeType']),
    scopeCode: _asString(message.data['scopeCode']),
    remoteDisplayName: _asString(message.data['remoteDisplayName']),
    requiresAction: _parseBool(message.data['requiresAction']),
  );

  return (title, body, payload);
}

NotificationTapPayload _parseTapPayloadFromMap(Map<String, dynamic> data) {
  return NotificationTapPayload(
    requestId: _intFrom(
      data,
      'requestId',
      'request_id',
      'ticketId',
      'ticket_id',
    ),
    orderId: _intFrom(data, 'orderId', 'order_id'),
    rideId: _intFrom(data, 'rideId', 'ride_id'),
    offerId: _intFrom(data, 'offerId', 'offer_id'),
    bidId: _intFrom(data, 'bidId', 'bid_id'),
    jobId: _intFrom(data, 'jobId', 'job_id'),
    applicationId: _intFrom(data, 'applicationId', 'application_id'),
    postId: _intFrom(data, 'postId', 'post_id'),
    reelId: _intFrom(data, 'reelId', 'reel_id'),
    storyId: _intFrom(data, 'storyId', 'story_id'),
    threadId: _intFrom(data, 'threadId', 'thread_id'),
    senderUserId: _intFrom(
      data,
      'senderUserId',
      'sender_user_id',
      'actorUserId',
      'actor_user_id',
    ),
    captainId: _intFrom(data, 'captainId', 'captain_id'),
    customerUserId: _intFrom(data, 'customerUserId', 'customer_user_id'),
    sessionId: _intFrom(data, 'sessionId', 'session_id'),
    notificationId: _intFrom(data, 'notificationId', 'notification_id'),
    type:
        _asString(data['type']) ??
        _asString(data['notificationType']) ??
        _asString(data['notification_type']),
    target: _asString(data['target']) ?? _asString(data['deepLinkTarget']),
    targetModule:
        _asString(data['targetModule']) ?? _asString(data['target_module']),
    roleScope: _asString(data['roleScope']) ?? _asString(data['role_scope']),
    appSurface: _asString(data['appSurface']) ?? _asString(data['app_surface']),
    action: _asString(data['action']) ?? _asString(data['target_action']),
    targetEntity:
        _asString(data['targetEntity']) ?? _asString(data['target_entity']),
    entityId: _intFrom(
      data,
      'entityId',
      'entity_id',
      'ticketId',
      'ticket_id',
      'listingId',
      'listing_id',
    ),
    scopeType: _asString(data['scopeType']) ?? _asString(data['scope_type']),
    scopeCode: _asString(data['scopeCode']) ?? _asString(data['scope_code']),
    remoteDisplayName:
        _asString(data['remoteDisplayName']) ??
        _asString(data['remote_display_name']),
    requiresAction: _parseBool(data['requiresAction']),
  );
}

Map<String, Object?> _tapPayloadToWebMap(NotificationTapPayload payload) {
  return <String, Object?>{
    'requestId': payload.requestId,
    'orderId': payload.orderId,
    'rideId': payload.rideId,
    'offerId': payload.offerId,
    'bidId': payload.bidId,
    'jobId': payload.jobId,
    'applicationId': payload.applicationId,
    'postId': payload.postId,
    'reelId': payload.reelId,
    'storyId': payload.storyId,
    'threadId': payload.threadId,
    'sessionId': payload.sessionId,
    'senderUserId': payload.senderUserId,
    'captainId': payload.captainId,
    'customerUserId': payload.customerUserId,
    'notificationId': payload.notificationId,
    'type': payload.type,
    'target': payload.target,
    'targetModule': payload.targetModule,
    'roleScope': payload.roleScope,
    'appSurface': payload.appSurface,
    'action': payload.action,
    'targetEntity': payload.targetEntity,
    'entityId': payload.entityId,
    'scopeType': payload.scopeType,
    'scopeCode': payload.scopeCode,
    'remoteDisplayName': payload.remoteDisplayName,
    'requiresAction': payload.requiresAction,
  };
}

int? _intFrom(
  Map<String, dynamic> data,
  String first, [
  String? second,
  String? third,
  String? fourth,
  String? fifth,
  String? sixth,
]) {
  for (final key in <String?>[first, second, third, fourth, fifth, sixth]) {
    if (key == null) continue;
    final parsed = int.tryParse('${data[key] ?? ''}');
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

String? _asString(dynamic value) {
  if (value == null) return null;
  final out = value.toString().trim();
  return out.isEmpty ? null : out;
}

bool _parseBool(dynamic value) {
  if (value == true) return true;
  final normalized = '$value'.trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}
