import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/media/cached_app_image.dart';
import '../../../core/media/media_cache_models.dart';
import '../../../core/media/media_cache_service.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/platform/app_platform_capabilities.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../models/social_story_document.dart';
import 'social_post_details_screen.dart';
import 'social_profile_screen.dart';
import 'social_share_sheet.dart';
import 'social_shell_screen.dart';
import 'widgets/social_story_canvas.dart';

Future<void> showSocialStoryQuickViewer({
  required BuildContext context,
  required SocialStoryGroup group,
  List<SocialStoryGroup>? storyGroups,
  int? initialStoryId,
  ValueChanged<int>? onStoryViewed,
  SocialApi? api,
  VoidCallback? onStoryArchiveChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SocialStoryQuickViewerSheet(
      group: group,
      storyGroups: storyGroups,
      initialStoryId: initialStoryId,
      onStoryViewed: onStoryViewed,
      api: api,
      onStoryArchiveChanged: onStoryArchiveChanged,
    ),
  );
}

class _SocialStoryQuickViewerSheet extends StatefulWidget {
  final SocialStoryGroup group;
  final List<SocialStoryGroup>? storyGroups;
  final int? initialStoryId;
  final ValueChanged<int>? onStoryViewed;
  final SocialApi? api;
  final VoidCallback? onStoryArchiveChanged;

  const _SocialStoryQuickViewerSheet({
    required this.group,
    this.storyGroups,
    this.initialStoryId,
    this.onStoryViewed,
    this.api,
    this.onStoryArchiveChanged,
  });

  @override
  State<_SocialStoryQuickViewerSheet> createState() =>
      _SocialStoryQuickViewerSheetState();
}

class _StoryTimelineEntry {
  final int groupIndex;
  final int storyIndex;
  final SocialStoryGroup group;
  final SocialStory story;

  const _StoryTimelineEntry({
    required this.groupIndex,
    required this.storyIndex,
    required this.group,
    required this.story,
  });
}

