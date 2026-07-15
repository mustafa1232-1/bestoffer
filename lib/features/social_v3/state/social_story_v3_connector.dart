import 'package:flutter/material.dart';

import '../../social/models/social_models.dart';
import '../domain/story_view_data.dart';
import '../stories/social_story_viewer_v3.dart';

/// Opens the full-screen [SocialStoryViewerV3] from live [SocialStoryGroup]
/// data. This is the single live entry point that all story call sites route
/// through after cutover.
Future<void> openSocialStoryViewerV3({
  required BuildContext context,
  required SocialStoryGroup group,
  List<SocialStoryGroup>? storyGroups,
  int? initialStoryId,
  ValueChanged<int>? onStoryViewed,
  void Function(int reelId)? onOpenSharedReel,
  StoryV3LikeCallback? onToggleLike,
  StoryV3CommentsCallback? onOpenComments,
  StoryV3ShareCallback? onShare,
}) {
  final groups = (storyGroups == null || storyGroups.isEmpty)
      ? <SocialStoryGroup>[group]
      : storyGroups;

  // Resolve the starting group index.
  var initialGroupIndex = groups.indexWhere((g) => g.userId == group.userId);
  if (initialGroupIndex < 0) initialGroupIndex = 0;

  final v3Groups = groups.map(StoryV3Group.fromGroup).toList(growable: false);
  var initialItemIndex = 0;
  if (initialStoryId != null && initialStoryId > 0) {
    final resolved = v3Groups[initialGroupIndex].items.indexWhere(
      (item) => item.storyId == initialStoryId,
    );
    if (resolved >= 0) initialItemIndex = resolved;
  }

  return Navigator.of(context).push(
    SocialStoryViewerV3.route(
      groups: v3Groups,
      initialGroupIndex: initialGroupIndex,
      initialItemIndex: initialItemIndex,
      onView: (userId, storyId) => onStoryViewed?.call(storyId),
      onOpenSharedReel: onOpenSharedReel == null
          ? null
          : (ref) => onOpenSharedReel(ref.reelId),
      onToggleLike: onToggleLike,
      onOpenComments: onOpenComments,
      onShare: onShare,
    ),
  );
}
