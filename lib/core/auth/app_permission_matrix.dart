import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/auth_controller.dart';

enum AppCapability {
  customerHome,
  customerOrders,
  customerCart,
  customerAddresses,
  customerCars,
  customerFavorites,
  customerActivity,
  customerPaidUpgrades,
  customerRealEstate,
  socialFeed,
  socialChats,
  socialCommunityScopes,
  ownerDashboard,
  deliveryDashboard,
  accountantDashboard,
  hrDashboard,
  adminDashboard,
  adminCustomerInsights,
  adminCompanies,
  adminCreateUsers,
  adminApproveCriticalActions,
  adminResidenceRequests,
  adminSocialRestrictions,
  adminRealEstate,
  aiDevSupportAccess,
  aiDevSupportViewIncidents,
  aiDevSupportApproveAction,
  aiDevSupportRejectAction,
  aiDevSupportRequestCodeFix,
  aiDevSupportCreateGithubIssue,
  aiDevSupportManageSettings,
  aiDevSupportViewAuditLogs,
}

class AppPermissionMatrix {
  final bool isAuthed;
  final String role;
  final bool isSuperAdmin;

  const AppPermissionMatrix({
    required this.isAuthed,
    required this.role,
    required this.isSuperAdmin,
  });

  factory AppPermissionMatrix.fromAuth(AuthState auth) {
    final role = auth.user?.role.trim().toLowerCase() ?? '';
    return AppPermissionMatrix(
      isAuthed: auth.isAuthed,
      role: role,
      isSuperAdmin: auth.isSuperAdmin,
    );
  }

  bool get isCustomer => isAuthed && role == 'user';
  bool get isOwner => isAuthed && role == 'owner';
  bool get isDelivery => isAuthed && role == 'delivery';
  bool get isAccountant => isAuthed && role == 'accountant';
  bool get isHr => isAuthed && role == 'hr';
  bool get isAdmin => isAuthed && role == 'admin';
  bool get isDeputyAdmin => isAuthed && role == 'deputy_admin';
  bool get isBackoffice => isAdmin || isDeputyAdmin || isSuperAdmin;

  bool can(AppCapability capability) {
    if (isSuperAdmin) return true;

    switch (capability) {
      case AppCapability.customerHome:
      case AppCapability.customerOrders:
      case AppCapability.customerCart:
      case AppCapability.customerAddresses:
      case AppCapability.customerCars:
      case AppCapability.customerFavorites:
      case AppCapability.customerActivity:
      case AppCapability.customerPaidUpgrades:
      case AppCapability.customerRealEstate:
      case AppCapability.socialFeed:
      case AppCapability.socialChats:
        return isCustomer;

      case AppCapability.socialCommunityScopes:
        return isCustomer || isDelivery || isBackoffice;

      case AppCapability.ownerDashboard:
        return isOwner;

      case AppCapability.deliveryDashboard:
        return isDelivery;

      case AppCapability.accountantDashboard:
        return isAccountant;

      case AppCapability.hrDashboard:
        return isHr;

      case AppCapability.adminDashboard:
      case AppCapability.adminResidenceRequests:
      case AppCapability.adminSocialRestrictions:
      case AppCapability.adminRealEstate:
        return isBackoffice;

      case AppCapability.adminCustomerInsights:
        return false;

      case AppCapability.adminCompanies:
      case AppCapability.adminCreateUsers:
      case AppCapability.adminApproveCriticalActions:
        return isAdmin;

      case AppCapability.aiDevSupportAccess:
      case AppCapability.aiDevSupportViewIncidents:
      case AppCapability.aiDevSupportApproveAction:
      case AppCapability.aiDevSupportRejectAction:
      case AppCapability.aiDevSupportRequestCodeFix:
      case AppCapability.aiDevSupportCreateGithubIssue:
      case AppCapability.aiDevSupportManageSettings:
      case AppCapability.aiDevSupportViewAuditLogs:
        return false;
    }
  }
}

final appPermissionMatrixProvider = Provider<AppPermissionMatrix>((ref) {
  final auth = ref.watch(authControllerProvider);
  return AppPermissionMatrix.fromAuth(auth);
});
