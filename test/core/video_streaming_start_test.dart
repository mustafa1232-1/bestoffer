import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:maslaki/core/media/media_cache_service.dart';

class _Cache extends Fake implements CacheManager {
  FileInfo? result;
  int lookups = 0;
  int downloads = 0;
  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    lookups++;
    return result;
  }

  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    downloads++;
    throw StateError('Playback must not download the entire file');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'uncached MP4 starts network streaming without HEAD or full download',
    () async {
      final cache = _Cache();
      final source = await MediaCacheService.withVideoCache(cache)
          .resolveVideoSource(url: 'https://unreachable.invalid/large.mp4')
          .timeout(const Duration(milliseconds: 200));
      expect(source.isLocalFile, isFalse);
      expect(cache.lookups, 1);
      expect(cache.downloads, 0);
    },
  );
  test(
    'valid cached video is reused; expired cache does not delay playback',
    () async {
      final file = MemoryFileSystem().file('/video.mp4')
        ..writeAsStringSync('fixture');
      final cache = _Cache()
        ..result = FileInfo(
          file,
          FileSource.Cache,
          DateTime.now().add(const Duration(hours: 1)),
          'https://test/video.mp4',
        );
      final service = MediaCacheService.withVideoCache(cache);
      expect(
        (await service.resolveVideoSource(
          url: 'https://test/video.mp4',
        )).isLocalFile,
        isTrue,
      );
      cache.result = FileInfo(
        file,
        FileSource.Cache,
        DateTime.now().subtract(const Duration(hours: 1)),
        'https://test/video.mp4',
      );
      expect(
        (await service.resolveVideoSource(
          url: 'https://test/video.mp4',
        )).isLocalFile,
        isFalse,
      );
      expect(cache.downloads, 0);
    },
  );
}
