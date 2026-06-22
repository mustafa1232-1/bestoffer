import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'maslaki_permission_models.dart';

/// Maps logical Maslaki permissions to platform permissions, normalizes status,
/// requests them safely (never throws to the UI), and persists whether the
/// first-run readiness flow was completed so it is not shown on every launch.
class MaslakiPermissionService {
  const MaslakiPermissionService();

  static const String setupCompleteKey = 'maslaki_permission_setup_done_v1';

  Permission _platform(MaslakiPermission permission) {
    switch (permission) {
      case MaslakiPermission.notifications:
        return Permission.notification;
      case MaslakiPermission.locationWhenInUse:
        return Permission.locationWhenInUse;
      case MaslakiPermission.locationAlways:
        return Permission.locationAlways;
      case MaslakiPermission.camera:
        return Permission.camera;
      case MaslakiPermission.microphone:
        return Permission.microphone;
      case MaslakiPermission.photos:
        return Permission.photos;
    }
  }

  MaslakiPermissionStatus _normalize(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return MaslakiPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied) {
      return MaslakiPermissionStatus.permanentlyDenied;
    }
    if (status.isRestricted) return MaslakiPermissionStatus.restricted;
    return MaslakiPermissionStatus.denied;
  }

  bool _isLocation(MaslakiPermission p) =>
      p == MaslakiPermission.locationWhenInUse ||
      p == MaslakiPermission.locationAlways;

  Future<MaslakiPermissionStatus> getStatus(MaslakiPermission permission) async {
    try {
      if (_isLocation(permission)) {
        final service = await Permission.location.serviceStatus;
        if (service == ServiceStatus.disabled) {
          return MaslakiPermissionStatus.serviceDisabled;
        }
      }
      final status = await _platform(permission).status;
      return _normalize(status);
    } catch (_) {
      // Permission unsupported on this platform/device — never a crash.
      return MaslakiPermissionStatus.unsupported;
    }
  }

  /// Requests a permission. Background location is only meaningful after
  /// when-in-use is granted, so callers should request when-in-use first.
  Future<MaslakiPermissionStatus> request(MaslakiPermission permission) async {
    try {
      final status = await _platform(permission).request();
      return _normalize(status);
    } catch (_) {
      return MaslakiPermissionStatus.unsupported;
    }
  }

  Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }

  // ── Central "ensure" helpers ────────────────────────────────────────────────
  // Each re-reads the LIVE status (never a cached one), requests if needed, and
  // returns whether the feature can proceed. Safe to call right before opening
  // camera/gallery/location so a grant made in Settings is picked up
  // immediately. They never throw and degrade to `false` if unsupported.

  void _log(String message) {
    if (kReleaseMode) return;
    debugPrint('[permissions] $message');
  }

  Future<bool> _ensure(MaslakiPermission permission) async {
    final current = await getStatus(permission);
    if (current.isGranted) {
      _log('$permission already granted');
      return true;
    }
    if (current == MaslakiPermissionStatus.permanentlyDenied) {
      _log('$permission permanently denied → needs settings');
      return false;
    }
    final next = await request(permission);
    _log('$permission requested → $next');
    return next.isGranted;
  }

  Future<bool> ensureCameraPermission() => _ensure(MaslakiPermission.camera);

  Future<bool> ensureMicrophonePermission() =>
      _ensure(MaslakiPermission.microphone);

  Future<bool> ensureMediaImagesPermission() =>
      _ensure(MaslakiPermission.photos);

  /// On Android the gallery video picker uses the same Photo Picker surface as
  /// images (permissionless), so this maps to the photos permission.
  Future<bool> ensureMediaVideoPermission() =>
      _ensure(MaslakiPermission.photos);

  Future<bool> ensureLocationPermission() =>
      _ensure(MaslakiPermission.locationWhenInUse);

  Future<bool> ensureNotificationPermission() =>
      _ensure(MaslakiPermission.notifications);

  // ── First-run readiness persistence ────────────────────────────────────────
  Future<bool> isSetupComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(setupCompleteKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markSetupComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(setupCompleteKey, true);
    } catch (_) {
      // best effort
    }
  }
}
