import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'media_cache_models.dart';
import 'media_cache_service.dart';

class CachedAppImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    if (url.isEmpty) {
      return _defaultError(context, '', Exception('Empty image URL'));
    }

    final service = MediaCacheService.instance;
    final key = service.buildKey(
      MediaCacheKeyInput(
        url: url,
        stableId: cacheIdentity,
        version: version,
        scope: scope,
        userId: userId,
      ),
    );

    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: key,
      cacheManager: service.imagesManager,
      httpHeaders: headers,
      fit: fit,
      width: width,
      height: height,
      maxWidthDiskCache: maxWidthDiskCache,
      maxHeightDiskCache: maxHeightDiskCache,
      placeholder: (context, value) =>
          placeholder?.call(context, value) ?? _defaultPlaceholder(context),
      errorWidget: (context, value, error) =>
          errorWidget?.call(context, value, error) ??
          _defaultError(context, value, error),
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

  static Widget _defaultError(BuildContext context, String url, Object error) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF12264A).withValues(alpha: 0.84),
      ),
      child: const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white70),
      ),
    );
  }
}

class AppCachedImageProvider extends CachedNetworkImageProvider {
  AppCachedImageProvider(
    super.url, {
    String? cacheIdentity,
    String? version,
    MediaCacheScope scope = MediaCacheScope.public,
    int? userId,
    super.headers,
    super.maxWidth,
    super.maxHeight,
  }) : super(
         cacheManager: MediaCacheService.instance.imagesManager,
         cacheKey: MediaCacheService.instance.buildKey(
           MediaCacheKeyInput(
             url: url,
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
  final value = (url ?? '').trim();
  if (value.isEmpty) return null;
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
