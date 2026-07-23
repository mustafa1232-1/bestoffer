import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../../social/state/social_controller.dart';
import '../../social/ui/social_profile_screen.dart';
import '../../social/models/social_models.dart';
import '../domain/reel_view_data.dart';
import '../upload/reel_map_normalizer.dart';
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
class SocialReelsScreenV3 extends ConsumerStatefulWidget {
  const SocialReelsScreenV3({
    super.key,
    required this.reels,
    this.initialIndex = 0,
    this.onLike,
    this.onSave,
    this.onComments,
    this.onShare,
    this.onMore,
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
  final Future<bool> Function(ReelV3ViewData reel, bool desiredLiked)? onLike;
  final void Function(ReelV3ViewData reel)? onSave;
  final void Function(ReelV3ViewData reel)? onComments;
  final void Function(ReelV3ViewData reel)? onShare;
  final void Function(ReelV3ViewData reel)? onMore;
  final Future<void> Function(ReelV3ViewData reel)? onOpenAuthor;
  final void Function(ReelV3ViewData reel)? onView;
  final VoidCallback? onReachedEnd;

  /// Opens the native gallery → V3 reel composer.
  final VoidCallback? onCreate;

  /// Test seam for injecting a coordinator with a fake controller factory.
  final ReelPlaybackCoordinator Function()? coordinatorFactory;

  @override
  ConsumerState<SocialReelsScreenV3> createState() =>
      _SocialReelsScreenV3State();
}

class _SocialReelsScreenV3State extends ConsumerState<SocialReelsScreenV3>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  late final ReelPlaybackCoordinator _coordinator;
  late List<ReelV3ViewData> _reels;
  final Set<int> _viewedPostIds = {};
  final Map<int, SocialRelation?> _relationCache = {};
  final Map<int, String> _followStateOverrides = {};
  final Set<int> _relationLoading = {};
  final Set<int> _likeLoading = {};
  bool _handlingCompletion = false;
  int? _relationScopeUserId;

  @override
  void initState() {
    super.initState();
    _reels = List.of(widget.reels);
    _pageController = PageController(initialPage: widget.initialIndex);
    _coordinator =
        widget.coordinatorFactory?.call() ?? ReelPlaybackCoordinator();
    _coordinator.setItems(_reels.map((r) => r.media).toList());
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _coordinator.setActiveIndex(widget.initialIndex);
      _recordView(widget.initialIndex);
      _syncFollowStates();
    });
  }

  @override
  void didUpdateWidget(covariant SocialReelsScreenV3 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reels, widget.reels)) {
      _reels = List.of(widget.reels);
      _coordinator.setItems(_reels.map((r) => r.media).toList());
      _syncFollowStates();
      if (_reels.isNotEmpty && _pageController.hasClients) {
        final safeIndex = _coordinator.activeIndex
            .clamp(0, _reels.length - 1)
            .toInt();
        if (safeIndex != _coordinator.activeIndex) {
          _pageController.jumpToPage(safeIndex);
          unawaited(_coordinator.setActiveIndex(safeIndex));
        }
      }
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

  int? _currentUserId() {
    final auth = ref.read(authControllerProvider);
    return auth.user?.id;
  }

  String _followStateFor(ReelV3ViewData reel, {int? currentUserId}) {
    currentUserId ??= _currentUserId();
    if (currentUserId != null && currentUserId == reel.authorId) {
      return 'self';
    }
    final overrideState = _followStateOverrides[reel.authorId];
    if (overrideState != null) return overrideState;
    return _relationCache[reel.authorId]?.state ?? reel.followState;
  }

  void _refreshFollowScope(int? currentUserId) {
    if (_relationScopeUserId == currentUserId) return;
    _relationScopeUserId = currentUserId;
    _relationCache.clear();
    _followStateOverrides.clear();
    _relationLoading.clear();
    _syncFollowStates();
  }

  void _syncFollowStates() {
    for (final reel in _reels) {
      _ensureRelation(reel.authorId);
    }
  }

  void _ensureRelation(int authorId) {
    final currentUserId = _currentUserId();
    if (authorId <= 0 || (currentUserId != null && currentUserId == authorId)) {
      return;
    }
    if (_relationCache.containsKey(authorId) ||
        _relationLoading.contains(authorId)) {
      return;
    }
    _relationLoading.add(authorId);
    unawaited(() async {
      try {
        final out = await ref.read(socialApiProvider).getUserRelation(authorId);
        final rawRelation = out['relation'];
        final relation = rawRelation is Map
            ? SocialRelation.fromJson(
                normalizeReelMap(rawRelation, 'REEL_RELATION_INVALID'),
              )
            : SocialRelation.fromJson(
                normalizeReelMap(out, 'REEL_RELATION_INVALID'),
              );
        if (!mounted) return;
        setState(() {
          _relationCache[authorId] = relation;
          _followStateOverrides.remove(authorId);
          _reels = _reels
              .map(
                (reel) => reel.authorId == authorId
                    ? reel.copyWith(nextFollowState: relation.state)
                    : reel,
              )
              .toList(growable: false);
        });
      } catch (_) {
        // Relation is advisory for labels; fall back to generic state.
      } finally {
        _relationLoading.remove(authorId);
      }
    }());
  }

  void _onPageChanged(int index) {
    _coordinator.setActiveIndex(index);
    _recordView(index);
    if (index >= _reels.length - 2) {
      widget.onReachedEnd?.call();
    }
    _syncFollowStates();
  }

  void _mutateReel(int index, ReelV3ViewData next) {
    setState(() => _reels[index] = next);
  }

  Future<bool> _toggleLike(int index, {bool? forceLiked}) async {
    final reel = _reels[index];
    if (_likeLoading.contains(reel.postId)) return false;
    final nextLiked = forceLiked ?? !reel.isLiked;
    if (nextLiked == reel.isLiked) return true;
    _likeLoading.add(reel.postId);
    _mutateReel(
      index,
      reel.copyWith(
        isLiked: nextLiked,
        likesCount: (reel.likesCount + (nextLiked ? 1 : -1)).clamp(0, 1 << 31),
      ),
    );
    try {
      final ok =
          await (widget.onLike?.call(_reels[index], nextLiked) ??
              Future.value(true));
      if (!ok && mounted) {
        _mutateReel(index, reel);
        return false;
      }
      return ok;
    } catch (_) {
      if (mounted) {
        _mutateReel(index, reel);
      }
      return false;
    } finally {
      _likeLoading.remove(reel.postId);
    }
  }

  Future<void> _toggleFollow(int index) async {
    final reel = _reels[index];
    final currentUserId = _currentUserId();
    if (currentUserId == null || currentUserId == reel.authorId) return;
    if (_relationLoading.contains(reel.authorId)) return;

    final api = ref.read(socialApiProvider);
    final currentState = _followStateFor(reel, currentUserId: currentUserId);
    if (currentState == 'blocked_by_other') return;

    Future<void> Function()? action;
    String optimisticState = 'none';
    switch (currentState) {
      case 'accepted':
        action = () => api.removeRelation(reel.authorId);
        optimisticState = 'none';
        break;
      case 'pending_outgoing':
        action = () => api.cancelRelationRequest(reel.authorId);
        optimisticState = 'none';
        break;
      case 'pending_incoming':
        action = () => api.acceptRelationRequest(reel.authorId);
        optimisticState = 'accepted';
        break;
      case 'blocked_by_me':
      case 'blocked':
        action = () => api.unblockRelation(reel.authorId);
        optimisticState = 'none';
        break;
      default:
        action = () => api.sendRelationRequest(reel.authorId);
        optimisticState = 'pending_outgoing';
        break;
    }

    setState(() {
      if (optimisticState == 'none') {
        _followStateOverrides.remove(reel.authorId);
      } else {
        _followStateOverrides[reel.authorId] = optimisticState;
      }
    });

    try {
      await action();
      if (!mounted) return;
      _ensureRelation(reel.authorId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (currentState == 'none') {
          _followStateOverrides.remove(reel.authorId);
        } else {
          _followStateOverrides[reel.authorId] = currentState;
        }
      });
    }
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

  Future<void> _openAuthor(int index) async {
    if (index < 0 || index >= _reels.length) return;
    final reel = _reels[index];
    final currentUserId = _currentUserId();
    if (currentUserId != null && currentUserId == reel.authorId) return;
    _coordinator.setRouteVisible(false);
    try {
      await (widget.onOpenAuthor?.call(reel) ??
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => SocialProfileScreen(
                userId: reel.authorId,
                initialName: reel.authorName,
              ),
            ),
          ));
    } finally {
      if (mounted) {
        _coordinator.setRouteVisible(true);
      }
    }
  }

  Future<void> _handlePlaybackCompleted(int index) async {
    if (_handlingCompletion || index != _coordinator.activeIndex) return;
    _handlingCompletion = true;
    try {
      if (_reels.length <= 1 || index >= _reels.length - 1) {
        await _coordinator.replayActive();
        return;
      }
      final nextIndex = index + 1;
      await _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _handlingCompletion = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authControllerProvider).user?.id;
    _refreshFollowScope(currentUserId);
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: _reels.isEmpty
          ? _EmptyReels(onCreate: widget.onCreate)
          : PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: _reels.length,
              itemBuilder: (context, index) {
                // Each page rebuilds only on this screen's setState (like/save/
                // follow); the coordinator is passed down so ONLY the video layer
                // inside ReelPageV3 listens to playback/buffering changes.
                final reel = _reels[index];
                return RepaintBoundary(
                  key: ValueKey('reel_page_${reel.postId}'),
                  child: ReelPageV3(
                    key: ValueKey(reel.postId),
                    reel: reel,
                    coordinator: _coordinator,
                    index: index,
                    onCreate: widget.onCreate,
                    onTogglePlay: _coordinator.togglePlay,
                    onToggleMute: _coordinator.toggleMuted,
                    onHoldSpeedChanged: (active) => unawaited(
                      _coordinator.setPlaybackSpeed(active ? 2.0 : 1.0),
                    ),
                    onPlaybackCompleted: () =>
                        unawaited(_handlePlaybackCompleted(index)),
                    onLike: (desiredLiked) =>
                        _toggleLike(index, forceLiked: desiredLiked),
                    onDoubleTapLike: (desiredLiked) =>
                        _toggleLike(index, forceLiked: desiredLiked),
                    onSave: () => _toggleSave(index),
                    onComments: () => widget.onComments?.call(reel),
                    onShare: () => widget.onShare?.call(reel),
                    onMore: () => widget.onMore?.call(reel),
                    onFollow: () => unawaited(_toggleFollow(index)),
                    onOpenAuthor: () => unawaited(_openAuthor(index)),
                    showFollow:
                        _followStateFor(reel, currentUserId: currentUserId) !=
                        'self',
                    followLabel: _followLabel(
                      _followStateFor(reel, currentUserId: currentUserId),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _followLabel(String state) {
  switch (state.trim().toLowerCase()) {
    case 'accepted':
      return 'Following';
    case 'pending_outgoing':
    case 'pending_incoming':
      return 'Requested';
    case 'blocked':
      return 'Blocked';
    case 'self':
      return '';
    default:
      return 'Follow';
  }
}

class _EmptyReels extends StatelessWidget {
  const _EmptyReels({required this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.movie_creation_outlined,
                  color: Colors.white38,
                  size: 56,
                ),
                const SizedBox(height: 12),
                const Text(
                  'لا توجد ريلز بعد',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                if (onCreate != null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.videocam_rounded),
                    label: const Text('إنشاء ريل'),
                  ),
                ],
              ],
            ),
          ),
          if (onCreate != null)
            PositionedDirectional(
              top: 12,
              end: 16,
              child: Tooltip(
                message: 'إنشاء ريل',
                child: Material(
                  color: const Color(0xCC0D1B2A),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onCreate,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.videocam_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
