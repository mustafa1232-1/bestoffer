import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../domain/reel_view_data.dart';
import 'reel_action_rail_v3.dart';
import 'reel_metadata_overlay_v3.dart';
import 'reel_video_surface_v3.dart';

/// One full-viewport reel page (§3 "ReelPageV3").
///
/// Layout hierarchy, top to bottom of the stack:
///   video surface (fills viewport, cover) → gradient scrims → top bar
///   ("ريلز") → right action rail → bottom metadata. No AppBar, no outer card,
///   no gold border, no rounded container around the video.
class ReelPageV3 extends StatefulWidget {
  const ReelPageV3({
    super.key,
    required this.reel,
    this.controller,
    this.isBuffering = false,
    this.isPaused = false,
    this.isMuted = false,
    this.onCreate,
    this.onTogglePlay,
    this.onToggleMute,
    this.onLike,
    this.onDoubleTapLike,
    this.onComments,
    this.onShare,
    this.onSave,
    this.onMore,
    this.onFollow,
    this.onOpenAuthor,
    this.showFollow = true,
  });

  final ReelV3ViewData reel;
  final VideoPlayerController? controller;
  final bool isBuffering;
  final bool isPaused;
  final bool isMuted;

  final VoidCallback? onCreate;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onToggleMute;
  final VoidCallback? onLike;
  final VoidCallback? onDoubleTapLike;
  final VoidCallback? onComments;
  final VoidCallback? onShare;
  final VoidCallback? onSave;
  final VoidCallback? onMore;
  final VoidCallback? onFollow;
  final VoidCallback? onOpenAuthor;
  final bool showFollow;

  @override
  State<ReelPageV3> createState() => _ReelPageV3State();
}

class _ReelPageV3State extends State<ReelPageV3>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    _heart.forward(from: 0);
    widget.onDoubleTapLike?.call();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return GestureDetector(
      onTap: widget.onTogglePlay,
      onDoubleTap: _onDoubleTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ReelVideoSurfaceV3(
            media: widget.reel.media,
            controller: widget.controller,
            isBuffering: widget.isBuffering,
          ),
          // Top + bottom scrims so white overlays stay legible over any frame.
          const _EdgeScrims(),

          // Center pause glyph when explicitly paused.
          if (widget.isPaused)
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white70,
                size: 78,
                shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
              ),
            ),

          // Double-tap heart burst.
          Center(
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.6, end: 1.25).animate(
                CurvedAnimation(parent: _heart, curve: Curves.easeOutBack),
              ),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.9, end: 0.0).animate(
                  CurvedAnimation(parent: _heart, curve: Curves.easeIn),
                ),
                child: const Icon(
                  Icons.favorite,
                  color: Color(0xFFFF3B5C),
                  size: 120,
                ),
              ),
            ),
          ),

          // Top bar: "ريلز" + mute control (no toolbar / AppBar).
          Positioned(
            top: padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ريلز',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                ),
                Row(
                  children: [
                    if (widget.onCreate != null)
                      _CircleGlyphButton(
                        icon: Icons.videocam_rounded,
                        onTap: widget.onCreate,
                      ),
                    if (widget.onCreate != null) const SizedBox(width: 8),
                    _CircleGlyphButton(
                      icon: widget.isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      onTap: widget.onToggleMute,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Right action rail.
          Positioned(
            right: 8,
            bottom: padding.bottom + 96,
            child: ReelActionRailV3(
              reel: widget.reel,
              onLike: widget.onLike,
              onComments: widget.onComments,
              onShare: widget.onShare,
              onSave: widget.onSave,
              onMore: widget.onMore,
              onAvatar: widget.onOpenAuthor,
            ),
          ),

          // Bottom metadata (leaves room for the bottom nav overlay).
          Positioned(
            left: 16,
            right: 84,
            bottom: padding.bottom + 84,
            child: ReelMetadataOverlayV3(
              reel: widget.reel,
              showFollow: widget.showFollow,
              onFollow: widget.onFollow,
              onOpenAuthor: widget.onOpenAuthor,
            ),
          ),
        ],
      ),
    );
  }
}

class _EdgeScrims extends StatelessWidget {
  const _EdgeScrims();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        children: [
          Container(
            height: 120,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0x00000000)],
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: 200,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x99000000), Color(0x00000000)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleGlyphButton extends StatelessWidget {
  const _CircleGlyphButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color(0x33000000),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
