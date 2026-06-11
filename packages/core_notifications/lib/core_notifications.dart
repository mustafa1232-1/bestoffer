import 'dart:async';
import 'dart:convert';

import 'package:core_networking/core_networking.dart';
import 'package:core_storage/core_storage.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final runtimeLocalNotificationsProvider =
    Provider<RuntimeLocalNotificationsService>((ref) {
      final service = RuntimeLocalNotificationsService();
      ref.onDispose(service.dispose);
      return service;
    });

final runtimePushNotificationsProvider =
    Provider<RuntimePushNotificationsService>((ref) {
      final service = RuntimePushNotificationsService(
        dio: ref.watch(runtimeDioProvider),
        store: ref.watch(appScopedSecureStoreProvider),
        local: ref.watch(runtimeLocalNotificationsProvider),
      );
      ref.onDispose(service.dispose);
      return service;
    });

class RuntimeNotificationTapPayload {
  final int? notificationId;
  final int? orderId;
  final int? rideId;
  final int? merchantId;
  final String? type;
  final String? title;
  final String? body;
  final String? target;

  const RuntimeNotificationTapPayload({
    this.notificationId,
    this.orderId,
    this.rideId,
    this.merchantId,
    this.type,
    this.title,
    this.body,
    this.target,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (notificationId != null) 'notificationId': notificationId,
      if (orderId != null) 'orderId': orderId,
      if (rideId != null) 'rideId': rideId,
      if (merchantId != null) 'merchantId': merchantId,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (target != null) 'target': target,
    };
  }

  factory RuntimeNotificationTapPayload.fromJson(Map<String, dynamic> json) {
    return RuntimeNotificationTapPayload(
      notificationId: _parseInt(
        json['notificationId'] ?? json['notification_id'] ?? json['id'],
      ),
      orderId: _parseInt(json['orderId'] ?? json['order_id']),
      rideId: _parseInt(json['rideId'] ?? json['ride_id']),
      merchantId: _parseInt(
        json['merchantId'] ??
            json['merchant_id'] ??
            json['storeId'] ??
            json['store_id'],
      ),
      type: _parseString(json['type']),
      title: _parseString(json['title'] ?? json['subject']),
      body: _parseString(json['body'] ?? json['message']),
      target: _parseString(json['target']),
    );
  }

  static RuntimeNotificationTapPayload fromRemoteMessage(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    return RuntimeNotificationTapPayload.fromJson({
      ...data,
      'title': message.notification?.title ?? data['title'] ?? data['subject'],
      'body': message.notification?.body ?? data['body'] ?? data['message'],
    });
  }
}

class RuntimeLocalNotificationsService {
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'maslaki_runtime_updates',
    'Maslaki Runtime Updates',
    description: 'Maslaki split-runtime updates',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<RuntimeNotificationTapPayload> _tapController =
      StreamController<RuntimeNotificationTapPayload>.broadcast();

  bool _initialized = false;
  int _fallbackId = 200000;

