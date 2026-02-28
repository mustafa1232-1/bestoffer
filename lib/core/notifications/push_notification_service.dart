import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/auth_controller.dart';
import '../../features/notifications/data/notifications_api.dart';
import '../storage/secure_storage.dart';
import 'firebase_runtime_options.dart';
import 'local_notification_service.dart';

const _tokenHeartbeatInterval = Duration(minutes: 15);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
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
      final orderId = int.tryParse(
        '${message.data['orderId'] ?? message.data['order_id'] ?? ''}',
      );
      final type =
          message.data['type']?.toString() ??
          message.data['notificationType']?.toString();
      final title = message.data['title']?.toString().trim();
      final body = message.data['body']?.toString().trim();
      await local.showRaw(
        title: (title == null || title.isEmpty) ? 'BestOffer' : title,
        body: (body == null || body.isEmpty) ? 'You have a new update' : body,
        orderId: orderId,
        type: type,
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
  bool _tokenSyncInFlight = false;

  Stream<NotificationTapPayload> get tapStream => _tapController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _firebaseReady = await _ensureFirebaseInitialized();
    if (!_firebaseReady) return;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    await messaging.requestPermission(alert: true, badge: true, sound: true);
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
      final title =
          message.notification?.title ??
          _asString(message.data['title']) ??
          'BestOffer';
      final body =
          message.notification?.body ??
          _asString(message.data['body']) ??
          'يوجد تحديث جديد';
      final parsed = _parseTapPayload(message);
      await local.showRaw(
        title: title,
        body: body,
        orderId: parsed.orderId,
        type: parsed.type,
      );
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
    if (!_firebaseReady) return;
    if (_tokenSyncInFlight) return;
    _tokenSyncInFlight = true;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _registerToken(token);
    } finally {
      _tokenSyncInFlight = false;
    }
  }

  Future<void> unregisterCurrentToken() async {
    if (!_firebaseReady) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    try {
      await api.unregisterPushToken(token: token);
    } catch (_) {
      // Best effort only.
    } finally {
      _lastSyncedToken = null;
    }
  }

  Future<void> _registerToken(String token) async {
    final clean = token.trim();
    if (clean.isEmpty) return;
    if (_lastSyncedToken == clean) return;

    // Avoid unauthenticated push-token registration requests.
    final accessToken = await store.readToken();
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    await api.registerPushToken(
      token: clean,
      platform: _platformName(),
      deviceModel: _deviceModel(),
    );
    _lastSyncedToken = clean;
  }

  Future<void> _registerTokenSafe(String token) async {
    try {
      await _registerToken(token);
    } catch (e) {
      debugPrint('Push token register failed: $e');
    }
  }

  NotificationTapPayload _parseTapPayload(RemoteMessage message) {
    final orderId = int.tryParse(
      '${message.data['orderId'] ?? message.data['order_id'] ?? ''}',
    );
    final type =
        _asString(message.data['type']) ??
        _asString(message.data['notificationType']) ??
        _asString(message.messageType);
    return NotificationTapPayload(orderId: orderId, type: type);
  }

  static Future<bool> _ensureFirebaseInitialized() async {
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
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String _deviceModel() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String? _asString(dynamic value) {
    if (value == null) return null;
    final out = value.toString().trim();
    return out.isEmpty ? null : out;
  }

  void dispose() {
    _tokenHeartbeatTimer?.cancel();
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _tapController.close();
  }
}
