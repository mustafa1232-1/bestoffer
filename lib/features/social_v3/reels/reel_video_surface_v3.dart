import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../media/social_media_presentation.dart';
import '../media/social_safe_image.dart';

/// The visual surface for one reel's video (§3 "ReelVideoSurfaceV3").
///
/// Invariants this widget guarantees:
///  * The poster is shown until the video produces its first frame — never a
///    blank/black gap and never a spinner-over-nothing.
///  * The video fills the viewport with [BoxFit.cover] (no letterboxing by
///    default), preserving aspect ratio with no circular clipping, no square
///    feed-card container, no gold border, no card padding.
///  * A missing playback URL never fakes a playing state — it shows the poster
///    (and, for the owner, the caller decides whether to show a retry).
///
/// It takes a *nullable* [controller] so the widget can be rendered
/// deterministically in golden tests (null controller → poster state).
class ReelVideoSurfaceV3 extends StatelessWidget {
  const ReelVideoSurfaceV3({
    super.key,
    required this.media,
    this.controller,
    this.isBuffering = false,
    this.fit = BoxFit.cover,
  });

  final SocialMediaPresentation media;
  final VideoPlayerController? controller;

  /// Explicit buffering flag (the coordinator drives this) so goldens can force
  /// the buffering state without a live controller.
  final bool isBuffering;

  /// Cover by default; a caller may pass [BoxFit.contain] for an explicit
  /// user-triggered "fit" mode.
  final BoxFit fit;

  bool get _hasFirstFrame {
    final c = controller;
    return c != null && c.value.isInitialized && c.value.size.width > 0;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Poster underlay — always present so there is never a blank frame.
          SocialSafeImage(
            imageUrl: media.posterImageUrl,
            fit: fit,
            showVideoGlyph: true,
          ),
          if (_hasFirstFrame)
            _CoveredVideo(controller: controller!, fit: fit),
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

/// Fills the viewport with the video, preserving aspect ratio via cover/contain.
class _CoveredVideo extends StatelessWidget {
  const _CoveredVideo({required this.controller, required this.fit});

  final VideoPlayerController controller;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
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
