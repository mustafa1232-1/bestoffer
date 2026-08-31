import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../domain/reel_view_data.dart';
import 'reel_action_rail_v3.dart';
import 'reel_metadata_overlay_v3.dart';
import 'reel_playback_coordinator.dart';
import 'reel_video_surface_v3.dart';

/// One full-viewport reel page.
///
/// Video playback is isolated from social interaction state: likes/comments and
/// metadata never recreate the underlying VideoPlayerController.
class ReelPageV3 extends StatefulWidget {
  const ReelPageV3({
    super.key,
    required this.reel,
    required this.coordinator,
    required this.index,
    this.onPlaybackCompleted,
    this.onCreate,
    this.onTogglePlay,
    this.onToggleMute,
    this.onHoldSpeedChanged,
    this.onLike,
    this.onDoubleTapLike,
    this.onComments,
    this.onShare,
    this.onSave,
    this.onMore,
    this.onFollow,
    this.onOpenAuthor,
    this.showFollow = true,
    this.followLabel = 'Follow',
  });

  final ReelV3ViewData reel;
  final ReelPlaybackCoordinator coordinator;
  final int index;
  final VoidCallback? onPlaybackCompleted;
  final VoidCallback? onCreate;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onToggleMute;
  final ValueChanged<bool>? onHoldSpeedChanged;
  final Future<bool> Function(bool desiredLiked)? onLike;
  final Future<bool> Function(bool desiredLiked)? onDoubleTapLike;
  final VoidCallback? onComments;
  final VoidCallback? onShare;
  final VoidCallback? onSave;
  final VoidCallback? onMore;
  final VoidCallback? onFollow;
  final VoidCallback? onOpenAuthor;
  final bool showFollow;
  final String followLabel;

  @override
  State<ReelPageV3> createState() => _ReelPageV3State();
}

class _ReelPageV3State extends State<ReelPageV3>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  VideoPlayerController? _observedController;
  bool _showHeart = false;
  bool _showFastForward = false;
  bool _completionNotified = false;

  @override
  void initState() {
    super.initState();
    _heart.addStatusListener(_onHeartStatus);
    widget.coordinator.addListener(_syncObservedController);
    _syncObservedController();
  }

  @override
  void didUpdateWidget(covariant ReelPageV3 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.coordinator, widget.coordinator)) {
      oldWidget.coordinator.removeListener(_syncObservedController);
      widget.coordinator.addListener(_syncObservedController);
    }
    _syncObservedController();
  }

  @override
  void dispose() {
    if (_showFastForward) {
      widget.onHoldSpeedChanged?.call(false);
    }
    widget.coordinator.removeListener(_syncObservedController);
    _detachController();
    _heart.removeStatusListener(_onHeartStatus);
    _heart.dispose();
    super.dispose();
  }

  void _syncObservedController() {
    _attachController(widget.coordinator.controllerFor(widget.index));
  }

  Future<void> _handleLikeAction({
    required bool desiredLiked,
    bool fromDoubleTap = false,
  }) async {
    final callback = fromDoubleTap
        ? (widget.onDoubleTapLike ?? widget.onLike)
        : widget.onLike;
    if (callback == null) return;
    final success = await callback(desiredLiked);
    if (!mounted || !success || !desiredLiked) return;
    if (!_showHeart) setState(() => _showHeart = true);
    _heart.forward(from: 0);
  }

  void _onDoubleTap() {
    unawaited(_handleLikeAction(desiredLiked: true, fromDoubleTap: true));
  }

  void _setHoldSpeed(bool active) {
    if (_showFastForward != active) {
      setState(() => _showFastForward = active);
    }
    widget.onHoldSpeedChanged?.call(active);
  }

  void _onHeartStatus(AnimationStatus status) {
    if (!mounted || status != AnimationStatus.completed || !_showHeart) return;
    setState(() => _showHeart = false);
  }

  void _attachController(VideoPlayerController? controller) {
    if (identical(_observedController, controller)) return;
    _detachController();
    _observedController = controller;
    _completionNotified = false;
    _observedController?.addListener(_handleControllerTick);
  }

  void _detachController() {
    final controller = _observedController;
    if (controller != null) controller.removeListener(_handleControllerTick);
    _observedController = null;
    _completionNotified = false;
  }

  void _handleControllerTick() {
    final controller = _observedController;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    final duration = value.duration;
    final position = value.position;
    if (position <= const Duration(milliseconds: 500)) {
      _completionNotified = false;
      return;
    }
    if (duration <= Duration.zero) return;
    final remaining = duration - position;
    if (remaining <= const Duration(milliseconds: 250) &&
        !_completionNotified) {
      _completionNotified = true;
      widget.onPlaybackCompleted?.call();
    }
  }

  static const double _railReservedWidth = 72;
  static const double _sideInset = 12;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final padding = mq.padding;
    final bottomInset = padding.bottom + 16;
    final metadataMaxHeight = mq.size.height * 0.42;

    return GestureDetector(
      onTap: widget.onTogglePlay,
      onDoubleTap: _onDoubleTap,
      onLongPressStart: (_) => _setHoldSpeed(true),
      onLongPressEnd: (_) => _setHoldSpeed(false),
      onLongPressCancel: () => _setHoldSpeed(false),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: ListenableBuilder(
              listenable: widget.coordinator,
              builder: (context, _) {
                final controller =
                    widget.coordinator.controllerFor(widget.index);
                final isBuffering =
                    widget.coordinator.isBuffering(widget.index);
                final failed = widget.coordinator.isFailed(widget.index);
                final isPaused =
                    widget.index == widget.coordinator.activeIndex &&
                    widget.coordinator.isActivePaused;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ReelVideoSurfaceV3(
                      media: widget.reel.media,
                      controller: controller,
                      isBuffering: isBuffering && !failed,
                    ),
                    if (failed)
                      _PlaybackRetryOverlay(
                        onRetry: () => widget.coordinator.retry(widget.index),
                      )
                    else if (isPaused)
                      const Center(
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white70,
                          size: 78,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 12),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const _EdgeScrims(),
          if (_showHeart)
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
          if (_showFastForward)
            Positioned(
              top: padding.top + 62,
              left: 0,
              right: 0,
              child: const IgnorePointer(child: _SpeedBadge()),
            ),
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
                    ListenableBuilder(
                      listenable: widget.coordinator,
                      builder: (context, _) => _CircleGlyphButton(
                        icon: widget.coordinator.isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        onTap: widget.onToggleMute,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: _sideInset,
            bottom: bottomInset,
            child: ReelActionRailV3(
              reel: widget.reel,
              onLike: () => unawaited(
                _handleLikeAction(desiredLiked: !widget.reel.isLiked),
              ),
              onComments: widget.onComments,
              onShare: widget.onShare,
              onSave: widget.onSave,
              onMore: widget.onMore,
              onAvatar: widget.onOpenAuthor,
            ),
          ),
          Positioned(
            left: 16,
            right: _railReservedWidth + _sideInset,
            bottom: bottomInset,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: metadataMaxHeight),
              child: SingleChildScrollView(
                reverse: true,
                child: ReelMetadataOverlayV3(
                  reel: widget.reel,
                  showFollow: widget.showFollow,
                  followLabel: widget.followLabel,
                  onFollow: widget.onFollow,
                  onOpenAuthor: widget.onOpenAuthor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackRetryOverlay extends StatelessWidget {
  const _PlaybackRetryOverlay({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تعذّر تشغيل الفيديو',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
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

class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fast_forward_rounded, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text(
                '2x',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
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
