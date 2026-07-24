import 'package:flutter/material.dart';

import '../../models/social_models.dart';
import '../social_content_navigation.dart';
import 'social_post_card_v2.dart';

class SocialFeedPostsSliver extends StatelessWidget {
  final List<SocialPost> posts;
  final bool loadingMore;
  final Future<int?> Function(SocialPost post) onOpenComments;
  final Future<void> Function(SocialPost post) onToggleLike;
  final Future<void> Function(SocialPost post) onToggleSave;
  final Future<void> Function(SocialPost post)? onReportPost;
  final VoidCallback? Function(SocialPost post) onOpenMerchantLink;
  final void Function(SocialPost post, int commentsCount)
  onCommentsCountChanged;

  const SocialFeedPostsSliver({
    super.key,
    required this.posts,
    required this.loadingMore,
    required this.onOpenComments,
    required this.onToggleLike,
    required this.onToggleSave,
    this.onReportPost,
    required this.onOpenMerchantLink,
    required this.onCommentsCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= posts.length) {
            if (!loadingMore) {
              return const SizedBox.shrink();
            }
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final post = posts[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SocialPostCardV2(
              key: ValueKey(post.id),
              post: post,
              autoPlayVideoPreview: isSocialReelPost(post),
              onOpenDetails: () => openSocialContent(
                context,
                post: post,
                reelContextPosts: posts,
              ),
              onOpenComments: () async {
                final count = await onOpenComments(post);
                if (count == null) return;
                onCommentsCountChanged(post, count);
              },
              onToggleLike: () => onToggleLike(post),
              onToggleSave: () => onToggleSave(post),
              onReport: onReportPost == null ? null : () => onReportPost!(post),
              onOpenMerchantLink: onOpenMerchantLink(post),
              onOpenProfile: () {
                openSocialProfileGuarded(
                  context,
                  userId: post.author.id,
                  initialName: post.author.fullName,
                );
              },
            ),
          );
        }, childCount: posts.length + 1),
      ),
    );
  }
}
