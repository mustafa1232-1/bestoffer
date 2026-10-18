import 'package:flutter/material.dart';
import 'package:core_design_system/core_design_system.dart'
    show showMaslakiBottomSheet;

import '../../../core/i18n/locale_text.dart';
import 'reel_gallery_entry_v3.dart';

/// The single V3 creation selector. Choosing a type opens the production V3
/// composer for that content.
Future<bool?> showSocialCreateSelectorV3(BuildContext context) async {
  final choice = await showMaslakiBottomSheet<String>(
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
    case 'review':
      return openPostComposerV3MerchantReview(context);
    case 'post':
      return openPostComposerV3(context);
  }
  return null;
}

class _CreateSelectorSheet extends StatelessWidget {
  const _CreateSelectorSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          _Tile(
            icon: Icons.grid_on_rounded,
            title: context.lt(ar: 'منشور', en: 'Post'),
            subtitle: context.lt(
              ar: 'صور أو فيديو من المعرض',
              en: 'Photos or video from your gallery',
            ),
            value: 'post',
          ),
          _Tile(
            icon: Icons.amp_stories_rounded,
            title: context.lt(ar: 'ستوري', en: 'Story'),
            subtitle: context.lt(
              ar: 'صورة أو فيديو تختفي بعد 24 ساعة',
              en: 'A photo or video that disappears after 24 hours',
            ),
            value: 'story',
          ),
          _Tile(
            icon: Icons.movie_creation_rounded,
            title: context.lt(ar: 'ريل', en: 'Reel'),
            subtitle: context.lt(
              ar: 'فيديو رأسي بملء الشاشة',
              en: 'Full-screen vertical video',
            ),
            value: 'reel',
          ),
          _Tile(
            icon: Icons.rate_review_rounded,
            title: context.lt(ar: 'مراجعة متجر', en: 'Store review'),
            subtitle: context.lt(
              ar: 'اختر متجرًا وانشر تقييمك وتجربتك',
              en: 'Choose a store and share your rating',
            ),
            value: 'review',
          ),
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
