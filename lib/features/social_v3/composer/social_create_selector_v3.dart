import 'package:flutter/material.dart';

import 'reel_gallery_entry_v3.dart';

/// The single V3 creation selector (§4). Replaces the old floating "Create"
/// button behavior: choosing Reel opens the native video gallery directly,
/// Story opens the blank V3 story editor, Post opens the V3 post composer.
///
/// Returns true when a create flow was completed.
Future<bool?> showSocialCreateSelectorV3(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _CreateSelectorSheet(),
  );
  if (choice == null || !context.mounted) return null;
  switch (choice) {
    case 'reel':
      await openReelComposerV3(context);
      return true;
    case 'story':
      await openStoryComposerV3Text(context);
      return true;
    case 'post':
      return await openPostComposerV3(context);
  }
  return null;
}

class _CreateSelectorSheet extends StatelessWidget {
  const _CreateSelectorSheet();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tile(
            icon: Icons.grid_on_rounded,
            title: 'منشور',
            subtitle: 'صور أو فيديو من المعرض',
            value: 'post',
          ),
          _Tile(
            icon: Icons.amp_stories_rounded,
            title: 'قصة',
            subtitle: 'صورة أو فيديو تختفي بعد 24 ساعة',
            value: 'story',
          ),
          _Tile(
            icon: Icons.movie_creation_rounded,
            title: 'ريل',
            subtitle: 'فيديو رأسي بملء الشاشة',
            value: 'reel',
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}
