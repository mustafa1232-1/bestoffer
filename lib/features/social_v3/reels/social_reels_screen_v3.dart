import 'package:flutter/material.dart';

import '../domain/reel_view_data.dart';
import 'reel_page_v3.dart';
import 'reel_playback_coordinator.dart';

/// Full-screen vertical Reels experience (§3 "SocialReelsScreenV3").
///
/// This is a pure, self-contained widget: it takes the reel list + interaction
/// callbacks and owns the [ReelPlaybackCoordinator] and page navigation. The
/// Riverpod-connected wrapper lives in `state/` so this widget stays
/// golden-testable.
///
/// Scaffold contract: black background, `extendBody`, no AppBar, no outer card,
/// no border. Each reel fills the viewport; controls respect SafeArea without
/// shrinking the video.
class SocialReelsScreenV3 extends StatefulWidget {
  const SocialReelsScreenV3({
    super.key,
    required this.reels,
    this.initialIndex = 0,
    this.onLike,
    this.onSave,
    this.onComments,
    this.onShare,
    this.onMore,
    this.onFollow,
    this.onOpenAuthor,
    this.onView,
    this.onReachedEnd,
    this.onCreate,
    this.coordinatorFactory,
  });

  final List<ReelV3ViewData> reels;
  final int initialIndex;

  /// Interaction callbacks. Like/save are expected to be optimistic on the
  /// caller side; this screen also updates its local copy so the video
  /// controller is never rebuilt for a like.
  final void Function(ReelV3ViewData reel)? onLike;
  final void Function(ReelV3ViewData reel)? onSave;
  final void Function(ReelV3ViewData reel)? onComments;
  final void Function(ReelV3ViewData reel)? onShare;
  final void Function(ReelV3ViewData reel)? onMore;
  final void Function(ReelV3ViewData reel)? onFollow;
  final void Function(ReelV3ViewData reel)? onOpenAuthor;
  final void Function(ReelV3ViewData reel)? onView;
  final VoidCallback? onReachedEnd;

  /// Opens the native gallery → V3 reel composer.
  final VoidCallback? onCreate;

  /// Test seam for injecting a coordinator with a fake controller factory.
  final ReelPlaybackCoordinator Function()? coordinatorFactory;

  @override
  State<SocialReelsScreenV3> createState() => _SocialReelsScreenV3State();
}

class _SocialReelsScreenV3State extends State<SocialReelsScreenV3>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  late final ReelPlaybackCoordinator _coordinator;
  late List<ReelV3ViewData> _reels;
  final Set<int> _viewedPostIds = {};

  @override
  void initState() {
    super.initState();
    _reels = List.of(widget.reels);
    _pageController = PageController(initialPage: widget.initialIndex);
    _coordinator = widget.coordinatorFactory?.call() ?? ReelPlaybackCoordinator();
    _coordinator.setItems(_reels.map((r) => r.media).toList());
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _coordinator.setActiveIndex(widget.initialIndex);
      _recordView(widget.initialIndex);
    });
  }

  @override
  void didUpdateWidget(covariant SocialReelsScreenV3 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reels, widget.reels)) {
      _reels = List.of(widget.reels);
      _coordinator.setItems(_reels.map((r) => r.media).toList());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _coordinator.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _coordinator.setAppActive(state == AppLifecycleState.resumed);
  }

  void _recordView(int index) {
    if (index < 0 || index >= _reels.length) return;
    final reel = _reels[index];
    if (_viewedPostIds.add(reel.postId)) {
      widget.onView?.call(reel);
    }
  }

  void _onPageChanged(int index) {
    _coordinator.setActiveIndex(index);
    _recordView(index);
    if (index >= _reels.length - 2) {
      widget.onReachedEnd?.call();
    }
  }

  void _mutateReel(int index, ReelV3ViewData next) {
    setState(() => _reels[index] = next);
  }

  void _toggleLike(int index) {
    final reel = _reels[index];
    final nextLiked = !reel.isLiked;
    _mutateReel(
      index,
      reel.copyWith(
        isLiked: nextLiked,
        likesCount: (reel.likesCount + (nextLiked ? 1 : -1)).clamp(0, 1 << 31),
      ),
    );
    widget.onLike?.call(_reels[index]);
  }

  void _toggleSave(int index) {
    final reel = _reels[index];
    final nextSaved = !reel.isSaved;
    _mutateReel(
      index,
      reel.copyWith(
        isSaved: nextSaved,
        savesCount: (reel.savesCount + (nextSaved ? 1 : -1)).clamp(0, 1 << 31),
      ),
    );
    widget.onSave?.call(_reels[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: _reels.isEmpty
          ? const _EmptyReels()
          : PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: _reels.length,
              itemBuilder: (context, index) {
                return AnimatedBuilder(
                  animation: _coordinator,
                  builder: (context, _) {
                    final reel = _reels[index];
                    return ReelPageV3(
                      reel: reel,
                      controller: _coordinator.controllerFor(index),
                      isBuffering: _coordinator.isBuffering(index),
                      isPaused: index == _coordinator.activeIndex &&
                          _coordinator.isActivePaused,
                      isMuted: _coordinator.isMuted,
                      onCreate: widget.onCreate,
                      onTogglePlay: _coordinator.togglePlay,
                      onToggleMute: _coordinator.toggleMuted,
                      onLike: () => _toggleLike(index),
                      onDoubleTapLike: () {
                        if (!_reels[index].isLiked) _toggleLike(index);
                      },
                      onSave: () => _toggleSave(index),
                      onComments: () => widget.onComments?.call(reel),
                      onShare: () => widget.onShare?.call(reel),
                      onMore: () => widget.onMore?.call(reel),
                      onFollow: () => widget.onFollow?.call(reel),
                      onOpenAuthor: () => widget.onOpenAuthor?.call(reel),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _EmptyReels extends StatelessWidget {
  const _EmptyReels();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.movie_creation_outlined, color: Colors.white38, size: 56),
          SizedBox(height: 12),
          Text(
            'لا توجد ريلز بعد',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
