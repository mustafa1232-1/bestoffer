import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/i18n/locale_text.dart';
import '../../social/creator/creator_filter_registry.dart';
import '../../social/models/social_story_document.dart';
import '../../social/state/social_story_draft_controller.dart';
import '../../social/ui/widgets/social_design_theme.dart';
import '../../social/ui/widgets/social_story_canvas.dart';
import '../../social/ui/widgets/social_story_tool_panels.dart';
import '../pickers/social_media_picker_v3.dart';
import 'reel_composer_state.dart';
import 'reel_publish_screen.dart';
import 'reel_cover_selector.dart';
import 'reel_video_controls.dart';
import 'reel_video_edits.dart';
import 'reel_video_preparation.dart';

typedef _EditorSnapshot = ({
  SocialStoryDraft draft,
  ReelVideoEdits? edits,
  int cover,
});

// A reel editor must not overwrite the separately persisted story draft.
final _reelDraftProvider = StateNotifierProvider.autoDispose
    .family<SocialStoryDraftController, SocialStoryDraftState, Object>(
      (ref, _) => SocialStoryDraftController(ref, persistAutomatically: false),
    );

class ReelComposerV3 extends ConsumerStatefulWidget {
  const ReelComposerV3({
    super.key,
    required this.video,
    required this.controller,
    this.onPublished,
    this.videoControllerFactory,
  });
  final PickedSocialMedia video;
  final ReelComposerController controller;
  final void Function(int reelId)? onPublished;
  final VideoPlayerController Function(String path)? videoControllerFactory;

  @override
  ConsumerState<ReelComposerV3> createState() => _ReelComposerV3State();
}

