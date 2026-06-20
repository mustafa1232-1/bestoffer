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
