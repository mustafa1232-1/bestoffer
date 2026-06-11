import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permission_matrix.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../auth/state/auth_controller.dart';
import '../../auth/ui/add_merchant_screen.dart';
import '../../coupons/ui/coupon_management_screen.dart';
import '../../jobs/ui/job_admin_jobs_reader_screen.dart';
import '../../jobs/ui/job_super_admin_monitor_screen.dart';
import '../../jobs/ui/jobs_hub_screen.dart';
import '../../social/ui/social_chat_quality_monitor_screen.dart';
import '../../social/ui/social_feed_screen.dart';
import '../ui/admin_ad_board_screen.dart';
import 'admin_customer_reliability_policy_screen.dart';
import 'admin_companies_screen.dart';
import 'admin_create_user_screen.dart';

class AdminAdvancedToolsHubScreen extends ConsumerWidget {
  const AdminAdvancedToolsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final permissions = ref.watch(appPermissionMatrixProvider);
    final isArabic = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('ar');
    String navText({required String ar, required String en}) =>
        isArabic ? ar : en;
    final isSuperAdmin = auth.isSuperAdmin;
    final canCreateManagedAccounts = permissions.can(
      AppCapability.adminCreateUsers,
    );
    final canManageCompanies = permissions.can(AppCapability.adminCompanies);
    final canCreateMerchant = auth.isAdmin || auth.isSuperAdmin;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminAdvancedToolsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (canCreateManagedAccounts)
            _ToolTile(
              icon: Icons.person_add_alt_1_outlined,
              title: l10n.adminAdvancedToolsCreateAccount,
              subtitle: l10n.adminAdvancedToolsCreateAccountDescription,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminCreateUserScreen(),
                ),
              ),
            ),
          if (canCreateMerchant)
            _ToolTile(
              icon: Icons.store_mall_directory_outlined,
              title: l10n.adminAdvancedToolsCreateMerchant,
              subtitle: l10n.adminAdvancedToolsCreateMerchantDescription,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AddMerchantScreen(),
                ),
              ),
            ),
          if (canManageCompanies)
            _ToolTile(
              icon: Icons.apartment_rounded,
              title: l10n.adminAdvancedToolsCompanyPortal,
              subtitle: l10n.adminAdvancedToolsCompanyPortalDescription,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminCompaniesScreen(),
                ),
              ),
            ),
          _ToolTile(
            icon: Icons.confirmation_number_outlined,
            title: l10n.adminAdvancedToolsCouponManagement,
            subtitle: l10n.adminAdvancedToolsCouponManagementDescription,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CouponManagementScreen(
                  mode: CouponManagerMode.superAdmin,
                ),
              ),
            ),
          ),
          if (isSuperAdmin)
            _ToolTile(
              icon: Icons.monitor_heart_outlined,
              title: l10n.adminAdvancedToolsChatMonitoring,
              subtitle: l10n.adminAdvancedToolsChatMonitoringDescription,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SocialChatQualityMonitorScreen(),
                ),
              ),
            ),
          _ToolTile(
            icon: Icons.dynamic_feed_rounded,
            title: l10n.adminAdvancedToolsFeed,
            subtitle: l10n.adminAdvancedToolsFeedDescription,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SocialFeedScreen()),
            ),
          ),
          _ToolTile(
            icon: Icons.campaign_outlined,
            title: l10n.adminAdvancedToolsAdBoard,
            subtitle: l10n.adminAdvancedToolsAdBoardDescription,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminAdBoardScreen(),
              ),
            ),
          ),
          if (isSuperAdmin || auth.isAdmin)
            _ToolTile(
              icon: Icons.verified_user_outlined,
              title: navText(
                ar: 'سياسة موثوقية العميل',
                en: 'Customer reliability policy',
              ),
              subtitle: navText(
                ar: 'اضبط الأوزان والعتبات التي تفعّل تنبيهات مخاطر المتاجر.',
                en: 'Tune weights and thresholds that trigger merchant risk warnings.',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminCustomerReliabilityPolicyScreen(),
                ),
              ),
            ),
          _ToolTile(
            icon: Icons.work_history_outlined,
            title: l10n.adminAdvancedToolsJobsHub,
            subtitle: l10n.adminAdvancedToolsJobsHubDescription,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const JobsHubScreen()),
            ),
          ),
          _ToolTile(
            icon: Icons.person_search_outlined,
            title: l10n.adminAdvancedToolsJobsReader,
            subtitle: l10n.adminAdvancedToolsJobsReaderDescription,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const JobAdminJobsReaderScreen(),
              ),
            ),
          ),
          if (isSuperAdmin)
            _ToolTile(
              icon: Icons.fact_check_outlined,
              title: l10n.adminAdvancedToolsApplicantsMonitor,
              subtitle: l10n.adminAdvancedToolsApplicantsMonitorDescription,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const JobSuperAdminMonitorScreen(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(subtitle),
        ),
        onTap: onTap,
      ),
    );
  }
}
