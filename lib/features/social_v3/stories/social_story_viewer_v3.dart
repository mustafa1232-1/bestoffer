import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
    this.onView,
    this.onOpenSharedReel,
    this.videoFactory,
  });

  final List<StoryV3Group> groups;
  final int initialGroupIndex;

  /// Called once per (user, story) per session for view counting.
  final void Function(int userId, int storyId)? onView;
  final void Function(SharedReelRef ref)? onOpenSharedReel;

  /// Test seam for the video controller.
  final VideoPlayerController Function(String url)? videoFactory;

  /// Opens the viewer as an opaque full-screen route (fade transition).
  static Route<void> route({
    required List<StoryV3Group> groups,
    int initialGroupIndex = 0,
    void Function(int userId, int storyId)? onView,
    void Function(SharedReelRef ref)? onOpenSharedReel,
  }) {
    return PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) =>
          SocialStoryViewerV3(
        groups: groups,
        initialGroupIndex: initialGroupIndex,
        onView: onView,
        onOpenSharedReel: onOpenSharedReel,
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

  VideoPlayerController? _video;
  int _groupIndex = 0;
  int _itemIndex = 0;
  bool _gesturePaused = false;

  StoryV3Group get _group => widget.groups[_groupIndex];
  StoryV3Item? get _item =>
      _itemIndex < _group.items.length ? _group.items[_itemIndex] : null;

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _groupPager = PageController(initialPage: _groupIndex);
    _imageCtrl = AnimationController(vsync: this)
      ..addListener(() => _progress.value = _imageCtrl.value)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startItem());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _imageCtrl.dispose();
    _disposeVideo();
    _progress.dispose();
    _groupPager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_gesturePaused) _resume();
    } else {
      _pause();
    }
  }

  void _disposeVideo() {
    _video?.removeListener(_onVideoTick);
    _video?.pause();
    _video?.dispose();
    _video = null;
  }

  void _recordView() {
    final item = _item;
    if (item == null) return;
    final key = '${_group.userId}:${item.storyId}';
    if (_viewed.add(key)) {
      widget.onView?.call(_group.userId, item.storyId);
    }
  }

  void _startItem() {
    _imageCtrl.stop();
    _disposeVideo();
    _progress.value = 0;
    final item = _item;
    if (item == null) {
      _next();
      return;
    }
    _recordView();

    if (item.isVideo && item.media.hasVideo) {
      _startVideo(item);
    } else {
      _imageCtrl.duration = item.imageDuration;
      _imageCtrl.forward(from: 0);
    }
  }

  void _startVideo(StoryV3Item item) {
    final url = item.media.videoPlaybackUrl!;
    final controller = widget.videoFactory?.call(url) ??
        VideoPlayerController.networkUrl(Uri.parse(url));
    _video = controller;
    controller.setLooping(false);
    controller.addListener(_onVideoTick);
    controller.initialize().then((_) {
      if (!mounted || _video != controller) return;
      final start = item.clipStart;
      if (start != null) controller.seekTo(start);
      controller.play();
      setState(() {});
    }).catchError((Object _) {
      // Failed media briefly shows a controlled failure then advances.
      if (!mounted || _video != controller) return;
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted && _video == controller) _next();
      });
    });
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

    final reachedEnd = posMs >= totalMs ||
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
    final item = _item;
    if (item == null) return;
    if (item.isVideo && item.media.hasVideo) {
      _video?.play();
    } else if (!_imageCtrl.isAnimating) {
      _imageCtrl.forward();
    }
  }

  void _next() {
    if (_itemIndex < _group.items.length - 1) {
      setState(() => _itemIndex += 1);
      _startItem();
    } else if (_groupIndex < widget.groups.length - 1) {
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
      setState(() => _itemIndex -= 1);
      _startItem();
    } else if (_groupIndex > 0) {
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
                  onOpenSharedReel: item.sharedReel == null
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
  });

  final StoryV3Group group;
  final StoryV3Item item;
  final int itemIndex;
  final VideoPlayerController? video;
  final ValueNotifier<double> progress;
  final bool isActive;
  final VoidCallback onClose;
  final VoidCallback? onOpenSharedReel;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
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
        if (item.caption.trim().isNotEmpty || onOpenSharedReel != null)
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
              ],
            ),
          ),
      ],
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
            group.authorHandle.isNotEmpty ? group.authorHandle : group.authorName,
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