  Stream<RuntimeNotificationTapPayload> get tapStream => _tapController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    if (!_supportsLocalNotifications) {
      _initialized = true;
      return;
    }

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: LinuxInitializationSettings(defaultActionName: 'Open notification'),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_channel);
    _initialized = true;

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchPayload == null || launchPayload.isEmpty) return;
    final parsed = _parsePayload(launchPayload);
    if (parsed != null) {
      _tapController.add(parsed);
    }
  }

  Future<void> requestPermissionIfNeeded() async {
    await initialize();
    if (!_supportsLocalNotifications) return;
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);
    final macosPlugin = _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    await macosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> showPayload(RuntimeNotificationTapPayload payload) async {
    await initialize();
    if (!_supportsLocalNotifications) return;
    final title = payload.title?.trim().isNotEmpty == true
        ? payload.title!.trim()
        : 'مسلكي';
    final body = payload.body?.trim().isNotEmpty == true
        ? payload.body!.trim()
        : 'لديك تحديث جديد';
    final notificationId = payload.notificationId ?? ++_fallbackId;
    await _plugin.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(payload.toJson()),
    );
  }

  void dispose() {
    _tapController.close();
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = _parsePayload(response.payload);
    if (payload != null) {
      _tapController.add(payload);
    }
  }

  RuntimeNotificationTapPayload? _parsePayload(String? rawPayload) {
    if (rawPayload == null || rawPayload.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map) {
        return RuntimeNotificationTapPayload.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class RuntimePushNotificationsService {
  final Dio dio;
  final AppScopedSecureStore store;
  final RuntimeLocalNotificationsService local;

  RuntimePushNotificationsService({
    required this.dio,
    required this.store,
    required this.local,
  });

  final StreamController<RuntimeNotificationTapPayload> _tapController =
      StreamController<RuntimeNotificationTapPayload>.broadcast();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  bool _initialized = false;
  bool _firebaseReady = false;
  String? _lastSyncedToken;
  DateTime? _lastSyncedAt;
  bool _tokenSyncInFlight = false;

  Stream<RuntimeNotificationTapPayload> get tapStream => _tapController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await local.initialize();
    if (!_supportsPushMessaging) return;

    _firebaseReady = await _ensureFirebaseInitialized();
    if (!_firebaseReady) return;

    FirebaseMessaging.onBackgroundMessage(
      runtimeFirebaseMessagingBackgroundHandler,
    );

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _tapController.add(
        RuntimeNotificationTapPayload.fromRemoteMessage(initialMessage),
      );
    }

    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _tapController.add(RuntimeNotificationTapPayload.fromRemoteMessage(message));
    });

    _foregroundSub = FirebaseMessaging.onMessage.listen((message) async {
      final payload = RuntimeNotificationTapPayload.fromRemoteMessage(message);
      await local.showPayload(payload);
    });

    _tokenRefreshSub = messaging.onTokenRefresh.listen((token) {
      unawaited(_registerTokenSafe(token));
    });
  }

  Future<void> requestPermissionIfNeeded() async {
    await initialize();
    await local.requestPermissionIfNeeded();
    if (!_supportsPushMessaging || !_firebaseReady) return;
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> syncToken() async {
    await initialize();
    if (!_supportsPushMessaging || !_firebaseReady || _tokenSyncInFlight) return;
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
    if (!_supportsPushMessaging || !_firebaseReady) return;
    final accessToken = await store.readToken();
    if (accessToken == null || accessToken.isEmpty) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    try {
      await dio.delete('/api/notifications/push-token', data: {'token': token});
    } catch (_) {
      // Best effort only.
    } finally {
      _lastSyncedToken = null;
      _lastSyncedAt = null;
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _tapController.close();
  }

  Future<void> _registerToken(String token) async {
    final clean = token.trim();
    if (clean.isEmpty) return;
    final now = DateTime.now();
    final recentlySynced =
        _lastSyncedAt != null &&
        now.difference(_lastSyncedAt!) < const Duration(hours: 6);
    if (_lastSyncedToken == clean && recentlySynced) return;

    final accessToken = await store.readToken();
    if (accessToken == null || accessToken.isEmpty) return;

    await dio.post(
      '/api/notifications/push-token',
      data: {
        'token': clean,
        'platform': _platformName,
        'deviceModel': _platformName,
        'locale': _currentLocaleCode(),
      },
    );
    _lastSyncedToken = clean;
    _lastSyncedAt = now;
  }

  Future<void> _registerTokenSafe(String token) async {
    try {
      await _registerToken(token);
    } catch (_) {
      // Best effort only.
    }
  }
}

@pragma('vm:entry-point')
Future<void> runtimeFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  if (!_supportsPushMessaging) return;
  try {
    if (Firebase.apps.isEmpty) {
      final runtimeOptions = _FirebaseRuntimeOptions.currentPlatform();
      if (runtimeOptions != null) {
        await Firebase.initializeApp(options: runtimeOptions);
      } else {
        await Firebase.initializeApp();
      }
    }
    final local = RuntimeLocalNotificationsService();
    await local.initialize();
    await local.showPayload(RuntimeNotificationTapPayload.fromRemoteMessage(message));
  } catch (_) {
    // Best effort only.
  }
}

class _FirebaseRuntimeOptions {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _genericAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _measurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
  );
  static const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
  static const _iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');
  static const _androidClientId = String.fromEnvironment(
    'FIREBASE_ANDROID_CLIENT_ID',
  );

  static FirebaseOptions? currentPlatform() {
    if (_apiKey.isEmpty || _projectId.isEmpty || _messagingSenderId.isEmpty) {
      return null;
    }

    if (kIsWeb) {
      final appId = _firstNonEmpty([_webAppId, _genericAppId]);
      if (appId == null) return null;
      return FirebaseOptions(
        apiKey: _apiKey,
        appId: appId,
        messagingSenderId: _messagingSenderId,
        projectId: _projectId,
        authDomain: _valueOrNull(_authDomain),
        storageBucket: _valueOrNull(_storageBucket),
        measurementId: _valueOrNull(_measurementId),
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final appId = _firstNonEmpty([_androidAppId, _genericAppId]);
        if (appId == null) return null;
        return FirebaseOptions(
          apiKey: _apiKey,
          appId: appId,
          messagingSenderId: _messagingSenderId,
          projectId: _projectId,
          storageBucket: _valueOrNull(_storageBucket),
          androidClientId: _valueOrNull(_androidClientId),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        final appId = _firstNonEmpty([_iosAppId, _genericAppId]);
        if (appId == null) return null;
        return FirebaseOptions(
          apiKey: _apiKey,
          appId: appId,
          messagingSenderId: _messagingSenderId,
          projectId: _projectId,
          storageBucket: _valueOrNull(_storageBucket),
          iosBundleId: _valueOrNull(_iosBundleId),
          iosClientId: _valueOrNull(_iosClientId),
        );
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return null;
    }
  }

  static String? _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static String? _valueOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

String _currentLocaleCode() {
  final device = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
  return device.startsWith('en') ? 'en' : 'ar';
}

int? _parseInt(dynamic value) => int.tryParse('${value ?? ''}');

String? _parseString(dynamic value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? null : text;
}

bool get _supportsPushMessaging {
  if (kIsWeb) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return false;
  }
}

bool get _supportsLocalNotifications {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return true;
    case TargetPlatform.windows:
    case TargetPlatform.fuchsia:
      return false;
  }
}

String get _platformName {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}

Future<bool> _ensureFirebaseInitialized() async {
  if (!_supportsPushMessaging) return false;
  try {
    if (Firebase.apps.isNotEmpty) return true;
    final runtimeOptions = _FirebaseRuntimeOptions.currentPlatform();
    if (runtimeOptions != null) {
      await Firebase.initializeApp(options: runtimeOptions);
    } else {
      await Firebase.initializeApp();
    }
    return true;
  } catch (_) {
    return false;
  }
}
