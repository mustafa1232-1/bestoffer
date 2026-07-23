import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:social_core/social_story_document.dart';

import '../../social/ui/widgets/social_story_canvas.dart';
import '../domain/story_view_data.dart';
import '../media/social_safe_image.dart';

/// Edge-to-edge 9:16 story media (§5 "StoryMediaSurfaceV3").
///
/// Vertical media fills the canvas (cover). Non-vertical media is centered
/// (contain) over a blurred fill of its own poster, so there is never a raw
/// letterbox. Video uses the [controller] once it has a first frame; until then
/// (and for image items) the poster/blur is shown.
class StoryMediaSurfaceV3 extends StatelessWidget {
  const StoryMediaSurfaceV3({super.key, required this.item, this.controller});

  final StoryV3Item item;
  final VideoPlayerController? controller;

  bool get _hasFrame {
    final c = controller;
    return c != null && c.value.isInitialized && c.value.size.width > 0;
  }

  @override
  Widget build(BuildContext context) {
    final vertical = item.media.isVertical;
    return ColoredBox(
      color: item.backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred backdrop for non-vertical media.
          if (!vertical && item.media.hasPoster)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: SocialSafeImage(
                imageUrl: item.media.posterImageUrl,
                fit: BoxFit.cover,
              ),
            ),
          Center(
            child: _hasFrame
                ? _StoryVideo(controller: controller!, cover: vertical)
                : SocialSafeImage(
                    imageUrl: item.media.posterImageUrl,
                    fit: vertical ? BoxFit.cover : BoxFit.contain,
                    showVideoGlyph: item.isVideo,
                  ),
          ),
          if (item.draft != null)
            IgnorePointer(
              child: SocialStoryCanvas(
                draft: _overlayDraft(item.draft!),
                active: true,
                showBackground: false,
                showBaseMedia: false,
                borderRadius: BorderRadius.zero,
              ),
            ),
        ],
      ),
    );
  }

  SocialStoryDraft _overlayDraft(SocialStoryDraft draft) {
    return draft.copyWith(
      layers: draft.layers
          .where(
            (layer) =>
                layer.type != SocialStoryLayerType.reelShare &&
                layer.type != SocialStoryLayerType.postShare,
          )
          .toList(growable: false),
    );
  }
}

class _StoryVideo extends StatelessWidget {
  const _StoryVideo({required this.controller, required this.cover});

  final VideoPlayerController controller;
  final bool cover;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (!cover) {
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
