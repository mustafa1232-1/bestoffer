import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../../social/models/social_models.dart';
import '../../social/state/social_controller.dart';
import '../../social/state/social_reels_controller.dart';
import '../../social/ui/social_reel_comments_sheet.dart';
import '../../../core/network/api_error_mapper.dart';
import '../composer/reel_gallery_entry_v3.dart';
import '../composer/story_composer_source.dart';
import '../domain/reel_view_data.dart';
import '../reels/social_reels_screen_v3.dart';
import '../sharing/canonical_links.dart';
import '../sharing/share_sheet_v3.dart';
import '../../../core/i18n/app_localizations_context.dart';

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
        final response = await ref.read(socialApiProvider).getReelById(reelId);
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
      await ref
          .read(socialApiProvider)
          .toggleSaved(entityType: 'reel', entityId: reel.postId);
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

  Future<void> _openMore(ReelV3ViewData reel) async {
    final l10n = context.l10n;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final messenger = ScaffoldMessenger.of(context);
    final currentUserId = ref.read(authControllerProvider).user?.id;
    final isOwner = currentUserId != null && currentUserId == reel.authorId;
    final api = ref.read(socialApiProvider);
    final relation = isOwner
        ? null
        : await (() async {
            try {
              final out = await api.getUserRelation(reel.authorId);
              final rawRelation = out['relation'];
              return rawRelation is Map
                  ? SocialRelation.fromJson(
                      Map<String, dynamic>.from(rawRelation),
                    )
                  : SocialRelation.fromJson(Map<String, dynamic>.from(out));
            } catch (_) {
              return null;
            }
          })();

    if (!context.mounted) return;
    _showMoreActionsSheet(
      reel: reel,
      relation: relation,
      isOwner: isOwner,
      isRtl: isRtl,
      messenger: messenger,
      l10n: l10n,
    );
  }

  void _showMoreActionsSheet({
    required ReelV3ViewData reel,
    required SocialRelation? relation,
    required bool isOwner,
    required bool isRtl,
    required ScaffoldMessengerState messenger,
    required dynamic l10n,
  }) {
    final links = const SocialCanonicalLinks();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(isRtl ? 'نسخ الرابط' : 'Copy link'),
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: links.guardShareUrl(links.reel(reel.postId)),
                  ),
                );
                if (!sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.commonCopied)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(isRtl ? 'إضافة إلى القصة' : 'Add to story'),
              onTap: () {
                Navigator.of(sheetContext).pop();
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
            ),
            if (!isOwner)
              ListTile(
                leading: const Icon(Icons.report_outlined),
                title: Text(l10n.commonReport),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _reportReel(reel);
                },
              ),
            if (!isOwner)
              ListTile(
                leading: Icon(
                  relation?.isBlockedByMe == true
                      ? Icons.lock_open_rounded
                      : Icons.block_outlined,
                ),
                title: Text(
                  relation?.isBlockedByMe == true
                      ? (isRtl ? 'إلغاء الحظر' : 'Unblock author')
                      : (isRtl ? 'حظر المستخدم' : 'Block author'),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _toggleBlockAuthor(reel, relation);
                },
              ),
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.commonDelete),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _deleteReel(reel);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteReel(ReelV3ViewData reel) async {
    final l10n = context.l10n;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(l10n.socialProfileDeletePostConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await ref.read(socialApiProvider).deletePost(reel.postId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isRtl ? 'تم حذف الريل.' : 'The reel was deleted.'),
        ),
      );
      await ref
          .read(socialReelsControllerProvider.notifier)
          .load(refresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: l10n.socialProfileDeletePostFailed),
          ),
        ),
      );
    }
  }

  Future<void> _reportReel(ReelV3ViewData reel) async {
    final l10n = context.l10n;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    String reason = '';
    String details = '';
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          scrollable: true,
          title: Text(l10n.commonReport, textAlign: TextAlign.end),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => reason = value,
                decoration: InputDecoration(labelText: l10n.commonReason),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => details = value,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: isRtl ? 'تفاصيل إضافية' : 'Additional details',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonConfirm),
            ),
          ],
        );
      },
    );
    reason = reason.trim();
    details = details.trim();
    if (!mounted || approved != true || reason.isEmpty) return;
    try {
      await ref
          .read(socialApiProvider)
          .reportPost(postId: reel.postId, reason: reason, details: details);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.socialProfileReportSubmitted)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: l10n.socialProfileReportSubmitFailed),
          ),
        ),
      );
    }
  }

  Future<void> _toggleBlockAuthor(
    ReelV3ViewData reel,
    SocialRelation? relation,
  ) async {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    try {
      if (relation?.isBlockedByMe == true) {
        await ref.read(socialApiProvider).unblockRelation(reel.authorId);
      } else {
        await ref.read(socialApiProvider).blockRelation(reel.authorId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            relation?.isBlockedByMe == true
                ? (isRtl ? 'تم إلغاء الحظر.' : 'Author unblocked.')
                : (isRtl ? 'تم حظر المستخدم.' : 'Author blocked.'),
          ),
        ),
      );
      await ref
          .read(socialReelsControllerProvider.notifier)
          .load(refresh: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: isRtl
                  ? 'تعذر تنفيذ الإجراء الآن.'
                  : 'Unable to complete the action right now.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _createReel() => openReelComposerV3(
    context,
    onPublished: (_) {
      ref.read(socialReelsControllerProvider.notifier).load(refresh: true);
    },
  );

  void _recordView(ReelV3ViewData reel) {
    ref
        .read(socialReelsControllerProvider.notifier)
        .recordView(reelId: reel.postId, context: 'reels_v3');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialReelsControllerProvider);
    final reels = _buildReels(state);

    if (!_bootstrapped && reels.isEmpty) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_bootstrapped &&
        reels.isEmpty &&
        (state.error?.trim().isNotEmpty ?? false)) {
      return _ReelsErrorState(
        errorText: state.error!.trim(),
        onRetry: () => ref
            .read(socialReelsControllerProvider.notifier)
            .load(refresh: true),
        onCreate: _createReel,
      );
    }

    return SocialReelsScreenV3(
      reels: reels,
      onLike: _like,
      onSave: _save,
      onComments: _comments,
      onShare: _share,
      onMore: _openMore,
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
