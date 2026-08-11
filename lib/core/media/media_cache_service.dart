import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'media_cache_models.dart';
import 'media_url.dart';

final mediaCacheServiceProvider = Provider<MediaCacheService>((ref) {
  final service = MediaCacheService.instance;
  unawaited(service.scheduleMaintenance());
  return service;
});

class MediaCacheService {
  static const String imageCacheKey = 'maslaki_media_images_v1';
  static const String videoCacheKey = 'maslaki_media_videos_v1';

  static final MediaCacheService instance = MediaCacheService._();

  final MediaCachePolicy policy;
  late final CacheInfoRepository _imagesRepo;
  late final CacheInfoRepository _videosRepo;
  late final CacheManager _imagesManager;
  late final CacheManager _videosManager;

  DateTime? _lastMaintenanceAt;

  factory MediaCacheService({MediaCachePolicy? policy}) {
    if (policy == null) return instance;
    return MediaCacheService._(policy: policy);
  }

  MediaCacheService._({this.policy = const MediaCachePolicy()}) {
    if (kIsWeb) {
      return;
    }
    _imagesRepo = JsonCacheInfoRepository(databaseName: imageCacheKey);
    _videosRepo = JsonCacheInfoRepository(databaseName: videoCacheKey);
    _imagesManager = CacheManager(
      Config(
        imageCacheKey,
        stalePeriod: policy.ttl,
        maxNrOfCacheObjects: policy.imageMaxObjects,
        repo: _imagesRepo,
        fileService: HttpFileService(),
      ),
    );
    _videosManager = CacheManager(
      Config(
        videoCacheKey,
        stalePeriod: policy.ttl,
        maxNrOfCacheObjects: policy.videoMaxObjects,
        repo: _videosRepo,
        fileService: HttpFileService(),
      ),
    );
    bindGlobalImageCacheManager();
  }

  CacheManager get imagesManager => _imagesManager;
  CacheManager get videosManager => _videosManager;

  void bindGlobalImageCacheManager() {
    CachedNetworkImageProvider.defaultCacheManager = _imagesManager;
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = policy.imageMemoryMaxObjects;
    imageCache.maximumSizeBytes = policy.imageMemoryMaxBytes;
  }

  static String computeKey(MediaCacheKeyInput input) {
    final stableBase = (input.stableId ?? input.url).trim();
    final version = (input.version ?? '').trim();
    final scopePrefix = _scopePrefixFor(input.scope, input.userId);
    final normalized = '$stableBase|$version|$scopePrefix';
    final digest = sha256.convert(utf8.encode(normalized));
    return '$scopePrefix${digest.toString()}';
  }

  String buildKey(MediaCacheKeyInput input) {
    return computeKey(input);
  }

  Future<void> scheduleMaintenance({bool force = false}) async {
    if (kIsWeb) return;
    final now = DateTime.now();
    if (!force && _lastMaintenanceAt != null) {
      final elapsed = now.difference(_lastMaintenanceAt!);
      if (elapsed < const Duration(minutes: 20)) return;
    }
    _lastMaintenanceAt = now;
    unawaited(_runMaintenance());
  }

  Future<void> _runMaintenance() async {
    try {
      await _removeStaleAndOverCapacity(
        manager: _imagesManager,
        repo: _imagesRepo,
        maxBytes: policy.imageMaxBytes,
      );
      await _removeStaleAndOverCapacity(
        manager: _videosManager,
        repo: _videosRepo,
        maxBytes: policy.videoMaxBytes,
      );
    } catch (error) {
      debugPrint('[media-cache] maintenance failed: $error');
    }
  }

  Future<void> prefetchImage({
    required String url,
    String? cacheIdentity,
    String? version,
    MediaCacheScope scope = MediaCacheScope.public,
    int? userId,
    Map<String, String>? headers,
  }) async {
    if (kIsWeb) return;
    if (url.trim().isEmpty) return;
    final key = buildKey(
      MediaCacheKeyInput(
        url: url,
        stableId: cacheIdentity,
        version: version,
        scope: scope,
        userId: userId,
      ),
    );
    await _imagesManager.downloadFile(url, key: key, authHeaders: headers);
  }

  Future<CachedVideoSource> resolveVideoSource({
    required String url,
    String? cacheIdentity,
    String? version,
    MediaCacheScope scope = MediaCacheScope.public,
    int? userId,
    Map<String, String>? headers,
  }) async {
    // Normalize transport (http->https) and encoding so reels/videos load on
    // strict Android/iOS builds exactly like images do.
    final cleaned = resolveMediaUrl(url) ?? '';
    if (cleaned.isEmpty) {
      throw ArgumentError.value(url, 'url', 'Video URL is empty');
    }

    if (_looksLikeStreamingUrl(cleaned)) {
      return CachedVideoSource.network(cleaned);
    }

    if (kIsWeb) {
      return CachedVideoSource.network(cleaned);
    }

    final uri = Uri.tryParse(cleaned);
    if (uri == null) return CachedVideoSource.network(cleaned);

    final contentLength = await _readContentLength(uri, headers: headers);
    if (contentLength != null && contentLength > policy.maxVideoFileBytes) {
      return CachedVideoSource.network(cleaned);
    }

    final key = buildKey(
      MediaCacheKeyInput(
        url: cleaned,
        stableId: cacheIdentity,
        version: version,
        scope: scope,
        userId: userId,
      ),
    );

    try {
      final file = await _videosManager.getSingleFile(
        cleaned,
        key: key,
        headers: headers,
      );
      return CachedVideoSource.file(file);
    } catch (_) {
      return CachedVideoSource.network(cleaned);
    }
  }

