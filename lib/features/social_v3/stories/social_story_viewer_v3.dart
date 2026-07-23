import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/media/media_url.dart';
import '../../../core/i18n/locale_text.dart';
import '../domain/story_view_data.dart';
import '../media/social_safe_image.dart';
import 'story_media_surface_v3.dart';
import 'story_progress_bar_v3.dart';

/// Full-screen story viewer (§5).
///
/// This is a full-screen route — **never** a `showModalBottomSheet`. There is
/// no drag handle, no 84%-height container, no rounded bottom-sheet shell. The
/// content is edge-to-edge 9:16 with a black backdrop around non-vertical media.
///
/// Progress semantics:
///  * The progress bar shows only the *current group's* items.
///  * Images run for a default 5s; videos use their real (or explicit clip)
///    duration and advance exactly once on completion — they never loop.
///  * Buffering pauses progress; a lifecycle pause preserves position.
class SocialStoryViewerV3 extends StatefulWidget {
  const SocialStoryViewerV3({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
    this.initialItemIndex = 0,
    this.onView,
    this.onOpenSharedReel,
    this.onToggleLike,
    this.onOpenComments,
    this.onShare,
    this.onMetric,
    this.videoFactory,
  }) : assert(groups.length > 0);

  final List<StoryV3Group> groups;
  final int initialGroupIndex;
  final int initialItemIndex;

  /// Called once per (user, story) per session for view counting.
  final void Function(int userId, int storyId)? onView;
  final void Function(SharedReelRef ref)? onOpenSharedReel;
  final StoryV3LikeCallback? onToggleLike;
  final StoryV3CommentsCallback? onOpenComments;
  final StoryV3ShareCallback? onShare;
  final SocialStoryMetricCallback? onMetric;

  /// Test seam for the video controller.
  final VideoPlayerController Function(String url)? videoFactory;

  /// Opens the viewer as an opaque full-screen route (fade transition).
  static Route<void> route({
    required List<StoryV3Group> groups,
    int initialGroupIndex = 0,
    int initialItemIndex = 0,
    void Function(int userId, int storyId)? onView,
    void Function(SharedReelRef ref)? onOpenSharedReel,
    StoryV3LikeCallback? onToggleLike,
    StoryV3CommentsCallback? onOpenComments,
    StoryV3ShareCallback? onShare,
    SocialStoryMetricCallback? onMetric,
  }) {
    return PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) =>
          SocialStoryViewerV3(
            groups: groups,
            initialGroupIndex: initialGroupIndex,
            initialItemIndex: initialItemIndex,
            onView: onView,
            onOpenSharedReel: onOpenSharedReel,
            onToggleLike: onToggleLike,
            onOpenComments: onOpenComments,
            onShare: onShare,
            onMetric: onMetric,
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  State<SocialStoryViewerV3> createState() => _SocialStoryViewerV3State();
}

class _SocialStoryViewerV3State extends State<SocialStoryViewerV3>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final PageController _groupPager;
  late final AnimationController _imageCtrl;
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  final Set<String> _viewed = {};
  final Map<int, bool> _likedByStoryId = <int, bool>{};
  final Map<int, int> _likesByStoryId = <int, int>{};
  final Map<int, int> _commentsByStoryId = <int, int>{};
  final Set<int> _likeBusyStoryIds = <int>{};
  final Map<int, VideoPlayerController> _videoControllers =
      <int, VideoPlayerController>{};
  final Map<int, String> _videoControllerUrls = <int, String>{};
  final Map<int, Future<void>> _videoInitFutures = <int, Future<void>>{};
  final Set<String> _reportedMetrics = <String>{};
  final DateTime _openedAt = DateTime.now();
  DateTime? _itemStartedAt;
  bool _currentItemStartedFromAdvance = false;

  VideoPlayerController? _video;
  int? _activeVideoIndex;
  int _groupIndex = 0;
  int _itemIndex = 0;
  bool _gesturePaused = false;
  bool _lifecyclePaused = false;
  int _overlayPauseDepth = 0;
  bool _advancing = false;
  int? _pendingImageReadyStoryId;

