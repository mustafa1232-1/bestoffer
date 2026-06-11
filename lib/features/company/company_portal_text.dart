import 'package:flutter/material.dart';

import '../../core/i18n/app_localizations_context.dart';

String companyRoleLabel(BuildContext context, String role) {
  final l10n = context.l10n;
  switch (role.trim().toLowerCase()) {
    case 'company_owner':
      return l10n.companyRoleOwner;
    case 'company_manager':
      return l10n.companyRoleManager;
    case 'finance_viewer':
      return l10n.companyRoleFinanceViewer;
    case 'operations_viewer':
      return l10n.companyRoleOperationsViewer;
    default:
      return role;
  }
}

String companyStatusLabel(BuildContext context, String status) {
  final l10n = context.l10n;
  switch (status.trim().toLowerCase()) {
    case 'active':
      return l10n.companyStatusActive;
    case 'inactive':
      return l10n.companyStatusInactive;
    case 'suspended':
      return l10n.companyStatusSuspended;
    case 'pending':
      return l10n.companyStatusPending;
    case 'pending_admin_review':
      return l10n.companyStatusPendingAdminReview;
    case 'approved':
      return l10n.companyStatusApproved;
    case 'rejected':
      return l10n.companyStatusRejected;
    default:
      return status;
  }
}

String companyBranchTypeLabel(BuildContext context, String type) {
  final l10n = context.l10n;
  switch (type.trim().toLowerCase()) {
    case 'restaurant':
      return l10n.companyBranchTypeRestaurant;
    case 'market':
      return l10n.companyBranchTypeMarket;
    default:
      return type;
  }
}

String companyInventoryModeLabel(BuildContext context, String mode) {
  final l10n = context.l10n;
  switch (mode.trim().toLowerCase()) {
    case 'strict_daily':
      return l10n.companyInventoryModeStrictDaily;
    case 'soft_reminder':
      return l10n.companyInventoryModeSoftReminder;
    case 'manual_override':
      return l10n.companyInventoryModeManualOverride;
    default:
      return mode;
  }
}

String companyStockStatusLabel(BuildContext context, String status) {
  final l10n = context.l10n;
  switch (status.trim().toLowerCase()) {
    case 'out_of_stock':
      return l10n.companyStockOutOfStock;
    case 'low_stock':
      return l10n.companyStockLowStock;
    case 'manual_disabled':
      return l10n.companyStockManualDisabled;
    case 'available':
      return l10n.companyStockAvailable;
    default:
      return status;
  }
}

String companyFallbackText(BuildContext context, {required String? value}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return context.l10n.commonNotSet;
  }
  return trimmed;
}