  Future<void> prefetchNextVideos({
    required List<String> urls,
    String? version,
    MediaCacheScope scope = MediaCacheScope.public,
    int? userId,
  }) async {
    if (kIsWeb) return;
    if (urls.isEmpty) return;
    final count = policy.videoPrefetchLimit.clamp(0, urls.length);
    for (var i = 0; i < count; i++) {
      final url = urls[i].trim();
      if (url.isEmpty || _looksLikeStreamingUrl(url)) continue;
      unawaited(
        resolveVideoSource(
          url: url,
          version: version,
          scope: scope,
          userId: userId,
        ),
      );
    }
  }

  Future<void> clearAllCaches() async {
    if (kIsWeb) return;
    await Future.wait<void>([
      _imagesManager.emptyCache(),
      _videosManager.emptyCache(),
    ]);
  }

  Future<void> clearUserScopedCache(int userId) async {
    if (kIsWeb) return;
    if (userId <= 0) return;
    final prefix = _scopePrefix(MediaCacheScope.userPrivate, userId);
    await _removeByPrefix(_imagesManager, _imagesRepo, prefix);
    await _removeByPrefix(_videosManager, _videosRepo, prefix);
  }

  Future<MediaCacheStats> getStats() async {
    if (kIsWeb) {
      return const MediaCacheStats(
        imageBytes: 0,
        imageFiles: 0,
        videoBytes: 0,
        videoFiles: 0,
      );
    }
    final imagesDir = await _resolveCacheDirectory(imageCacheKey);
    final videosDir = await _resolveCacheDirectory(videoCacheKey);
    final imageStats = await _calculateDirectoryStats(imagesDir);
    final videoStats = await _calculateDirectoryStats(videosDir);
    return MediaCacheStats(
      imageBytes: imageStats.bytes,
      imageFiles: imageStats.files,
      videoBytes: videoStats.bytes,
      videoFiles: videoStats.files,
    );
  }

  Future<void> _removeByPrefix(
    CacheManager manager,
    CacheInfoRepository repo,
    String prefix,
  ) async {
    await repo.open();
    final objects = await repo.getAllObjects();
    final keys = objects
        .where((item) => (item.key).startsWith(prefix))
        .map((item) => item.key)
        .toList(growable: false);
    for (final key in keys) {
      await manager.removeFile(key);
    }
    await repo.close();
  }

  Future<void> _removeStaleAndOverCapacity({
    required CacheManager manager,
    required CacheInfoRepository repo,
    required int maxBytes,
  }) async {
    await repo.open();

    final oldEntries = await repo.getOldObjects(policy.ttl);
    for (final item in oldEntries) {
      await manager.removeFile(item.key);
    }

    final directory = await _resolveCacheDirectory(
      manager == _imagesManager ? imageCacheKey : videoCacheKey,
    );
    final stats = await _calculateDirectoryStats(directory);
    if (stats.bytes > maxBytes) {
      final ordered = await repo.getAllObjects();
      ordered.sort((a, b) {
        final left = a.touched ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.touched ?? DateTime.fromMillisecondsSinceEpoch(0);
        return left.compareTo(right);
      });

      var runningBytes = stats.bytes;
      for (final item in ordered) {
        if (runningBytes <= maxBytes) break;
        final size = item.length ?? 0;
        await manager.removeFile(item.key);
        if (size > 0) {
          runningBytes -= size;
        }
      }
    }

    await repo.close();
  }

  Future<Directory> _resolveCacheDirectory(String key) async {
    final temp = await getTemporaryDirectory();
    final sep = Platform.pathSeparator;
    return Directory('${temp.path}$sep$key');
  }

  Future<_DirectoryStats> _calculateDirectoryStats(Directory dir) async {
    if (!await dir.exists()) return const _DirectoryStats(bytes: 0, files: 0);
    var totalBytes = 0;
    var files = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) continue;
        totalBytes += stat.size;
        files += 1;
      } catch (_) {
        // Ignore inaccessible files during stats sampling.
      }
    }
    return _DirectoryStats(bytes: totalBytes, files: files);
  }

  Future<int?> _readContentLength(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.headUrl(uri);
      headers?.forEach(request.headers.add);
      final response = await request.close();
      await response.drain<void>();
      final raw = response.headers.value(HttpHeaders.contentLengthHeader);
      if (raw == null || raw.trim().isEmpty) return null;
      return int.tryParse(raw.trim());
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  bool _looksLikeStreamingUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('format=hls');
  }

  String _scopePrefix(MediaCacheScope scope, int? userId) {
    return _scopePrefixFor(scope, userId);
  }

  static String _scopePrefixFor(MediaCacheScope scope, int? userId) {
    switch (scope) {
      case MediaCacheScope.public:
        return 'pub_';
      case MediaCacheScope.userPrivate:
        final id = userId ?? 0;
        return 'u${id}_';
    }
  }
}

class _DirectoryStats {
  final int bytes;
  final int files;

  const _DirectoryStats({required this.bytes, required this.files});
}
