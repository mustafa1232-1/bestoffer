import 'package:flutter/painting.dart';
import 'package:maslaki/features/social_v3/domain/story_view_data.dart';
import 'package:maslaki/features/social_v3/media/social_media_presentation.dart';

StoryV3Item imageStory(int id) => StoryV3Item(
      storyId: id,
      caption: 'story $id',
      media: const SocialMediaPresentation(
        mediaAssetId: null,
        provider: null,
        mediaKind: SocialMediaKind.image,
        playbackType: SocialPlaybackType.none,
        videoPlaybackUrl: null,
        posterImageUrl: null,
        width: 1080,
        height: 1920,
        durationMs: null,
        processingStatus: SocialProcessingStatus.ready,
      ),
      backgroundColor: const Color(0xFF1E3A8A),
      imageDuration: const Duration(seconds: 5),
      clipStart: null,
      clipDuration: null,
      isLiked: false,
      sharedReel: null,
    );

StoryV3Group storyGroup({
  required int userId,
  required String name,
  required int itemCount,
}) =>
    StoryV3Group(
      userId: userId,
      authorName: name,
      authorHandle: '@$name',
      authorAvatarUrl: null,
      items: List.generate(itemCount, (i) => imageStory(userId * 100 + i)),
    );
