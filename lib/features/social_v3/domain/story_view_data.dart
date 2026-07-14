import 'package:flutter/painting.dart';
import 'package:social_core/social_models.dart';

import '../media/social_media_presentation.dart';

/// A single story item in the V3 viewer.
class StoryV3Item {
  const StoryV3Item({
    required this.storyId,
    required this.caption,
    required this.media,
    required this.backgroundColor,
    required this.imageDuration,
    required this.clipStart,
    required this.clipDuration,
    required this.isLiked,
    required this.sharedReel,
  });

  final int storyId;
  final String caption;
  final SocialMediaPresentation media;
  final Color backgroundColor;

  /// How long an image item stays on screen (§5: default 5s).
  final Duration imageDuration;

  /// Explicit clip window for a video item, when the story defines one.
  /// Never used to clamp an ordinary video to a fixed length.
  final Duration? clipStart;
  final Duration? clipDuration;

  final bool isLiked;

  /// When this story is a shared reel, the reference to open the original.
  final SharedReelRef? sharedReel;

  bool get isVideo =>
      media.mediaKind == SocialMediaKind.reel ||
      media.mediaKind == SocialMediaKind.video;

  bool get isImage => !isVideo;

  static Color _parseColor(String hex, {Color fallback = const Color(0xFF1E3A8A)}) {
    var value = hex.trim().replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  factory StoryV3Item.fromStory(SocialStory story) {
    final style = story.style;
    final kind = (story.mediaKind ?? '').trim().toLowerCase();
    final mediaKind = switch (kind) {
      'reel' => SocialMediaKind.reel,
      'video' => SocialMediaKind.video,
      'image' || 'photo' => SocialMediaKind.image,
      _ => story.asset?.playbackUrl != null
          ? SocialMediaKind.video
          : SocialMediaKind.image,
    };
    final media = SocialMediaPresentation.fromAsset(story.asset, kind: mediaKind);
    final clipDurationSec = style.clipDurationSec;
    final clipStartSec = style.clipStartSec;
    return StoryV3Item(
      storyId: story.id,
      caption: story.caption,
      media: media,
      backgroundColor: _parseColor(style.backgroundColor),
      imageDuration: const Duration(seconds: 5),
      clipStart: clipStartSec == null
          ? null
          : Duration(milliseconds: (clipStartSec * 1000).round()),
      clipDuration: clipDurationSec == null
          ? null
          : Duration(milliseconds: (clipDurationSec * 1000).round()),
      isLiked: story.isLiked,
      sharedReel: style.sharedPostId == null
          ? null
          : SharedReelRef(
              reelId: style.sharedPostId!,
              author: style.sharedPostAuthor,
              caption: style.sharedPostCaption,
            ),
    );
  }
}

/// A per-user story group (the progress bar only ever shows one group's items).
class StoryV3Group {
  const StoryV3Group({
    required this.userId,
    required this.authorName,
    required this.authorHandle,
    required this.authorAvatarUrl,
    required this.items,
  });

  final int userId;
  final String authorName;
  final String authorHandle;
  final String? authorAvatarUrl;
  final List<StoryV3Item> items;

  factory StoryV3Group.fromGroup(SocialStoryGroup group) {
    final handle = (group.author.username ?? '').trim();
    return StoryV3Group(
      userId: group.userId,
      authorName: group.author.fullName.trim().isEmpty
          ? (handle.isEmpty ? 'user_${group.userId}' : handle)
          : group.author.fullName.trim(),
      authorHandle: handle.isEmpty ? '' : '@$handle',
      authorAvatarUrl: group.author.imageUrl,
      items: group.stories
          .map(StoryV3Item.fromStory)
          .toList(growable: false),
    );
  }
}

/// Lightweight reference to a shared reel embedded in a story.
class SharedReelRef {
  const SharedReelRef({
    required this.reelId,
    required this.author,
    required this.caption,
  });

  final int reelId;
  final String? author;
  final String? caption;
}
