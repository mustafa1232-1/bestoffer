import 'dart:io';

enum MediaCacheScope { public, userPrivate }

class MediaCacheKeyInput {
  final String url;
  final String? stableId;
  final String? version;
  final MediaCacheScope scope;
  final int? userId;

  const MediaCacheKeyInput({
    required this.url,
    this.stableId,
    this.version,
    this.scope = MediaCacheScope.public,
    this.userId,
  });
}

class MediaCachePolicy {
  final Duration ttl;
  final int imageMaxBytes;
  final int videoMaxBytes;
  final int maxVideoFileBytes;
  final int imageMaxObjects;
  final int videoMaxObjects;
  final int videoPrefetchLimit;

  const MediaCachePolicy({
    this.ttl = const Duration(days: 30),
    this.imageMaxBytes = 400 * 1024 * 1024,
    this.videoMaxBytes = 800 * 1024 * 1024,
    this.maxVideoFileBytes = 60 * 1024 * 1024,
    this.imageMaxObjects = 3000,
    this.videoMaxObjects = 420,
    this.videoPrefetchLimit = 1,
  });
}

class MediaCacheStats {
  final int imageBytes;
  final int imageFiles;
  final int videoBytes;
  final int videoFiles;

  const MediaCacheStats({
    required this.imageBytes,
    required this.imageFiles,
    required this.videoBytes,
    required this.videoFiles,
  });

  int get totalBytes => imageBytes + videoBytes;
  int get totalFiles => imageFiles + videoFiles;
}

class CachedVideoSource {
  final File? file;
  final Uri uri;

  const CachedVideoSource._({required this.file, required this.uri});

  factory CachedVideoSource.file(File file) {
    return CachedVideoSource._(file: file, uri: Uri.file(file.path));
  }

  factory CachedVideoSource.network(String url) {
    return CachedVideoSource._(file: null, uri: Uri.parse(url));
  }

  bool get isLocalFile => file != null;
}
