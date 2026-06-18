import 'package:permission_handler/permission_handler.dart';

import 'creator_models.dart';

class CreatorPermissionsService {
  Future<CreatorPermissionState> ensure({
    required bool needsMicrophone,
  }) async {
    final permissions = <Permission>[
      Permission.camera,
      if (needsMicrophone) Permission.microphone,
    ];
    final statuses = await permissions.request();
    if (statuses.values.every((status) => status.isGranted)) {
      return CreatorPermissionState.granted;
    }
    if (statuses.values.any((status) => status.isPermanentlyDenied)) {
      return CreatorPermissionState.permanentlyDenied;
    }
    return CreatorPermissionState.denied;
  }

  Future<void> openSettings() => openAppSettings();
}
