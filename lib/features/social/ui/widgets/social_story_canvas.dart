import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/media/media_cache_models.dart';
import '../../../../core/media/media_cache_service.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../models/social_story_document.dart';
import 'social_story_layer_widget.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialStoryCanvas extends StatefulWidget {
  final SocialStoryDraft draft;
  final String? selectedLayerId;
  final bool drawEnabled;
  final String? remoteMediaUrl;
  final String? remoteMediaKind;
  final Widget? baseMedia;
  final bool showBackground;
  final bool showBaseMedia;
  final bool active;
  final BorderRadius borderRadius;
  final ValueChanged<String?>? onSelectLayer;
  final ValueChanged<SocialStoryLayer>? onLayerChanged;
  final ValueChanged<SocialStoryDrawStroke>? onDrawStroke;
  final ValueChanged<SocialStoryLayer>? onLayerTap;
  final VoidCallback? onAttachmentTap;

  const SocialStoryCanvas({
    super.key,
    required this.draft,
    this.selectedLayerId,
    this.drawEnabled = false,
    this.remoteMediaUrl,
    this.remoteMediaKind,
    this.baseMedia,
    this.showBackground = true,
    this.showBaseMedia = true,
    this.active = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.onSelectLayer,
    this.onLayerChanged,
    this.onDrawStroke,
    this.onLayerTap,
    this.onAttachmentTap,
  });

  @override
  State<SocialStoryCanvas> createState() => _SocialStoryCanvasState();
}

class _SocialStoryCanvasState extends State<SocialStoryCanvas> {
  final List<SocialStoryPoint> _activePoints = <SocialStoryPoint>[];

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final sortedLayers = [...widget.draft.layers]
            ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
          return ClipRRect(
            borderRadius: widget.borderRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.showBackground)
                  _StoryBackground(draft: widget.draft),
                if (widget.showBaseMedia)
                  _StoryBaseMedia(
                    draft: widget.draft,
                    remoteMediaUrl: widget.remoteMediaUrl,
                    remoteMediaKind: widget.remoteMediaKind,
                    child: widget.baseMedia,
                  ),
                CustomPaint(
                  painter: _StoryDrawPainter(
                    strokes: sortedLayers
                        .where(
                          (layer) => layer.type == SocialStoryLayerType.draw,
                        )
                        .expand((layer) => layer.strokes)
                        .toList(growable: false),
                    livePoints: _activePoints,
                  ),
                ),
                ...sortedLayers
                    .where((layer) => layer.type != SocialStoryLayerType.draw)
                    .map(
                      (layer) => SocialStoryLayerWidget(
                        key: ValueKey(layer.id),
                        layer: layer,
                        selected: widget.selectedLayerId == layer.id,
                        canvasSize: size,
                        onTap: () {
                          if (widget.onLayerTap != null) {
                            widget.onLayerTap!.call(layer);
                            return;
                          }
                          widget.onSelectLayer?.call(layer.id);
                        },
                        onChanged: widget.onLayerChanged ?? (_) {},
                        child: _buildLayerChild(context, layer),
                      ),
                    ),
                if (widget.drawEnabled)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        setState(() {
                          _activePoints
                            ..clear()
                            ..add(
                              SocialStoryPoint(
                                x: details.localPosition.dx / size.width,
                                y: details.localPosition.dy / size.height,
                              ),
                            );
                        });
                      },
                      onPanUpdate: (details) {
                        setState(() {
                          _activePoints.add(
                            SocialStoryPoint(
                              x: details.localPosition.dx / size.width,
                              y: details.localPosition.dy / size.height,
                            ),
                          );
                        });
                      },
                      onPanEnd: (_) {
                        if (_activePoints.length < 2) {
                          setState(_activePoints.clear);
                          return;
                        }
                        widget.onDrawStroke?.call(
                          SocialStoryDrawStroke(
                            color: '#FFFFFF',
                            width: 4,
                            points: List<SocialStoryPoint>.from(_activePoints),
                          ),
                        );
                        setState(_activePoints.clear);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLayerChild(BuildContext context, SocialStoryLayer layer) {
    switch (layer.type) {
      case SocialStoryLayerType.text:
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: layer.backgroundColor == null
                  ? Colors.transparent
                  : colorFromHex(
                      layer.backgroundColor,
                      fallback: Colors.transparent,
                    ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                layer.text?.trim().isNotEmpty == true
                    ? layer.text!.trim()
                    : 'Text',
                textAlign: textAlignFromStoryValue(layer.textAlign),
                style: TextStyle(
                  color: colorFromHex(layer.color, fallback: Colors.white),
                  fontWeight: fontWeightFromStoryValue(layer.fontWeight),
                  fontFamily: fontFamilyFromStoryValue(layer.fontFamily),
                  fontSize: 22 * (layer.fontScale ?? 1.0),
                  height: 1.28,
                ),
              ),
            ),
          ),
        );
      case SocialStoryLayerType.mention:
        final label = layer.displayLabel?.trim().isNotEmpty == true
            ? layer.displayLabel!.trim()
            : (layer.text ?? '').replaceFirst('@', '').trim();
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorFromHex(
              layer.backgroundColor,
              fallback: Colors.black.withValues(alpha: 0.28),
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              '@${label.isEmpty ? 'user' : label}',
              style: TextStyle(
                color: colorFromHex(layer.color, fallback: Colors.white),
                fontWeight: fontWeightFromStoryValue(layer.fontWeight),
                fontSize: 18 * (layer.fontScale ?? 1.0),
              ),
            ),
          ),
        );
      case SocialStoryLayerType.sticker:
        return Text(layer.sticker ?? '?', style: const TextStyle(fontSize: 54));
      case SocialStoryLayerType.reelShare:
      case SocialStoryLayerType.postShare:
        return _AttachmentCard(
          attachment: widget.draft.attachment,
          onTap: widget.onAttachmentTap,
          active: widget.active,
        );
      case SocialStoryLayerType.draw:
        return const SizedBox.shrink();
    }
  }
}

