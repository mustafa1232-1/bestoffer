import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';

class SettingsUsageGuideScreen extends ConsumerWidget {
  const SettingsUsageGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sections = _buildSections(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsUsageGuideTitle)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                l10n.settingsUsageGuideIntro,
                textAlign: TextAlign.start,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...sections.map((section) => _GuideSectionCard(section: section)),
        ],
      ),
    );
  }

  List<_GuideSection> _buildSections(BuildContext context) {
    final l10n = context.l10n;
    return [
      _GuideSection(
        icon: Icons.home_outlined,
        title: l10n.settingsUsageGuideMainHomeTitle,
        description: l10n.settingsUsageGuideMainHomeDescription,
        steps: [
          l10n.settingsUsageGuideMainHomeStepMaslaki,
          l10n.settingsUsageGuideMainHomeStepTaxi,
          l10n.settingsUsageGuideMainHomeStepCommunity,
          l10n.settingsUsageGuideMainHomeStepJobs,
        ],
      ),
      _GuideSection(
        icon: Icons.person_outline,
        title: l10n.settingsUsageGuideCustomerTitle,
        description: l10n.settingsUsageGuideCustomerDescription,
        steps: [
          l10n.settingsUsageGuideCustomerStepBrowse,
          l10n.settingsUsageGuideCustomerStepCart,
          l10n.settingsUsageGuideCustomerStepTrack,
          l10n.settingsUsageGuideCustomerStepReview,
        ],
      ),
      _GuideSection(
        icon: Icons.storefront_outlined,
        title: l10n.settingsUsageGuideStoreTitle,
        description: l10n.settingsUsageGuideStoreDescription,
        steps: [
          l10n.settingsUsageGuideStoreStepCategories,
          l10n.settingsUsageGuideStoreStepStatusFlow,
          l10n.settingsUsageGuideStoreStepAssignCourier,
          l10n.settingsUsageGuideStoreStepStaff,
        ],
      ),
      _GuideSection(
        icon: Icons.delivery_dining_rounded,
        title: l10n.settingsUsageGuideDeliveryTitle,
        description: l10n.settingsUsageGuideDeliveryDescription,
        steps: [
          l10n.settingsUsageGuideDeliveryStepAccept,
          l10n.settingsUsageGuideDeliveryStepStatusFlow,
          l10n.settingsUsageGuideDeliveryStepCloseDay,
          l10n.settingsUsageGuideDeliveryStepNotifications,
        ],
      ),
      _GuideSection(
        icon: Icons.local_taxi_outlined,
        title: l10n.settingsUsageGuideTaxiTitle,
        description: l10n.settingsUsageGuideTaxiDescription,
        steps: [
          l10n.settingsUsageGuideTaxiStepPresence,
          l10n.settingsUsageGuideTaxiStepBid,
          l10n.settingsUsageGuideTaxiStepChat,
          l10n.settingsUsageGuideTaxiStepStatusFlow,
        ],
      ),
      _GuideSection(
        icon: Icons.groups_2_outlined,
        title: l10n.settingsUsageGuideCommunityTitle,
        description: l10n.settingsUsageGuideCommunityDescription,
        steps: [
          l10n.settingsUsageGuideCommunityStepScopes,
          l10n.settingsUsageGuideCommunityStepBuildings,
          l10n.settingsUsageGuideCommunityStepSearch,
          l10n.settingsUsageGuideCommunityStepPermissions,
        ],
      ),
      _GuideSection(
        icon: Icons.badge_outlined,
        title: l10n.settingsUsageGuideHrTitle,
        description: l10n.settingsUsageGuideHrDescription,
        steps: [
          l10n.settingsUsageGuideHrStepPayroll,
          l10n.settingsUsageGuideHrStepRequests,
          l10n.settingsUsageGuideHrStepShifts,
          l10n.settingsUsageGuideHrStepArchive,
        ],
      ),
      _GuideSection(
        icon: Icons.account_balance_wallet_outlined,
        title: l10n.settingsUsageGuideAccountantTitle,
        description: l10n.settingsUsageGuideAccountantDescription,
        steps: [
          l10n.settingsUsageGuideAccountantStepOpeningBalance,
          l10n.settingsUsageGuideAccountantStepSettlements,
          l10n.settingsUsageGuideAccountantStepExpenses,
          l10n.settingsUsageGuideAccountantStepNegativeBalance,
        ],
      ),
      _GuideSection(
        icon: Icons.admin_panel_settings_outlined,
        title: l10n.settingsUsageGuideAdminTitle,
        description: l10n.settingsUsageGuideAdminDescription,
        steps: [
          l10n.settingsUsageGuideAdminStepApprovals,
          l10n.settingsUsageGuideAdminStepAudit,
          l10n.settingsUsageGuideAdminStepPermissions,
          l10n.settingsUsageGuideAdminStepSuperAdmin,
        ],
      ),
      _GuideSection(
        icon: Icons.notifications_active_outlined,
        title: l10n.settingsUsageGuideNotificationsTitle,
        description: l10n.settingsUsageGuideNotificationsDescription,
        steps: [
          l10n.settingsUsageGuideNotificationsStepPermission,
          l10n.settingsUsageGuideNotificationsStepDeepLinks,
          l10n.settingsUsageGuideNotificationsStepRefresh,
          l10n.settingsUsageGuideNotificationsStepCalls,
        ],
      ),
    ];
  }
}

class _GuideSection {
  final IconData icon;
  final String title;
  final String description;
  final List<String> steps;

  const _GuideSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.steps,
  });
}

class _GuideSectionCard extends StatelessWidget {
  final _GuideSection section;

  const _GuideSectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          radius: 17,
          backgroundColor: scheme.primary.withValues(alpha: 0.14),
          child: Icon(section.icon, color: scheme.primary, size: 19),
        ),
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(section.description),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final step in section.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(Icons.circle, size: 8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(step)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
