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
  final String? type;

  const NotificationTapPayload({this.orderId, this.type});
}

class LocalNotificationService {
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'bestoffer_live_updates',
    'BestOffer Live Updates',
    description: 'Live order and notification updates',
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
    final payload = jsonEncode({'orderId': orderId, 'type': notification.type});

    final id = notification.id > 0 ? notification.id : ++_fallbackId;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        ticker: 'bestoffer_update',
      ),
    );

    await _plugin.show(
      id,
      notification.title,
      notification.body ?? 'يوجد تحديث جديد',
      details,
      payload: payload,
    );
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
      final orderId = int.tryParse('${map['orderId'] ?? ''}');
      final type = map['type']?.toString();
      return NotificationTapPayload(orderId: orderId, type: type);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _tapController.close();
  }
}