class _StoryBackground extends StatelessWidget {
  final SocialStoryDraft draft;

  const _StoryBackground({required this.draft});

  @override
  Widget build(BuildContext context) {
    final background = draft.background;
    switch (background.type) {
      case SocialStoryBackgroundType.gradient:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorFromHex(
                  background.primaryColor,
                  fallback: const Color(0xFF1E3A8A),
                ),
                colorFromHex(
                  background.secondaryColor,
                  fallback: const Color(0xFF0F766E),
                ),
              ],
            ),
          ),
        );
      case SocialStoryBackgroundType.posterBlur:
        final imageUrl = (background.imageUrl ?? '').trim();
        if (imageUrl.isEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: colorFromHex(
                background.primaryColor,
                fallback: const Color(0xFF0F172A),
              ),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            CachedAppImage(
              imageUrl: imageUrl,
              cacheIdentity: 'story_bg_${imageUrl.hashCode}',
              fit: BoxFit.cover,
            ),
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: CachedAppImage(
                  imageUrl: imageUrl,
                  cacheIdentity: 'story_bg_blur_${imageUrl.hashCode}',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
              ),
            ),
          ],
        );
      case SocialStoryBackgroundType.solid:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorFromHex(
              background.primaryColor,
              fallback: const Color(0xFF1E3A8A),
            ),
          ),
        );
    }
  }
}

class _StoryBaseMedia extends StatelessWidget {
  final SocialStoryDraft draft;
  final String? remoteMediaUrl;
  final String? remoteMediaKind;
  final Widget? child;

