import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/auth_controller.dart';
import '../../features/notifications/data/notifications_api.dart';
import 'active_chat_context_registry.dart';
import '../platform/app_platform_capabilities.dart';
import '../storage/secure_storage.dart';
import 'firebase_runtime_options.dart';
import 'local_notification_service.dart';

const _tokenHeartbeatInterval = Duration(minutes: 15);
const _tokenForceResyncInterval = Duration(hours: 6);
const _appLocaleStorageKey = 'app_locale';

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
        jobId: parsed.$3.jobId,
        applicationId: parsed.$3.applicationId,
        postId: parsed.$3.postId,
        storyId: parsed.$3.storyId,
        threadId: parsed.$3.threadId,
        senderUserId: parsed.$3.senderUserId,
        sessionId: parsed.$3.sessionId,
        notificationId: parsed.$3.notificationId,
        type: parsed.$3.type,
        target: parsed.$3.target,
        targetModule: parsed.$3.targetModule,
        roleScope: parsed.$3.roleScope,
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
      _tapController.add(_parseTapPayload(initialMessage));
    }

    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _tapController.add(_parseTapPayload(message));
    });

    _foregroundSub = FirebaseMessaging.onMessage.listen((message) async {
      final parsed = _parseRemoteMessagePayload(message);
      if (!_shouldSuppressForegroundNotification(parsed.$3)) {
        await local.showRaw(
          title: parsed.$1,
          body: parsed.$2,
          orderId: parsed.$3.orderId,
          rideId: parsed.$3.rideId,
          jobId: parsed.$3.jobId,
          applicationId: parsed.$3.applicationId,
          postId: parsed.$3.postId,
          storyId: parsed.$3.storyId,
          threadId: parsed.$3.threadId,
          senderUserId: parsed.$3.senderUserId,
          sessionId: parsed.$3.sessionId,
          notificationId: parsed.$3.notificationId,
          type: parsed.$3.type,
          target: parsed.$3.target,
          targetModule: parsed.$3.targetModule,
          roleScope: parsed.$3.roleScope,
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
        _tapController.add(parsed.$3);
      }
    });

    _tokenRefreshSub = messaging.onTokenRefresh.listen((token) {
      unawaited(_registerTokenSafe(token));
    });

    _tokenHeartbeatTimer = Timer.periodic(_tokenHeartbeatInterval, (_) {
      unawaited(syncToken());
    });
  }

  Future<void> syncToken() async {
    await initialize();
    if (!appSupportsPushMessaging) return;
    if (!_firebaseReady) return;
    if (_tokenSyncInFlight) return;
    _tokenSyncInFlight = true;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _registerTokenWithRetry(token);
    } finally {
      _tokenSyncInFlight = false;
    }
  }

  Future<void> unregisterCurrentToken() async {
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

  Future<void> _registerToken(String token) async {
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
      return;
    }

    await api.registerPushToken(
      token: clean,
      platform: _platformName(),
      deviceModel: _deviceModel(),
      localeCode: await _currentLocaleCode(),
    );
    _lastSyncedToken = clean;
    _lastSyncedAt = now;
  }

  Future<void> _registerTokenWithRetry(String token) async {
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
        await _registerToken(token);
        return;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) {
      throw lastError;
    }
  }

  Future<void> _registerTokenSafe(String token) async {
    try {
      await _registerTokenWithRetry(token);
    } catch (e) {
      debugPrint('Push token register failed: $e');
    }
  }

  NotificationTapPayload _parseTapPayload(RemoteMessage message) {
    final payload = _parseRemoteMessagePayload(message).$3;
    return payload;
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

  static String _deviceModel() {
    return appPlatformName;
  }

  Future<String> _currentLocaleCode() async {
    final stored = (await store.readString(_appLocaleStorageKey))?.trim();
    if (stored == 'en' || stored == 'ar') {
      return stored!;
    }
    final device = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
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
      target == 'courier_order_offer') {
    return true;
  }

  final type = (payload.type ?? '').trim().toLowerCase();
  return type.startsWith('social.call.') ||
      type == 'delivery_order_available' ||
      type == 'delivery_order_offer' ||
      type == 'courier_order_offer' ||
      type.startsWith('courier.');
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
