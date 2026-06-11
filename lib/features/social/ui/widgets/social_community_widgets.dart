import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/media/media_cache_models.dart';
import '../../../../core/media/media_cache_service.dart';
import '../../../../core/platform/app_platform_capabilities.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class CommunityOverviewCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const CommunityOverviewCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          width: 146,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? scheme.primary.withValues(alpha: 0.2)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.42),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                  const Spacer(),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                label,
                textDirection: Directionality.of(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommunityPostMediaPreview extends StatelessWidget {
  final String mediaUrl;
  final bool isImage;
  final VoidCallback onOpenMedia;
  final String heroTag;
  final bool muted;
  final VoidCallback onToggleMute;

  const CommunityPostMediaPreview({
    super.key,
    required this.mediaUrl,
    required this.isImage,
    required this.onOpenMedia,
    required this.heroTag,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    if (isImage) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpenMedia,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedAppImage(
            imageUrl: mediaUrl,
            cacheIdentity: 'community_media_${mediaUrl.hashCode}',
            width: double.infinity,
            height: 250,
            fit: BoxFit.cover,
            errorWidget: (context, error, stackTrace) => const SizedBox(
              height: 250,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      );
    }

    return _InlineCommunityVideoPreview(
      mediaUrl: mediaUrl,
      heroTag: heroTag,
      onOpenMedia: onOpenMedia,
      muted: muted,
      onToggleMute: onToggleMute,
    );
  }
}

class _InlineCommunityVideoPreview extends StatefulWidget {
  final String mediaUrl;
  final String heroTag;
  final VoidCallback onOpenMedia;
  final bool muted;
  final VoidCallback onToggleMute;

  const _InlineCommunityVideoPreview({
    required this.mediaUrl,
    required this.heroTag,
    required this.onOpenMedia,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  State<_InlineCommunityVideoPreview> createState() =>
      _InlineCommunityVideoPreviewState();
}

class _InlineCommunityVideoPreviewState
    extends State<_InlineCommunityVideoPreview> {
  static final ValueNotifier<String?> _activeInlineHeroTag =
      ValueNotifier<String?>(null);

  VideoPlayerController? _video;
  Timer? _visibilityTicker;
  bool _ready = false;
  bool _initializing = false;
  bool _isVisibleEnough = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _activeInlineHeroTag.addListener(_onActiveInlineVideoChanged);
    _startVisibilityWatcher();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPlaybackForViewport(force: true);
    });
  }

  Future<void> _ensureVideoInitialized() async {
    if (_ready || _initializing || !appSupportsInlineVideoPlayback) return;
    try {
      _initializing = true;
      final uri = Uri.tryParse(widget.mediaUrl);
      if (uri == null) {
        if (!mounted) return;
        setState(() {
          _error = context.l10n.socialCommunityInvalidVideoUrl;
          _initializing = false;
        });
        return;
      }
      final source = await MediaCacheService.instance.resolveVideoSource(
        url: widget.mediaUrl,
        cacheIdentity: 'community_video_${widget.mediaUrl.hashCode}',
        scope: MediaCacheScope.public,
      );
      final controller = source.isLocalFile
          ? VideoPlayerController.file(source.file!)
          : VideoPlayerController.networkUrl(source.uri);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setPlaybackSpeed(1.0);
      await controller.setVolume(widget.muted ? 0 : 1);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = controller;
        _ready = true;
        _initializing = false;
      });
      _syncPlaybackForViewport(force: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.socialCommunityVideoLoadFailed;
        _initializing = false;
      });
    }
  }

  void _startVisibilityWatcher() {
    _visibilityTicker?.cancel();
    _visibilityTicker = Timer.periodic(
      const Duration(milliseconds: 220),
      (_) => _syncPlaybackForViewport(),
    );
  }

  void _onActiveInlineVideoChanged() {
    final video = _video;
    if (!mounted || video == null || !video.value.isInitialized) return;
    final isActive = _activeInlineHeroTag.value == widget.heroTag;
    if (!isActive && video.value.isPlaying) {
      unawaited(video.pause());
    } else if (isActive && _isVisibleEnough && !video.value.isPlaying) {
      unawaited(video.play());
    }
  }

  void _syncPlaybackForViewport({bool force = false}) {
    if (!mounted || !appSupportsInlineVideoPlayback) return;
    final route = ModalRoute.of(context);
    final routeIsCurrent = route?.isCurrent ?? true;

    final render = context.findRenderObject();
    if (render is! RenderBox || !render.attached) return;

    final topLeft = render.localToGlobal(Offset.zero);
    final bottomRight = render.localToGlobal(
      Offset(render.size.width, render.size.height),
    );
    final screenSize = MediaQuery.sizeOf(context);
    final screenRect = Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
    final itemRect = Rect.fromPoints(topLeft, bottomRight);
    final visibleRect = itemRect.intersect(screenRect);

    final totalArea = math.max(1.0, itemRect.width * itemRect.height);
    final visibleArea = math.max(0.0, visibleRect.width * visibleRect.height);
    final ratio = visibleArea / totalArea;
    final visibleHeightRatio =
        visibleRect.height / math.max(1.0, itemRect.height);
    final visibleWidthRatio = visibleRect.width / math.max(1.0, itemRect.width);
    final preloadThreshold = force ? 0.04 : 0.08;
    final threshold = force ? 0.06 : 0.18;
    final shouldInitialize =
        routeIsCurrent &&
        ratio >= preloadThreshold &&
        visibleHeightRatio >= preloadThreshold &&
        visibleWidthRatio >= 0.45;
    final shouldPlay =
        routeIsCurrent &&
        ratio >= threshold &&
        visibleHeightRatio >= threshold &&
        visibleWidthRatio >= 0.55;

    _isVisibleEnough = shouldPlay;
    if (shouldInitialize && _video == null && _error == null) {
      unawaited(_ensureVideoInitialized());
      if (!shouldPlay) return;
    }

    final video = _video;
    if (video == null || !video.value.isInitialized) return;

    if (shouldPlay) {
      if (_activeInlineHeroTag.value != widget.heroTag) {
        _activeInlineHeroTag.value = widget.heroTag;
      }
      if (!video.value.isPlaying) {
        unawaited(video.play());
      }
    } else {
      if (_activeInlineHeroTag.value == widget.heroTag) {
        _activeInlineHeroTag.value = null;
      }
      if (video.value.isPlaying) {
        unawaited(video.pause());
      }
    }
  }

  @override
  void didUpdateWidget(covariant _InlineCommunityVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      _video?.dispose();
      _video = null;
      _ready = false;
      _error = null;
      _initializing = false;
      _isVisibleEnough = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncPlaybackForViewport(force: true);
      });
      return;
    }
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (oldWidget.muted != widget.muted) {
      unawaited(video.setVolume(widget.muted ? 0 : 1));
    }
  }

  @override
  void dispose() {
    _visibilityTicker?.cancel();
    _activeInlineHeroTag.removeListener(_onActiveInlineVideoChanged);
    if (_activeInlineHeroTag.value == widget.heroTag) {
      _activeInlineHeroTag.value = null;
    }
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unsupportedMessage = l10n.socialCommunityVideoUnsupported;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : (MediaQuery.of(context).size.width - 24);
        final rawAspect = _ready ? _video?.value.aspectRatio ?? 0 : (9 / 16);
        final aspect = (rawAspect.isFinite && rawAspect > 0.01)
            ? rawAspect
            : (9 / 16);
        final previewHeight = (maxWidth / aspect).clamp(220.0, 460.0);

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onOpenMedia,
          child: Container(
            height: previewHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.black,
            ),
            clipBehavior: Clip.antiAlias,
            child: !appSupportsInlineVideoPlayback
                ? Center(
                    child: Text(
                      unsupportedMessage,
                      textDirection: Directionality.of(context),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      textDirection: Directionality.of(context),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : !_ready
                ? Center(
                    child: _initializing
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : Icon(
                            Icons.play_circle_outline_rounded,
                            size: 54,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: _video!.value.size.width,
                          height: _video!.value.size.height,
                          child: VideoPlayer(_video!),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: FilledButton.tonalIcon(
                          onPressed: widget.onToggleMute,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.46,
                            ),
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: Icon(
                            widget.muted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            size: 16,
                          ),
                          label: Text(
                            widget.muted
                                ? l10n.socialCommunityMuted
                                : l10n.socialCommunitySoundOn,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class CommunityActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const CommunityActionChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                textDirection: Directionality.of(context),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String communityKindLabel(BuildContext context, String kind) {
  switch (kind.trim().toLowerCase()) {
    case 'image':
      return context.l10n.commonImage;
    case 'video':
      return context.l10n.socialCommunityKindReel;
    case 'merchant_review':
      return context.l10n.socialCommunityKindReview;
    default:
      return context.l10n.socialCommunityKindPost;
  }
}
