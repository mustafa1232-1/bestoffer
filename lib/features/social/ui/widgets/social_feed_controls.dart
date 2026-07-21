import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';

class SocialFeedActionStrip extends StatelessWidget {
  const SocialFeedActionStrip({
    super.key,
    required this.onOpenSearch,
    required this.onOpenCreateMenu,
    this.createLabel,
    this.createIcon = Icons.add_circle_outline_rounded,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenCreateMenu;
  final String? createLabel;
  final IconData createIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onOpenSearch,
            icon: const Icon(Icons.search_rounded),
            label: Text(l10n.socialFeedControlsSearchSocial),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.tonalIcon(
          onPressed: onOpenCreateMenu,
          icon: Icon(createIcon),
          label: Text(createLabel ?? l10n.socialFeedControlsCreatePostOrStory),
        ),
      ],
    );
  }
}

class SocialCommunityQuickActionsRow extends StatelessWidget {
  const SocialCommunityQuickActionsRow({
    super.key,
    required this.onOpenAnnouncements,
    required this.onOpenCommunityChat,
    required this.onOpenBills,
  });

  final VoidCallback onOpenAnnouncements;
  final VoidCallback onOpenCommunityChat;
  final VoidCallback onOpenBills;

  @override
  Widget build(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    String t(String ar, String en) => isEnglish ? en : ar;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CommunityQuickActionChip(
            icon: Icons.campaign_outlined,
            label: t('تبليغات المجتمع', 'Community announcements'),
            onTap: onOpenAnnouncements,
          ),
          const SizedBox(width: 8),
          _CommunityQuickActionChip(
            icon: Icons.forum_outlined,
            label: t('محادثات المجتمع', 'Community chat'),
            onTap: onOpenCommunityChat,
          ),
          const SizedBox(width: 8),
          _CommunityQuickActionChip(
            icon: Icons.receipt_long_outlined,
            label: t('فواتير المجتمع', 'Community bills'),
            onTap: onOpenBills,
          ),
        ],
      ),
    );
  }
}

class _CommunityQuickActionChip extends StatelessWidget {
  const _CommunityQuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}

class SocialFeedFiltersRow extends StatelessWidget {
  const SocialFeedFiltersRow({
    super.key,
    required this.activeKind,
    required this.onSelectKind,
  });

  final String? activeKind;
  final ValueChanged<String?> onSelectKind;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _feedFilters
            .map(
              (filter) => Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  selected: activeKind == filter.kind,
                  showCheckmark: false,
                  onSelected: (_) => onSelectKind(filter.kind),
                  avatar: Icon(filter.icon, size: 16),
                  label: Text(filter.label(context)),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class SocialFeedEmptyState extends StatelessWidget {
  const SocialFeedEmptyState({
    super.key,
    required this.onCreate,
    this.actionLabel,
    this.actionIcon = Icons.add_rounded,
    this.illustrationIcon = Icons.auto_awesome_mosaic_rounded,
  });

  final VoidCallback onCreate;
  final String? actionLabel;
  final IconData actionIcon;
  final IconData illustrationIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(illustrationIcon, color: scheme.primary, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.socialFeedControlsEmptyTitle,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.socialFeedControlsEmptyBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: Icon(actionIcon),
              label: Text(actionLabel ?? l10n.socialFeedControlsStartNow),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedFilter {
  const _FeedFilter(this.label, this.kind, this.icon);

  final String Function(BuildContext context) label;
  final String? kind;
  final IconData icon;
}

final List<_FeedFilter> _feedFilters = <_FeedFilter>[
  _FeedFilter(
    (context) => context.l10n.commonAll,
    null,
    Icons.grid_view_rounded,
  ),
  _FeedFilter(
    (context) => context.l10n.socialFeedControlsPhotos,
    'image',
    Icons.image_outlined,
  ),
  _FeedFilter(
    (context) => context.l10n.socialFeedControlsReels,
    'reel',
    Icons.ondemand_video_rounded,
  ),
  _FeedFilter(
    (context) => context.l10n.socialFeedControlsReviews,
    'merchant_review',
    Icons.rate_review_outlined,
  ),
  _FeedFilter(
    (context) => context.l10n.socialFeedControlsTextPosts,
    'text',
    Icons.text_fields_rounded,
  ),
];
