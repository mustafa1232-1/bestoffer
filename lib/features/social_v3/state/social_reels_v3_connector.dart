import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../social/models/social_models.dart';
import '../../social/state/social_controller.dart';
import '../../social/state/social_reels_controller.dart';
import '../../social/ui/social_reel_comments_sheet.dart';
import '../composer/reel_gallery_entry_v3.dart';
import '../composer/story_composer_source.dart';
import '../domain/reel_view_data.dart';
import '../reels/social_reels_screen_v3.dart';
import '../sharing/share_sheet_v3.dart';

/// Riverpod-connected wrapper that feeds live reel data into
/// [SocialReelsScreenV3] and wires interaction callbacks to the existing API.
///
/// This is the single live entry point for the Reels experience after cutover.
/// It reuses the proven [socialReelsControllerProvider] and [SocialApi] so no
/// data-layer code is duplicated.
class SocialReelsV3Connector extends ConsumerStatefulWidget {
  const SocialReelsV3Connector({
    super.key,
    this.initialReelId,
    this.playbackEnabledListenable,
  });

  final int? initialReelId;
  final ValueListenable<bool>? playbackEnabledListenable;

  @override
  ConsumerState<SocialReelsV3Connector> createState() =>
      _SocialReelsV3ConnectorState();
}

class _SocialReelsV3ConnectorState
    extends ConsumerState<SocialReelsV3Connector> {
  SocialReelItem? _pinnedInitial;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    final reelId = widget.initialReelId;
    if (reelId != null && reelId > 0) {
      try {
        final response =
            await ref.read(socialApiProvider).getReelById(reelId);
        final target = SocialReelItem.fromJson(
          Map<String, dynamic>.from(response['reel'] as Map? ?? const {}),
        );
        if (mounted) setState(() => _pinnedInitial = target);
      } catch (_) {
        // fall back to the explore feed below
      }
    }
    await ref.read(socialReelsControllerProvider.notifier).load(refresh: true);
    if (mounted) setState(() => _bootstrapped = true);
  }

  List<ReelV3ViewData> _buildReels(SocialReelsState state) {
    final items = <SocialReelItem>[];
    final pinned = _pinnedInitial;
    if (pinned != null) items.add(pinned);
    for (final item in state.items) {
      if (pinned != null && item.post.id == pinned.post.id) continue;
      items.add(item);
    }
    return items
        .map((i) => ReelV3ViewData.fromReelItem(i))
        .toList(growable: false);
  }

  Future<bool> _like(ReelV3ViewData reel, bool desiredLiked) async {
    try {
      await ref.read(socialApiProvider).toggleLike(reel.postId);
      return true;
    } catch (_) {}
    return false;
  }

  Future<void> _save(ReelV3ViewData reel) async {
    try {
      await ref.read(socialApiProvider).toggleSaved(
            entityType: 'reel',
            entityId: reel.postId,
          );
    } catch (_) {}
  }

  SocialPost? _postFor(int postId) {
    for (final item in ref.read(socialReelsControllerProvider).items) {
      if (item.post.id == postId) return item.post;
    }
    if (_pinnedInitial?.post.id == postId) return _pinnedInitial!.post;
    return null;
  }

  Future<void> _comments(ReelV3ViewData reel) async {
    final post = _postFor(reel.postId);
    if (post == null) return;
    await showSocialReelCommentsSheet(context, reelPost: post);
  }

  Future<void> _share(ReelV3ViewData reel) async {
    await ShareSheetV3.show(
      context,
      target: ShareTargetV3(
        kind: ShareEntityKind.reel,
        entityId: reel.postId,
        ownerId: reel.authorId,
        title: reel.authorName,
        subtitle: reel.caption,
      ),
      onAddToStory: () {
        Navigator.of(context).pop();
        openStoryComposerV3WithReel(
          context,
          reel: SharedReelSource(
            reelId: reel.postId,
            originalOwnerId: reel.authorId,
            playbackUrl: reel.media.videoPlaybackUrl,
            thumbnailUrl: reel.media.posterImageUrl,
            posterUrl: reel.media.posterImageUrl,
            width: reel.media.width,
            height: reel.media.height,
            caption: reel.caption,
            available: true,
            authorName: reel.authorName,
            authorAvatarUrl: reel.authorAvatarUrl,
            authorHandle: reel.authorHandle,
          ),
        );
      },
    );
  }

  Future<void> _createReel() => openReelComposerV3(context, onPublished: (_) {
        ref.read(socialReelsControllerProvider.notifier).load(refresh: true);
      });

  void _recordView(ReelV3ViewData reel) {
    ref.read(socialReelsControllerProvider.notifier).recordView(
          reelId: reel.postId,
          context: 'reels_v3',
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialReelsControllerProvider);
    final reels = _buildReels(state);

    if (!_bootstrapped && reels.isEmpty) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_bootstrapped && reels.isEmpty && (state.error?.trim().isNotEmpty ?? false)) {
      return _ReelsErrorState(
        errorText: state.error!.trim(),
        onRetry: () => ref.read(socialReelsControllerProvider.notifier).load(
              refresh: true,
            ),
        onCreate: _createReel,
      );
    }

    return SocialReelsScreenV3(
      reels: reels,
      onLike: _like,
      onSave: _save,
      onComments: _comments,
      onShare: _share,
      onView: _recordView,
      onCreate: _createReel,
      onReachedEnd: () =>
          ref.read(socialReelsControllerProvider.notifier).loadMore(),
    );
  }
}

class _ReelsErrorState extends StatelessWidget {
  const _ReelsErrorState({
    required this.errorText,
    required this.onRetry,
    required this.onCreate,
  });

  final String errorText;
  final VoidCallback onRetry;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.movie_creation_outlined,
                  color: Colors.white54,
                  size: 72,
                ),
                const SizedBox(height: 16),
                Text(
                  errorText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                    OutlinedButton(
                      onPressed: onCreate,
                      child: const Text('Create reel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
