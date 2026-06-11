import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/media/cached_app_image.dart';
import '../../../core/media/media_cache_models.dart';
import '../../../core/media/media_cache_service.dart';
import '../../../core/platform/app_platform_capabilities.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../models/social_story_document.dart';
import 'social_post_details_screen.dart';
import 'social_profile_screen.dart';
import 'social_shell_screen.dart';
import 'widgets/social_story_canvas.dart';

Future<void> showSocialStoryQuickViewer({
  required BuildContext context,
  required SocialStoryGroup group,
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
      initialStoryId: initialStoryId,
      onStoryViewed: onStoryViewed,
      api: api,
      onStoryArchiveChanged: onStoryArchiveChanged,
    ),
  );
}

class _SocialStoryQuickViewerSheet extends StatefulWidget {
  final SocialStoryGroup group;
  final int? initialStoryId;
  final ValueChanged<int>? onStoryViewed;
  final SocialApi? api;
  final VoidCallback? onStoryArchiveChanged;

  const _SocialStoryQuickViewerSheet({
    required this.group,
    this.initialStoryId,
    this.onStoryViewed,
    this.api,
    this.onStoryArchiveChanged,
  });

  @override
  State<_SocialStoryQuickViewerSheet> createState() =>
      _SocialStoryQuickViewerSheetState();
}

class _SocialStoryQuickViewerSheetState
    extends State<_SocialStoryQuickViewerSheet> {
  late final PageController _controller;
  late int _index;
  bool _consumeNextTapUp = false;

  SocialStory get _currentStory => widget.group.stories[_index];

  @override
  void initState() {
    super.initState();
    _index = _resolveInitialIndex();
    _controller = PageController(initialPage: _index);
    _markViewed(_index);
  }

  int _resolveInitialIndex() {
    if (widget.initialStoryId == null || widget.initialStoryId! <= 0) return 0;
    final idx = widget.group.stories.indexWhere(
      (story) => story.id == widget.initialStoryId,
    );
    return idx >= 0 ? idx : 0;
  }

  void _markViewed(int index) {
    if (index < 0 || index >= widget.group.stories.length) return;
    widget.onStoryViewed?.call(widget.group.stories[index].id);
  }

  void _next() {
    if (_index >= widget.group.stories.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _prev() {
    if (_index <= 0) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openAttachment(SocialStory story) async {
    final attachment = SocialStoryDraft.fromStoryStyle(story: story).attachment;
    if (!mounted || attachment == null) return;
    _consumeNextTapUp = true;
    if (attachment.isReelShare && (attachment.reelId ?? 0) > 0) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SocialShellScreen(
            initialTab: SocialShellTab.reels,
            initialReelId: attachment.reelId,
          ),
        ),
      );
      return;
    }
    if (attachment.isPostShare && (attachment.postId ?? 0) > 0) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SocialPostDetailsScreen(postId: attachment.postId),
        ),
      );
    }
  }

  Future<void> _openMentionProfile(int userId, String? displayLabel) async {
    if (userId <= 0) return;
    _consumeNextTapUp = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SocialProfileScreen(userId: userId, initialName: displayLabel),
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stories = widget.group.stories;
    if (stories.isEmpty) {
      return SafeArea(
        child: SizedBox(
          height: 260,
          child: Center(
            child: Text(context.l10n.socialProfileArchiveEmptyStories),
          ),
        ),
      );
    }

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
                child: PageView.builder(
                  controller: _controller,
                  itemCount: stories.length,
                  onPageChanged: (value) {
                    setState(() => _index = value);
                    _markViewed(value);
                  },
                  itemBuilder: (context, idx) {
                    final story = stories[idx];
                    return _StoryCanvas(
                      story: story,
                      isActive: idx == _index,
                      onAttachmentTap: () => _openAttachment(story),
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
                        (widget.group.author.imageUrl ?? '').trim().isNotEmpty
                        ? appCachedImageProvider(
                            widget.group.author.imageUrl!,
                            cacheIdentity:
                                'user_avatar_${widget.group.author.id}',
                          )
                        : null,
                    child: (widget.group.author.imageUrl ?? '').trim().isEmpty
                        ? const Icon(Icons.person_outline)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.group.author.fullName,
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
              child: Row(
                children: List.generate(stories.length, (idx) {
                  final active = idx <= _index;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: active ? Colors.white : Colors.white24,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
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

  const _StoryVideoCanvas({
    required this.mediaUrl,
    required this.isActive,
    required this.storyId,
    required this.version,
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
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
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
      unawaited(video.play());
    } else {
      unawaited(video.pause());
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
