import 'package:flutter/painting.dart';
import 'package:social_core/social_models.dart';
import 'package:social_core/social_story_document.dart';

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
    this.likesCount = 0,
    this.commentsCount = 0,
    this.allowLikes = true,
    this.allowPrivateReplies = true,
    this.allowComments = true,
    this.allowSharing = true,
    this.allowReshare = true,
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
  final int likesCount;
  final int commentsCount;
  final bool allowLikes;
  final bool allowPrivateReplies;
  final bool allowComments;
  final bool allowSharing;
  final bool allowReshare;

  /// When this story is a shared reel, the reference to open the original.
  final SharedReelRef? sharedReel;

  bool get isVideo =>
      media.mediaKind == SocialMediaKind.reel ||
      media.mediaKind == SocialMediaKind.video;

  bool get isImage => !isVideo;

  static Color _parseColor(
    String hex, {
    Color fallback = const Color(0xFF1E3A8A),
  }) {
    var value = hex.trim().replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  factory StoryV3Item.fromStory(SocialStory story) {
    final style = story.style;
    final draft = SocialStoryDraft.fromStoryStyle(story: story);
    final attachment = draft.attachment;
    final kind = (story.mediaKind ?? '').trim().toLowerCase();
    final mediaKind = switch (kind) {
      'reel' => SocialMediaKind.reel,
      'video' => SocialMediaKind.video,
      'image' || 'photo' => SocialMediaKind.image,
      _ =>
        story.asset?.playbackUrl != null
            ? SocialMediaKind.video
            : SocialMediaKind.image,
    };
    final media = SocialMediaPresentation.fromAsset(
      story.asset,
      kind: mediaKind,
    );
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
      likesCount: story.likesCount,
      commentsCount: story.commentsCount,
      allowLikes: story.allowLikes,
      allowPrivateReplies: story.allowPrivateReplies,
      allowComments: story.allowComments,
      allowSharing: story.allowSharing,
      allowReshare: story.allowReshare,
      sharedReel: attachment?.isReelShare != true
          ? null
          : SharedReelRef(
              reelId: attachment?.reelId ?? style.sharedPostId ?? story.id,
              originalOwnerId: story.userId,
              playbackUrl:
                  attachment?.playbackUrl ??
                  attachment?.mediaUrl ??
                  style.sharedPostMediaUrl ??
                  story.mediaUrl ??
                  story.asset?.playbackUrl,
              thumbnailUrl:
                  attachment?.thumbnailUrl ??
                  attachment?.posterUrl ??
                  story.asset?.thumbnailUrl ??
                  story.asset?.posterUrl,
              posterUrl:
                  attachment?.posterUrl ??
                  attachment?.thumbnailUrl ??
                  story.asset?.posterUrl ??
                  story.asset?.thumbnailUrl,
              aspectRatio:
                  attachment?.aspectRatio ?? story.asset?.aspectRatio ?? 9 / 16,
              available: story.asset?.isReady != false,
              author:
                  attachment?.authorName ??
                  style.sharedPostAuthor ??
                  'user_${story.userId}',
              authorName: attachment?.authorName ?? style.sharedPostAuthor,
              authorAvatarUrl: null,
              authorHandle: null,
              caption:
                  attachment?.caption ??
                  style.sharedPostCaption ??
                  story.caption,
            ),
    );
  }
}

/// The authoritative fields returned after toggling a story like.
///
/// Either field may be absent when an older API response only acknowledges the
/// mutation. In that case the viewer keeps its optimistic value for that field.
class StoryV3LikeResult {
  const StoryV3LikeResult({this.isLiked, this.likesCount});

  final bool? isLiked;
  final int? likesCount;
}

typedef StoryV3LikeCallback = Future<StoryV3LikeResult?> Function(int storyId);

/// Returns how many comments were added while the comments overlay was open.
/// A null result means the action was cancelled before opening the overlay.
typedef StoryV3CommentsCallback = Future<int?> Function(int storyId);

typedef StoryV3ShareCallback = Future<void> Function(int storyId);

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
      items: group.stories.map(StoryV3Item.fromStory).toList(growable: false),
    );
  }
}

/// Lightweight reference to a shared reel embedded in a story.
class SharedReelRef {
  const SharedReelRef({
    required this.reelId,
    required this.originalOwnerId,
    required this.playbackUrl,
    required this.thumbnailUrl,
    required this.posterUrl,
    required this.aspectRatio,
    required this.available,
    required this.author,
    required this.caption,
    this.authorName,
    this.authorAvatarUrl,
    this.authorHandle,
    this.width,
    this.height,
  });

  final int reelId;
  final int originalOwnerId;
  final String? playbackUrl;
  final String? thumbnailUrl;
  final String? posterUrl;
  final double? aspectRatio;
  final bool available;
  final String? author;
  final String? authorName;
  final String? authorAvatarUrl;
  final String? authorHandle;
  final String? caption;
  final int? width;
  final int? height;
}