  StoryV3Group get _group => widget.groups[_groupIndex];
  StoryV3Item? get _item =>
      _itemIndex < _group.items.length ? _group.items[_itemIndex] : null;
  bool get _isProgressPaused =>
      _gesturePaused || _lifecyclePaused || _overlayPauseDepth > 0;

  bool _isLiked(StoryV3Item item) =>
      _likedByStoryId[item.storyId] ?? item.isLiked;

  int _likesCount(StoryV3Item item) =>
      _likesByStoryId[item.storyId] ?? item.likesCount;

  int _commentsCount(StoryV3Item item) =>
      _commentsByStoryId[item.storyId] ?? item.commentsCount;

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex
        .clamp(0, widget.groups.length - 1)
        .toInt();
    final initialItems = widget.groups[_groupIndex].items;
    if (initialItems.isNotEmpty) {
      _itemIndex = widget.initialItemIndex
          .clamp(0, initialItems.length - 1)
          .toInt();
    }
    _groupPager = PageController(initialPage: _groupIndex);
    _imageCtrl = AnimationController(vsync: this)
      ..addListener(() => _progress.value = _imageCtrl.value)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncVideoWindow();
      _startItem();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _imageCtrl.dispose();
    _disposeActiveVideo();
    for (final controller in _videoControllers.values) {
      controller.removeListener(_onVideoTick);
      controller.dispose();
    }
    _videoControllers.clear();
    _videoControllerUrls.clear();
    _videoInitFutures.clear();
    _progress.dispose();
    _groupPager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecyclePaused = state != AppLifecycleState.resumed;
    if (_lifecyclePaused) {
      _pause();
    } else {
      _resume();
    }
  }

  void _recordView() {
    final item = _item;
    if (item == null) return;
    final key = '${_group.userId}:${item.storyId}';
    if (_viewed.add(key)) {
      widget.onView?.call(_group.userId, item.storyId);
    }
  }

  void _disposeActiveVideo() {
    final index = _activeVideoIndex;
    final controller = index == null ? _video : _videoControllers[index];
    controller?.removeListener(_onVideoTick);
    controller?.pause();
    _video = null;
    _activeVideoIndex = null;
  }

  void _startItem() {
    _advancing = false;
    _imageCtrl.stop();
    _disposeActiveVideo();
    _progress.value = 0;
    final item = _item;
    if (item == null) {
      _next();
      return;
    }
    _recordView();
    _itemStartedAt = DateTime.now();
    final startedByAdvance = _currentItemStartedFromAdvance;
    _currentItemStartedFromAdvance = false;
    _syncVideoWindow();

    if (item.isVideo && item.media.hasVideo) {
      _startVideo(item, startedByAdvance: startedByAdvance);
    } else {
      _startImage(item, startedByAdvance: startedByAdvance);
    }
  }

  void _startImage(StoryV3Item item, {required bool startedByAdvance}) {
    _imageCtrl.duration = item.imageDuration;
    final posterUrl = (item.media.posterImageUrl ?? '').trim();
    if (posterUrl.isEmpty) {
      _pendingImageReadyStoryId = null;
      if (!_isProgressPaused) _imageCtrl.forward(from: 0);
      _reportFirstFrameMetric(startedByAdvance: startedByAdvance);
      return;
    }

    final storyId = item.storyId;
    _pendingImageReadyStoryId = storyId;
    unawaited(() async {
      final resolved = resolveMediaUrl(posterUrl) ?? posterUrl;
      try {
        await precacheImage(
          NetworkImage(resolved),
          context,
        ).timeout(const Duration(seconds: 12));
      } catch (_) {
        // A broken/slow image must not auto-skip before the user sees the
        // placeholder. After the bounded wait, start progress from zero.
      }
      if (!mounted ||
          _pendingImageReadyStoryId != storyId ||
          _item?.storyId != storyId) {
        return;
      }
      _pendingImageReadyStoryId = null;
      if (!_isProgressPaused) _imageCtrl.forward(from: 0);
      _reportFirstFrameMetric(startedByAdvance: startedByAdvance);
    }());
  }

  void _startVideo(StoryV3Item item, {required bool startedByAdvance}) {
    final index = _itemIndex;
    final controller = _ensureVideoController(
      index,
      activate: true,
      startedByAdvance: startedByAdvance,
    );
    if (controller == null) {
      return;
    }
    if (controller.value.isInitialized) {
      _attachActiveVideoController(
        index,
        controller,
        startedByAdvance: startedByAdvance,
      );
    }
  }

  void _onVideoTick() {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    final item = _item;
    if (item == null) return;

    final total = item.clipDuration ?? controller.value.duration;
    final startMs = item.clipStart?.inMilliseconds ?? 0;
    final posMs = controller.value.position.inMilliseconds - startMs;
    final totalMs = total.inMilliseconds;
    if (totalMs <= 0) return;

    _progress.value = (posMs / totalMs).clamp(0.0, 1.0);

    final reachedEnd =
        posMs >= totalMs ||
        (controller.value.position >= controller.value.duration &&
            !controller.value.isPlaying);
    if (reachedEnd) {
      controller.removeListener(_onVideoTick);
      _next();
    }
  }

  void _pause() {
    _imageCtrl.stop();
    _video?.pause();
  }

  void _resume() {
    if (_isProgressPaused) return;
    final item = _item;
    if (item == null) return;
    if (item.isVideo && item.media.hasVideo) {
      _video?.play();
    } else if (_pendingImageReadyStoryId != item.storyId &&
        !_imageCtrl.isAnimating) {
      _imageCtrl.forward();
    }
  }

  void _reportMetricOnce(String name, Duration elapsed) {
    final item = _item;
    final storyId = item?.storyId ?? -1;
    final key = '$name:${_groupIndex}_$_itemIndex:$storyId';
    if (_reportedMetrics.add(key)) {
      widget.onMetric?.call(name, elapsed);
    }
  }

  void _reportFirstFrameMetric({required bool startedByAdvance}) {
    final startedAt = _itemStartedAt ?? _openedAt;
    _reportMetricOnce(
      startedByAdvance ? 'storyNextItemFirstFrameMs' : 'storyTapToFirstFrameMs',
      DateTime.now().difference(startedAt),
    );
  }

  StoryV3Item? _itemAtIndex(int index) {
    if (index < 0 || index >= _group.items.length) return null;
    return _group.items[index];
  }

  VideoPlayerController? _ensureVideoController(
    int index, {
    required bool activate,
    required bool startedByAdvance,
  }) {
    final item = _itemAtIndex(index);
    if (item == null || !item.isVideo || !item.media.hasVideo) return null;
    final effectiveUrl = item.media.videoPlaybackUrl!;
    final existing = _videoControllers[index];
    if (existing != null && _videoControllerUrls[index] == effectiveUrl) {
      if (activate) {
        _attachActiveVideoController(
          index,
          existing,
          startedByAdvance: startedByAdvance,
        );
      }
      return existing;
    }

    if (existing != null) {
      existing.removeListener(_onVideoTick);
      existing.pause();
      existing.dispose();
    }

    final controller =
        widget.videoFactory?.call(effectiveUrl) ??
        VideoPlayerController.networkUrl(Uri.parse(effectiveUrl));
    _videoControllers[index] = controller;
    _videoControllerUrls[index] = effectiveUrl;
    controller.setLooping(false);
    _videoInitFutures[index] = controller
        .initialize()
        .then((_) {
          if (!mounted || _videoControllers[index] != controller) return;
          if (activate && _itemIndex == index) {
            _attachActiveVideoController(
              index,
              controller,
              startedByAdvance: startedByAdvance,
            );
          }
        })
        .catchError((Object _) {
          if (!mounted || _videoControllers[index] != controller) return;
          if (activate && _itemIndex == index) setState(() {});
        });
    if (activate && _itemIndex == index) {
      _video = controller;
      _activeVideoIndex = index;
    }
    return controller;
  }

  void _attachActiveVideoController(
    int index,
    VideoPlayerController controller, {
    required bool startedByAdvance,
  }) {
    final previousIndex = _activeVideoIndex;
    if (previousIndex != null && previousIndex != index) {
      _videoControllers[previousIndex]?.removeListener(_onVideoTick);
      if (_videoControllers[previousIndex] != null &&
          !identical(_videoControllers[previousIndex], controller)) {
        _videoControllers[previousIndex]?.pause();
      }
    }
    _activeVideoIndex = index;
    _video = controller;
    controller.removeListener(_onVideoTick);
    controller.addListener(_onVideoTick);
    controller.setVolume(1);
    if (controller.value.isInitialized) {
      final start = _item?.clipStart;
      if (start != null) {
        unawaited(controller.seekTo(start));
      }
      if (!_isProgressPaused) {
        unawaited(controller.play());
      }
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _activeVideoIndex != index) return;
          _reportFirstFrameMetric(startedByAdvance: startedByAdvance);
        });
      }
    }
  }

  void _syncVideoWindow() {
    final indexes = <int>{
      _itemIndex - 1,
      _itemIndex,
      _itemIndex + 1,
    }.where((index) => index >= 0 && index < _group.items.length).toList();

    for (final index in indexes) {
      final item = _itemAtIndex(index);
      if (item == null || !item.isVideo || !item.media.hasVideo) continue;
      final url = item.media.videoPlaybackUrl!;
      final existing = _videoControllers[index];
      if (existing != null && _videoControllerUrls[index] == url) {
        continue;
      }
      _ensureVideoController(
        index,
        activate: index == _itemIndex,
        startedByAdvance: index == _itemIndex && _currentItemStartedFromAdvance,
      );
    }

    for (final index in _videoControllers.keys.toList()) {
      if (indexes.contains(index)) continue;
      final controller = _videoControllers.remove(index);
      _videoControllerUrls.remove(index);
      _videoInitFutures.remove(index);
      controller?.removeListener(_onVideoTick);
      controller?.pause();
      controller?.dispose();
    }
  }

  Future<T> _withOverlayPause<T>(Future<T> Function() action) async {
    _overlayPauseDepth += 1;
    _pause();
    try {
      return await action();
    } finally {
      _overlayPauseDepth = (_overlayPauseDepth - 1).clamp(0, 1 << 30).toInt();
      if (mounted) _resume();
    }
  }

  Future<void> _toggleLike(StoryV3Item item) async {
    final callback = widget.onToggleLike;
    if (!item.allowLikes ||
        callback == null ||
        _likeBusyStoryIds.contains(item.storyId)) {
      return;
    }

    final wasLiked = _isLiked(item);
    final originalCount = _likesCount(item);
    setState(() {
      _likeBusyStoryIds.add(item.storyId);
      _likedByStoryId[item.storyId] = !wasLiked;
      _likesByStoryId[item.storyId] = (originalCount + (wasLiked ? -1 : 1))
          .clamp(0, 1 << 30)
          .toInt();
    });

    try {
      final result = await callback(item.storyId);
      if (!mounted) return;
      setState(() {
        if (result == null) {
          _likedByStoryId[item.storyId] = wasLiked;
          _likesByStoryId[item.storyId] = originalCount;
          return;
        }
        final liked = result.isLiked;
        final likesCount = result.likesCount;
        if (liked != null) _likedByStoryId[item.storyId] = liked;
        if (likesCount != null) {
          _likesByStoryId[item.storyId] = likesCount.clamp(0, 1 << 30).toInt();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _likedByStoryId[item.storyId] = wasLiked;
        _likesByStoryId[item.storyId] = originalCount;
      });
    } finally {
      if (mounted) {
        setState(() => _likeBusyStoryIds.remove(item.storyId));
      }
    }
  }

  Future<void> _openComments(StoryV3Item item) async {
    final callback = widget.onOpenComments;
    if (!item.allowComments || callback == null) return;
    final added = await _withOverlayPause(() => callback(item.storyId));
    if (!mounted || added == null || added <= 0) return;
    setState(() {
      _commentsByStoryId[item.storyId] = (_commentsCount(item) + added)
          .clamp(0, 1 << 30)
          .toInt();
    });
  }

  Future<void> _share(StoryV3Item item) async {
    final callback = widget.onShare;
    if (!item.allowSharing || callback == null) return;
    await _withOverlayPause(() => callback(item.storyId));
  }

  void _next() {
    if (_advancing) return;
    _advancing = true;
    if (_itemIndex < _group.items.length - 1) {
      _currentItemStartedFromAdvance = true;
      setState(() => _itemIndex += 1);
      _startItem();
    } else if (_groupIndex < widget.groups.length - 1) {
      _currentItemStartedFromAdvance = true;
      _groupPager.animateToPage(
        _groupIndex + 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } else {
      _close();
    }
  }

  void _prev() {
    if (_itemIndex > 0) {
      _currentItemStartedFromAdvance = false;
      setState(() => _itemIndex -= 1);
      _startItem();
    } else if (_groupIndex > 0) {
      _currentItemStartedFromAdvance = false;
      _groupPager.animateToPage(
        _groupIndex - 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  void _onGroupChanged(int index) {
    setState(() {
      _groupIndex = index;
      _itemIndex = 0;
    });
    _advancing = false;
    _currentItemStartedFromAdvance = false;
    _startItem();
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// Resolves a tap on the left/right visual third to previous/next, honoring
  /// RTL: forward progression follows the reading direction (RTL advances on a
  /// left-side tap; LTR advances on a right-side tap). Middle taps are ignored.
  void _handleTap(TapUpDetails details, double width) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final x = details.localPosition.dx;
    final onLeadingSide = x < width * 0.33;
    final onTrailingSide = x > width * 0.66;
    if (!onLeadingSide && !onTrailingSide) return;
    // "forward" = trailing edge in LTR, leading (left) edge in RTL.
    final tappedForward = isRtl ? onLeadingSide : onTrailingSide;
    if (tappedForward) {
      _next();
    } else {
      _prev();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            onTapUp: (d) => _handleTap(d, width),
            onLongPressStart: (_) {
              _gesturePaused = true;
              _pause();
            },
            onLongPressEnd: (_) {
              _gesturePaused = false;
              _resume();
            },
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 250) _close();
            },
            child: PageView.builder(
              controller: _groupPager,
              onPageChanged: _onGroupChanged,
              itemCount: widget.groups.length,
              itemBuilder: (context, groupIndex) {
                final isActive = groupIndex == _groupIndex;
                final group = widget.groups[groupIndex];
                final item = isActive
                    ? _item
                    : (group.items.isNotEmpty ? group.items.first : null);
                if (item == null) return const ColoredBox(color: Colors.black);
                return _StoryGroupPage(
                  group: group,
                  item: item,
                  itemIndex: isActive ? _itemIndex : 0,
                  video: isActive ? _video : null,
                  progress: _progress,
                  isActive: isActive,
                  onClose: _close,
                  liked: _isLiked(item),
                  likesCount: _likesCount(item),
                  commentsCount: _commentsCount(item),
                  likeBusy: _likeBusyStoryIds.contains(item.storyId),
                  onLike: !isActive || widget.onToggleLike == null
                      ? null
                      : () => _toggleLike(item),
                  onComments: !isActive || widget.onOpenComments == null
                      ? null
                      : () => _openComments(item),
                  onShare: !isActive || widget.onShare == null
                      ? null
                      : () => _share(item),
                  onOpenSharedReel: !isActive || item.sharedReel == null
                      ? null
                      : () => widget.onOpenSharedReel?.call(item.sharedReel!),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _StoryGroupPage extends StatelessWidget {
  const _StoryGroupPage({
    required this.group,
    required this.item,
    required this.itemIndex,
    required this.video,
    required this.progress,
    required this.isActive,
    required this.onClose,
    required this.onOpenSharedReel,
    required this.liked,
    required this.likesCount,
    required this.commentsCount,
    required this.likeBusy,
    required this.onLike,
    required this.onComments,
    required this.onShare,
  });

  final StoryV3Group group;
  final StoryV3Item item;
  final int itemIndex;
  final VideoPlayerController? video;
  final ValueNotifier<double> progress;
  final bool isActive;
  final VoidCallback onClose;
  final VoidCallback? onOpenSharedReel;
  final bool liked;
  final int likesCount;
  final int commentsCount;
  final bool likeBusy;
  final Future<void> Function()? onLike;
  final Future<void> Function()? onComments;
  final Future<void> Function()? onShare;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    final hasActions =
        (item.allowLikes && onLike != null) ||
        (item.allowComments && onComments != null) ||
        (item.allowSharing && onShare != null);
    return Stack(
      fit: StackFit.expand,
      children: [
        StoryMediaSurfaceV3(item: item, controller: video),
        const _TopScrim(),
        Positioned(
          top: padding.top + 10,
          left: 12,
          right: 12,
          child: Column(
            children: [
              isActive
                  ? ValueListenableBuilder<double>(
                      valueListenable: progress,
                      builder: (context, value, _) => StoryProgressBarV3(
                        itemCount: group.items.length,
                        currentIndex: itemIndex,
                        currentProgress: value,
                      ),
                    )
                  : StoryProgressBarV3(
                      itemCount: group.items.length,
                      currentIndex: 0,
                      currentProgress: 0,
                    ),
              const SizedBox(height: 10),
              _StoryHeader(group: group, onClose: onClose),
            ],
          ),
        ),
        if (item.caption.trim().isNotEmpty ||
            onOpenSharedReel != null ||
            hasActions)
          Positioned(
            left: 16,
            right: 16,
            bottom: padding.bottom + 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.caption.trim().isNotEmpty)
                  Text(
                    item.caption.trim(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                    ),
                  ),
                if (onOpenSharedReel != null) ...[
                  const SizedBox(height: 10),
                  _OpenReelChip(onTap: onOpenSharedReel!),
                ],
                if (hasActions) ...[
                  const SizedBox(height: 12),
                  _StoryActionBarV3(
                    storyId: item.storyId,
                    canLike: item.allowLikes && onLike != null,
                    canComment: item.allowComments && onComments != null,
                    canShare: item.allowSharing && onShare != null,
                    liked: liked,
                    likesCount: likesCount,
                    commentsCount: commentsCount,
                    likeBusy: likeBusy,
                    onLike: onLike,
                    onComments: onComments,
                    onShare: onShare,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _StoryActionBarV3 extends StatelessWidget {
  const _StoryActionBarV3({
    required this.storyId,
    required this.canLike,
    required this.canComment,
    required this.canShare,
    required this.liked,
    required this.likesCount,
    required this.commentsCount,
    required this.likeBusy,
    required this.onLike,
    required this.onComments,
    required this.onShare,
  });

  final int storyId;
  final bool canLike;
  final bool canComment;
  final bool canShare;
  final bool liked;
  final int likesCount;
  final int commentsCount;
  final bool likeBusy;
  final Future<void> Function()? onLike;
  final Future<void> Function()? onComments;
  final Future<void> Function()? onShare;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (canLike)
        _StoryActionButtonV3(
          key: ValueKey<String>('story-v3-like-$storyId'),
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: liked ? const Color(0xFFFF4D67) : Colors.white,
          label: likesCount > 0
              ? '$likesCount'
              : context.lt(ar: 'إعجاب', en: 'Like'),
          onTap: likeBusy ? null : onLike,
        ),
      if (canComment)
        _StoryActionButtonV3(
          key: ValueKey<String>('story-v3-comment-$storyId'),
          icon: Icons.mode_comment_outlined,
          color: Colors.white,
          label: commentsCount > 0
              ? '$commentsCount'
              : context.lt(ar: 'تعليق', en: 'Comment'),
          onTap: onComments,
        ),
      if (canShare)
        _StoryActionButtonV3(
          key: ValueKey<String>('story-v3-share-$storyId'),
          icon: Icons.send_rounded,
          color: Colors.white,
          label: context.lt(ar: 'مشاركة', en: 'Share'),
          onTap: onShare,
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [for (final button in buttons) Expanded(child: button)],
        ),
      ),
    );
  }
}

class _StoryActionButtonV3 extends StatelessWidget {
  const _StoryActionButtonV3({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryHeader extends StatelessWidget {
  const _StoryHeader({required this.group, required this.onClose});

  final StoryV3Group group;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: SocialSafeImage(imageUrl: group.authorAvatarUrl),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            group.authorHandle.isNotEmpty
                ? group.authorHandle
                : group.authorName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ],
    );
  }
}

class _OpenReelChip extends StatelessWidget {
  const _OpenReelChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xCC0D1B2A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7B24B)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text('فتح الريل', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _TopScrim extends StatelessWidget {
  const _TopScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
