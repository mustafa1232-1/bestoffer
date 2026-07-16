import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:video_player/video_player.dart';

import '../../../../core/platform/app_platform_capabilities.dart';
import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/media/media_cache_models.dart';
import '../../../../core/media/media_cache_service.dart';
import '../../models/social_models.dart';
import '../social_share_sheet.dart';
import 'social_mention_hashtag_text.dart';

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
    final callback = onReport;
    if (callback == null) return;
    try {
      await callback.call();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.socialProfileReportSubmitFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final scheme = Theme.of(context).colorScheme;
    final dateText = post.createdAt == null
        ? ''
        : intl.DateFormat(
            isEnglish ? 'MMM d, h:mm a' : 'd MMM - h:mm a',
            isEnglish ? 'en' : 'ar',
          ).format(post.createdAt!);
    final mediaUrl = resolveSocialPostPosterUrl(post);
    final isVideo = isSocialVideoPost(post);
    final isReel = isSocialReelPost(post);
    final isMerchantReview = isSocialMerchantReviewPost(post);
    final mediaItems = _buildPostMediaDisplayItems(post);
    final caption = post.caption.trim();
    final hasCaption = caption.isNotEmpty;
    final username = (post.author.username ?? '').trim();
    final userLabel = username.isNotEmpty ? '@$username' : '@${post.author.id}';
    final showPremiumBadge =
        post.author.isPremiumCreator ||
        post.author.badges.any((badge) => badge == 'premium_creator');
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: scheme.surface,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.36),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpenDetails,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: onOpenProfile,
                    child: CircleAvatar(
                      radius: 22,
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
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  userLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (showPremiumBadge) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.verified_rounded,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isReel)
                    const _MiniBadge(
                      label: 'Reel',
                      icon: Icons.play_circle_outline_rounded,
                    ),
                  if (onReport != null)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value != 'report') return;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!context.mounted) return;
                          Future<void>.delayed(
                            const Duration(milliseconds: 220),
                            () {
                              if (!context.mounted) return;
                              unawaited(_runReportSafely(context));
                            },
                          );
                        });
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem<String>(
                          value: 'report',
                          child: Text(l10n.commonReport),
                        ),
                      ],
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                ],
              ),
              if (hasCaption) ...[
                const SizedBox(height: 12),
                SocialMentionHashtagText(
                  text: caption,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
                if (dateText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      dateText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ] else if (dateText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    dateText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              if (mediaItems.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  // Bound the media height so a reel/portrait card never occupies
                  // almost the whole screen inside the Community feed (§9).
                  constraints: const BoxConstraints(maxHeight: 460),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _InlineFeedMediaGalleryPreview(
                      items: mediaItems,
                      // Compact vertical preview for reels (4:5), not full-screen
                      // 9:16; normal images use 4:5 too.
                      aspectRatio: 4 / 5,
                      autoPlay: false,
                      fallbackColor: scheme.surfaceContainerHighest,
                      cacheIdentity: 'post_${post.id}',
                      cacheVersion: post.updatedAt?.toIso8601String(),
                    ),
                  ),
                ),
              ],
              if (post.reviewRating != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 4,
                  children: List<Widget>.generate(
                    5,
                    (index) => Icon(
                      index < post.reviewRating!
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: const Color(0xFFF4B942),
                      size: 18,
                    ),
                  ),
                ),
              ],
              if (isMerchantReview) ...[
                const SizedBox(height: 10),
                _MerchantReviewPreview(
                  post: post,
                  onOpenMerchantLink: onOpenMerchantLink,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    icon: post.isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: '${post.likesCount}',
                    accent: post.isLiked ? const Color(0xFFDD4268) : null,
                    onTap: onToggleLike,
                  ),
                  _MetricChip(
                    icon: Icons.mode_comment_outlined,
                    label: '${post.commentsCount}',
                    onTap: onOpenComments == null
                        ? null
                        : () async => onOpenComments!.call(),
                  ),
                  _MetricChip(
                    icon: post.isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    label: '${post.savesCount}',
                    accent: post.isSaved ? const Color(0xFF3468E8) : null,
                    onTap: onToggleSave,
                  ),
                  _MetricChip(
                    icon: isVideo
                        ? Icons.ondemand_video_outlined
                        : Icons.visibility_outlined,
                    label:
                        '${isVideo ? post.reelViewsCount : post.impressionsCount}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (post.contentLink != null || post.merchantId != null)
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: onOpenMerchantLink,
                        icon: const Icon(Icons.storefront_outlined),
                        label: Text(
                          isMerchantReview
                              ? l10n.socialOpenStoreCta
                              : l10n.socialPostCardOpenLinkedCommerce,
                        ),
                      ),
                    ),
                  if (post.contentLink != null || post.merchantId != null)
                    const SizedBox(width: 8),
                  IconButton(
                    tooltip: l10n.commonShare,
                    onPressed: () => showSocialShareSheet(
                      context: context,
                      entityType: socialEntityTypeFromPost(post),
                      entityId: post.id,
                      previewTitle: userLabel,
                      previewSubtitle: post.caption.trim(),
                      externalShareText: [
                        post.caption.trim(),
                        if ((mediaUrl ?? '').trim().isNotEmpty) mediaUrl!,
                      ].where((item) => item.trim().isNotEmpty).join('\n'),
                      sharedSnapshot: buildSocialSharedSnapshotFromPost(post),
                    ),
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                ],
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
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Reel',
                    style: TextStyle(
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
      final isReel = mediaKind == 'reel';
      final posterUrl =
          (media.asset?.thumbnailUrl ??
                  media.asset?.posterUrl ??
                  socialCloudflareThumbnail(media.asset) ??
                  (!isVideo
                      ? (media.asset?.normalizedUrl ?? media.mediaUrl)
                      : null) ??
                  '')
              .trim();
      if (posterUrl.isEmpty) {
        continue;
      }
      items.add(
        _PostMediaDisplayItem(
          posterUrl: posterUrl,
          videoUrl: isVideo
              ? (media.asset?.playbackUrl ??
                        media.asset?.normalizedUrl ??
                        media.mediaUrl)
                    ?.trim()
              : null,
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
  if (posterUrl == null || posterUrl.isEmpty) {
    return const <_PostMediaDisplayItem>[];
  }
  return <_PostMediaDisplayItem>[
    _PostMediaDisplayItem(
      posterUrl: posterUrl,
      videoUrl: resolveSocialPostVideoUrl(post)?.trim(),
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
    with WidgetsBindingObserver {
  static final ValueNotifier<String?> _activeVideoKey = ValueNotifier<String?>(
    null,
  );
  final GlobalKey _containerKey = GlobalKey();
  VideoPlayerController? _controller;
  ScrollPosition? _scrollPosition;
  bool _videoReady = false;
  bool _appActive = true;
  bool _scrollIdle = true;
  bool _visibilityCheckQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeVideoKey.addListener(_onActiveVideoChanged);
    _initializeVideo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindScrollPosition();
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(covariant _InlineFeedVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.videoUrl ?? '').trim() != (widget.videoUrl ?? '').trim()) {
      unawaited(_disposeController());
      _initializeVideo();
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
    if (!appSupportsInlineVideoPlayback) return;
    final rawUrl = (widget.videoUrl ?? '').trim();
    if (rawUrl.isEmpty) return;
    final source = await MediaCacheService.instance.resolveVideoSource(
      url: rawUrl,
      cacheIdentity: '${widget.cacheIdentity}_video',
      version: widget.cacheVersion,
      scope: MediaCacheScope.public,
    );
    final controller = source.isLocalFile
        ? VideoPlayerController.file(source.file!)
        : VideoPlayerController.networkUrl(source.uri);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(widget.muted ? 0 : 1);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _videoReady = true;
      setState(() {});
      _scheduleVisibilityCheck();
    } catch (_) {
      await controller.dispose();
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
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final shouldPlay = _appActive && _scrollIdle && _visibleFraction() >= 0.72;
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
    _scheduleVisibilityCheck();
  }

  Future<void> _disposeController() async {
    if (_scrollPosition != null) {
      _scrollPosition!.removeListener(_handleScroll);
      _scrollPosition!.isScrollingNotifier.removeListener(
        _handleScrollActivityChanged,
      );
      _scrollPosition = null;
    }
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
            width: 40,
            height: 40,
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

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accent;
  final Future<void> Function()? onTap;

  const _MetricChip({
    required this.icon,
    required this.label,
    this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = accent ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap == null ? null : () => onTap!.call(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: baseColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: baseColor, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _MiniBadge({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