  const _StoryBaseMedia({
    required this.draft,
    required this.remoteMediaUrl,
    required this.remoteMediaKind,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (child != null) return child!;

    final media = draft.buildLocalMediaFile();
    if (media != null) {
      final path = (media.path ?? '').trim();
      if (path.isNotEmpty) {
        if (media.isVideo) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
            ),
            child: const Center(
              child: Icon(
                Icons.play_circle_outline_rounded,
                color: Colors.white,
                size: 58,
              ),
            ),
          );
        }
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink();
          },
        );
      }
    }

    final url = (remoteMediaUrl ?? '').trim();
    if (url.isEmpty) return const SizedBox.shrink();
    final kind = (remoteMediaKind ?? '').trim().toLowerCase();
    if (kind == 'video' || kind == 'reel') {
      return DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28)),
        child: const Center(
          child: Icon(
            Icons.play_circle_outline_rounded,
            color: Colors.white,
            size: 58,
          ),
        ),
      );
    }
    return CachedAppImage(
      imageUrl: url,
      cacheIdentity: 'story_base_${url.hashCode}',
      fit: BoxFit.cover,
      errorWidget: (context, error, stackTrace) {
        return const SizedBox.shrink();
      },
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  final SocialStoryAttachment? attachment;
  final VoidCallback? onTap;
  final bool active;

  const _AttachmentCard({
    required this.attachment,
    this.onTap,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    final data = attachment;
    if (data == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isReelShare = data.isReelShare;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isReelShare ? 278 : 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: isReelShare ? 9 / 14 : 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _AttachmentPreviewFrame(attachment: data, active: active),
                    if (isReelShare)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.08),
                              Colors.black.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                    PositionedDirectional(
                      top: 10,
                      start: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.34),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          data.isReelShare
                              ? (Directionality.of(context) == TextDirection.rtl
                                    ? 'ريل'
                                    : 'Reel')
                              : (Directionality.of(context) == TextDirection.rtl
                                    ? 'منشور'
                                    : 'Post'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      bottom: 12,
                      end: 12,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.32),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data.authorName?.trim().isNotEmpty == true
                  ? data.authorName!.trim()
                  : 'Maslaki',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            if ((data.caption ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                data.caption!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, height: 1.3),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                data.isReelShare
                    ? (Directionality.of(context) == TextDirection.rtl
                          ? 'شاهد الريل'
                          : 'Watch reel')
                    : (Directionality.of(context) == TextDirection.rtl
                          ? 'شاهد المنشور'
                          : 'View post'),
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPreviewFrame extends StatefulWidget {
  final SocialStoryAttachment attachment;
  final bool active;

  const _AttachmentPreviewFrame({
    required this.attachment,
    required this.active,
  });

  @override
  State<_AttachmentPreviewFrame> createState() =>
      _AttachmentPreviewFrameState();
}

class _AttachmentPreviewFrameState extends State<_AttachmentPreviewFrame>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initVideoIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _AttachmentPreviewFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUrl = (oldWidget.attachment.mediaUrl ?? '').trim();
    final newUrl = (widget.attachment.mediaUrl ?? '').trim();
    if (oldUrl != newUrl) {
      _disposeVideo();
      _initVideoIfNeeded();
      return;
    }
    _syncPlayback();
  }

  Future<void> _initVideoIfNeeded() async {
    if (!widget.attachment.isReelShare || !appSupportsInlineVideoPlayback) {
      return;
    }
    final mediaKind = (widget.attachment.mediaKind ?? '').trim().toLowerCase();
    final mediaUrl = (widget.attachment.mediaUrl ?? '').trim();
    if (mediaUrl.isEmpty || (mediaKind != 'video' && mediaKind != 'reel')) {
      return;
    }
    final uri = Uri.tryParse(mediaUrl);
    if (uri == null) return;
    final source = await MediaCacheService.instance.resolveVideoSource(
      url: mediaUrl,
      cacheIdentity: 'story_attachment_video_${mediaUrl.hashCode}',
      scope: MediaCacheScope.public,
    );
    final controller = source.isLocalFile
        ? VideoPlayerController.file(source.file!)
        : VideoPlayerController.networkUrl(source.uri);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _video = controller;
      _videoReady = true;
      setState(() {});
      await _syncPlayback();
    } catch (_) {
      await controller.dispose();
    }
  }

  Future<void> _syncPlayback() async {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    final shouldPlay = widget.active && _appActive;
    if (shouldPlay) {
      if (!video.value.isPlaying) {
        await video.play();
      }
    } else if (video.value.isPlaying) {
      await video.pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    unawaited(_syncPlayback());
  }

  Future<void> _disposeVideo() async {
    final video = _video;
    _video = null;
    _videoReady = false;
    if (video != null) {
      await video.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeVideo());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.attachment;
    final imageUrl = (data.posterUrl ?? data.mediaUrl ?? '').trim();
    if (_videoReady && _video != null && _video!.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _video!.value.size.width,
          height: _video!.value.size.height,
          child: VideoPlayer(_video!),
        ),
      );
    }
    if (imageUrl.isNotEmpty) {
      return CachedAppImage(
        imageUrl: imageUrl,
        cacheIdentity: 'story_attachment_poster_${imageUrl.hashCode}',
        fit: BoxFit.cover,
        errorWidget: (context, error, stackTrace) =>
            _AttachmentPreviewFallback(isReelShare: data.isReelShare),
      );
    }
    return _AttachmentPreviewFallback(isReelShare: data.isReelShare);
  }
}

class _AttachmentPreviewFallback extends StatelessWidget {
  final bool isReelShare;

  const _AttachmentPreviewFallback({required this.isReelShare});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08)),
      child: Icon(
        isReelShare ? Icons.play_circle_fill_rounded : Icons.article_outlined,
        color: Colors.white,
        size: 42,
      ),
    );
  }
}

class _StoryDrawPainter extends CustomPainter {
  final List<SocialStoryDrawStroke> strokes;
  final List<SocialStoryPoint> livePoints;

  const _StoryDrawPainter({required this.strokes, required this.livePoints});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(canvas, size, stroke);
    }
    if (livePoints.length > 1) {
      _paintStroke(
        canvas,
        size,
        SocialStoryDrawStroke(color: '#FFFFFF', width: 4, points: livePoints),
      );
    }
  }

  void _paintStroke(Canvas canvas, Size size, SocialStoryDrawStroke stroke) {
    if (stroke.points.length < 2) return;
    final paint = Paint()
      ..color = colorFromHex(stroke.color, fallback: Colors.white)
      ..strokeWidth = stroke.width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    path.moveTo(
      stroke.points.first.x * size.width,
      stroke.points.first.y * size.height,
    );
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.x * size.width, point.y * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StoryDrawPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.livePoints != livePoints;
  }
}
