import 'package:flutter/material.dart';
import 'package:social_core/social_story_document.dart';

import '../../social/ui/social_profile_screen.dart';
import '../../social/ui/widgets/social_story_canvas.dart';

/// Replays the existing editor document without creating another video player.
class ReelDocumentOverlay extends StatelessWidget {
  const ReelDocumentOverlay({super.key, required this.style});

  final Map<String, dynamic> style;

  @override
  Widget build(BuildContext context) {
    if (style['layers'] is! List || (style['layers'] as List).isEmpty) {
      return const SizedBox.shrink();
    }
    final draft = SocialStoryDraft.fromJson(style);
    return Center(
      child: SocialStoryCanvas(
        draft: draft.copyWith(
          layers: draft.layers
              .map((layer) => layer.copyWith(locked: true))
              .toList(),
        ),
        showBackground: false,
        showBaseMedia: false,
        borderRadius: BorderRadius.zero,
        onLayerTap: (layer) {
          final userId = layer.mentionedUserId;
          if (layer.type != SocialStoryLayerType.mention ||
              userId == null ||
              userId <= 0) {
            return;
          }
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => SocialProfileScreen(
                userId: userId,
                initialName: layer.displayLabel,
              ),
            ),
          );
        },
      ),
    );
  }
}
