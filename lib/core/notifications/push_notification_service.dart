import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/state/auth_controller.dart';
import '../../features/notifications/data/notifications_api.dart';
import 'active_chat_context_registry.dart';
import '../platform/app_platform_capabilities.dart';
import '../platform/app_flavor.dart';
import '../storage/secure_storage.dart';
import 'firebase_runtime_options.dart';
import 'local_notification_service.dart';

const _tokenHeartbeatInterval = Duration(minutes: 15);
const _tokenForceResyncInterval = Duration(hours: 6);
const _appLocaleStorageKey = 'app_locale';

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
  return intended == null || intended == canonicalAppSurface(flavor);
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
    if (userId == null ||
        userId <= 0 ||
        userId != expectedUserId ||
        sessionId == null ||
        sessionId <= 0 ||
        (claimedSurface != null && claimedSurface != expectedSurface)) {
      return null;
    }
    return PushTokenSessionContext(
      userId: userId,
      sessionId: sessionId,
      appSurface: expectedSurface,
    );
  } catch (_) {
    return null;
  }
}

void _pushDebugLog(String message) {
  if (kDebugMode) debugPrint('[push] $message');
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
      final local = LocalNotificationService();
      await local.initialize();
      final parsed = _parseRemoteMessagePayload(message);

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

  PushNotificationService({
    required this.api,
    required this.local,
    required this.store,
  });

  final StreamController<NotificationTapPayload> _tapController =
      StreamController<NotificationTapPayload>.broadcast();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  Timer? _tokenHeartbeatTimer;

  bool _initialized = false;
  bool _firebaseReady = false;
  String? _lastSyncedToken;
  DateTime? _lastSyncedAt;
  bool _tokenSyncInFlight = false;
  int? _activeUserId;

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
      if (!_shouldSuppressForegroundNotification(parsed.$3)) {
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

      // Open urgent realtime overlays immediately while app is foregrounded.
      if (_isUrgentRealtimePayload(parsed.$3)) {
        _emitTapIfAllowed(parsed.$3, source: 'foreground_urgent');
      }
    });

    _tokenRefreshSub = messaging.onTokenRefresh.listen((token) {
      final userId = _activeUserId;
      if (userId != null) unawaited(_registerTokenSafe(token, userId));
    });

    _tokenHeartbeatTimer = Timer.periodic(_tokenHeartbeatInterval, (_) {
      final userId = _activeUserId;
      if (userId != null) unawaited(syncToken(userId: userId));
    });
  }

  Future<void> syncToken({required int userId}) async {
    _activeUserId = userId;
    await initialize();
    if (!appSupportsPushMessaging) return;
    if (!_firebaseReady) return;
    if (_tokenSyncInFlight) return;
    _tokenSyncInFlight = true;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _registerTokenWithRetry(token, userId);
    } finally {
      _tokenSyncInFlight = false;
    }
  }

  Future<void> unregisterCurrentToken() async {
    _activeUserId = null;
    if (!appSupportsPushMessaging) return;
    if (!_firebaseReady) return;
    final accessToken = await store.readToken();
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }
    final token = await FirebaseMessaging.instance.getToken();
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

  Future<void> requestPermissionIfNeeded() async {
    await initialize();
    if (!appSupportsPushMessaging) return;
    if (!_firebaseReady) return;
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _registerToken(String token, int userId) async {
    final clean = token.trim();
    if (clean.isEmpty) return;
    final now = DateTime.now();
    final recentlySynced =
        _lastSyncedAt != null &&
        now.difference(_lastSyncedAt!) < _tokenForceResyncInterval;
    if (_lastSyncedToken == clean && recentlySynced) return;

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
      platform: _platformName(),
      appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
      deviceModel: deviceModel,
      localeCode: await _currentLocaleCode(),
    );
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
    _tapController.add(payload);
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
    _tokenHeartbeatTimer?.cancel();
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
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

bool _isUrgentRealtimePayload(NotificationTapPayload payload) {
  if (!appInAppCallsEnabled) return false;
  final target = (payload.target ?? '').trim().toLowerCase();
  if (target == 'social_call' ||
      target == 'courier_orders_new' ||
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
      target == 'taxi_ride_completed' ||
      target == 'taxi_ride_canceled' ||
      target == 'taxi_chat_message') {
    return true;
  }

  final type = (payload.type ?? '').trim().toLowerCase();
  return type.startsWith('social.call.') ||
      type == 'delivery_order_available' ||
      type == 'delivery_order_offer' ||
      type == 'courier_order_offer' ||
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
      type == 'taxi.ride.completed' ||
      type == 'taxi.ride.canceled' ||
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
      '${message.data['entityId'] ?? message.data['entity_id'] ?? ''}',
    ),
    scopeType: _asString(message.data['scopeType']),
    scopeCode: _asString(message.data['scopeCode']),
    remoteDisplayName: _asString(message.data['remoteDisplayName']),
    requiresAction: _parseBool(message.data['requiresAction']),
  );

  return (title, body, payload);
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