class _SocialStoryQuickViewerSheetState
    extends State<_SocialStoryQuickViewerSheet>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final PageController _controller;
  late final AnimationController _progressController;
  late final List<_StoryTimelineEntry> _timeline;
  late int _index;
  bool _consumeNextTapUp = false;
  bool _pausedByLifecycle = false;
  bool _pausedByGesture = false;
  bool _pausedByOverlay = false;

  // Local optimistic state for like/comment counts (SocialStory has no copyWith).
  final Map<int, bool> _likedById = <int, bool>{};
  final Map<int, int> _likesById = <int, int>{};
  final Map<int, int> _commentsById = <int, int>{};
  bool _likeBusy = false;

  List<SocialStoryGroup> get _groups {
    final storyGroups = widget.storyGroups;
    if (storyGroups != null && storyGroups.isNotEmpty) {
      return storyGroups;
    }
    return <SocialStoryGroup>[widget.group];
  }

  SocialStory get _currentStory => _timeline[_index].story;
  SocialStoryGroup get _currentGroup => _timeline[_index].group;

  bool _isLiked(SocialStory s) => _likedById[s.id] ?? s.isLiked;
  int _likes(SocialStory s) => _likesById[s.id] ?? s.likesCount;
  int _comments(SocialStory s) => _commentsById[s.id] ?? s.commentsCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timeline = _buildTimeline();
    _index = _resolveInitialIndex();
    _controller = PageController(initialPage: _index);
    _progressController = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _advance(autoAdvance: true);
        }
      });
    _markViewed(_index);
    _syncProgress(restart: true);
  }

  List<_StoryTimelineEntry> _buildTimeline() {
    final entries = <_StoryTimelineEntry>[];
    final groups = _groups;
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final group = groups[groupIndex];
      for (var storyIndex = 0; storyIndex < group.stories.length; storyIndex++) {
        entries.add(
          _StoryTimelineEntry(
            groupIndex: groupIndex,
            storyIndex: storyIndex,
            group: group,
            story: group.stories[storyIndex],
          ),
        );
      }
    }
    return entries;
  }

  Duration _storyDuration(SocialStory story) {
    final clipSeconds = story.style.clipDurationSec;
    if (clipSeconds != null && clipSeconds > 0) {
      return Duration(milliseconds: (clipSeconds * 1000).round());
    }
    final assetDuration = story.asset?.durationMs;
    if (assetDuration != null && assetDuration > 0) {
      return Duration(milliseconds: assetDuration.clamp(2500, 12000).toInt());
    }
    return const Duration(seconds: 5);
  }

  bool get _isProgressPaused =>
      _pausedByLifecycle || _pausedByGesture || _pausedByOverlay;

  void _syncProgress({bool restart = false}) {
    if (_timeline.isEmpty) return;
    final duration = _storyDuration(_currentStory);
    _progressController.duration = duration;
    if (_isProgressPaused) {
      if (_progressController.isAnimating) {
        _progressController.stop();
      }
      return;
    }
    if (restart || _progressController.value <= 0 || _progressController.value >= 1) {
      _progressController.forward(from: 0);
      return;
    }
    if (!_progressController.isAnimating) {
      _progressController.forward(from: _progressController.value);
    }
  }

  void _setLifecyclePaused(bool paused) {
    if (_pausedByLifecycle == paused) return;
    if (!mounted) return;
    setState(() => _pausedByLifecycle = paused);
    _syncProgress();
  }

  void _setGesturePaused(bool paused) {
    if (_pausedByGesture == paused) return;
    if (!mounted) return;
    setState(() => _pausedByGesture = paused);
    _syncProgress();
  }

  Future<T> _withOverlayPause<T>(Future<T> Function() action) async {
    if (mounted) {
      setState(() => _pausedByOverlay = true);
      _syncProgress();
    }
    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() => _pausedByOverlay = false);
        _syncProgress();
      }
    }
  }

  int _resolveInitialIndex() {
    if (_timeline.isEmpty) return 0;
    if (widget.initialStoryId == null || widget.initialStoryId! <= 0) return 0;
    final idx = _timeline.indexWhere(
      (entry) => entry.story.id == widget.initialStoryId,
    );
    return idx >= 0 ? idx : 0;
  }

  void _markViewed(int index) {
    if (index < 0 || index >= _timeline.length) return;
    widget.onStoryViewed?.call(_timeline[index].story.id);
  }

  void _advance({bool autoAdvance = false}) {
    if (_timeline.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    if (_index >= _timeline.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    _controller.nextPage(
      duration: autoAdvance
          ? const Duration(milliseconds: 180)
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _previous() {
    if (_index <= 0) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _toggleLike() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'إعجاب بالقصة',
      featureEnglish: 'liking a story',
    )) {
      return;
    }
    if (!mounted) return;
    final api = widget.api;
    if (api == null || _likeBusy) return;
    final story = _currentStory;
    final wasLiked = _isLiked(story);
    final originalLikes = _likes(story);
    setState(() {
      _likeBusy = true;
      _likedById[story.id] = !wasLiked;
      _likesById[story.id] = (originalLikes + (wasLiked ? -1 : 1)).clamp(0, 1 << 30);
    });
    try {
      final out = await api.toggleStoryLike(story.id);
      final liked = out['isLiked'] ?? out['is_liked'];
      final count = out['likesCount'] ?? out['likes_count'];
      if (!mounted) return;
      setState(() {
        if (liked is bool) _likedById[story.id] = liked;
        if (count is int) _likesById[story.id] = count;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _likedById[story.id] = wasLiked;
        _likesById[story.id] = originalLikes;
      });
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  Future<void> _openComments() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'التعليق على القصة',
      featureEnglish: 'commenting on a story',
    )) {
      return;
    }
    if (!mounted) return;
    final api = widget.api;
    if (api == null) return;
    final story = _currentStory;
    _consumeNextTapUp = true;
    await _withOverlayPause(() {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _StoryCommentsSheet(
          api: api,
          storyId: story.id,
          onCommentAdded: () {
            if (!mounted) return;
            setState(() => _commentsById[story.id] = _comments(story) + 1);
          },
        ),
      );
    });
  }

  Future<void> _shareStory() async {
    final story = _currentStory;
    _consumeNextTapUp = true;
    await _withOverlayPause(() {
      return showSocialShareSheet(
        context: context,
        entityType: 'story',
        entityId: story.id,
        previewTitle: _currentGroup.author.fullName,
        previewSubtitle:
            story.caption.trim().isEmpty ? null : story.caption.trim(),
      );
    });
  }

  Future<void> _openAttachment(SocialStory story) async {
    final attachment = SocialStoryDraft.fromStoryStyle(story: story).attachment;
    if (!mounted || attachment == null) return;
    _consumeNextTapUp = true;
    if (attachment.isReelShare && (attachment.reelId ?? 0) > 0) {
      await _withOverlayPause(
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SocialShellScreen(
              initialTab: SocialShellTab.reels,
              initialReelId: attachment.reelId,
            ),
          ),
        ),
      );
      return;
    }
    if (attachment.isPostShare && (attachment.postId ?? 0) > 0) {
      await _withOverlayPause(
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SocialPostDetailsScreen(postId: attachment.postId),
          ),
        ),
      );
    }
  }

  Future<void> _openMentionProfile(int userId, String? displayLabel) async {
    if (userId <= 0) return;
    _consumeNextTapUp = true;
    await _withOverlayPause(
      () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SocialProfileScreen(userId: userId, initialName: displayLabel),
        ),
      ),
    );
  }

  Future<void> _toggleStoryArchive(bool archived) async {
    final api = widget.api;
    if (api == null) return;
    final story = _currentStory;
    if (!story.isMine) return;
    if (archived) {
      await api.archiveStory(story.id);
    } else {
      await api.restoreStory(story.id);
    }
    widget.onStoryArchiveChanged?.call();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setLifecyclePaused(state != AppLifecycleState.resumed);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _setGesturePaused(true);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _setGesturePaused(false);
  }

  void _next() {
    _advance();
  }

  void _prev() {
    _previous();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_timeline.isEmpty) {
      return SafeArea(
        child: SizedBox(
          height: 260,
          child: Center(
            child: Text(context.l10n.socialProfileArchiveEmptyStories),
          ),
        ),
      );
    }

    final currentEntry = _timeline[_index];

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.84,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  if (_consumeNextTapUp) {
                    _consumeNextTapUp = false;
                    return;
                  }
                  final width = MediaQuery.of(context).size.width;
                  if (details.localPosition.dx < width / 2) {
                    _next();
                  } else {
                    _prev();
                  }
                },
                onLongPressStart: _handleLongPressStart,
                onLongPressEnd: _handleLongPressEnd,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _timeline.length,
                  onPageChanged: (value) {
                    setState(() => _index = value);
                    _markViewed(value);
                    _syncProgress(restart: true);
                  },
                  itemBuilder: (context, idx) {
                    final entry = _timeline[idx];
                    return _StoryCanvas(
                      story: entry.story,
                      isActive: idx == _index,
                      onAttachmentTap: () => _openAttachment(entry.story),
                      onMentionTap: _openMentionProfile,
                    );
                  },
                ),
              ),
            ),
            Positioned(
              right: 12,
              left: 12,
              top: 10,
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage:
                        (currentEntry.group.author.imageUrl ?? '')
                                .trim()
                                .isNotEmpty
                        ? appCachedImageProvider(
                            currentEntry.group.author.imageUrl!,
                            cacheIdentity:
                                'user_avatar_${currentEntry.group.author.id}',
                          )
                        : null,
                    child: (currentEntry.group.author.imageUrl ?? '')
                                .trim()
                                .isEmpty
                        ? const Icon(Icons.person_outline)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      currentEntry.group.author.fullName,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_currentStory.isMine && widget.api != null)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'archive') {
                          _toggleStoryArchive(true);
                        } else if (value == 'restore') {
                          _toggleStoryArchive(false);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem<String>(
                          value: _currentStory.archivedAt == null
                              ? 'archive'
                              : 'restore',
                          child: Text(
                            _currentStory.archivedAt == null
                                ? context.l10n.commonArchive
                                : context.l10n.socialProfilePostsRestore,
                          ),
                        ),
                      ],
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white,
                      ),
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              left: 12,
              top: 56,
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, child) {
                  return Row(
                    children: List.generate(_timeline.length, (idx) {
                      final progress = idx < _index
                          ? 1.0
                          : idx > _index
                              ? 0.0
                              : _progressController.value
                                  .clamp(0.0, 1.0)
                                  .toDouble();
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: Colors.white24,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
            if (widget.api != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: _StoryActionBar(
                  liked: _isLiked(_currentStory),
                  likes: _likes(_currentStory),
                  comments: _comments(_currentStory),
                  busy: _likeBusy,
                  onLike: _toggleLike,
                  onComment: _openComments,
                  onShare: _shareStory,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Like / comment / share bar pinned to the bottom of the story viewer.
class _StoryActionBar extends StatelessWidget {
  final bool liked;
  final int likes;
  final int comments;
  final bool busy;
  final Future<void> Function() onLike;
  final Future<void> Function() onComment;
  final Future<void> Function() onShare;

  const _StoryActionBar({
    required this.liked,
    required this.likes,
    required this.comments,
    required this.busy,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StoryActionButton(
              icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: liked ? const Color(0xFFFF4D67) : Colors.white,
              label: likes > 0 ? '$likes' : context.lt(ar: 'إعجاب', en: 'Like'),
              onTap: busy ? null : () => onLike(),
            ),
            _StoryActionButton(
              icon: Icons.mode_comment_outlined,
              color: Colors.white,
              label: comments > 0
                  ? '$comments'
                  : context.lt(ar: 'تعليق', en: 'Comment'),
              onTap: () => onComment(),
            ),
            _StoryActionButton(
              icon: Icons.send_rounded,
              color: Colors.white,
              label: context.lt(ar: 'مشاركة', en: 'Share'),
              onTap: () => onShare(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _StoryActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing and posting comments on a story. Returns the number of
/// comments added so the viewer can update its count.
class _StoryCommentsSheet extends StatefulWidget {
  final SocialApi api;
  final int storyId;
  final VoidCallback? onCommentAdded;

  const _StoryCommentsSheet({
    required this.api,
    required this.storyId,
    this.onCommentAdded,
  });

  @override
  State<_StoryCommentsSheet> createState() => _StoryCommentsSheetState();
}

class _StoryCommentsSheetState extends State<_StoryCommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  List<SocialComment> _comments = const <SocialComment>[];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await widget.api.listStoryComments(widget.storyId);
      final raw = List<dynamic>.from(out['comments'] as List? ?? const []);
      final parsed = raw
          .map((e) => SocialComment.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _comments = parsed;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(error, fallback: context.l10n.commonRetry);
      });
    }
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final out = await widget.api.addStoryComment(widget.storyId, body);
      final comment = out['comment'] is Map
          ? SocialComment.fromJson(Map<String, dynamic>.from(out['comment'] as Map))
          : null;
      if (!mounted) return;
      setState(() {
        if (comment != null) {
          _comments = <SocialComment>[comment, ..._comments];
        }
        _controller.clear();
        _sending = false;
      });
      widget.onCommentAdded?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapAnyError(error, fallback: context.l10n.commonRetry))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.lt(ar: 'التعليقات', en: 'Comments'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!, textAlign: TextAlign.center),
                                  const SizedBox(height: 10),
                                  FilledButton(
                                    onPressed: _load,
                                    child: Text(context.l10n.commonRetry),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _comments.isEmpty
                            ? Center(
                                child: Text(
                                  context.lt(
                                    ar: 'كن أول من يعلّق',
                                    en: 'Be the first to comment',
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: _comments.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (context, index) {
                                  final c = _comments[index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundImage:
                                          (c.author.imageUrl ?? '').trim().isNotEmpty
                                          ? appCachedImageProvider(
                                              c.author.imageUrl!,
                                              cacheIdentity:
                                                  'user_avatar_${c.author.id}',
                                            )
                                          : null,
                                      child: (c.author.imageUrl ?? '').trim().isEmpty
                                          ? const Icon(Icons.person_outline)
                                          : null,
                                    ),
                                    title: Text(
                                      c.author.fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(c.body),
                                  );
                                },
                              ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: context.lt(
                            ar: 'أضف تعليقًا…',
                            en: 'Add a comment…',
                          ),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
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

class _StoryCanvas extends StatelessWidget {
  final SocialStory story;
  final bool isActive;
  final VoidCallback? onAttachmentTap;
  final void Function(int userId, String? displayLabel)? onMentionTap;

  const _StoryCanvas({
    required this.story,
    required this.isActive,
    this.onAttachmentTap,
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo =
        (story.mediaKind == 'video') &&
        (story.mediaUrl ?? '').trim().isNotEmpty;
    final draft = SocialStoryDraft.fromStoryStyle(story: story);
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: SocialStoryCanvas(
          draft: draft,
          active: isActive,
          remoteMediaUrl: story.mediaUrl,
          remoteMediaKind: story.mediaKind,
          baseMedia: isVideo
              ? _StoryVideoCanvas(
                  mediaUrl: story.mediaUrl!,
                  isActive: isActive,
                  storyId: story.id,
                  version: story.createdAt?.toIso8601String(),
                  clipStartSec: story.style.clipStartSec,
                  clipDurationSec: story.style.clipDurationSec,
                )
              : null,
          onAttachmentTap: onAttachmentTap,
          onLayerTap: (layer) {
            if (layer.type == SocialStoryLayerType.mention &&
                (layer.mentionedUserId ?? 0) > 0) {
              onMentionTap?.call(layer.mentionedUserId!, layer.displayLabel);
              return;
            }
            if ((layer.type == SocialStoryLayerType.reelShare ||
                    layer.type == SocialStoryLayerType.postShare) &&
                onAttachmentTap != null) {
              onAttachmentTap!.call();
            }
          },
        ),
      ),
    );
  }
}

class _StoryVideoCanvas extends StatefulWidget {
  final String mediaUrl;
  final bool isActive;
  final int storyId;
  final String? version;
  final double? clipStartSec;
  final double? clipDurationSec;

  const _StoryVideoCanvas({
    required this.mediaUrl,
    required this.isActive,
    required this.storyId,
    required this.version,
    required this.clipStartSec,
    required this.clipDurationSec,
  });

  @override
  State<_StoryVideoCanvas> createState() => _StoryVideoCanvasState();
}

class _StoryVideoCanvasState extends State<_StoryVideoCanvas>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _muted = false;
  String? _error;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!appSupportsInlineVideoPlayback) {
      _error = 'Video is not supported on this platform';
      return;
    }
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final source = await MediaCacheService.instance.resolveVideoSource(
        url: widget.mediaUrl,
        cacheIdentity: 'story_video_${widget.storyId}',
        version: widget.version,
        scope: MediaCacheScope.public,
      );
      final controller = source.isLocalFile
          ? VideoPlayerController.file(source.file!)
          : VideoPlayerController.networkUrl(source.uri);
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(_muted ? 0 : 1);
      controller.addListener(_enforceClipWindow);
      await _seekToClipStart(controller);
      if (widget.isActive && _appActive) {
        await controller.play();
      } else {
        await controller.pause();
      }
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
      setState(() => _error = 'Unable to play video');
    }
  }

  @override
  void didUpdateWidget(covariant _StoryVideoCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (widget.isActive && _appActive) {
      unawaited(_seekToClipStart(video));
      unawaited(video.play());
    } else {
      unawaited(video.pause());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (widget.isActive && _appActive) {
      unawaited(_seekToClipStart(video));
      unawaited(video.play());
    } else {
      unawaited(video.pause());
    }
  }

  Duration get _clipStart => Duration(
    milliseconds: ((widget.clipStartSec ?? 0) * 1000).round(),
  );

  Duration? get _clipDuration {
    final seconds = widget.clipDurationSec;
    if (seconds == null || seconds <= 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Duration? get _clipEnd {
    final duration = _clipDuration;
    if (duration == null) return null;
    return _clipStart + duration;
  }

  Future<void> _seekToClipStart(VideoPlayerController controller) async {
    final start = _clipStart;
    if (start > Duration.zero && controller.value.position < start) {
      await controller.seekTo(start);
    }
  }

  void _enforceClipWindow() {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    final end = _clipEnd;
    if (end == null) return;
    if (controller.value.position < _clipStart) return;
    if (controller.value.position < end) return;
    unawaited(controller.seekTo(_clipStart));
    if (widget.isActive && _appActive) {
      unawaited(controller.play());
    }
  }

  Future<void> _toggleMute() async {
    final video = _video;
    if (video == null) return;
    final next = !_muted;
    await video.setVolume(next ? 0 : 1);
    if (!mounted) return;
    setState(() => _muted = next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _video?.removeListener(_enforceClipWindow);
    unawaited(_video?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _StoryViewerError(message: _error!);
    }
    if (!_videoReady || _video == null || !_video!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
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
          bottom: 12,
          child: IconButton.filledTonal(
            onPressed: _toggleMute,
            icon: Icon(
              _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            ),
          ),
        ),
      ],
    );
  }
}

class _StoryViewerError extends StatelessWidget {
  final String message;

  const _StoryViewerError({required this.message});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0E1730),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
