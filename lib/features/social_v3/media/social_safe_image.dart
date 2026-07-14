import 'package:flutter/material.dart';

import '../../../core/media/cached_app_image.dart';
import 'social_media_presentation.dart';

/// The only image widget Social V3 uses for posters/thumbnails.
///
/// It routes through [CachedAppImage] but first runs [assertNotStreamingManifest],
/// so any attempt to hand a video/HLS URL to an image widget fails loudly in
/// debug and tests (§2 "Add assertions… reject a streaming manifest used as an
/// image URL"). When the URL is null/empty it renders the neutral Maslaki video
/// placeholder rather than a broken box — a missing poster must never look like
/// a failure.
class SocialSafeImage extends StatelessWidget {
  const SocialSafeImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.showVideoGlyph = false,
  });

  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// When true, the neutral placeholder shows a small "video" glyph (used for
  /// reel posters that have no thumbnail yet).
  final bool showVideoGlyph;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) {
      return _MaslakiMediaPlaceholder(
        width: width,
        height: height,
        showVideoGlyph: showVideoGlyph,
      );
    }

    // Contract enforcement: a manifest/MP4 must never reach an image widget.
    assertNotStreamingManifest(url, context: 'SocialSafeImage');

    // Defensive release-mode fallback: if a bad URL slips through in production,
    // degrade to the placeholder instead of a broken image.
    if (isStreamingManifestUrl(url) || isVideoFileUrl(url)) {
      return _MaslakiMediaPlaceholder(
        width: width,
        height: height,
        showVideoGlyph: true,
      );
    }

    return CachedAppImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
    );
  }
}

/// Neutral, brand-consistent placeholder shown while/instead of a poster.
class _MaslakiMediaPlaceholder extends StatelessWidget {
  const _MaslakiMediaPlaceholder({
    this.width,
    this.height,
    this.showVideoGlyph = false,
  });

  final double? width;
  final double? height;
  final bool showVideoGlyph;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D1B2A), Color(0xFF16324F)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: showVideoGlyph
            ? const Center(
                child: Icon(
                  Icons.movie_creation_outlined,
                  color: Colors.white24,
                  size: 40,
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}
