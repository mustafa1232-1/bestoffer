import 'package:flutter/material.dart';

import '../../../features/notifications/ui/notifications_screen.dart';
import '../../../features/settings/ui/settings_screen.dart';
import 'admin_advanced_tools_hub_screen.dart';
import 'admin_approvals_hub_screen.dart';
import 'admin_audit_security_center_screen.dart';
import 'admin_crash_error_center_screen.dart';
import 'admin_audit_log_screen.dart';
import 'admin_competitions_screen.dart';
import 'admin_customer_profiles_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_device_reliability_screen.dart';
import 'admin_feature_flags_center_screen.dart';
import 'admin_financial_reports_hub_screen.dart';
import 'admin_maintenance_screen.dart';
import 'admin_merchant_approvals_screen.dart';
import 'admin_merchant_state_management_screen.dart';
import 'admin_notification_center_screen.dart';
import 'admin_notifications_operations_screen.dart';
import 'admin_permissions_matrix_screen.dart';
import 'admin_rbac_management_screen.dart';
import 'admin_receivables_screen.dart';
import 'admin_support_tickets_screen.dart';
import 'admin_taxi_captain_requests_screen.dart';
import 'admin_taxi_cash_payments_screen.dart';
import '../../ai_dev_support/screens/ai_dev_support_dashboard_screen.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminDashboardScreen();
}

class AdminRequestsInboxPage extends StatelessWidget {
  const AdminRequestsInboxPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminApprovalsHubScreen();
}

class AdminApprovalRequestsPage extends StatelessWidget {
  const AdminApprovalRequestsPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminMerchantApprovalsScreen();
}

class AdminPaymentRequestsPage extends StatelessWidget {
  const AdminPaymentRequestsPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminReceivablesScreen();
}

class AdminMerchantsPage extends StatelessWidget {
  const AdminMerchantsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const AdminMerchantStateManagementScreen();
}

class AdminCourierPage extends StatelessWidget {
  const AdminCourierPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminTaxiCaptainRequestsScreen();
}

class AdminTaxiCaptainsPage extends StatelessWidget {
  const AdminTaxiCaptainsPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminTaxiCaptainRequestsScreen();
}

class AdminNotificationsPage extends StatelessWidget {
  const AdminNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) => const NotificationsScreen();
}

class AdminReportsPage extends StatelessWidget {
  const AdminReportsPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminFinancialReportsHubScreen();
}

class AdminSupportOrComplaintsPage extends StatelessWidget {
  const AdminSupportOrComplaintsPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminSupportTicketsScreen();
}

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const SettingsScreen();
}

class AdminReceivablesPage extends StatelessWidget {
  const AdminReceivablesPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminReceivablesScreen();
}

class AdminCompetitionsPage extends StatelessWidget {
  const AdminCompetitionsPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminCompetitionsScreen();
}

class AdminMaintenancePage extends StatelessWidget {
  const AdminMaintenancePage({super.key});

  @override
  Widget build(BuildContext context) => const AdminMaintenanceScreen();
}

class AdminAuditPage extends StatelessWidget {
  const AdminAuditPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminAuditLogScreen();
}

class AdminCustomerProfilesPage extends StatelessWidget {
  const AdminCustomerProfilesPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminCustomerProfilesScreen();
}

class AdminTaxiCashPaymentsPage extends StatelessWidget {
  const AdminTaxiCashPaymentsPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminTaxiCashPaymentsScreen();
}

class AdminAdvancedHubPage extends StatelessWidget {
  const AdminAdvancedHubPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminAdvancedToolsHubScreen();
}

class AdminNotificationCenterPage extends StatelessWidget {
  const AdminNotificationCenterPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminNotificationCenterScreen();
}

class AdminCrashErrorCenterPage extends StatelessWidget {
  const AdminCrashErrorCenterPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminCrashErrorCenterScreen();
}

class AdminAuditSecurityCenterPage extends StatelessWidget {
  const AdminAuditSecurityCenterPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminAuditSecurityCenterScreen();
}

class AdminFeatureFlagsCenterPage extends StatelessWidget {
  const AdminFeatureFlagsCenterPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminFeatureFlagsCenterScreen();
}

class AdminPermissionsMatrixPage extends StatelessWidget {
  const AdminPermissionsMatrixPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminPermissionsMatrixScreen();
}

class AdminRbacManagementPage extends StatelessWidget {
  const AdminRbacManagementPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminRbacManagementScreen();
}

class AdminNotificationsOperationsPage extends StatelessWidget {
  const AdminNotificationsOperationsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const AdminNotificationsOperationsScreen();
}

class AdminDeviceReliabilityPage extends StatelessWidget {
  const AdminDeviceReliabilityPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminDeviceReliabilityScreen();
}

class AdminAiDevSupportPage extends StatelessWidget {
  const AdminAiDevSupportPage({super.key});

  @override
  Widget build(BuildContext context) => const AiDevSupportDashboardScreen();
}
