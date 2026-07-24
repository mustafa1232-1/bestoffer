import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../models/social_models.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialStoriesStrip extends StatelessWidget {
  final bool loading;
  final List<SocialStoryGroup> stories;
  final VoidCallback onAddStory;
  final ValueChanged<SocialStoryGroup> onOpenStoryGroup;

  /// When false (guest mode) the "add story" tile and the empty-state label are
  /// suppressed: a guest with no stories to view sees a clean, empty area with
  /// no creation prompt.
  final bool showAddStory;

  const SocialStoriesStrip({
    super.key,
    required this.loading,
    required this.stories,
    required this.onAddStory,
    required this.onOpenStoryGroup,
    this.showAddStory = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Guest with nothing to show → keep the region empty and clean.
    if (!showAddStory && stories.isEmpty && !loading) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (showAddStory)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _AddStoryCircle(onTap: onAddStory),
            ),
          if (loading && stories.isEmpty)
            const SizedBox(
              width: 68,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (stories.isEmpty)
            // Only signed-in users get the "no stories yet" hint; for guests the
            // strip has already collapsed above.
            if (showAddStory)
              Padding(
                padding: const EdgeInsets.only(top: 36),
                child: Text(
                  l10n.socialStoriesStripEmpty,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              )
            else
              const SizedBox.shrink()
          else
            ...stories.map(
              (group) => Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: _StoryCircle(
                  group: group,
                  onTap: () => onOpenStoryGroup(group),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddStoryCircle extends StatelessWidget {
  final VoidCallback onTap;

  const _AddStoryCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: const Color(0xFF22D3EE).withValues(alpha: 0.9),
                  width: 2,
                ),
              ),
              child: const Icon(Icons.add_rounded, size: 28),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.socialStoriesStripAdd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  final SocialStoryGroup group;
  final VoidCallback onTap;

  const _StoryCircle({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasImage = (group.author.imageUrl ?? '').trim().isNotEmpty;
    final ringColor = group.hasUnviewed
        ? const Color(0xFF22D3EE)
        : Colors.white.withValues(alpha: 0.38);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: 2),
              ),
              child: CircleAvatar(
                backgroundImage: hasImage
                    ? AppCachedImageProvider(group.author.imageUrl!)
                    : null,
                child: hasImage
                    ? null
                    : const Icon(Icons.person_outline_rounded, size: 24),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              group.author.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
