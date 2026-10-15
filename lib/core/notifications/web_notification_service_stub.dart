import 'dart:async';

class WebNotificationService {
  WebNotificationService._();

  static final WebNotificationService instance = WebNotificationService._();

  bool get supported => false;
  bool get permissionGranted => false;
  bool get needsHomeScreenInstall => false;
  String get permission => 'unsupported';
  Stream<Map<String, dynamic>> get clickStream => const Stream.empty();

  Future<String> requestPermissionIfNeeded({bool userInitiated = false}) async {
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
  }) async {}
}
