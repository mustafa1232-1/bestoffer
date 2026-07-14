import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/media/media_cache_models.dart';
import '../../../../core/media/media_cache_service.dart';
import '../../models/social_models.dart';
import 'social_identity_view.dart';
import 'social_mention_hashtag_text.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialReelCard extends StatefulWidget {
  final SocialReelItem item;
  final bool active;
  final bool muted;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenComments;
  final VoidCallback? onOpenMerchantLink;
  final VoidCallback? onToggleMute;
  final Future<void> Function()? onToggleLike;
  final Future<void> Function()? onToggleSave;
  final Future<void> Function()? onShare;
  final Future<void> Function()? onShareToStory;

  const SocialReelCard({
    super.key,
    required this.item,
    required this.active,
    required this.muted,
    this.onOpenProfile,
    this.onOpenComments,
    this.onOpenMerchantLink,
    this.onToggleMute,
    this.onToggleLike,
    this.onToggleSave,
    this.onShare,
    this.onShareToStory,
  });

  @override
  State<SocialReelCard> createState() => _SocialReelCardState();
}

class _SocialReelCardState extends State<SocialReelCard> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _videoFailed = false;
  bool _speedBoosting = false;
  bool _showMuteFeedback = false;
  Timer? _muteFeedbackTimer;
  int _videoGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant SocialReelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.post.id != widget.item.post.id) {
      _disposeVideo();
      _initialize();
      return;
    }
    if (oldWidget.muted != widget.muted && _controller != null) {
      unawaited(_controller!.setVolume(widget.muted ? 0 : 1));
    }
    _syncPlayback();
  }

  Future<void> _initialize() async {
    final generation = ++_videoGeneration;
    if (mounted) {
      setState(() {
        _ready = false;
        _videoFailed = false;
      });
    }
    final url =
        widget.item.post.asset?.playbackUrl ??
        widget.item.post.asset?.normalizedUrl ??
        widget.item.post.mediaUrl ??
        '';
    if (url.trim().isEmpty) return;
    final CachedVideoSource source;
    try {
      source = await MediaCacheService.instance
          .resolveVideoSource(
            url: url,
            cacheIdentity: 'reel_video_${widget.item.post.id}',
            version: widget.item.post.updatedAt?.toIso8601String(),
            scope: MediaCacheScope.public,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      if (!mounted || generation != _videoGeneration) return;
      setState(() => _videoFailed = true);
      return;
    }
    if (!mounted || generation != _videoGeneration) return;
    final controller = source.isLocalFile
        ? VideoPlayerController.file(source.file!)
        : VideoPlayerController.networkUrl(source.uri);
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 8));
      await controller.setLooping(true);
      await controller.setVolume(widget.muted ? 0 : 1);
      if (!mounted || generation != _videoGeneration) {
        await controller.dispose();
        return;
      }
      setState(() => _ready = true);
      _syncPlayback();
    } catch (_) {
      if (identical(_controller, controller)) {
        _controller = null;
      }
      await controller.dispose();
      if (!mounted || generation != _videoGeneration) return;
      setState(() {
        _ready = false;
        _videoFailed = true;
      });
    }
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.active) {
      controller.play();
    } else {
      if (_speedBoosting) {
        unawaited(controller.setPlaybackSpeed(1.0));
        _speedBoosting = false;
      }
      controller.pause();
    }
  }

  void _disposeVideo() {
    _videoGeneration++;
    _muteFeedbackTimer?.cancel();
    _controller?.dispose();
    _controller = null;
    _ready = false;
    _videoFailed = false;
    _speedBoosting = false;
  }

  Future<void> _toggleMuteWithFeedback() async {
    widget.onToggleMute?.call();
    if (!mounted) return;
    _muteFeedbackTimer?.cancel();
    setState(() => _showMuteFeedback = true);
    _muteFeedbackTimer = Timer(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      setState(() => _showMuteFeedback = false);
    });
  }

  Future<void> _setTemporarySpeedBoost(bool enabled) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final nextSpeed = enabled ? 2.0 : 1.0;
    try {
      await controller.setPlaybackSpeed(nextSpeed);
      if (!mounted) return;
      setState(() => _speedBoosting = enabled);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final post = widget.item.post;
    final poster =
        post.asset?.thumbnailUrl ??
        post.asset?.posterUrl ??
        post.asset?.playbackUrl ??
        post.asset?.normalizedUrl ??
        post.mediaUrl;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF060A14), Color(0xFF101A32)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready && _controller != null)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else if ((poster ?? '').trim().isNotEmpty)
            CachedAppImage(
              imageUrl: poster!,
              cacheIdentity: 'reel_poster_${post.id}',
              version: post.updatedAt?.toIso8601String(),
              fit: BoxFit.cover,
              errorWidget: (context, error, stackTrace) => const ColoredBox(
                color: Color(0xFF0E1730),
                child: Center(
                  child: Icon(
                    Icons.ondemand_video_outlined,
                    color: Colors.white70,
                  ),
                ),
              ),
            )
          else
            const ColoredBox(
              color: Color(0xFF0E1730),
              child: Center(
                child: Icon(
                  Icons.ondemand_video_outlined,
                  color: Colors.white70,
                ),
              ),
            ),
          if (_videoFailed && !_ready)
            const Center(child: _VideoUnavailablePill()),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.72),
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.active ? _toggleMuteWithFeedback : null,
              onLongPressStart: widget.active
                  ? (_) => unawaited(_setTemporarySpeedBoost(true))
                  : null,
              onLongPressEnd: widget.active
                  ? (_) => unawaited(_setTemporarySpeedBoost(false))
                  : null,
              onLongPressCancel: widget.active
                  ? () => unawaited(_setTemporarySpeedBoost(false))
                  : null,
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 96,
            child: _ReelEdgeGestureZone(
              onTap: widget.active ? _toggleMuteWithFeedback : null,
              onLongPressStart: widget.active
                  ? () => unawaited(_setTemporarySpeedBoost(true))
                  : null,
              onLongPressEnd: widget.active
                  ? () => unawaited(_setTemporarySpeedBoost(false))
                  : null,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 96,
            child: _ReelEdgeGestureZone(
              onTap: widget.active ? _toggleMuteWithFeedback : null,
              onLongPressStart: widget.active
                  ? () => unawaited(_setTemporarySpeedBoost(true))
                  : null,
              onLongPressEnd: widget.active
                  ? () => unawaited(_setTemporarySpeedBoost(false))
                  : null,
            ),
          ),
          Positioned(
            left: 14,
            right: 86,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: widget.onOpenProfile,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundImage:
                            (post.author.imageUrl ?? '').trim().isNotEmpty
                            ? appCachedImageProvider(
                                post.author.imageUrl!,
                                cacheIdentity: 'user_avatar_${post.author.id}',
                                version: post.updatedAt?.toIso8601String(),
                              )
                            : null,
                        child: (post.author.imageUrl ?? '').trim().isEmpty
                            ? const Icon(Icons.person_outline)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SocialIdentityView(
                          author: post.author,
                          showRoleFallback: false,
                          primaryStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                          secondaryStyle: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (post.caption.trim().isNotEmpty)
                  SocialMentionHashtagText(
                    text: post.caption.trim(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ReelPill(
                      icon: Icons.visibility_outlined,
                      label: '${widget.item.metrics.viewsCount}',
                    ),
                    _ReelPill(
                      icon: Icons.repeat_rounded,
                      label: '${widget.item.metrics.replayCount}',
                    ),
                    _ReelPill(
                      icon: Icons.timer_outlined,
                      label:
                          '${(widget.item.metrics.averageWatchDurationMs / 1000).toStringAsFixed(1)}s',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_showMuteFeedback)
            Center(
              child: _CenterFeedbackPill(
                icon: widget.muted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                label: widget.muted
                    ? l10n.socialReelUnmute
                    : l10n.socialReelMute,
              ),
            ),
          if (_speedBoosting)
            const Positioned(
              top: 98,
              left: 0,
              right: 0,
              child: Center(
                child: _CenterFeedbackPill(
                  icon: Icons.speed_rounded,
                  label: '2x',
                ),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 24,
            child: Column(
              children: [
                _ActionBubble(
                  icon: post.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: '${post.likesCount}',
                  color: post.isLiked ? const Color(0xFFE65073) : Colors.white,
                  onTap: widget.onToggleLike,
                ),
                const SizedBox(height: 12),
                _ActionBubble(
                  icon: Icons.mode_comment_outlined,
                  label: '${post.commentsCount}',
                  onTap: widget.onOpenComments == null
                      ? null
                      : () async => widget.onOpenComments!.call(),
                ),
                const SizedBox(height: 12),
                _ActionBubble(
                  icon: post.isSaved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_outline_rounded,
                  label: '${post.savesCount}',
                  color: post.isSaved ? const Color(0xFF4B7CFF) : Colors.white,
                  onTap: widget.onToggleSave,
                ),
                const SizedBox(height: 12),
                _ActionBubble(
                  icon: Icons.send_rounded,
                  label: l10n.commonShare,
                  onTap: widget.onShare,
                ),
                const SizedBox(height: 12),
                _ActionBubble(
                  icon: Icons.add_to_photos_outlined,
                  label: l10n.socialReelCardStory,
                  onTap: widget.onShareToStory,
                ),
                if (post.contentLink != null || post.merchantId != null) ...[
                  const SizedBox(height: 12),
                  _ActionBubble(
                    icon: Icons.storefront_outlined,
                    label: l10n.socialReelCardLink,
                    onTap: widget.onOpenMerchantLink == null
                        ? null
                        : () async => widget.onOpenMerchantLink!.call(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoUnavailablePill extends StatelessWidget {
  const _VideoUnavailablePill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'Video unavailable',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReelEdgeGestureZone extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;

  const _ReelEdgeGestureZone({
    this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      onLongPressStart: onLongPressStart == null
          ? null
          : (_) => onLongPressStart!.call(),
      onLongPressEnd: onLongPressEnd == null
          ? null
          : (_) => onLongPressEnd!.call(),
      onLongPressCancel: onLongPressEnd,
      child: const SizedBox.expand(),
    );
  }
}

class _CenterFeedbackPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CenterFeedbackPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBubble extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function()? onTap;

  const _ActionBubble({
    required this.icon,
    required this.label,
    this.color = Colors.white,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap == null ? null : () => onTap!.call(),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ReelPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
