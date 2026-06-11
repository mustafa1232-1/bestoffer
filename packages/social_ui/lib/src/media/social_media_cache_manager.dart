import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class SocialMediaCacheManager extends CacheManager {
  static const key = 'social_media_cache_v1';
  static final SocialMediaCacheManager instance = SocialMediaCacheManager._();

  SocialMediaCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 2400,
          repo: JsonCacheInfoRepository(databaseName: key),
          fileService: HttpFileService(),
        ),
      );
}
