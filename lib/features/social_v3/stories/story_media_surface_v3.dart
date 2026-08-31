import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:social_core/social_story_document.dart';
import 'package:video_player/video_player.dart';

import '../../social/ui/widgets/social_story_canvas.dart';
import '../domain/story_view_data.dart';
import '../media/social_safe_image.dart';

/// Reserved transform layer written by StoryComposerV3. Keeping this marker in
/// storyStyle preserves backwards compatibility with existing Story documents
/// while allowing the viewer to reproduce the exact crop/zoom/pan/rotation the
/// author chose before publishing.
const String _baseMediaTransformLayerId = '__base_media_transform_v1__';

/// Edge-to-edge 9:16 story media.
///
/// Existing stories without an explicit transform keep the historical behavior:
/// vertical media covers the canvas, while non-vertical media is contained over
/// a blurred backdrop. New stories can persist Fit/Fill + pan/zoom/rotation and
/// the exact transform is replayed here after publishing.
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
    final transform = _StoryMediaTransform.fromDraft(
      item.draft,
      fallbackVertical: item.media.isVertical,
    );
    final showBackdrop =
        transform.fit == BoxFit.contain || !item.media.isVertical;

    return ColoredBox(
      color: item.backgroundColor,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showBackdrop && item.media.hasPoster) ...[
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: SocialSafeImage(
                  imageUrl: item.media.posterImageUrl,
                  fit: BoxFit.cover,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                ),
              ),
            ],
            Positioned.fill(
              child: _TransformedStoryMedia(
                transform: transform,
                child: _hasFrame
                    ? _StoryVideo(
                        controller: controller!,
                        fit: transform.fit,
                      )
                    : SocialSafeImage(
                        imageUrl: item.media.posterImageUrl,
                        fit: transform.fit,
                        showVideoGlyph: item.isVideo,
                      ),
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
      ),
    );
  }

  SocialStoryDraft _overlayDraft(SocialStoryDraft draft) {
    return draft.copyWith(
      layers: draft.layers
          .where(
            (layer) =>
                layer.id != _baseMediaTransformLayerId &&
                layer.type != SocialStoryLayerType.reelShare &&
                layer.type != SocialStoryLayerType.postShare,
          )
          .toList(growable: false),
    );
  }
}

class _StoryMediaTransform {
  const _StoryMediaTransform({
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.fit,
  });

  final double x;
  final double y;
  final double scale;
  final double rotation;
  final BoxFit fit;

  factory _StoryMediaTransform.fromDraft(
    SocialStoryDraft? draft, {
    required bool fallbackVertical,
  }) {
    SocialStoryLayer? layer;
    if (draft != null) {
      for (final candidate in draft.layers) {
        if (candidate.id == _baseMediaTransformLayerId) {
          layer = candidate;
          break;
        }
      }
    }

    if (layer == null) {
      return _StoryMediaTransform(
        x: 0.5,
        y: 0.5,
        scale: 1,
        rotation: 0,
        fit: fallbackVertical ? BoxFit.cover : BoxFit.contain,
      );
    }

    final fitValue = (layer.text ?? 'contain').trim().toLowerCase();
    return _StoryMediaTransform(
      x: layer.x.clamp(-0.25, 1.25).toDouble(),
      y: layer.y.clamp(-0.25, 1.25).toDouble(),
      scale: layer.scale.clamp(0.5, 5.0).toDouble(),
      rotation: layer.rotation,
      fit: fitValue == 'cover' ? BoxFit.cover : BoxFit.contain,
    );
  }
}

class _TransformedStoryMedia extends StatelessWidget {
  const _TransformedStoryMedia({required this.transform, required this.child});

  final _StoryMediaTransform transform;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
        final dx = (transform.x - 0.5) * width;
        final dy = (transform.y - 0.5) * height;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: transform.rotation,
            child: Transform.scale(
              scale: transform.scale,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _StoryVideo extends StatelessWidget {
  const _StoryVideo({required this.controller, required this.fit});

  final VideoPlayerController controller;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return const SizedBox.shrink();
    }
    return ClipRect(
      child: FittedBox(
        fit: fit,
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
