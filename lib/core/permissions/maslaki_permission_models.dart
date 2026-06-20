/// Centralized, vendor-neutral permission model for every Maslaki role app.
/// This replaces ad-hoc per-screen permission logic with one typed contract.
library;

/// The Maslaki role apps that share one permission policy.
enum MaslakiAppRole { customer, merchant, delivery, taxiCaptain, admin, pharmacy }

/// Logical permissions Maslaki asks for (mapped to platform permissions by the
/// service layer, so the UI/policy never reference Android/iOS specifics).
enum MaslakiPermission {
  notifications,
  locationWhenInUse,
  locationAlways,
  camera,
  microphone,
  photos,
}

/// When a permission should be requested.
/// - [required]: requested during first-run readiness; core to the role.
/// - [optional]: shown in readiness but the user may skip it.
/// - [onDemand]: never requested at startup — only when a feature needs it.
enum MaslakiPermissionImportance { required, optional, onDemand }

/// Normalized live status of a permission.
enum MaslakiPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  serviceDisabled, // location services turned off at the OS level
  unsupported, // platform/device cannot offer it (never shown as "broken")
}

extension MaslakiPermissionStatusX on MaslakiPermissionStatus {
  bool get isGranted => this == MaslakiPermissionStatus.granted;
  bool get needsSettings => this == MaslakiPermissionStatus.permanentlyDenied;
  bool get isActionable =>
      this == MaslakiPermissionStatus.denied ||
      this == MaslakiPermissionStatus.serviceDisabled;
}

/// One role requirement: which permission, and how important it is for the role.
class PermissionRequirement {
  final MaslakiPermission permission;
  final MaslakiPermissionImportance importance;

  const PermissionRequirement(this.permission, this.importance);

  bool get isRequired => importance == MaslakiPermissionImportance.required;
  bool get isOptional => importance == MaslakiPermissionImportance.optional;
  bool get isOnDemand => importance == MaslakiPermissionImportance.onDemand;

  /// Requirements shown on the first-run readiness screen (required + optional).
  bool get isFirstRun => isRequired || isOptional;
}
