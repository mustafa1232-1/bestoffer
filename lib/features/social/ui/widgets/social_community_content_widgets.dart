import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:video_player/video_player.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/media/media_cache_models.dart';
import '../../../../core/media/media_cache_service.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../models/social_models.dart';
import 'social_community_widgets.dart';
import 'social_inline_attachment_message_card.dart';
import 'social_voice_message_widgets.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class CommunityPostCard extends StatelessWidget {
  final SocialPost post;
  final intl.DateFormat timeFmt;
  final VoidCallback onOpenAuthorProfile;
  final VoidCallback onMessageAuthor;
  final VoidCallback onShare;
  final VoidCallback onLike;
  final VoidCallback onOpenComments;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenMerchantReview;
  final bool reelsMuted;
  final VoidCallback onToggleReelsMuted;

  const CommunityPostCard({
    super.key,
    required this.post,
    required this.timeFmt,
    required this.onOpenAuthorProfile,
    required this.onMessageAuthor,
    required this.onShare,
    required this.onLike,
    required this.onOpenComments,
    required this.onOpenMedia,
    required this.onOpenMerchantReview,
    required this.reelsMuted,
    required this.onToggleReelsMuted,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final subtitle = post.createdAt == null
        ? communityKindLabel(context, post.postKind)
        : '${communityKindLabel(context, post.postKind)} • ${timeFmt.format(post.createdAt!.toLocal())}';
    final kind = (post.mediaKind ?? post.postKind).trim().toLowerCase();
    final isImage = kind == 'image';
    final isVideo = kind == 'video';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surface.withValues(alpha: 0.92),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                CircleAvatar(
                  backgroundImage:
                      (post.author.imageUrl ?? '').trim().isNotEmpty
                      ? appCachedImageProvider(
                          post.author.imageUrl!,
                          cacheIdentity: 'user_avatar_${post.author.id}',
                          version: post.updatedAt?.toIso8601String(),
                        )
                      : null,
                  child: (post.author.imageUrl ?? '').trim().isEmpty
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: onOpenAuthorProfile,
                    borderRadius: BorderRadius.circular(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          post.author.fullName,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          subtitle,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (post.caption.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                post.caption,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  fontSize: 15,
                ),
              ),
            ],
            if (post.postKind == 'merchant_review') ...[
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: post.merchantId == null ? null : onOpenMerchantReview,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.6,
                      ),
                    ),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundImage:
                              (post.merchantImageUrl ?? '').trim().isNotEmpty
                              ? appCachedImageProvider(
                                  post.merchantImageUrl!,
                                  cacheIdentity:
                                      'merchant_${post.merchantId ?? 0}',
                                  version: post.updatedAt?.toIso8601String(),
                                )
                              : null,
                          child: (post.merchantImageUrl ?? '').trim().isEmpty
                              ? const Icon(Icons.storefront_rounded, size: 18)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${l10n.socialCommunityKindReview}: ${post.merchantName ?? l10n.commonStore}',
                                textDirection: Directionality.of(context),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: List.generate(
                                  5,
                                  (i) => Icon(
                                    i < (post.reviewRating ?? 0)
                                        ? Icons.star_rounded
                                        : Icons.star_border_rounded,
                                    color: Colors.amber,
                                    size: 18,
                                  ),
                                ),
                              ),
                              if (post.merchantId != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  l10n.socialCommunityTapToOpenStore,
                                  textDirection: Directionality.of(context),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (post.merchantId != null)
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 18,
                            color: scheme.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (isImage || isVideo) ...[
              const SizedBox(height: 10),
              CommunityPostMediaPreview(
                mediaUrl: post.mediaUrl ?? '',
                isImage: isImage,
                onOpenMedia: onOpenMedia,
                heroTag: 'community-post-${post.id}',
                muted: reelsMuted,
                onToggleMute: onToggleReelsMuted,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                CommunityActionChip(
                  label: l10n.commonShare,
                  icon: Icons.ios_share_rounded,
                  onTap: onShare,
                ),
                CommunityActionChip(
                  label: l10n.commonMessage,
                  icon: Icons.chat_bubble_outline_rounded,
                  onTap: onMessageAuthor,
                ),
                CommunityActionChip(
                  label: '${l10n.commonComments} ${post.commentsCount}',
                  icon: Icons.mode_comment_outlined,
                  onTap: onOpenComments,
                ),
                CommunityActionChip(
                  label: '${l10n.socialCommunityLikes} ${post.likesCount}',
                  icon: post.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  onTap: onLike,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CommunityChatBubble extends StatelessWidget {
  final SocialCommunityChatMessage message;
  final String timeLabel;
  final ValueChanged<SocialAuthor> onOpenProfile;
  final VoidCallback onMore;
  final VoidCallback? onOpenAttachment;
  final VoidCallback? onOpenSharedEntity;

  const CommunityChatBubble({
    super.key,
    required this.message,
    required this.timeLabel,
    required this.onOpenProfile,
    required this.onMore,
    this.onOpenAttachment,
    this.onOpenSharedEntity,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mine = message.isMine;
    final isDeleted = message.isDeleted;
    final displayBody = isDeleted
        ? l10n.socialCommunityMessageDeleted
        : message.body;
    final showEdited = !isDeleted && message.editedAt != null;
    final bubbleColor = message.isSystem
        ? Colors.blueGrey.shade100
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: InkWell(
        onLongPress: onMore,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              if (!message.isSystem)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!mine)
                      CircleAvatar(
                        radius: 12,
                        backgroundImage:
                            (message.sender.imageUrl ?? '').trim().isNotEmpty
                            ? appCachedImageProvider(
                                message.sender.imageUrl!,
                                cacheIdentity:
                                    'community_sender_${message.sender.id}',
                              )
                            : null,
                        child: (message.sender.imageUrl ?? '').trim().isEmpty
                            ? const Icon(Icons.person, size: 14)
                            : null,
                      ),
                    if (!mine) const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => onOpenProfile(message.sender),
                      child: Text(
                        message.sender.fullName.isEmpty
                            ? l10n.socialCommunityUserFallback
                            : message.sender.fullName,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              if (!isDeleted && message.replyToMessage != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message.replyToMessage!.previewText.trim().isEmpty
                        ? l10n.socialCommunityReplyToMessage
                        : message.replyToMessage!.previewText,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              if (displayBody.trim().isNotEmpty || isDeleted) ...[
                const SizedBox(height: 6),
                Text(
                  displayBody,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                    color: isDeleted
                        ? Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.72)
                        : null,
                  ),
                ),
              ],
              if (!isDeleted &&
                  message.attachment != null &&
                  message.attachment!.isAudio) ...[
                const SizedBox(height: 6),
                SocialAudioAttachmentBubble(attachment: message.attachment!),
              ],
              if (!isDeleted &&
                  message.attachment != null &&
                  !message.attachment!.isAudio) ...[
                const SizedBox(height: 6),
                SocialInlineAttachmentMessageCard(
                  attachment: message.attachment!,
                  onTap: onOpenAttachment ?? () {},
                ),
              ],
              if (!isDeleted && message.sharedEntity != null) ...[
                const SizedBox(height: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onOpenSharedEntity,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundImage:
                              (message.sharedEntity!.authorAvatarUrl ?? '')
                                  .trim()
                                  .isNotEmpty
                              ? appCachedImageProvider(
                                  message.sharedEntity!.authorAvatarUrl!,
                                  cacheIdentity:
                                      'shared_${message.sharedEntity!.type}_${message.sharedEntity!.id}',
                                )
                              : null,
                          child:
                              (message.sharedEntity!.authorAvatarUrl ?? '')
                                  .trim()
                                  .isEmpty
                              ? Icon(
                                  message.sharedEntity!.type
                                              .trim()
                                              .toLowerCase() ==
                                          'location'
                                      ? Icons.location_on_outlined
                                      : Icons.link_rounded,
                                  size: 18,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            message.sharedEntity!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isDeleted &&
                      (message.myReaction ?? '').trim().isNotEmpty)
                    Text(
                      communityReactionEmoji(message.myReaction),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  if (!isDeleted &&
                      (message.myReaction ?? '').trim().isNotEmpty &&
                      message.reactionTotalCount > 0)
                    const SizedBox(width: 6),
                  if (!isDeleted && message.reactionTotalCount > 0)
                    Text(
                      '${message.reactionTotalCount} ${l10n.socialCommunityReactions}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  if ((!isDeleted &&
                              ((message.myReaction ?? '').trim().isNotEmpty ||
                                  message.reactionTotalCount > 0) ||
                          showEdited) &&
                      timeLabel.isNotEmpty)
                    const SizedBox(width: 6),
                  if (showEdited) ...[
                    Text(
                      l10n.socialCommunityEdited,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (timeLabel.isNotEmpty) const SizedBox(width: 6),
                  ],
                  if (timeLabel.isNotEmpty)
                    Text(timeLabel, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String communityReactionEmoji(String? reactionKey) {
  switch ((reactionKey ?? '').trim().toLowerCase()) {
    case 'heart':
      return '❤️';
    case 'laugh':
      return 'ðŸ˜‚';
    case 'fire':
      return 'ðŸ”¥';
    case 'like':
      return 'ðŸ‘';
    default:
      return '';
  }
}

class CommunityMediaViewerPage extends StatefulWidget {
  final String mediaUrl;
  final bool isVideo;
  final bool initiallyMuted;
  final String title;
  final String subtitle;
  final String? caption;

  const CommunityMediaViewerPage({
    super.key,
    required this.mediaUrl,
    required this.isVideo,
    required this.initiallyMuted,
    required this.title,
    required this.subtitle,
    this.caption,
  });

  @override
  State<CommunityMediaViewerPage> createState() =>
      _CommunityMediaViewerPageState();
}

class _CommunityMediaViewerPageState extends State<CommunityMediaViewerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _muted = true;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _muted = widget.initiallyMuted;
    if (widget.isVideo) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    if (!appSupportsInlineVideoPlayback) {
      setState(() {
        _videoError = context.l10n.socialCommunityVideoUnsupported;
      });
      return;
    }
    try {
      final uri = Uri.tryParse(widget.mediaUrl);
      if (uri == null) {
        setState(() {
          _videoError = context.l10n.socialCommunityInvalidVideoUrl;
        });
        return;
      }
      final source = await MediaCacheService.instance.resolveVideoSource(
        url: widget.mediaUrl,
        cacheIdentity: 'community_viewer_video_${widget.mediaUrl.hashCode}',
        scope: MediaCacheScope.public,
      );
      final controller = source.isLocalFile
          ? VideoPlayerController.file(source.file!)
          : VideoPlayerController.networkUrl(source.uri);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = controller;
        _videoReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _videoError = context.l10n.socialCommunityVideoPlayFailed;
      });
    }
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    setState(() => _muted = next);
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    await video.setVolume(next ? 0 : 1);
  }

  Future<void> _togglePlayPause() async {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (video.value.isPlaying) {
      await video.pause();
    } else {
      await video.play();
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (state == AppLifecycleState.resumed && !video.value.isPlaying) {
      unawaited(video.play());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              widget.title,
              textDirection: Directionality.of(context),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            if (widget.subtitle.trim().isNotEmpty)
              Text(
                widget.subtitle,
                textDirection: Directionality.of(context),
                style: const TextStyle(fontSize: 11),
              ),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!widget.isVideo)
            InteractiveViewer(
              minScale: 0.9,
              maxScale: 4,
              child: Center(
                child: CachedAppImage(
                  imageUrl: widget.mediaUrl,
                  cacheIdentity:
                      'community_viewer_image_${widget.mediaUrl.hashCode}',
                  fit: BoxFit.contain,
                  errorWidget: (context, error, stackTrace) => Center(
                    child: Text(
                      context.l10n.socialCommunityImageLoadFailed,
                      textDirection: Directionality.of(context),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            )
          else if (_videoError != null)
            Center(
              child: Text(
                _videoError!,
                textDirection: Directionality.of(context),
                style: const TextStyle(color: Colors.white),
              ),
            )
          else if (!_videoReady)
            const Center(child: CircularProgressIndicator())
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlayPause,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: _video!.value.size.width,
                      height: _video!.value.size.height,
                      child: VideoPlayer(_video!),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 16,
                    child: FilledButton.tonalIcon(
                      onPressed: _toggleMute,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.52),
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                      ),
                      label: Text(
                        _muted
                            ? context.l10n.socialCommunityMuted
                            : context.l10n.socialCommunitySoundOn,
                      ),
                    ),
                  ),
                  if (!_video!.value.isPlaying)
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 72,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          if ((widget.caption ?? '').trim().isNotEmpty)
            Positioned(
              right: 12,
              left: 12,
              bottom: 72,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  widget.caption!.trim(),
                  textDirection: Directionality.of(context),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
