import 'maslaki_permission_models.dart';

/// The single source of truth for *which* permissions each Maslaki role needs
/// and *how* (required at first run / optional / on-demand).
///
/// Key safety rules encoded here:
/// - Background location (`locationAlways`) is required ONLY for delivery and
///   taxi-captain (live tracking while backgrounded). Customers never get it.
/// - Camera / microphone / photos are on-demand for most roles (requested when
///   the actual feature is used), never spammed at startup.
/// - Notifications are required for every role (orders, taxi, delivery, chat).
class MaslakiPermissionPolicy {
  const MaslakiPermissionPolicy._();

  static List<PermissionRequirement> requirementsForRole(MaslakiAppRole role) {
    switch (role) {
      case MaslakiAppRole.customer:
        return const [
          PermissionRequirement(
              MaslakiPermission.notifications, MaslakiPermissionImportance.required),
          PermissionRequirement(MaslakiPermission.locationWhenInUse,
              MaslakiPermissionImportance.onDemand),
          PermissionRequirement(
              MaslakiPermission.camera, MaslakiPermissionImportance.onDemand),
          PermissionRequirement(
              MaslakiPermission.microphone, MaslakiPermissionImportance.onDemand),
          PermissionRequirement(
              MaslakiPermission.photos, MaslakiPermissionImportance.onDemand),
        ];
      case MaslakiAppRole.taxiCaptain:
        return const [
          PermissionRequirement(
              MaslakiPermission.notifications, MaslakiPermissionImportance.required),
          PermissionRequirement(MaslakiPermission.locationWhenInUse,
              MaslakiPermissionImportance.required),
          PermissionRequirement(MaslakiPermission.locationAlways,
              MaslakiPermissionImportance.required),
          PermissionRequirement(
              MaslakiPermission.camera, MaslakiPermissionImportance.onDemand),
          PermissionRequirement(
              MaslakiPermission.photos, MaslakiPermissionImportance.onDemand),
        ];
      case MaslakiAppRole.delivery:
        return const [
          PermissionRequirement(
              MaslakiPermission.notifications, MaslakiPermissionImportance.required),
          PermissionRequirement(MaslakiPermission.locationWhenInUse,
              MaslakiPermissionImportance.required),
          PermissionRequirement(MaslakiPermission.locationAlways,
              MaslakiPermissionImportance.required),
          PermissionRequirement(
              MaslakiPermission.camera, MaslakiPermissionImportance.onDemand),
          PermissionRequirement(
              MaslakiPermission.photos, MaslakiPermissionImportance.onDemand),
        ];
      case MaslakiAppRole.merchant:
        return const [
          PermissionRequirement(
              MaslakiPermission.notifications, MaslakiPermissionImportance.required),
          PermissionRequirement(
              MaslakiPermission.camera, MaslakiPermissionImportance.optional),
          // Gallery uses the permissionless Android Photo Picker, so media is
          // on-demand (no system media permission card needed).
          PermissionRequirement(
              MaslakiPermission.photos, MaslakiPermissionImportance.onDemand),
          PermissionRequirement(MaslakiPermission.locationWhenInUse,
              MaslakiPermissionImportance.onDemand),
        ];
      case MaslakiAppRole.pharmacy:
        return const [
          PermissionRequirement(
              MaslakiPermission.notifications, MaslakiPermissionImportance.required),
          PermissionRequirement(
              MaslakiPermission.camera, MaslakiPermissionImportance.onDemand),
          PermissionRequirement(
              MaslakiPermission.photos, MaslakiPermissionImportance.onDemand),
          PermissionRequirement(MaslakiPermission.locationWhenInUse,
              MaslakiPermissionImportance.onDemand),
        ];
      case MaslakiAppRole.admin:
        return const [
          PermissionRequirement(
              MaslakiPermission.notifications, MaslakiPermissionImportance.required),
          PermissionRequirement(
              MaslakiPermission.photos, MaslakiPermissionImportance.onDemand),
        ];
    }
  }

  /// Permissions to surface on the first-run readiness screen (required +
  /// optional), in a stable order.
  static List<PermissionRequirement> firstRunRequirements(MaslakiAppRole role) =>
      requirementsForRole(role).where((r) => r.isFirstRun).toList();

  /// Permissions that block "fully ready" until granted.
  static List<MaslakiPermission> requiredPermissions(MaslakiAppRole role) =>
      requirementsForRole(role)
          .where((r) => r.isRequired)
          .map((r) => r.permission)
          .toList();

  /// Background location is gated to roles that actually track in the background.
  static bool requiresBackgroundLocation(MaslakiAppRole role) =>
      role == MaslakiAppRole.delivery || role == MaslakiAppRole.taxiCaptain;

  static bool isRequiredForRole(MaslakiAppRole role, MaslakiPermission p) =>
      requirementsForRole(role)
          .any((r) => r.permission == p && r.isRequired);
}
