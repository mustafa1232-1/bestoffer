import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'cached_app_image.dart';
import 'media_cache_models.dart';
import 'media_cache_service.dart';

class CachedAppVideoLoader extends StatefulWidget {
  final String videoUrl;
  final String? posterUrl;
  final String? cacheIdentity;
  final String? version;
  final MediaCacheScope scope;
  final int? userId;
  final bool active;
  final bool muted;
  final bool loop;
  final BoxFit fit;
  final List<String> prefetchNextUrls;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const CachedAppVideoLoader({
    super.key,
    required this.videoUrl,
    this.posterUrl,
    this.cacheIdentity,
    this.version,
    this.scope = MediaCacheScope.public,
    this.userId,
    this.active = true,
    this.muted = false,
    this.loop = true,
    this.fit = BoxFit.cover,
    this.prefetchNextUrls = const <String>[],
    this.errorBuilder,
  });

  @override
  State<CachedAppVideoLoader> createState() => _CachedAppVideoLoaderState();
}

class _CachedAppVideoLoaderState extends State<CachedAppVideoLoader>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _appActive = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didUpdateWidget(covariant CachedAppVideoLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUrl = oldWidget.videoUrl.trim();
    final newUrl = widget.videoUrl.trim();
    if (oldUrl != newUrl || oldWidget.version != widget.version) {
      unawaited(_disposeController());
      _initialize();
      return;
    }
    if (oldWidget.muted != widget.muted && _controller != null) {
      unawaited(_controller!.setVolume(widget.muted ? 0 : 1));
    }
    _syncPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  Future<void> _initialize() async {
    final url = widget.videoUrl.trim();
    if (url.isEmpty) return;

    try {
      final source = await MediaCacheService.instance.resolveVideoSource(
        url: url,
        cacheIdentity: widget.cacheIdentity,
        version: widget.version,
        scope: widget.scope,
        userId: widget.userId,
      );
      final controller = source.isLocalFile
          ? VideoPlayerController.file(source.file!)
          : VideoPlayerController.networkUrl(source.uri);
      await controller.initialize();
      await controller.setLooping(widget.loop);
      await controller.setVolume(widget.muted ? 0 : 1);
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _ready = true;
      });
      _syncPlayback();

      if (widget.prefetchNextUrls.isNotEmpty) {
        unawaited(
          MediaCacheService.instance.prefetchNextVideos(
            urls: widget.prefetchNextUrls,
            version: widget.version,
            scope: widget.scope,
            userId: widget.userId,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.active && _appActive) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    _ready = false;
    if (controller != null) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeController());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!) ??
          _PosterFallback(
            posterUrl: widget.posterUrl,
            icon: Icons.error_outline_rounded,
          );
    }

    if (!_ready || _controller == null || !_controller!.value.isInitialized) {
      return _PosterFallback(posterUrl: widget.posterUrl);
    }

    return FittedBox(
      fit: widget.fit,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  final String? posterUrl;
  final IconData icon;

  const _PosterFallback({
    required this.posterUrl,
    this.icon = Icons.ondemand_video_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final poster = (posterUrl ?? '').trim();
    if (poster.isEmpty) {
      return ColoredBox(
        color: const Color(0xFF0E1730),
        child: Center(child: Icon(icon, color: Colors.white70)),
      );
    }

    return CachedAppImage(
      imageUrl: poster,
      fit: BoxFit.cover,
      errorWidget: (context, url, error) => ColoredBox(
        color: const Color(0xFF0E1730),
        child: Center(child: Icon(icon, color: Colors.white70)),
      ),
    );
  }
}