class _ReelComposerV3State extends ConsumerState<ReelComposerV3>
    with WidgetsBindingObserver {
  final Object _session = Object();
  final List<_EditorSnapshot> _undo = [];
  final List<_EditorSnapshot> _redo = [];
  VideoPlayerController? _video;
  bool _videoFailed = false;
  bool _openingPublish = false;
  bool _published = false;
  String _caption = '';
  int _coverFrameMs = 0;
  ReelVideoEdits? _videoEdits;
  ReelVideoTool? _videoTool;
  late final _preparation = ReelVideoPreparation(widget.video);
  bool _loopSeeking = false;
  bool _selectingCover = false;
  bool _comments = true;
  bool _sharing = true;

  SocialStoryDraftController get _editor =>
      ref.read(_reelDraftProvider(_session).notifier);
  SocialStoryDraft get _draft => ref.read(_reelDraftProvider(_session)).draft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editor.replaceDraft(
        SocialStoryDraft.initialText().copyWith(
          mode: SocialStoryComposerMode.media,
          mediaPath: widget.video.path,
          mediaName: widget.video.name,
          mediaMimeType: widget.video.mimeType,
        ),
      );
      unawaited(_initializeVideo());
    });
  }

  Future<void> _initializeVideo() async {
    final previous = _video;
    _video = null;
    previous?.removeListener(_guardTrim);
    await previous?.dispose();
    if (!mounted) return;
    setState(() => _videoFailed = false);
    final controller =
        widget.videoControllerFactory?.call(widget.video.path) ??
        (kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(widget.video.path))
            : VideoPlayerController.file(File(widget.video.path)));
    _video = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (!mounted || !identical(_video, controller)) return;
      await controller.setLooping(true);
      if (!mounted || !identical(_video, controller)) return;
      _videoEdits ??= ReelVideoEdits(
        sourceDurationMs: controller.value.duration.inMilliseconds,
      );
      controller.addListener(_guardTrim);
      await _syncPlaybackEdits();
      if (!mounted || !identical(_video, controller)) return;
      setState(() {});
    } catch (_) {
      if (!mounted || !identical(_video, controller)) return;
      _video = null;
      await controller.dispose();
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_video?.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _video?.removeListener(_guardTrim);
    unawaited(_video?.dispose());
    unawaited(_preparation.dispose());
    super.dispose();
  }

  _EditorSnapshot get _snapshot =>
      (draft: _draft, edits: _videoEdits, cover: _coverFrameMs);

  void _remember() {
    setState(() {
      _undo.add(_snapshot);
      if (_undo.length > 50) _undo.removeAt(0);
      _redo.clear();
    });
  }

  void _edit(VoidCallback change) {
    _remember();
    change();
  }

  void _restore(List<_EditorSnapshot> from, List<_EditorSnapshot> to) {
    if (from.isEmpty) return;
    to.add(_snapshot);
    final restored = from.removeLast();
    _editor.replaceDraft(restored.draft);
    setState(() {
      _videoEdits = restored.edits;
      _coverFrameMs = restored.cover;
    });
    unawaited(_syncPlaybackEdits());
    _editor.setTool(SocialStoryComposerTool.none);
  }

  void _updateVideoEdits(ReelVideoEdits edits) {
    setState(() {
      _videoEdits = edits;
      _coverFrameMs = _coverFrameMs.clamp(
        edits.startMs,
        edits.effectiveEndMs - 1,
      );
    });
    unawaited(_syncPlaybackEdits());
  }

  Future<void> _syncPlaybackEdits() async {
    final controller = _video;
    final edits = _videoEdits;
    if (controller == null ||
        !controller.value.isInitialized ||
        edits == null) {
      return;
    }
    try {
      await controller.setPlaybackSpeed(edits.speed);
      if (!mounted || !identical(controller, _video)) return;
      await controller.setVolume(edits.volume);
      if (!mounted || !identical(controller, _video)) return;
      if (controller.value.position.inMilliseconds < edits.startMs ||
          controller.value.position.inMilliseconds >= edits.effectiveEndMs) {
        await controller.seekTo(Duration(milliseconds: edits.startMs));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.lt(
                ar: 'تعذر تحديث المعاينة، حاول مرة أخرى',
                en: 'Could not update preview. Please retry.',
              ),
            ),
          ),
        );
      }
    }
  }

  void _guardTrim() {
    final video = _video;
    final edits = _videoEdits;
    if (_loopSeeking ||
        _openingPublish ||
        _selectingCover ||
        video == null ||
        edits == null ||
        !video.value.isPlaying) {
      return;
    }
    final position = video.value.position.inMilliseconds;
    if (position >= edits.startMs && position < edits.effectiveEndMs) return;
    _loopSeeking = true;
    unawaited(
      video
          .seekTo(Duration(milliseconds: edits.startMs))
          .catchError((Object _) {})
          .whenComplete(() => _loopSeeking = false),
    );
  }

  Future<void> _preview() async {
    if (_video?.value.isInitialized != true || _videoEdits?.isValid != true) {
      return;
    }
    _editor.setTool(SocialStoryComposerTool.none);
    FocusScope.of(context).unfocus();
    final document = _draft;
    final next = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => Scaffold(
          backgroundColor: SocialDesignTheme.dark,
          appBar: AppBar(
            backgroundColor: SocialDesignTheme.dark,
            foregroundColor: Colors.white,
            title: Text(context.lt(ar: 'معاينة الريل', en: 'Reel preview')),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(child: _canvas(document, editable: false)),
                ),
                if (_video?.value.isInitialized == true)
                  _PlaybackControls(controller: _video!, edits: _videoEdits!),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(context.lt(ar: 'التالي', en: 'Next')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    await _video?.pause();
    if (next == true && mounted) await _openPublish();
  }

  Future<void> _openPublish() async {
    if (_openingPublish) return;
    _openingPublish = true;
    try {
      await _video?.pause();
      if (!mounted) return;
      if (_video?.value.isInitialized == true) {
        await _video!.seekTo(Duration(milliseconds: _coverFrameMs));
      }
      if (!mounted) return;
      final document = _draft;
      final edits = _videoEdits!;
      final id = await Navigator.of(context).push<int>(
        MaterialPageRoute<int>(
          builder: (_) => ReelPublishScreen(
            video: widget.video,
            controller: widget.controller,
            initialCaption: _caption,
            onCaptionChanged: (value) => _caption = value,
            initialCommentsEnabled: _comments,
            initialSharingEnabled: _sharing,
            onSettingsChanged: (comments, sharing) {
              _comments = comments;
              _sharing = sharing;
            },
            prepareVideo: edits.requiresExport
                ? (progress, cancellation) =>
                      _preparation.prepare(edits, progress, cancellation)
                : null,
            reelStyle: {
              ...document.toStoryStyleJson(),
              'coverFrameMs': edits.outputFrameMs(_coverFrameMs),
            },
            preview: FittedBox(
              child: SizedBox(
                width: 360,
                height: 640,
                child: _canvas(document, editable: false),
              ),
            ),
          ),
        ),
      );
      if (!mounted) return;
      final publishedId = id ?? widget.controller.publishedReelId;
      if (publishedId != null && !_published) {
        _published = true;
        widget.onPublished?.call(publishedId);
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          context.lt(ar: 'تعذر فتح إعدادات النشر، حاول مرة أخرى', en: 'Could not open publishing settings. Please retry.'),
        )));
      }
    } finally {
      _openingPublish = false;
    }
  }

  Widget _canvas(SocialStoryDraft document, {required bool editable}) {
    final controller = _video;
    final Widget media;
    if (controller?.value.isInitialized == true) {
      media = FittedBox(
        fit: controller!.value.aspectRatio < 1 ? BoxFit.cover : BoxFit.contain,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(
              resolveCreatorFilterPreset(_videoEdits?.filterId).previewMatrix,
            ),
            child: VideoPlayer(controller),
          ),
        ),
      );
    } else {
      media = Center(
        child: _videoFailed
            ? IconButton(
                onPressed: _initializeVideo,
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: context.lt(ar: 'إعادة المحاولة', en: 'Retry'),
              )
            : const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(color: Colors.white),
              ),
      );
    }
    final state = ref.read(_reelDraftProvider(_session));
    return SocialStoryCanvas(
      draft: editable
          ? document
          : document.copyWith(
              layers: document.layers
                  .map((l) => l.copyWith(locked: true))
                  .toList(),
            ),
      selectedLayerId: editable ? state.selectedLayerId : null,
      showBackground: false,
      borderRadius: BorderRadius.zero,
      baseMedia: media,
      drawEnabled: editable && state.activeTool == SocialStoryComposerTool.draw,
      onSelectLayer: editable ? _editor.selectLayer : null,
      onLayerChanged: editable
          ? (layer) => _edit(() => _editor.updateLayer(layer.id, layer))
          : null,
      onDrawStroke: editable
          ? (stroke) => _edit(() => _editor.addDrawStroke(stroke))
          : null,
    );
  }

  Future<void> _chooseCover() async {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    final previous = video.value.position;
    _selectingCover = true;
    await video.pause();
    if (!mounted) return;
    final selected = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => ReelCoverSelector(
          controller: video,
          initialFrameMs: _coverFrameMs,
          startMs: _videoEdits?.startMs ?? 0,
          endMs: _videoEdits?.effectiveEndMs,
        ),
      ),
    );
    if (!mounted) return;
    if (selected != null) {
      _remember();
      setState(() => _coverFrameMs = selected);
    }
    await video.seekTo(previous);
    _selectingCover = false;
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = keyboardHeight > 0;
    final availableHeight =
        (MediaQuery.sizeOf(context).height -
                keyboardHeight -
                MediaQuery.paddingOf(context).vertical -
                kToolbarHeight -
                52)
            .clamp(0.0, double.infinity);
    final state = ref.watch(_reelDraftProvider(_session));
    final selected = state.draft.layers
        .where((l) => l.id == state.selectedLayerId)
        .firstOrNull;
    final tool = SocialStoryComposerToolView.values.firstWhere(
      (t) => t.name == state.activeTool.name,
    );
    final darkTheme = Theme.of(context).copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SocialDesignTheme.dark,
      colorScheme: const ColorScheme.dark(
        primary: SocialDesignTheme.gold,
        onPrimary: SocialDesignTheme.ink,
        surface: Color(0xFF171A20),
        onSurface: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      textTheme: Theme.of(
        context,
      ).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
    );
    return Theme(
      data: darkTheme,
      child: Scaffold(
        backgroundColor: SocialDesignTheme.dark,
        appBar: AppBar(
          backgroundColor: SocialDesignTheme.dark,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: context.lt(ar: 'إغلاق', en: 'Close'),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text(
            context.lt(ar: 'تحرير الريل', en: 'Edit reel'),
            style: const TextStyle(fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: context.lt(ar: 'تراجع', en: 'Undo'),
              onPressed: _undo.isEmpty ? null : () => _restore(_undo, _redo),
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: context.lt(ar: 'إعادة', en: 'Redo'),
              onPressed: _redo.isEmpty ? null : () => _restore(_redo, _undo),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.text_fields),
                        tooltip: context.lt(ar: 'نص', en: 'Text'),
                        onPressed: () {
                          if (selected?.type != SocialStoryLayerType.text) {
                            _edit(() => _editor.addTextLayer());
                          }
                          _editor.setTool(SocialStoryComposerTool.text);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.alternate_email),
                        tooltip: context.lt(ar: 'إشارة', en: 'Mention'),
                        onPressed: () =>
                            _editor.setTool(SocialStoryComposerTool.mention),
                      ),
                      IconButton(
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        tooltip: context.lt(ar: 'ملصقات', en: 'Stickers'),
                        onPressed: () =>
                            _editor.setTool(SocialStoryComposerTool.stickers),
                      ),
                      IconButton(
                        icon: const Icon(Icons.draw_outlined),
                        tooltip: context.lt(ar: 'رسم', en: 'Draw'),
                        onPressed: () =>
                            _editor.setTool(SocialStoryComposerTool.draw),
                      ),
                      IconButton(
                        icon: const Icon(Icons.image_outlined),
                        tooltip: context.lt(
                          ar: 'اختيار الغلاف',
                          en: 'Choose cover',
                        ),
                        onPressed: _video?.value.isInitialized == true
                            ? _chooseCover
                            : null,
                      ),
                      if (selected != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: context.lt(
                            ar: 'حذف العنصر',
                            en: 'Delete layer',
                          ),
                          onPressed: () => _edit(_editor.removeSelectedLayer),
                        ),
                      IconButton(
                        icon: const Icon(Icons.fullscreen),
                        tooltip: context.lt(ar: 'معاينة', en: 'Preview'),
                        onPressed: _videoEdits?.isValid == true
                            ? _preview
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: RepaintBoundary(
                    child: _canvas(state.draft, editable: true),
                  ),
                ),
              ),
              if (!keyboardVisible && _video?.value.isInitialized == true)
                _PlaybackControls(controller: _video!, edits: _videoEdits!),
              if (!keyboardVisible && !kIsWeb && _videoEdits != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final entry in [
                      (
                        ReelVideoTool.trim,
                        Icons.content_cut,
                        context.lt(ar: 'قص', en: 'Trim'),
                      ),
                      (
                        ReelVideoTool.speed,
                        Icons.speed,
                        context.lt(ar: 'السرعة', en: 'Speed'),
                      ),
                      (
                        ReelVideoTool.audio,
                        Icons.volume_up_outlined,
                        context.lt(ar: 'الصوت', en: 'Audio'),
                      ),
                      (
                        ReelVideoTool.filter,
                        Icons.filter_vintage_outlined,
                        context.lt(ar: 'الفلاتر', en: 'Filters'),
                      ),
                    ])
                      IconButton(
                        isSelected: _videoTool == entry.$1,
                        tooltip: entry.$3,
                        icon: Icon(entry.$2),
                        onPressed: () {
                          _editor.setTool(SocialStoryComposerTool.none);
                          setState(
                            () => _videoTool = _videoTool == entry.$1
                                ? null
                                : entry.$1,
                          );
                        },
                      ),
                  ],
                ),
                if (_videoTool != null &&
                    tool == SocialStoryComposerToolView.none)
                  ReelVideoControls(
                    edits: _videoEdits!,
                    tool: _videoTool!,
                    onEditStart: _remember,
                    onChanged: _updateVideoEdits,
                  ),
              ],
              if (tool != SocialStoryComposerToolView.none)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: keyboardVisible
                        ? availableHeight * .8
                        : MediaQuery.sizeOf(context).height * .32,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: IconButton(
                            icon: const Icon(Icons.check),
                            tooltip: context.lt(ar: 'تم', en: 'Done'),
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              _editor.setTool(SocialStoryComposerTool.none);
                            },
                          ),
                        ),
                        SocialStoryToolPanels(
                          tool: tool,
                          selectedLayer: selected,
                          onTextChanged: (v) => _edit(
                            () => _editor.updateSelectedTextLayer(text: v),
                          ),
                          onTextColorChanged: (v) => _edit(
                            () => _editor.updateSelectedTextLayer(color: v),
                          ),
                          onTextBackgroundChanged: (v) => _edit(
                            () => _editor.updateSelectedTextLayer(
                              backgroundColor: v,
                            ),
                          ),
                          onFontScaleChanged: (v) => _edit(
                            () => _editor.updateSelectedTextLayer(fontScale: v),
                          ),
                          onStickerSelected: (v) =>
                              _edit(() => _editor.addStickerLayer(v)),
                          onMentionSelected: (id, label) => _edit(
                            () => _editor.addMentionLayer(
                              userId: id,
                              displayLabel: label,
                            ),
                          ),
                          onClearSelection: () =>
                              _editor.setTool(SocialStoryComposerTool.none),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!keyboardVisible)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _videoEdits?.isValid == true ? _preview : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(
                        context.lt(
                          ar: 'معاينة ومتابعة',
                          en: 'Preview and continue',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller, required this.edits});
  final VideoPlayerController controller;
  final ReelVideoEdits edits;

  String _time(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                tooltip: value.isPlaying
                    ? context.lt(ar: 'إيقاف مؤقت', en: 'Pause')
                    : context.lt(ar: 'تشغيل', en: 'Play'),
                onPressed: () =>
                    value.isPlaying ? controller.pause() : controller.play(),
              ),
              Text(
                _time(
                  Duration(
                    milliseconds:
                        ((value.position.inMilliseconds - edits.startMs) /
                                edits.speed)
                            .round()
                            .clamp(0, edits.outputDurationMs),
                  ),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Slider(
                    min: edits.startMs.toDouble(),
                    max: edits.effectiveEndMs.toDouble(),
                    value: value.position.inMilliseconds.toDouble().clamp(
                      edits.startMs.toDouble(),
                      edits.effectiveEndMs.toDouble(),
                    ),
                    activeColor: SocialDesignTheme.gold,
                    onChanged: (v) =>
                        controller.seekTo(Duration(milliseconds: v.round())),
                  ),
                ),
              ),
              Text(
                _time(Duration(milliseconds: edits.outputDurationMs)),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
              IconButton(
                color: Colors.white,
                icon: Icon(
                  value.volume == 0 ? Icons.volume_off : Icons.volume_up,
                ),
                tooltip: value.volume == 0
                    ? context.lt(ar: 'تشغيل صوت المعاينة', en: 'Unmute preview')
                    : context.lt(ar: 'كتم المعاينة', en: 'Mute preview'),
                onPressed: edits.volume == 0
                    ? null
                    : () => controller.setVolume(
                        value.volume == 0 ? edits.volume : 0,
                      ),
              ),
            ],
          ),
        ),
      );
}
