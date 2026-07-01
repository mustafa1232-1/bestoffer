import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../paid_upgrades/models/paid_upgrade_models.dart';
import '../models/social_models.dart';
import 'social_restrictions_screen.dart';

class SocialProfileAccountManagementScreen extends StatelessWidget {
  final SocialUserProfile profile;
  final PaidUpgradesSummaryModel? paidSummary;
  final Future<void> Function()? onEditProfile;
  final Future<void> Function()? onOpenRelationRequests;
  final Future<void> Function()? onOpenResidenceChange;
  final Future<void> Function()? onOpenPremiumStatus;
  final Future<void> Function()? onOpenPaidUpgrades;
  final Future<void> Function()? onOpenReportedPosts;
  final Future<void> Function()? onOpenInsights;

  const SocialProfileAccountManagementScreen({
    super.key,
    required this.profile,
    required this.paidSummary,
    this.onEditProfile,
    this.onOpenRelationRequests,
    this.onOpenResidenceChange,
    this.onOpenPremiumStatus,
    this.onOpenPaidUpgrades,
    this.onOpenReportedPosts,
    this.onOpenInsights,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final infoItems = <_InfoRowData>[
      _InfoRowData(
        label: l10n.socialProfileManagePhone,
        value: (profile.phone ?? '').trim().isEmpty
            ? l10n.socialProfileManageHidden
            : profile.phone!.trim(),
      ),
      _InfoRowData(
        label: l10n.socialProfileManageJoined,
        value: _formatDate(profile.joinedAt, context),
      ),
      if (profile.age != null)
        _InfoRowData(
          label: l10n.socialProfileManageAge,
          value: l10n.socialProfileManageAgeValue('${profile.age}'),
        ),
      if ((profile.workTitle ?? '').trim().isNotEmpty)
        _InfoRowData(
          label: l10n.socialProfileManageWorkTitle,
          value: profile.workTitle!.trim(),
        ),
      if ((profile.workCompany ?? '').trim().isNotEmpty)
        _InfoRowData(
          label: l10n.socialProfileManageCompany,
          value: profile.workCompany!.trim(),
        ),
      if ((profile.localContext ?? '').trim().isNotEmpty)
        _InfoRowData(
          label: l10n.socialProfileManageLocalContext,
          value: profile.localContext!.trim(),
        ),
      _InfoRowData(
        label: l10n.socialProfileManageAccountStatus,
        value: profile.accountDisabled
            ? l10n.socialProfileManageDisabled
            : l10n.socialProfileManageActive,
      ),
      if (profile.coreProfileLockedUntil != null)
        _InfoRowData(
          label: l10n.socialProfileManageNextCoreUpdate,
          value: _formatDate(profile.coreProfileLockedUntil, context),
        ),
    ];

    return Directionality(
      textDirection: context.appTextDirection,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.socialProfileManageTitle)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _SectionCard(
              title: l10n.socialProfileManageProfilePrivacy,
              child: Column(
                children: [
                  _ActionTile(
                    icon: Icons.edit_outlined,
                    title: l10n.socialProfileManageEditProfilePrivacy,
                    subtitle: l10n.socialProfileManageEditProfilePrivacyHint,
                    onTap: onEditProfile,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusChip(
                        icon: Icons.phone_enabled_outlined,
                        label: profile.showPhone
                            ? l10n.socialProfileManagePhoneVisible
                            : l10n.socialProfileManagePhoneHidden,
                      ),
                      _StatusChip(
                        icon: Icons.public_rounded,
                        label: profile.postsPublic
                            ? l10n.socialProfileManagePostsPublic
                            : l10n.socialProfileManagePostsPrivate,
                      ),
                      _StatusChip(
                        icon: Icons.auto_stories_rounded,
                        label: profile.storiesPublic
                            ? l10n.socialProfileManageStoriesPublic
                            : l10n.socialProfileManageStoriesPrivate,
                      ),
                      _StatusChip(
                        icon: Icons.group_outlined,
                        label: profile.relationsPublic
                            ? l10n.socialProfileManageRelationsVisible
                            : l10n.socialProfileManageRelationsPrivate,
                      ),
                      _StatusChip(
                        icon: Icons.circle_notifications_outlined,
                        label: l10n.socialProfileManageOnlineStatus(
                          _visibilityLabel(
                            context,
                            profile.onlineStatusVisibility,
                          ),
                        ),
                      ),
                      _StatusChip(
                        icon: Icons.schedule_outlined,
                        label: l10n.socialProfileManageLastSeen(
                          _visibilityLabel(context, profile.lastSeenVisibility),
                        ),
                      ),
                      _StatusChip(
                        icon: Icons.done_all_rounded,
                        label: profile.readReceiptsEnabled
                            ? l10n.socialProfileManageReadReceiptsOn
                            : l10n.socialProfileManageReadReceiptsHidden,
                      ),
                      _StatusChip(
                        icon: Icons.keyboard_rounded,
                        label: profile.typingIndicatorsEnabled
                            ? l10n.socialProfileManageTypingOn
                            : l10n.socialProfileManageTypingHidden,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: l10n.socialProfileManageAccountActions,
              child: Column(
                children: [
                  if (onOpenRelationRequests != null)
                    _ActionTile(
                      icon: Icons.person_add_alt_1_rounded,
                      title: l10n.socialProfileManageConnectionRequests,
                      subtitle: l10n.socialProfileManageConnectionRequestsHint,
                      onTap: onOpenRelationRequests,
                    ),
                  if (onOpenResidenceChange != null)
                    _ActionTile(
                      icon: Icons.home_work_outlined,
                      title: l10n.socialProfileManageResidenceChange,
                      subtitle: l10n.socialProfileManageResidenceChangeHint,
                      onTap: onOpenResidenceChange,
                    ),
                  if (onOpenPremiumStatus != null)
                    _ActionTile(
                      icon: Icons.workspace_premium_outlined,
                      title: 'اشتراك بريميوم',
                      subtitle: 'عرض المتبقي من الاشتراك وتجديده',
                      onTap: onOpenPremiumStatus,
                    ),
                  if (onOpenPaidUpgrades != null)
                    _ActionTile(
                      icon: Icons.workspace_premium_outlined,
                      title: l10n.socialProfileManageUpgrades,
                      subtitle: _upgradeSubtitle(context, paidSummary),
                      onTap: onOpenPaidUpgrades,
                    ),
                  _ActionTile(
                    icon: Icons.shield_outlined,
                    title: l10n.socialProfileManageSocialRestrictions,
                    subtitle: l10n.socialProfileManageSocialRestrictionsHint,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SocialRestrictionsScreen(),
                        ),
                      );
                    },
                  ),
                  if (onOpenReportedPosts != null)
                    _ActionTile(
                      icon: Icons.rule_folder_outlined,
                      title: l10n.socialProfileManageReportedPosts,
                      subtitle: l10n.socialProfileManageReportedPostsHint,
                      onTap: onOpenReportedPosts,
                    ),
                  if (onOpenInsights != null)
                    _ActionTile(
                      icon: Icons.insights_outlined,
                      title: l10n.socialProfileManageInsights,
                      subtitle: l10n.socialProfileManageInsightsHint,
                      onTap: onOpenInsights,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: l10n.socialProfileManageAccountInfo,
              child: Column(
                children: infoItems
                    .map((item) => _InfoRow(item: item))
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function()? onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap == null ? null : () => onTap!.call(),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _InfoRowData {
  final String label;
  final String value;

  const _InfoRowData({required this.label, required this.value});
}

class _InfoRow extends StatelessWidget {
  final _InfoRowData item;

  const _InfoRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              item.value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? value, BuildContext context) {
  if (value == null) {
    return context.l10n.socialProfileManageUnavailable;
  }
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString().padLeft(4, '0');
  return '$year/$month/$day';
}

String _visibilityLabel(BuildContext context, String value) {
  final l10n = context.l10n;
  switch (value.trim().toLowerCase()) {
    case 'everyone':
      return l10n.socialProfileManageVisibilityEveryone;
    case 'nobody':
      return l10n.socialProfileManageVisibilityNobody;
    default:
      return l10n.socialProfileManageVisibilityConnectionsOnly;
  }
}

String _upgradeSubtitle(
  BuildContext context,
  PaidUpgradesSummaryModel? summary,
) {
  if (summary == null) {
    return context.l10n.socialProfileManageUpgradeStatusSummary;
  }
  if (summary.premiumBadgeActive) {
    return context.l10n.socialProfileManageUpgradeStatusActive;
  }
  if ((summary.requests).isNotEmpty) {
    return context.l10n.socialProfileManageUpgradeStatusRequests;
  }
  return context.l10n.socialProfileManageUpgradeStatusSummary;
}
