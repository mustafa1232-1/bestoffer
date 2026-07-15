import 'package:flutter/foundation.dart';
import 'package:social_core/social_models.dart';

import '../media/social_media_presentation.dart';

/// Immutable view-model for a single reel in the V3 full-screen viewer.
///
/// Adapts the backend [SocialPost]/[SocialReelItem] into exactly what the UI
/// needs, so the widgets never touch raw JSON-shaped models and the media is
/// always routed through the [SocialMediaPresentation] contract.
@immutable
class ReelV3ViewData {
  const ReelV3ViewData({
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.authorHandle,
    required this.authorAvatarUrl,
    required this.isAuthorVerified,
    required this.caption,
    required this.media,
    required this.likesCount,
    required this.commentsCount,
    required this.savesCount,
    required this.viewsCount,
    required this.isLiked,
    required this.isSaved,
    required this.audioLabel,
    required this.localContextBadge,
    this.followState = 'none',
  });

  final int postId;
  final int authorId;
  final String authorName;

  /// `@username` style handle, or empty when the author has no username.
  final String authorHandle;
  final String? authorAvatarUrl;
  final bool isAuthorVerified;
  final String caption;
  final SocialMediaPresentation media;

  final int likesCount;
  final int commentsCount;
  final int savesCount;
  final int viewsCount;
  final bool isLiked;
  final bool isSaved;

  /// "Original audio" label (or a track name when available).
  final String audioLabel;

  /// Maslaki local-context badge (building/block/residence), or null.
  final String? localContextBadge;

  /// Follow relation to the author from the viewer's perspective.
  ///
  /// Supported values: `none`, `pending_outgoing`, `pending_incoming`,
  /// `accepted`, `blocked`, `self`.
  final String followState;

  ReelV3ViewData copyWith({
    int? likesCount,
    int? savesCount,
    bool? isLiked,
    bool? isSaved,
    String? nextFollowState,
  }) {
    return ReelV3ViewData(
      postId: postId,
      authorId: authorId,
      authorName: authorName,
      authorHandle: authorHandle,
      authorAvatarUrl: authorAvatarUrl,
      isAuthorVerified: isAuthorVerified,
      caption: caption,
      media: media,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount,
      savesCount: savesCount ?? this.savesCount,
      viewsCount: viewsCount,
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      audioLabel: audioLabel,
      localContextBadge: localContextBadge,
      followState: nextFollowState ?? followState,
    );
  }

  factory ReelV3ViewData.fromPost(
    SocialPost post, {
    String defaultAudioLabel = 'Original audio',
  }) {
    final author = post.author;
    final handle = (author.username ?? '').trim();
    return ReelV3ViewData(
      postId: post.id,
      authorId: author.id,
      authorName: author.fullName.trim().isEmpty
          ? (handle.isEmpty ? 'user_${author.id}' : handle)
          : author.fullName.trim(),
      authorHandle: handle.isEmpty ? '' : '@$handle',
      authorAvatarUrl: author.imageUrl,
      isAuthorVerified: author.isResidentVerified || author.isMerchantVerified,
      caption: post.caption,
      media: SocialMediaPresentation.fromPost(post),
      likesCount: post.likesCount,
      commentsCount: post.commentsCount,
      savesCount: post.savesCount,
      viewsCount: post.reelViewsCount,
      isLiked: post.isLiked,
      isSaved: post.isSaved,
      audioLabel: defaultAudioLabel,
      localContextBadge: _localContextBadge(post),
      followState: 'none',
    );
  }

  factory ReelV3ViewData.fromReelItem(SocialReelItem item) =>
      ReelV3ViewData.fromPost(item.post);

  static String? _localContextBadge(SocialPost post) {
    final scope = post.audienceScopeType.trim().toLowerCase();
    final code = (post.audienceScopeCode ?? '').trim();
    if (code.isEmpty) return null;
    switch (scope) {
      case 'building':
      case 'block':
      case 'residence':
      case 'neighborhood':
        return code;
      default:
        return null;
    }
  }
}
