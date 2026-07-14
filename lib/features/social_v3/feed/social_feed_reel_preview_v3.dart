import 'package:flutter/material.dart';

import '../media/social_media_presentation.dart';
import '../media/social_safe_image.dart';

/// A reel preview inside the normal community feed (§4).
///
/// This is deliberately NOT the full-screen viewer — it is a bounded,
/// **rectangular** card that opens [SocialReelsScreenV3] on tap. It fixes every
/// defect visible in the failure baseline:
///  * rectangular, never circular (`ClipRRect`, never `ClipOval`);
///  * poster/thumbnail only — a playback URL can never be its image (routed
///    through [SocialSafeImage] + the media contract);
///  * a constrained aspect ratio (9:16 or 4:5), so it never becomes a giant
///    empty black area;
///  * a centered play indicator before playback;
///  * a controlled fallback when the poster is missing.
class SocialFeedReelPreviewV3 extends StatelessWidget {
  const SocialFeedReelPreviewV3({
    super.key,
    required this.media,
    this.onTap,
    this.maxAspectRatioPortrait = 9 / 16,
    this.minAspectRatioPortrait = 4 / 5,
  });

  final SocialMediaPresentation media;
  final VoidCallback? onTap;

  /// The tallest allowed preview (9:16). The preview never exceeds this.
  final double maxAspectRatioPortrait;

  /// The least-tall allowed preview (4:5).
  final double minAspectRatioPortrait;

  double get _aspectRatio {
    final natural = media.aspectRatio;
    // Clamp into [9:16 .. 4:5] so the preview stays a sane, bounded rectangle.
    if (natural == null) return maxAspectRatioPortrait;
    return natural.clamp(maxAspectRatioPortrait, minAspectRatioPortrait);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SocialSafeImage(
                imageUrl: media.posterImageUrl,
                fit: BoxFit.cover,
                showVideoGlyph: true,
              ),
              const _CenterPlayIcon(),
              // Small "reel" glyph, top-start.
              const Positioned(
                top: 10,
                left: 10,
                child: Icon(
                  Icons.movie_creation_rounded,
                  color: Colors.white,
                  size: 20,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterPlayIcon extends StatelessWidget {
  const _CenterPlayIcon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 54,
        height: 54,
        decoration: const BoxDecoration(
          color: Color(0x55000000),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
      ),
    );
  }
}
