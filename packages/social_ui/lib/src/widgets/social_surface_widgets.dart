import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:social_core/social_core.dart';
import '../media/social_media_cache_manager.dart';
import '../media/social_media_url.dart';

String _t(BuildContext context, {required String ar, required String en}) {
  final code = Localizations.maybeLocaleOf(context)?.languageCode.toLowerCase();
  return code == 'ar' ? ar : en;
}

ImageProvider<Object>? _cachedAvatarProvider(String? url) {
  final value = resolveSocialMediaUrl(url);
  if (value == null || value.isEmpty) return null;
  return CachedNetworkImageProvider(
    value,
    cacheManager: SocialMediaCacheManager.instance,
  );
}

class SocialStatusChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const SocialStatusChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}

class SocialMediaFallback extends StatelessWidget {
  const SocialMediaFallback({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.8),
            theme.colorScheme.secondary.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome_rounded, size: 44, color: Colors.white),
      ),
    );
  }
}

class SocialSuggestedPersonTile extends StatelessWidget {
  final SocialUserSearchResult item;
  final String? trailingLabel;

  const SocialSuggestedPersonTile({
    super.key,
    required this.item,
    this.trailingLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = item.user;
    return Container(
      width: 188,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: _cachedAvatarProvider(user.imageUrl),
            child: (user.imageUrl ?? '').trim().isEmpty
                ? Text(
                    user.fullName.trim().isEmpty
                        ? '?'
                        : user.fullName.trim()[0],
                    style: theme.textTheme.titleMedium,
                  )
                : null,
          ),
          const SizedBox(height: 10),
          Text(
            user.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            user.username == null || user.username!.trim().isEmpty
                ? _t(context, ar: 'عضو في المجتمع', en: 'Community member')
                : '@${user.username}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          Row(
            children: [
              if (user.isResidentVerified)
                Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              if (user.isPremiumCreator) ...[
                if (user.isResidentVerified) const SizedBox(width: 6),
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: theme.colorScheme.secondary,
                ),
              ],
              const Spacer(),
              Text(
                trailingLabel ?? _t(context, ar: 'مقترح', en: 'Suggested'),
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SocialSuggestedPersonRow extends StatelessWidget {
  final SocialUserSearchResult item;

  const SocialSuggestedPersonRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = item.user;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: _cachedAvatarProvider(user.imageUrl),
          child: (user.imageUrl ?? '').trim().isEmpty
              ? Text(
                  user.fullName.trim().isEmpty ? '?' : user.fullName.trim()[0],
                  style: theme.textTheme.titleMedium,
                )
              : null,
        ),
        title: Text(
          user.fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          user.username == null || user.username!.trim().isEmpty
              ? _t(context, ar: 'عضو في المجتمع', en: 'Community member')
              : '@${user.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user.isResidentVerified)
              Icon(
                Icons.verified_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            if (user.isPremiumCreator) ...[
              if (user.isResidentVerified) const SizedBox(width: 6),
              Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SocialStoryGroupTile extends StatelessWidget {
  final SocialStoryGroup group;

  const SocialStoryGroupTile({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: group.hasUnviewed
                    ? [theme.colorScheme.primary, theme.colorScheme.secondary]
                    : [
                        theme.colorScheme.outlineVariant,
                        theme.colorScheme.outlineVariant,
                      ],
              ),
            ),
            child: CircleAvatar(
              backgroundImage: _cachedAvatarProvider(group.author.imageUrl),
              child: (group.author.imageUrl ?? '').trim().isEmpty
                  ? Text(
                      group.author.fullName.trim().isEmpty
                          ? '?'
                          : group.author.fullName.trim()[0],
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            group.author.fullName.trim().isEmpty
                ? group.author.username ?? '@user'
                : group.author.fullName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class SocialMediaCard extends StatelessWidget {
  final SocialPost post;

  const SocialMediaCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualUrl = resolveSocialMediaUrl(resolveSocialPostPosterUrl(post));
    final hasVisual = visualUrl != null && visualUrl.trim().isNotEmpty;
    final mediaClass = normalizeSocialPostMediaClass(post);
    final isVideo = mediaClass == 'video' || mediaClass == 'reel';
    final chipLabel = switch (mediaClass) {
      'reel' => _t(context, ar: 'ريل', en: 'Reel'),
      'video' => _t(context, ar: 'فيديو', en: 'Video'),
      'image' => _t(context, ar: 'صورة', en: 'Image'),
      'merchant_review' => _t(context, ar: 'مراجعة متجر', en: 'Store review'),
      _ => _t(context, ar: 'منشور', en: 'Post'),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasVisual)
                  CachedNetworkImage(
                    imageUrl: visualUrl,
                    cacheManager: SocialMediaCacheManager.instance,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SocialMediaFallback(),
                  )
                else
                  const SocialMediaFallback(),
                if (isVideo)
                  const Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                PositionedDirectional(
                  top: 12,
                  start: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        chipLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.author.fullName,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (post.caption.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    post.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SocialStatusChip(
                      icon: Icons.favorite_border_rounded,
                      label: '${post.likesCount}',
                    ),
                    SocialStatusChip(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '${post.commentsCount}',
                    ),
                    if ((post.merchantName ?? '').trim().isNotEmpty)
                      SocialStatusChip(
                        icon: Icons.storefront_rounded,
                        label: post.merchantName!,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SocialProfileSummaryCard extends StatelessWidget {
  final SocialUserProfile profile;

  const SocialProfileSummaryCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: _cachedAvatarProvider(profile.imageUrl),
                  child: (profile.imageUrl ?? '').trim().isEmpty
                      ? Text(
                          profile.fullName.trim().isEmpty
                              ? '?'
                              : profile.fullName.trim()[0],
                          style: theme.textTheme.titleLarge,
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName,
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.username == null ||
                                profile.username!.trim().isEmpty
                            ? _t(
                                context,
                                ar: 'ملف اجتماعي مشترك',
                                en: 'Shared social profile',
                              )
                            : '@${profile.username}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (profile.isResidentVerified)
                  Icon(
                    Icons.verified_rounded,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            if (profile.bio.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(profile.bio, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SocialStatusChip(
                  icon: Icons.grid_view_rounded,
                  label: '${profile.stats.totalPosts}',
                ),
                SocialStatusChip(
                  icon: Icons.favorite_border_rounded,
                  label: '${profile.stats.likesReceived}',
                ),
                SocialStatusChip(
                  icon: Icons.people_alt_outlined,
                  label: '${profile.stats.connectionsCount}',
                ),
                if ((profile.localContext ?? '').trim().isNotEmpty)
                  SocialStatusChip(
                    icon: Icons.location_on_outlined,
                    label: profile.localContext!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
