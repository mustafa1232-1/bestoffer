import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notifications/models/app_notification_model.dart';

final localNotificationsProvider = Provider<LocalNotificationService>((ref) {
  final service = LocalNotificationService();
  ref.onDispose(service.dispose);
  return service;
});

class NotificationTapPayload {
  final int? orderId;
  final int? rideId;
  final int? postId;
  final int? threadId;
  final int? notificationId;
  final String? type;
  final String? target;

  const NotificationTapPayload({
    this.orderId,
    this.rideId,
    this.postId,
    this.threadId,
    this.notificationId,
    this.type,
    this.target,
  });
}

class LocalNotificationService {
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'shakaky_live_updates',
    'Shakaky Live Updates',
    description: 'Shakaky live order, taxi, and alert updates',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<NotificationTapPayload> _tapController =
      StreamController<NotificationTapPayload>.broadcast();

  bool _initialized = false;
  int _fallbackId = 100000;

  Stream<NotificationTapPayload> get tapStream => _tapController.stream;

  Future<void> initialize() async {
    if (_initialized) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchPayload != null && launchPayload.isNotEmpty) {
      final parsed = _parsePayload(launchPayload);
      if (parsed != null) {
        _tapController.add(parsed);
      }
    }
  }

  Future<void> showFromModel(AppNotificationModel notification) async {
    await initialize();

    final orderId =
        notification.orderId ??
        int.tryParse('${notification.payload?['orderId'] ?? ''}');
    final rideId =
        notification.rideId ??
        int.tryParse('${notification.payload?['rideId'] ?? ''}');
    final target =
        notification.target ?? notification.payload?['target']?.toString();
    final id = notification.id > 0 ? notification.id : ++_fallbackId;

    await showRaw(
      title: notification.title,
      body:
          notification.body ??
          '\u064A\u0648\u062C\u062F \u062A\u062D\u062F\u064A\u062B \u062C\u062F\u064A\u062F',
      orderId: orderId,
      rideId: rideId,
      postId: int.tryParse('${notification.payload?['postId'] ?? ''}'),
      threadId: int.tryParse('${notification.payload?['threadId'] ?? ''}'),
      type: notification.type,
      target: target,
      notificationId: id,
    );
  }

  Future<void> showRaw({
    required String title,
    required String body,
    int? orderId,
    int? rideId,
    int? postId,
    int? threadId,
    int? notificationId,
    String? type,
    String? target,
  }) async {
    await initialize();

    final id = (notificationId != null && notificationId > 0)
        ? notificationId
        : ++_fallbackId;

    final payload = jsonEncode({
      'orderId': orderId,
      'rideId': rideId,
      'postId': postId,
      'threadId': threadId,
      'notificationId': id,
      'type': type,
      'target': target,
    });

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        ticker: 'shakaky_update',
      ),
    );

    await _plugin.show(id, title, body, details, payload: payload);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final parsed = _parsePayload(payload);
    if (parsed != null) {
      _tapController.add(parsed);
    }
  }

  NotificationTapPayload? _parsePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      return NotificationTapPayload(
        orderId: int.tryParse('${map['orderId'] ?? ''}'),
        rideId: int.tryParse('${map['rideId'] ?? ''}'),
        postId: int.tryParse('${map['postId'] ?? ''}'),
        threadId: int.tryParse('${map['threadId'] ?? ''}'),
        notificationId: int.tryParse('${map['notificationId'] ?? ''}'),
        type: map['type']?.toString(),
        target: map['target']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _tapController.close();
  }
}
