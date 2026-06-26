import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'media_cache_models.dart';
import 'media_cache_service.dart';
import 'media_url.dart';

class CachedAppImage extends StatefulWidget {
  final String imageUrl;
  final String? cacheIdentity;
  final String? version;
  final MediaCacheScope scope;
  final int? userId;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;
  final Widget Function(BuildContext context, String url)? placeholder;
  final Widget Function(BuildContext context, String url, Object error)?
  errorWidget;
  final Map<String, String>? headers;

  const CachedAppImage({
    super.key,
    required this.imageUrl,
    this.cacheIdentity,
    this.version,
    this.scope = MediaCacheScope.public,
    this.userId,
    this.fit,
    this.width,
    this.height,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
    this.placeholder,
    this.errorWidget,
    this.headers,
  });

  @override
  State<CachedAppImage> createState() => _CachedAppImageState();
}

class _CachedAppImageState extends State<CachedAppImage> {
  // Bumping this forces CachedNetworkImage to retry a previously failed fetch
  // (e.g. a transient CDN 5xx / network blip) without rebuilding the screen.
  int _retryToken = 0;

  void _retry() {
    if (!mounted) return;
    setState(() => _retryToken += 1);
  }

  @override
  Widget build(BuildContext context) {
    final url = resolveMediaUrl(widget.imageUrl) ?? '';
    if (url.isEmpty) {
      return widget.errorWidget?.call(
            context,
            '',
            Exception('Empty image URL'),
          ) ??
          const _RetryableImageError(url: '', onRetry: null);
    }

    final service = MediaCacheService.instance;
    final key = service.buildKey(
      MediaCacheKeyInput(
        url: url,
        stableId: widget.cacheIdentity,
        version: widget.version,
        scope: widget.scope,
        userId: widget.userId,
      ),
    );

    return CachedNetworkImage(
      // The ValueKey ties the widget identity to the retry token so a tap on
      // "retry" tears down the failed image and starts a fresh request.
      key: ValueKey('$key#$_retryToken'),
      imageUrl: url,
      cacheKey: key,
      cacheManager: service.imagesManager,
      httpHeaders: widget.headers,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      maxWidthDiskCache: widget.maxWidthDiskCache,
      maxHeightDiskCache: widget.maxHeightDiskCache,
      placeholder: (context, value) =>
          widget.placeholder?.call(context, value) ??
          _defaultPlaceholder(context),
      errorWidget: (context, value, error) =>
          widget.errorWidget?.call(context, value, error) ??
          _RetryableImageError(url: value, onRetry: _retry),
    );
  }

  static Widget _defaultPlaceholder(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0D1C3A).withValues(alpha: 0.92),
            const Color(0xFF1D3D72).withValues(alpha: 0.78),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}

/// Graceful, tappable failure state. A single failed image never blanks the
/// post or red-screens the feed; the user can retry the media in place.
class _RetryableImageError extends StatelessWidget {
  final String url;
  final VoidCallback? onRetry;

  const _RetryableImageError({required this.url, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_outlined, color: Colors.white70),
        if (onRetry != null) ...[
          const SizedBox(height: 6),
          Icon(Icons.refresh_rounded, size: 18, color: Colors.white.withValues(alpha: 0.85)),
        ],
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF12264A).withValues(alpha: 0.84),
      ),
      child: Center(
        child: onRetry == null
            ? content
            : InkWell(
                onTap: onRetry,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: content,
                ),
              ),
      ),
    );
  }
}

class AppCachedImageProvider extends CachedNetworkImageProvider {
  AppCachedImageProvider(
    String url, {
    String? cacheIdentity,
    String? version,
    MediaCacheScope scope = MediaCacheScope.public,
    int? userId,
    super.headers,
    super.maxWidth,
    super.maxHeight,
  }) : super(
         resolveMediaUrl(url) ?? url,
         cacheManager: MediaCacheService.instance.imagesManager,
         cacheKey: MediaCacheService.instance.buildKey(
           MediaCacheKeyInput(
             url: resolveMediaUrl(url) ?? url,
             stableId: cacheIdentity,
             version: version,
             scope: scope,
             userId: userId,
           ),
         ),
       );
}

ImageProvider<Object>? appCachedImageProvider(
  String? url, {
  String? cacheIdentity,
  String? version,
  MediaCacheScope scope = MediaCacheScope.public,
  int? userId,
  Map<String, String>? headers,
  int? maxWidth,
  int? maxHeight,
}) {
  final value = resolveMediaUrl(url);
  if (value == null || value.isEmpty) return null;
  return AppCachedImageProvider(
    value,
    cacheIdentity: cacheIdentity,
    version: version,
    scope: scope,
    userId: userId,
    headers: headers,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
}
