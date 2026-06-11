import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../models/social_story_document.dart';
import 'social_story_composer_screen.dart';

Future<bool?> showSocialStoryComposerEntrySheet(BuildContext context) async {
  final mode = await showModalBottomSheet<SocialStoryComposerMode>(
    context: context,
    showDragHandle: true,
    builder: (_) => const SocialStoryComposerEntrySheet(),
  );
  if (mode == null || !context.mounted) return null;
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SocialStoryComposerScreen(initialMode: mode),
    ),
  );
}

class SocialStoryComposerEntrySheet extends StatelessWidget {
  const SocialStoryComposerEntrySheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.socialStoryEntryTitle,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.socialStoryEntrySubtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            _EntryTile(
              icon: Icons.photo_library_outlined,
              title: l10n.socialStoryEntryMediaTitle,
              subtitle: l10n.socialStoryEntryMediaBody,
              onTap: () =>
                  Navigator.of(context).pop(SocialStoryComposerMode.media),
            ),
            const SizedBox(height: 10),
            _EntryTile(
              icon: Icons.text_fields_rounded,
              title: l10n.socialStoryEntryTextTitle,
              subtitle: l10n.socialStoryEntryTextBody,
              onTap: () =>
                  Navigator.of(context).pop(SocialStoryComposerMode.text),
              trailingIcon: isRtl
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData? trailingIcon;

  const _EntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedTrailingIcon =
        trailingIcon ??
        (Directionality.of(context) == TextDirection.rtl
            ? Icons.chevron_left_rounded
            : Icons.chevron_right_rounded);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(resolvedTrailingIcon),
          ],
        ),
      ),
    );
  }
}
