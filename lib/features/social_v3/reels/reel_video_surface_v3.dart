import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../media/social_media_presentation.dart';
import '../media/social_safe_image.dart';

/// The visual surface for one reel's video.
///
/// The foreground preserves the video's natural aspect ratio by default. When
/// it does not match the phone viewport, a blurred poster/frame fills the
/// background rather than cropping the actual video. Callers can still request
/// [BoxFit.cover] explicitly for a deliberate fill/crop presentation.
class ReelVideoSurfaceV3 extends StatelessWidget {
  const ReelVideoSurfaceV3({
    super.key,
    required this.media,
    this.controller,
    this.isBuffering = false,
    this.fit = BoxFit.contain,
  });

  final SocialMediaPresentation media;
  final VideoPlayerController? controller;
  final bool isBuffering;
  final BoxFit fit;

  bool get _hasFirstFrame {
    final c = controller;
    return c != null && c.value.isInitialized && c.value.size.width > 0;
  }

  bool get _usesNaturalFit => fit == BoxFit.contain || fit == BoxFit.scaleDown;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Fill unused viewport space with a soft version of the same content.
          // This keeps square/landscape reels attractive without cutting their
          // edges, and doubles as an immediate first-frame placeholder.
          if (_usesNaturalFit)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: SocialSafeImage(
                imageUrl: media.posterImageUrl,
                fit: BoxFit.cover,
              ),
            ),
          if (_usesNaturalFit)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.34),
              ),
            ),
          Center(
            child: _hasFirstFrame
                ? _FittedVideo(controller: controller!, fit: fit)
                : SocialSafeImage(
                    imageUrl: media.posterImageUrl,
                    fit: fit,
                    showVideoGlyph: true,
                  ),
          ),
          if (isBuffering && !_hasFirstFrame)
            const Center(
              child: SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FittedVideo extends StatelessWidget {
  const _FittedVideo({required this.controller, required this.fit});

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
