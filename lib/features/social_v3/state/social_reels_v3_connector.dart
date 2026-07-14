import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../social/data/social_api.dart';
import '../../social/models/social_models.dart';
import '../../social/state/social_controller.dart';
import '../../social/state/social_reels_controller.dart';
import '../../social/ui/social_reel_comments_sheet.dart';
import '../../social/ui/social_share_sheet.dart';
import '../domain/reel_view_data.dart';
import '../reels/social_reels_screen_v3.dart';

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

  Future<void> _like(ReelV3ViewData reel) async {
    try {
      await ref.read(socialApiProvider).toggleLike(reel.postId);
    } catch (_) {}
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
    await showSocialShareSheet(
      context: context,
      entityType: 'reel',
      entityId: reel.postId,
      previewTitle: reel.authorName,
      previewSubtitle: reel.caption,
    );
  }

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

    return SocialReelsScreenV3(
      reels: reels,
      onLike: _like,
      onSave: _save,
      onComments: _comments,
      onShare: _share,
      onView: _recordView,
      onReachedEnd: () =>
          ref.read(socialReelsControllerProvider.notifier).loadMore(),
    );
  }
}
