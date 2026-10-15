import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:video_player/video_player.dart';

import '../../../../core/platform/app_platform_capabilities.dart';
import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/media/media_cache_models.dart';
import '../../../../core/media/media_cache_service.dart';
import '../../../../core/navigation/app_route_observer.dart';
import '../../models/social_models.dart';
import '../social_content_navigation.dart';
import '../social_share_sheet.dart';
import '../../../../core/i18n/locale_text.dart';
import 'social_design_theme.dart';
import 'social_post_caption.dart';
import 'social_post_action.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialPostCardV2 extends StatelessWidget {
  final SocialPost post;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenMerchantLink;
  final Future<void> Function()? onToggleLike;
  final Future<void> Function()? onToggleSave;
  final VoidCallback? onOpenComments;
  final Future<void> Function()? onReport;
  final bool autoPlayVideoPreview;

  const SocialPostCardV2({
    super.key,
    required this.post,
    this.onOpenDetails,
    this.onOpenProfile,
    this.onOpenMerchantLink,
    this.onToggleLike,
    this.onToggleSave,
    this.onOpenComments,
    this.onReport,
    this.autoPlayVideoPreview = false,
  });

  Future<void> _runReportSafely(BuildContext context) async {
    try {
      await onReport?.call();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.socialProfileReportSubmitFailed)),
      );
    }
  }

  Future<void> _share(BuildContext context) async {
    await showSocialShareSheet(
      context: context,
      entityType: socialEntityTypeFromPost(post),
      entityId: post.id,
      previewTitle: post.author.fullName,
      previewSubtitle: post.caption.trim(),
      externalShareText: post.caption.trim(),
      sharedSnapshot: buildSocialSharedSnapshotFromPost(post),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final dateText = post.createdAt == null
        ? ''
        : intl.DateFormat(
            isEnglish ? 'MMM d, h:mm a' : 'd MMM - h:mm a',
            isEnglish ? 'en' : 'ar',
          ).format(post.createdAt!.toLocal());
    final isReel = isSocialReelPost(post);
    final isMerchantReview = isSocialMerchantReviewPost(post);
    final commentsEnabled = post.commentsEnabled;
    final sharingEnabled = post.sharingEnabled;
    final availabilityNote = !commentsEnabled && !sharingEnabled
        ? context.lt(
            ar: 'التعليقات والمشاركة مغلقة لهذا المنشور',
            en: 'Comments and sharing are turned off for this post',
          )
        : !commentsEnabled
        ? context.lt(
            ar: 'التعليقات مغلقة لهذا المنشور',
            en: 'Comments are turned off for this post',
          )
        : !sharingEnabled
        ? context.lt(
            ar: 'المشاركة مغلقة لهذا المنشور',
            en: 'Sharing is turned off for this post',
          )
        : null;
    final mediaItems = _buildPostMediaDisplayItems(post);
    final username = (post.author.username ?? '').trim();
    final userLabel = username.isNotEmpty ? '@$username' : post.author.fullName;
    final authorLabel = post.author.fullName.trim().isNotEmpty
        ? post.author.fullName.trim()
        : username.isNotEmpty
        ? '@$username'
        : context.lt(ar: 'مستخدم مسلكي', en: 'Maslaki member');
    final showPremiumBadge =
        post.author.isPremiumCreator ||
        post.author.badges.contains('premium_creator');
    final asset = post.mediaGallery.isNotEmpty
        ? post.mediaGallery.first.asset
        : post.asset;
    final ratio =
        !isSocialVideoPost(post) &&
            asset != null &&
            (asset.aspectRatio ?? 0) > 0
        ? asset.aspectRatio!.clamp(4 / 5, 1.91).toDouble()
        : 4 / 5;

    return Theme(
      data: SocialDesignTheme.of(context),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: authorLabel,
                    child: InkWell(
                      onTap: onOpenProfile,
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: SocialDesignTheme.background,
                        backgroundImage:
                            (post.author.imageUrl ?? '').trim().isEmpty
                            ? null
                            : appCachedImageProvider(post.author.imageUrl!),
                        child: (post.author.imageUrl ?? '').trim().isEmpty
                            ? const Icon(
                                Icons.person_outline,
                                color: SocialDesignTheme.indigo,
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: onOpenProfile,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  authorLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: SocialDesignTheme.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (showPremiumBadge) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.verified_rounded,
                                  color: SocialDesignTheme.gold,
                                  size: 17,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            [
                              if (username.isNotEmpty) userLabel,
                              dateText,
                            ].where((v) => v.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SocialDesignTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: context.lt(
                      ar: 'خيارات المنشور',
                      en: 'Post options',
                    ),
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      color: SocialDesignTheme.indigo,
                    ),
                    onSelected: (value) {
                      if (value == 'report') {
                        unawaited(_runReportSafely(context));
                      } else {
                        onOpenDetails?.call();
                      }
                    },
                    itemBuilder: (_) => [
                      if (onOpenDetails != null)
                        PopupMenuItem(
                          value: 'details',
                          child: Text(
                            context.lt(ar: 'عرض المنشور', en: 'View post'),
                          ),
                        ),
                      if (onReport != null)
                        PopupMenuItem(
                          value: 'report',
                          child: Text(l10n.commonReport),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (post.sharedEntity != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: _SharedEntityPreviewCard(entity: post.sharedEntity!),
              ),
            if (mediaItems.isNotEmpty)
              GestureDetector(
                onTap: onOpenDetails,
                onDoubleTap: onToggleLike == null
                    ? null
                    : () {
                        if (!post.isLiked) unawaited(onToggleLike!());
                      },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 600),
                  child: _InlineFeedMediaGalleryPreview(
                    items: mediaItems,
                    aspectRatio: ratio,
                    autoPlay: autoPlayVideoPreview || isReel,
                    fallbackColor: SocialDesignTheme.background,
                    cacheIdentity: 'post_${post.id}',
                    cacheVersion: post.updatedAt?.toIso8601String(),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  SocialPostAction(
                    icon: post.isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: context.lt(ar: 'إعجاب', en: 'Like'),
                    count: post.likesCount,
                    active: post.isLiked,
                    onPressed: onToggleLike,
                  ),
                  SocialPostAction(
                    icon: Icons.mode_comment_outlined,
                    label: context.lt(ar: 'التعليقات', en: 'Comments'),
                    count: post.commentsCount,
                    onPressed: !commentsEnabled || onOpenComments == null
                        ? null
                        : () async => onOpenComments!(),
                  ),
                  SocialPostAction(
                    icon: Icons.share_outlined,
                    label: l10n.commonShare,
                    onPressed: sharingEnabled ? () => _share(context) : null,
                  ),
                  SocialPostAction(
                    icon: post.isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    label: context.lt(ar: 'حفظ', en: 'Save'),
                    active: post.isSaved,
                    onPressed: onToggleSave,
                  ),
                ],
              ),
            ),
            if (availabilityNote != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _PostAvailabilityNote(
                  icon: !commentsEnabled
                      ? Icons.mode_comment_outlined
                      : Icons.share_outlined,
                  text: availabilityNote,
                ),
              ),
            if (post.caption.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SocialPostCaption(
                  username: userLabel,
                  caption: post.caption.trim(),
                ),
              ),
            if (post.reviewRating != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(
                  spacing: 4,
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < post.reviewRating!
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: SocialDesignTheme.gold,
                      size: 18,
                    ),
                  ),
                ),
              ),
            if (isMerchantReview)
              Padding(
                padding: const EdgeInsets.all(12),
                child: _MerchantReviewPreview(
                  post: post,
                  onOpenMerchantLink: onOpenMerchantLink,
                ),
              ),
            if (commentsEnabled)
              for (final comment in post.commentPreview)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: InkWell(
                    onTap: onOpenComments,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundImage: appCachedImageProvider(
                            comment.author.imageUrl,
                          ),
                          child: (comment.author.imageUrl ?? '').trim().isEmpty
                              ? const Icon(Icons.person_outline, size: 16)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text:
                                      '${comment.author.fullName.trim().isNotEmpty ? comment.author.fullName : comment.author.username ?? context.lt(ar: 'مستخدم', en: 'Member')}  ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(text: comment.body),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SocialDesignTheme.ink,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (onOpenComments != null && commentsEnabled)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onOpenComments,
                  child: Text(
                    context.lt(
                      ar: 'عرض جميع التعليقات (${post.commentsCount})',
                      en: 'View all comments (${post.commentsCount})',
                    ),
                    style: const TextStyle(
                      color: SocialDesignTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            if (post.contentLink != null || post.merchantId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: TextButton.icon(
                  onPressed: onOpenMerchantLink,
                  icon: const Icon(Icons.storefront_outlined),
                  label: Text(
                    isMerchantReview
                        ? l10n.socialOpenStoreCta
                        : l10n.socialPostCardOpenLinkedCommerce,
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _PostAvailabilityNote extends StatelessWidget {
  const _PostAvailabilityNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: SocialDesignTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SocialDesignTheme.muted.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: SocialDesignTheme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SocialDesignTheme.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedEntityPreviewCard extends StatelessWidget {
  final SocialSharedEntity entity;

  const _SharedEntityPreviewCard({required this.entity});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = (entity.imageUrl ?? '').trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openSocialSharedEntity(context, entity: entity),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageUrl.isEmpty
                    ? Container(
                        width: 64,
                        height: 64,
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.repeat_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : CachedAppImage(
                        imageUrl: imageUrl,
                        cacheIdentity: 'shared_entity_${entity.id}',
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entity.previewLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entity.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((entity.subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entity.subtitle!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineFeedMediaPreview extends StatefulWidget {
  final String posterUrl;
  final String? videoUrl;
  final double aspectRatio;
  final bool isVideo;
  final bool isReel;
  final bool autoPlay;
  final Color fallbackColor;
  final String cacheIdentity;
  final String? cacheVersion;

  const _InlineFeedMediaPreview({
    required this.posterUrl,
    required this.videoUrl,
    required this.aspectRatio,
    required this.isVideo,
    required this.isReel,
    required this.autoPlay,
    required this.fallbackColor,
    required this.cacheIdentity,
    required this.cacheVersion,
  });

  @override
  State<_InlineFeedMediaPreview> createState() =>
      _InlineFeedMediaPreviewState();
}

class _InlineFeedMediaPreviewState extends State<_InlineFeedMediaPreview> {
  static bool _rememberedMuted = true;
  late bool _muted;

  @override
  void initState() {
    super.initState();
    _muted = _rememberedMuted;
  }

  void _toggleMuted() {
    setState(() {
      _muted = !_muted;
      _rememberedMuted = _muted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muteLabel = _muted ? l10n.socialReelUnmute : l10n.socialReelMute;
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: _InlineFeedMediaContent(
        posterUrl: widget.posterUrl,
        videoUrl: widget.videoUrl,
        isVideo: widget.isVideo,
        isReel: widget.isReel,
        autoPlay: widget.autoPlay,
        fallbackColor: widget.fallbackColor,
        cacheIdentity: widget.cacheIdentity,
        cacheVersion: widget.cacheVersion,
        muted: _muted,
        muteLabel: muteLabel,
        onToggleMuted: _toggleMuted,
      ),
    );
  }
}

class _InlineFeedMediaContent extends StatelessWidget {
  final String posterUrl;
  final String? videoUrl;
  final bool isVideo;
  final bool isReel;
  final bool autoPlay;
  final Color fallbackColor;
  final String cacheIdentity;
  final String? cacheVersion;
  final bool muted;
  final String muteLabel;
  final VoidCallback onToggleMuted;

  const _InlineFeedMediaContent({
    required this.posterUrl,
    required this.videoUrl,
    required this.isVideo,
    required this.isReel,
    required this.autoPlay,
    required this.fallbackColor,
    required this.cacheIdentity,
    required this.cacheVersion,
    required this.muted,
    required this.muteLabel,
    required this.onToggleMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (isVideo && autoPlay)
          _InlineFeedVideoPreview(
            posterUrl: posterUrl,
            videoUrl: videoUrl,
            fallbackColor: fallbackColor,
            muted: muted,
            cacheIdentity: cacheIdentity,
            cacheVersion: cacheVersion,
          )
        else if (posterUrl.trim().isEmpty)
          ColoredBox(
            color: fallbackColor,
            child: Icon(
              isVideo
                  ? Icons.play_circle_outline_rounded
                  : Icons.image_outlined,
              size: 46,
            ),
          )
        else
          CachedAppImage(
            imageUrl: posterUrl,
            cacheIdentity: '${cacheIdentity}_poster',
            version: cacheVersion,
            fit: BoxFit.cover,
            errorWidget: (context, error, stackTrace) => ColoredBox(
              color: fallbackColor,
              child: const Icon(Icons.broken_image_outlined, size: 36),
            ),
          ),
        if (isVideo && !autoPlay)
          PositionedDirectional(
            end: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          )
        else if (isReel && autoPlay)
          PositionedDirectional(
            top: 12,
            start: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.36),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    context.lt(ar: 'ريلز', en: 'Reels'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (isVideo && autoPlay)
          PositionedDirectional(
            start: 10,
            bottom: 10,
            child: _FeedPreviewMuteButton(
              muted: muted,
              tooltip: muteLabel,
              onTap: onToggleMuted,
            ),
          ),
      ],
    );
  }
}

class _InlineFeedMediaGalleryPreview extends StatefulWidget {
  final List<_PostMediaDisplayItem> items;
  final double aspectRatio;
  final bool autoPlay;
  final Color fallbackColor;
  final String cacheIdentity;
  final String? cacheVersion;

  const _InlineFeedMediaGalleryPreview({
    required this.items,
    required this.aspectRatio,
    required this.autoPlay,
    required this.fallbackColor,
    required this.cacheIdentity,
    required this.cacheVersion,
  });

  @override
  State<_InlineFeedMediaGalleryPreview> createState() =>
      _InlineFeedMediaGalleryPreviewState();
}

class _InlineFeedMediaGalleryPreviewState
    extends State<_InlineFeedMediaGalleryPreview> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  static bool _rememberedMuted = true;
  late bool _muted;

  @override
  void initState() {
    super.initState();
    _muted = _rememberedMuted;
  }

  void _toggleMuted() {
    setState(() {
      _muted = !_muted;
      _rememberedMuted = _muted;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.length == 1) {
      final item = items.first;
      return _InlineFeedMediaPreview(
        posterUrl: item.posterUrl,
        videoUrl: item.videoUrl,
        aspectRatio: widget.aspectRatio,
        isVideo: item.isVideo,
        isReel: item.isReel,
        autoPlay: widget.autoPlay,
        fallbackColor: widget.fallbackColor,
        cacheIdentity: widget.cacheIdentity,
        cacheVersion: widget.cacheVersion,
      );
    }
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            onPageChanged: (value) => setState(() => _currentIndex = value),
            itemBuilder: (context, index) {
              final item = items[index];
              return _InlineFeedMediaContent(
                posterUrl: item.posterUrl,
                videoUrl: item.videoUrl,
                isVideo: item.isVideo,
                isReel: item.isReel,
                autoPlay: widget.autoPlay && index == _currentIndex,
                fallbackColor: widget.fallbackColor,
                cacheIdentity: '${widget.cacheIdentity}_$index',
                cacheVersion: widget.cacheVersion,
                muted: _muted,
                muteLabel: _muted
                    ? context.l10n.socialReelUnmute
                    : context.l10n.socialReelMute,
                onToggleMuted: _toggleMuted,
              );
            },
          ),
          PositionedDirectional(
            top: 12,
            end: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_currentIndex + 1}/${items.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(items.length, (index) {
                final active = index == _currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostMediaDisplayItem {
  final String posterUrl;
  final String? videoUrl;
  final bool isVideo;
  final bool isReel;

  const _PostMediaDisplayItem({
    required this.posterUrl,
    required this.videoUrl,
    required this.isVideo,
    required this.isReel,
  });
}

List<_PostMediaDisplayItem> _buildPostMediaDisplayItems(SocialPost post) {
  if (post.mediaGallery.isNotEmpty) {
    final items = <_PostMediaDisplayItem>[];
    for (final media in post.mediaGallery) {
      final mediaKind = (media.mediaKind ?? '').trim().toLowerCase();
      final isVideo = mediaKind == 'video' || mediaKind == 'reel';
      final isReel = mediaKind == 'reel' || isSocialReelPost(post);
      final videoUrl = isVideo
          ? (media.asset?.playbackUrl ??
                    media.asset?.normalizedUrl ??
                    media.mediaUrl)
                ?.trim()
          : null;
      final posterUrl =
          (media.asset?.thumbnailUrl ??
                  media.asset?.posterUrl ??
                  socialCloudflareThumbnail(media.asset) ??
                  (!isVideo
                      ? (media.asset?.normalizedUrl ?? media.mediaUrl)
                      : null) ??
                  '')
              .trim();
      if (posterUrl.isEmpty && (videoUrl ?? '').isEmpty) {
        continue;
      }
      items.add(
        _PostMediaDisplayItem(
          posterUrl: posterUrl,
          videoUrl: videoUrl,
          isVideo: isVideo,
          isReel: isReel,
        ),
      );
    }
    if (items.isNotEmpty) {
      return items;
    }
  }

  final posterUrl = resolveSocialPostPosterUrl(post)?.trim();
  final videoUrl = resolveSocialPostVideoUrl(post)?.trim();
  if ((posterUrl == null || posterUrl.isEmpty) && (videoUrl ?? '').isEmpty) {
    return const <_PostMediaDisplayItem>[];
  }
  return <_PostMediaDisplayItem>[
    _PostMediaDisplayItem(
      posterUrl: posterUrl ?? '',
      videoUrl: videoUrl,
      isVideo: isSocialVideoPost(post),
      isReel: isSocialReelPost(post),
    ),
  ];
}

class _MerchantReviewPreview extends StatelessWidget {
  final SocialPost post;
  final VoidCallback? onOpenMerchantLink;

  const _MerchantReviewPreview({
    required this.post,
    required this.onOpenMerchantLink,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final merchantName = (post.merchantName ?? '').trim();
    final merchantImage = (post.merchantImageUrl ?? '').trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpenMerchantLink,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: merchantImage.isNotEmpty
                    ? appCachedImageProvider(
                        merchantImage,
                        cacheIdentity: 'merchant_${post.merchantId ?? 0}',
                        version: post.updatedAt?.toIso8601String(),
                      )
                    : null,
                child: merchantImage.isEmpty
                    ? const Icon(Icons.storefront_outlined)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchantName.isNotEmpty ? merchantName : l10n.commonStore,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.socialOpenStoreCta,
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineFeedVideoPreview extends StatefulWidget {
  final String posterUrl;
  final String? videoUrl;
  final Color fallbackColor;
  final bool muted;
  final String cacheIdentity;
  final String? cacheVersion;

  const _InlineFeedVideoPreview({
    required this.posterUrl,
    required this.videoUrl,
    required this.fallbackColor,
    required this.muted,
    required this.cacheIdentity,
    required this.cacheVersion,
  });

  @override
  State<_InlineFeedVideoPreview> createState() =>
      _InlineFeedVideoPreviewState();
}

class _InlineFeedVideoPreviewState extends State<_InlineFeedVideoPreview>
    with WidgetsBindingObserver, RouteAware {
  static final ValueNotifier<String?> _activeVideoKey = ValueNotifier<String?>(
    null,
  );
  final GlobalKey _containerKey = GlobalKey();
  VideoPlayerController? _controller;
  ModalRoute<dynamic>? _route;
  ScrollPosition? _scrollPosition;
  bool _videoReady = false;
  bool _appActive = true;
  bool _routeVisible = true;
  bool _tickerEnabled = true;
  bool _scrollIdle = true;
  bool _visibilityCheckQueued = false;
  bool _initializing = false;
  int _initializationGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeVideoKey.addListener(_onActiveVideoChanged);
    _scheduleVisibilityCheck();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextTickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_tickerEnabled != nextTickerEnabled) {
      _tickerEnabled = nextTickerEnabled;
      if (!_tickerEnabled) {
        _pausePlayback();
      }
    }
    final nextRoute = ModalRoute.of(context);
    if (!identical(_route, nextRoute)) {
      if (_route != null) {
        appRouteObserver.unsubscribe(this);
      }
      _route = nextRoute;
      _routeVisible = nextRoute?.isCurrent ?? true;
      if (nextRoute != null) {
        appRouteObserver.subscribe(this, nextRoute);
      }
      if (!_routeVisible) {
        _pausePlayback();
      }
    }
    _bindScrollPosition();
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(covariant _InlineFeedVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.videoUrl ?? '').trim() != (widget.videoUrl ?? '').trim()) {
      unawaited(_disposeController());
      _scheduleVisibilityCheck();
      return;
    }
    if (oldWidget.muted != widget.muted && _controller != null) {
      unawaited(_controller!.setVolume(widget.muted ? 0 : 1));
    }
    _scheduleVisibilityCheck();
  }

  void _bindScrollPosition() {
    final nextPosition = Scrollable.maybeOf(context)?.position;
    if (identical(_scrollPosition, nextPosition)) return;
    if (_scrollPosition != null) {
      _scrollPosition!.removeListener(_handleScroll);
      _scrollPosition!.isScrollingNotifier.removeListener(
        _handleScrollActivityChanged,
      );
    }
    _scrollPosition = nextPosition;
    if (_scrollPosition != null) {
      _scrollPosition!.addListener(_handleScroll);
      _scrollPosition!.isScrollingNotifier.addListener(
        _handleScrollActivityChanged,
      );
      _scrollIdle = !_scrollPosition!.isScrollingNotifier.value;
    } else {
      _scrollIdle = true;
    }
  }

  void _handleScroll() {
    if (_scrollPosition?.isScrollingNotifier.value == true) {
      final controller = _controller;
      if (controller != null &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        unawaited(controller.pause());
      }
      if (_activeVideoKey.value == widget.cacheIdentity) {
        _activeVideoKey.value = null;
      }
    }
    _scheduleVisibilityCheck();
  }

  void _handleScrollActivityChanged() {
    _scrollIdle = !(_scrollPosition?.isScrollingNotifier.value ?? false);
    _scheduleVisibilityCheck();
  }

  Future<void> _initializeVideo() async {
    if (!appSupportsInlineVideoPlayback || _initializing) return;
    final generation = ++_initializationGeneration;
    final rawUrl = (widget.videoUrl ?? '').trim();
    if (rawUrl.isEmpty) return;
    _initializing = true;
    VideoPlayerController? controller;
    try {
      final source = await MediaCacheService.instance.resolveVideoSource(
        url: rawUrl,
        cacheIdentity: '${widget.cacheIdentity}_video',
        version: widget.cacheVersion,
        scope: MediaCacheScope.public,
      );
      if (!mounted || generation != _initializationGeneration) return;
      controller = source.isLocalFile
          ? VideoPlayerController.file(source.file!)
          : VideoPlayerController.networkUrl(source.uri);
      await controller.initialize().timeout(const Duration(seconds: 20));
      await controller.setLooping(true);
      await controller.setVolume(widget.muted ? 0 : 1);
      if (!mounted || generation != _initializationGeneration) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _videoReady = true;
      setState(() {});
      _scheduleVisibilityCheck();
    } catch (_) {
      await controller?.dispose();
    } finally {
      _initializing = false;
      if (mounted && generation != _initializationGeneration) {
        _scheduleVisibilityCheck();
      }
    }
  }

  void _scheduleVisibilityCheck() {
    if (!mounted || _visibilityCheckQueued) return;
    _visibilityCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckQueued = false;
      if (!mounted) return;
      unawaited(_syncPlaybackToViewport());
    });
  }

  double _visibleFraction() {
    final renderObject = _containerKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return 0;
    final size = renderObject.size;
    if (size.height <= 0) return 0;
    final offset = renderObject.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final top = offset.dy;
    final bottom = offset.dy + size.height;
    final visibleTop = top.clamp(0.0, screenHeight);
    final visibleBottom = bottom.clamp(0.0, screenHeight);
    final visibleHeight = (visibleBottom - visibleTop).clamp(0.0, size.height);
    return visibleHeight / size.height;
  }

  Future<void> _syncPlaybackToViewport() async {
    // Sliver cache children are built before they enter the viewport. Do not
    // let their downloads/decoders compete with the visible post.
    if (_controller == null &&
        !_initializing &&
        _appActive &&
        _routeVisible &&
        _tickerEnabled &&
        _scrollIdle &&
        _visibleFraction() >= 0.72) {
      await _initializeVideo();
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final shouldPlay =
        _appActive &&
        _routeVisible &&
        _tickerEnabled &&
        _scrollIdle &&
        _visibleFraction() >= 0.72;
    if (shouldPlay) {
      if (_activeVideoKey.value != widget.cacheIdentity) {
        _activeVideoKey.value = widget.cacheIdentity;
      }
      if (!controller.value.isPlaying) {
        await controller.play();
      }
    } else if (controller.value.isPlaying) {
      await controller.pause();
    }
    if (!shouldPlay && _activeVideoKey.value == widget.cacheIdentity) {
      _activeVideoKey.value = null;
    }
  }

  void _pausePlayback() {
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isPlaying) {
      unawaited(controller.pause());
    }
    if (_activeVideoKey.value == widget.cacheIdentity) {
      _activeVideoKey.value = null;
    }
  }

  void _onActiveVideoChanged() {
    final controller = _controller;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }
    if (_activeVideoKey.value != widget.cacheIdentity &&
        controller.value.isPlaying) {
      unawaited(controller.pause());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) {
      _pausePlayback();
    }
    _scheduleVisibilityCheck();
  }

  @override
  void didPush() {
    _routeVisible = true;
    _scheduleVisibilityCheck();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _scheduleVisibilityCheck();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _pausePlayback();
  }

  @override
  void didPop() {
    _routeVisible = false;
    _pausePlayback();
  }

  Future<void> _disposeController() async {
    _initializationGeneration++;
    final controller = _controller;
    _controller = null;
    _videoReady = false;
    if (controller != null) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _scrollPosition?.removeListener(_handleScroll);
    _scrollPosition?.isScrollingNotifier.removeListener(
      _handleScrollActivityChanged,
    );
    _activeVideoKey.removeListener(_onActiveVideoChanged);
    if (_activeVideoKey.value == widget.cacheIdentity) {
      _activeVideoKey.value = null;
    }
    unawaited(_disposeController());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _containerKey,
      child:
          _videoReady && _controller != null && _controller!.value.isInitialized
          ? FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          : widget.posterUrl.trim().isEmpty
          ? ColoredBox(
              color: widget.fallbackColor,
              child: const Icon(Icons.play_circle_outline_rounded, size: 46),
            )
          : CachedAppImage(
              imageUrl: widget.posterUrl,
              cacheIdentity: '${widget.cacheIdentity}_video_poster',
              version: widget.cacheVersion,
              fit: BoxFit.cover,
              errorWidget: (context, error, stackTrace) => ColoredBox(
                color: widget.fallbackColor,
                child: const Icon(Icons.broken_image_outlined, size: 36),
              ),
            ),
    );
  }
}

class _FeedPreviewMuteButton extends StatelessWidget {
  final bool muted;
  final String tooltip;
  final VoidCallback onTap;

  const _FeedPreviewMuteButton({
    required this.muted,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.42),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
