// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

class WebNotificationService {
  WebNotificationService._();

  static final WebNotificationService instance = WebNotificationService._();

  final Set<String> _recentKeys = <String>{};
  final List<String> _recentOrder = <String>[];
  final StreamController<Map<String, dynamic>> _clickController =
      StreamController<Map<String, dynamic>>.broadcast();
  bool _messageListenerAttached = false;
  bool _initialUrlPayloadChecked = false;

  bool get supported => html.Notification.supported;
  String get permission =>
      supported ? (html.Notification.permission ?? 'default') : 'unsupported';
  bool get permissionGranted => permission == 'granted';
  bool get installedWebApp {
    return html.window.matchMedia('(display-mode: standalone)').matches;
  }

  bool get isAppleMobileBrowser {
    final ua = html.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  }

  bool get needsHomeScreenInstall => isAppleMobileBrowser && !installedWebApp;
  Stream<Map<String, dynamic>> get clickStream {
    _ensureServiceWorkerClickListener();
    return _clickController.stream;
  }

  Future<String> requestPermissionIfNeeded({bool userInitiated = false}) async {
    if (!supported) return permission;
    if (html.Notification.permission != 'default') return permission;
    if (needsHomeScreenInstall) return permission;
    if (isAppleMobileBrowser && !userInitiated) return permission;
    try {
      await html.Notification.requestPermission();
    } catch (_) {
      return permission;
    }
    return permission;
  }

  Future<void> showRaw({
    required String title,
    required String body,
    int? notificationId,
    String? type,
    String? target,
    bool requiresAction = false,
    bool urgent = false,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    if (!supported) return;
    if (html.Notification.permission != 'granted') return;

    final isUrgent = urgent || requiresAction || _looksUrgent(type, target);
    final key = notificationId != null && notificationId > 0
        ? 'id:$notificationId'
        : '${type ?? ''}:${target ?? ''}:$title:$body';
    if (_recentKeys.contains(key)) return;
    _remember(key);

    final notificationTitle = isUrgent
        ? _urgentTitle(title)
        : (title.trim().isEmpty ? 'Maslaki' : title.trim());
    final shownByServiceWorker = await _showWithServiceWorker(
      notificationTitle,
      <String, Object?>{
        'body': body.trim(),
        'icon': '/icons/Icon-192.png',
        'badge': '/icons/Icon-192.png',
        'tag': key,
        'dir': 'rtl',
        'lang': 'ar',
        'renotify': isUrgent,
        'requireInteraction': isUrgent,
        'silent': false,
        if (isUrgent) 'vibrate': <int>[0, 700, 250, 700, 250, 900],
        if (isUrgent)
          'actions': <Map<String, String>>[
            <String, String>{
              'action': 'open',
              'title': '\u0641\u062a\u062d \u0627\u0644\u0622\u0646',
            },
          ],
        'data': <String, Object?>{
          ...payload,
          'notificationId': notificationId,
          'type': type,
          'target': target,
          'requiresAction': isUrgent,
        },
      },
    );
    if (shownByServiceWorker) return;

    final notification = html.Notification(
      notificationTitle,
      body: body.trim(),
      icon: '/icons/Icon-192.png',
      tag: key,
    );
    notification.onClick.first.then((_) {
      notification.close();
      _emitClick(<String, dynamic>{
        ...payload,
        'notificationId': notificationId,
        'type': type,
        'target': target,
        'requiresAction': isUrgent,
      });
    }).ignore();
    if (!isUrgent) {
      Timer(const Duration(seconds: 8), notification.close);
    }
  }

  void _ensureServiceWorkerClickListener() {
    if (_messageListenerAttached) return;
    _messageListenerAttached = true;
    _drainInitialUrlPayload();
    html.window.navigator.serviceWorker?.onMessage.listen((event) {
      final raw = event.data;
      if (raw is! Map) return;
      final message = Map<String, dynamic>.from(raw);
      if (message['type'] != 'maslaki_notification_click') return;
      final payload = message['payload'];
      if (payload is Map) {
        _emitClick(Map<String, dynamic>.from(payload));
      }
    });
  }

  void _drainInitialUrlPayload() {
    if (_initialUrlPayloadChecked) return;
    _initialUrlPayloadChecked = true;
    final uri = Uri.parse(html.window.location.href);
    final encoded = uri.queryParameters['notificationPayload'];
    if (encoded == null || encoded.trim().isEmpty) return;
    try {
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
      );
      final raw = jsonDecode(decoded);
      if (raw is Map) {
        scheduleMicrotask(() => _emitClick(Map<String, dynamic>.from(raw)));
      }
    } catch (_) {
      return;
    } finally {
      final cleaned = uri.replace(
        queryParameters: Map<String, String>.from(uri.queryParameters)
          ..remove('notificationPayload'),
      );
      html.window.history.replaceState(
        null,
        html.document.title,
        cleaned.toString(),
      );
    }
  }

  void _emitClick(Map<String, dynamic> payload) {
    if (!_clickController.isClosed) {
      _clickController.add(payload);
    }
  }

  void _remember(String key) {
    _recentKeys.add(key);
    _recentOrder.add(key);
    while (_recentOrder.length > 80) {
      _recentKeys.remove(_recentOrder.removeAt(0));
    }
  }

  Future<bool> _showWithServiceWorker(
    String title,
    Map<String, Object?> options,
  ) async {
    try {
      final registration = await html.window.navigator.serviceWorker?.ready;
      if (registration == null) return false;
      await registration.showNotification(title, options);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _urgentTitle(String title) {
    final clean = title.trim();
    if (clean.isEmpty) {
      return '\u062a\u0646\u0628\u064a\u0647 \u0645\u0647\u0645 \u0645\u0646 \u0645\u0633\u0644\u0643\u064a';
    }
    if (clean.contains('\u0645\u0647\u0645') ||
        clean.contains('\u0639\u0627\u062c\u0644')) {
      return clean;
    }
    return '\u062a\u0646\u0628\u064a\u0647 \u0645\u0647\u0645: $clean';
  }

  bool _looksUrgent(String? type, String? target) {
    final value = '${type ?? ''} ${target ?? ''}'.toLowerCase();
    return value.contains('call') ||
        value.contains('urgent') ||
        value.contains('assigned') ||
        value.contains('request') ||
        value.contains('new_order') ||
        value.contains('delivery_order_ready') ||
        value.contains('delivery_order_cancelled') ||
        value.contains('taxi_ride') ||
        value.contains('courier');
  }
}
