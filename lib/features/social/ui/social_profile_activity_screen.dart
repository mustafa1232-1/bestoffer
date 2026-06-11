import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../models/social_models.dart';

class SocialProfileActivityScreen extends StatelessWidget {
  final SocialUserProfile profile;
  final List<String> favoriteMerchants;
  final int savedCount;
  final Future<void> Function()? onOpenImages;
  final Future<void> Function()? onOpenReels;
  final Future<void> Function()? onOpenReviews;
  final Future<void> Function()? onOpenHighlights;
  final Future<void> Function()? onOpenFriends;
  final Future<void> Function()? onOpenLikedPosts;
  final Future<void> Function()? onOpenCommentedPosts;
  final Future<void> Function()? onOpenReceivedLikes;
  final Future<void> Function()? onOpenReceivedComments;
  final Future<void> Function()? onOpenSaved;
  final Future<void> Function()? onOpenInsights;
  final Future<void> Function()? onOpenTagged;

  const SocialProfileActivityScreen({
    super.key,
    required this.profile,
    required this.favoriteMerchants,
    required this.savedCount,
    this.onOpenImages,
    this.onOpenReels,
    this.onOpenReviews,
    this.onOpenHighlights,
    this.onOpenFriends,
    this.onOpenLikedPosts,
    this.onOpenCommentedPosts,
    this.onOpenReceivedLikes,
    this.onOpenReceivedComments,
    this.onOpenSaved,
    this.onOpenInsights,
    this.onOpenTagged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stats = profile.stats;
    final primaryItems = <_ActivityMetric>[
      _ActivityMetric(
        label: l10n.socialProfileActivityImages,
        value: stats.imagePosts,
        icon: Icons.image_outlined,
        onTap: onOpenImages,
      ),
      _ActivityMetric(
        label: l10n.socialProfileActivityReels,
        value: stats.videoPosts,
        icon: Icons.play_circle_outline_rounded,
        onTap: onOpenReels,
      ),
      _ActivityMetric(
        label: l10n.socialProfileActivityReviews,
        value: stats.reviewPosts,
        icon: Icons.rate_review_outlined,
        onTap: onOpenReviews,
      ),
      _ActivityMetric(
        label: l10n.socialProfileActivityHighlights,
        value: stats.highlightsCount,
        icon: Icons.highlight_alt_outlined,
        onTap: onOpenHighlights,
      ),
      _ActivityMetric(
        label: l10n.socialProfileActivityFriends,
        value: stats.friendsCount,
        icon: Icons.groups_2_outlined,
        onTap: onOpenFriends,
      ),
      _ActivityMetric(
        label: l10n.socialProfileActivitySaved,
        value: savedCount,
        icon: Icons.bookmark_outline_rounded,
        onTap: onOpenSaved,
      ),
    ];
    final engagementItems = <_ActivityMetric>[
      _ActivityMetric(
        label: l10n.socialProfileActivityLikesReceived,
        value: stats.likesReceived,
        icon: Icons.favorite_border_rounded,
        onTap: onOpenReceivedLikes,
      ),
      _ActivityMetric(
        label: l10n.socialProfileActivityCommentsReceived,
        value: stats.commentsReceived,
        icon: Icons.mode_comment_outlined,
        onTap: onOpenReceivedComments,
      ),
      _ActivityMetric(
        label: l10n.socialProfileActivityLikesMade,
        value: stats.likesGiven,
        icon: Icons.thumb_up_off_alt_outlined,
        onTap: onOpenLikedPosts,
      ),
      _ActivityMetric(
        label: l10n.socialProfileActivityCommentsMade,
        value: stats.commentsMade,
        icon: Icons.chat_bubble_outline_rounded,
        onTap: onOpenCommentedPosts,
      ),
      _ActivityMetric(
        label: l10n.socialProfileActivityTagged,
        value: _readTabCount(profile.tabs['tagged']),
        icon: Icons.alternate_email_rounded,
        onTap: onOpenTagged,
      ),
      _ActivityMetric(
        label: l10n.socialProfileActivityActiveStories,
        value: stats.activeStories,
        icon: Icons.auto_stories_outlined,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.socialProfileActivityTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SectionTitle(
            title: l10n.socialProfileActivityContentTitle,
            subtitle: l10n.socialProfileActivityContentSubtitle,
          ),
          const SizedBox(height: 12),
          _MetricsGrid(items: primaryItems),
          if (favoriteMerchants.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              l10n.socialProfileActivityFrequentMerchants,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: favoriteMerchants
                  .map((item) => _MerchantPill(label: item))
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 24),
          _SectionTitle(
            title: l10n.socialProfileActivityEngagementTitle,
            subtitle: l10n.socialProfileActivityEngagementSubtitle,
          ),
          const SizedBox(height: 12),
          _MetricsGrid(items: engagementItems),
          if (onOpenInsights != null) ...[
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: onOpenInsights,
              icon: const Icon(Icons.insights_outlined),
              label: Text(l10n.socialProfileActivityOpenInsights),
            ),
          ],
        ],
      ),
    );
  }
}

int _readTabCount(dynamic value) {
  if (value is bool) return value ? 1 : 0;
  return int.tryParse('$value') ?? 0;
}

class _ActivityMetric {
  final String label;
  final int value;
  final IconData icon;
  final Future<void> Function()? onTap;

  const _ActivityMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final List<_ActivityMetric> items;

  const _MetricsGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        const columns = 2.0;
        final usableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final tileWidth =
            ((usableWidth - ((columns - 1) * spacing)) / columns)
                .clamp(120.0, 460.0)
                .toDouble();
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map((item) => _ActivityMetricTile(item: item, width: tileWidth))
              .toList(growable: false),
        );
      },
    );
  }
}

class _ActivityMetricTile extends StatelessWidget {
  final _ActivityMetric item;
  final double width;

  const _ActivityMetricTile({required this.item, required this.width});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final content = Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surface.withValues(alpha: 0.92),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            '${item.value}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            item.onTap == null ? l10n.commonMetric : l10n.commonOpen,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
    if (item.onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => item.onTap!.call(),
      child: content,
    );
  }
}

class _MerchantPill extends StatelessWidget {
  final String label;

  const _MerchantPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
