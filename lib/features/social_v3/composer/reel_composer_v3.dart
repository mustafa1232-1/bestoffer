import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:social_core/local_media_file.dart';

import '../../social/models/social_story_document.dart';
import '../../social/state/social_story_draft_controller.dart';
import '../../social/ui/widgets/social_story_canvas.dart';
import '../../social/ui/widgets/social_story_tool_panels.dart';
import '../pickers/social_media_picker_v3.dart';
import '../upload/reel_map_normalizer.dart';
import 'reel_composer_state.dart';

/// Reel editor + publish screen (Social V3). This is the production reel
/// composer: it keeps a live draft, renders the selected video inside the
/// canonical 9:16 canvas, and exposes the same overlay tools used by the Story
/// composer so the reel can be reviewed before publishing.
class ReelComposerV3 extends ConsumerStatefulWidget {
  const ReelComposerV3({
    super.key,
    required this.video,
    required this.controller,
    this.onPublished,
  });

  final PickedSocialMedia video;
  final ReelComposerController controller;
  final void Function(int reelId)? onPublished;

  @override
  ConsumerState<ReelComposerV3> createState() => _ReelComposerV3State();
}

class _ReelComposerV3State extends ConsumerState<ReelComposerV3> {
  late final TextEditingController _captionController;
  bool _seededDraft = false;
  bool _publishedCallbackFired = false;
  bool _publishedCloseScheduled = false;
  bool _comments = true;
  bool _sharing = true;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _seedDraft();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _captionController.dispose();
    super.dispose();
  }

  void _seedDraft() {
    if (_seededDraft) return;
    _seededDraft = true;
    final notifier = ref.read(socialStoryDraftControllerProvider.notifier);
    final initial = SocialStoryDraft.initialText().copyWith(
      mode: SocialStoryComposerMode.media,
      caption: '',
      mediaPath: widget.video.path,
      mediaName: widget.video.name,
      mediaMimeType: widget.video.mimeType,
    );
    notifier.replaceDraft(initial);
    _captionController.text = initial.caption;
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final stage = widget.controller.stage;
    if (stage == ReelComposerStage.published && !_publishedCallbackFired) {
      final reelId = widget.controller.publishedReelId;
      if (reelId != null && reelId > 0) {
        _publishedCallbackFired = true;
        widget.onPublished?.call(reelId);
        _scheduleCloseAfterPublish();
      }
    }
    setState(() {});
  }

  void _scheduleCloseAfterPublish() {
    if (_publishedCloseScheduled) return;
    _publishedCloseScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  SocialStoryLayer? _selectedLayer(SocialStoryDraft draft, String? layerId) {
    if (layerId == null) return null;
    for (final layer in draft.layers) {
      if (layer.id == layerId) return layer;
    }
    return null;
  }

  void _setTool(SocialStoryComposerTool tool) {
    ref.read(socialStoryDraftControllerProvider.notifier).setTool(tool);
  }

  Future<void> _publish() async {
    if (widget.controller.stage != ReelComposerStage.draft &&
        widget.controller.stage != ReelComposerStage.failed) {
      return;
    }
    final draft = ref.read(socialStoryDraftControllerProvider).draft;
    final caption = _captionController.text.trim().isNotEmpty
        ? _captionController.text.trim()
        : draft.caption.trim();
    await widget.controller.publish(
      video: widget.video,
      caption: caption,
      audience: 'public',
      commentsEnabled: _comments,
      sharingEnabled: _sharing,
      reelStyle: normalizeOptionalMap(draft.toStoryStyleJson()),
    );
  }

  Future<void> _pause() async {
    widget.controller.pauseUpload();
  }

  Future<void> _resume() async {
    await widget.controller.resumeUpload();
  }

  void _deleteSelectedLayer() {
    final notifier = ref.read(socialStoryDraftControllerProvider.notifier);
    notifier.removeSelectedLayer();
    notifier.setTool(SocialStoryComposerTool.none);
  }

  Widget? _buildBaseMedia(SocialStoryDraft draft) {
    final media = draft.buildLocalMediaFile();
    if (media == null) return null;
    if (media.isVideo) return _ReelLocalVideoPreview(media: media);
    final path = (media.path ?? '').trim();
    if (path.isEmpty) return null;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  SocialStoryComposerToolView _toolViewFor(SocialStoryComposerTool tool) {
    switch (tool) {
      case SocialStoryComposerTool.text:
        return SocialStoryComposerToolView.text;
      case SocialStoryComposerTool.mention:
        return SocialStoryComposerToolView.mention;
      case SocialStoryComposerTool.stickers:
        return SocialStoryComposerToolView.stickers;
      case SocialStoryComposerTool.draw:
        return SocialStoryComposerToolView.draw;
      case SocialStoryComposerTool.media:
        return SocialStoryComposerToolView.none;
      case SocialStoryComposerTool.none:
        return SocialStoryComposerToolView.none;
    }
  }

  @override
  Widget build(BuildContext context) {
    final draftState = ref.watch(socialStoryDraftControllerProvider);
    final draft = draftState.draft;
    final selectedLayer = _selectedLayer(draft, draftState.selectedLayerId);
    final toolView = _toolViewFor(draftState.activeTool);
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final padding = MediaQuery.of(context).padding;
    final notifier = ref.read(socialStoryDraftControllerProvider.notifier);
    final stage = widget.controller.stage;
    final busy =
        stage != ReelComposerStage.draft &&
        stage != ReelComposerStage.failed &&
        stage != ReelComposerStage.cancelled;
    final showToolPanel = draftState.activeTool != SocialStoryComposerTool.none;
    final hasSelectedEditableLayer =
        selectedLayer != null && !selectedLayer.locked;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Center(
              child: SocialStoryCanvas(
                draft: draft,
                selectedLayerId: draftState.selectedLayerId,
                drawEnabled:
                    draftState.activeTool == SocialStoryComposerTool.draw,
                active: true,
                borderRadius: BorderRadius.zero,
                baseMedia: _buildBaseMedia(draft),
                onSelectLayer: notifier.selectLayer,
                onLayerChanged: (layer) =>
                    notifier.updateLayer(layer.id, layer),
                onDrawStroke: notifier.addDrawStroke,
                onLayerTap: (layer) {
                  if (layer.type == SocialStoryLayerType.mention &&
                      (layer.mentionedUserId ?? 0) > 0) {
                    return;
                  }
                  notifier.selectLayer(layer.id);
                },
              ),
            ),
          ),
          Positioned(
            top: padding.top + 10,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _RoundButton(
                  icon: Icons.close_rounded,
                  onTap: busy ? null : () => Navigator.of(context).maybePop(),
                ),
                Row(
                  children: [
                    if (hasSelectedEditableLayer) ...[
                      _RoundButton(
                        icon: Icons.delete_outline_rounded,
                        onTap: _deleteSelectedLayer,
                        foregroundColor: const Color(0xFFF87171),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _RoundButton(
                      icon: Icons.text_fields_rounded,
                      onTap: busy
                          ? null
                          : () {
                              if (draftState.selectedLayerId == null ||
                                  selectedLayer?.type !=
                                      SocialStoryLayerType.text) {
                                notifier.addTextLayer(
                                  text: _captionController.text,
                                );
                              }
                              _setTool(SocialStoryComposerTool.text);
                            },
                    ),
                    const SizedBox(width: 8),
                    _RoundButton(
                      icon: Icons.alternate_email_rounded,
                      onTap: busy
                          ? null
                          : () => _setTool(SocialStoryComposerTool.mention),
                    ),
                    const SizedBox(width: 8),
                    _RoundButton(
                      icon: Icons.emoji_emotions_outlined,
                      onTap: busy
                          ? null
                          : () => _setTool(SocialStoryComposerTool.stickers),
                    ),
                    const SizedBox(width: 8),
                    _RoundButton(
                      icon: Icons.brush_rounded,
                      onTap: busy
                          ? null
                          : () => _setTool(SocialStoryComposerTool.draw),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: keyboardInset + 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showToolPanel) ...[
                  SocialStoryToolPanels(
                    tool: toolView,
                    selectedLayer: selectedLayer,
                    onTextChanged: (value) {
                      notifier.setCaption(value);
                      notifier.updateSelectedTextLayer(text: value);
                    },
                    onTextColorChanged: (value) {
                      notifier.updateSelectedTextLayer(color: value);
                    },
                    onTextBackgroundChanged: (value) {
                      notifier.updateSelectedTextLayer(backgroundColor: value);
                    },
                    onFontScaleChanged: (value) {
                      notifier.updateSelectedTextLayer(fontScale: value);
                    },
                    onStickerSelected: (sticker) {
                      notifier.addStickerLayer(sticker);
                    },
                    onMentionSelected: (userId, label) {
                      notifier.addMentionLayer(
                        userId: userId,
                        displayLabel: label,
                      );
                    },
                    onClearSelection: () =>
                        _setTool(SocialStoryComposerTool.none),
                  ),
                  const SizedBox(height: 10),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0D1B2A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE7B24B)),
                  ),
                  child: TextField(
                    controller: _captionController,
                    enabled: !busy,
                    onChanged: (value) => notifier.setCaption(value),
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'اكتب وصفًا للريل...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const _ScopeChip(
                      label: 'عام',
                      official: false,
                      locked: true,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              setState(() {
                                _comments = !_comments;
                              });
                            },
                      child: Text(
                        _comments ? 'التعليقات: مفعلة' : 'التعليقات: متوقفة',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              setState(() {
                                _sharing = !_sharing;
                              });
                            },
                      child: Text(
                        _sharing ? 'المشاركة: مفعلة' : 'المشاركة: متوقفة',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: busy ? null : _publish,
                      child: const Text(
                        'نشر',
                        style: TextStyle(
                          color: Color(0xFFE7B24B),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _StageView(controller: widget.controller),
                if (stage == ReelComposerStage.uploading)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _pause,
                        child: const Text('إيقاف مؤقت'),
                      ),
                    ),
                  ),
                if (stage == ReelComposerStage.paused)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _resume,
                        child: const Text('استئناف'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageView extends StatelessWidget {
  const _StageView({required this.controller});

  final ReelComposerController controller;

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    switch (stage) {
      case ReelComposerStage.draft:
        return const SizedBox.shrink();
      case ReelComposerStage.creatingSession:
        return const _StatusLine(text: 'جاري تجهيز الرفع...');
      case ReelComposerStage.uploading:
      case ReelComposerStage.paused:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: controller.progress,
              color: const Color(0xFFE7B24B),
              backgroundColor: Colors.white12,
            ),
            const SizedBox(height: 6),
            Text(
              '${(controller.progress * 100).round()}%'
              '${stage == ReelComposerStage.paused ? ' (متوقف)' : ''}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        );
      case ReelComposerStage.processing:
        return const _StatusLine(text: 'جاري تجهيز الفيديو...');
      case ReelComposerStage.published:
        return const _StatusLine(text: 'تم النشر ✓', color: Color(0xFF4CAF50));
      case ReelComposerStage.failed:
        return _StatusLine(
          text: 'فشل: ${controller.error ?? ''}',
          color: const Color(0xFFE53935),
        );
      case ReelComposerStage.cancelled:
        return const _StatusLine(text: 'أُلغِي الرفع');
    }
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text, this.color = Colors.white70});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.official,
    required this.locked,
  });

  final String label;
  final bool official;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2438),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE7B24B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            official ? Icons.verified_rounded : Icons.public_rounded,
            size: 16,
            color: const Color(0xFFE7B24B),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (locked) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: Colors.white70,
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.foregroundColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xAA0D1B2A),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: foregroundColor, size: 22),
        ),
      ),
    );
  }
}

class _ReelLocalVideoPreview extends StatefulWidget {
  const _ReelLocalVideoPreview({required this.media});

  final LocalMediaFile media;

  @override
  State<_ReelLocalVideoPreview> createState() => _ReelLocalVideoPreviewState();
}

class _ReelLocalVideoPreviewState extends State<_ReelLocalVideoPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final path = widget.media.path;
      if (path == null || path.trim().isEmpty) {
        throw StateError('Local video preview requires a file path');
      }
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ready = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return const ColoredBox(
        color: Color(0xFF0D1B2A),
        child: Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white54,
            size: 72,
          ),
        ),
      );
    }

    final controller = _controller!;
    final aspect = controller.value.aspectRatio;
    final isVertical = aspect < 1.0;
    final player = FittedBox(
      fit: isVertical ? BoxFit.cover : BoxFit.contain,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );

    if (isVertical) {
      return player;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: VideoPlayer(controller),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
          ),
        ),
        Center(
          child: AspectRatio(
            aspectRatio: aspect <= 0 ? 9 / 16 : aspect,
            child: player,
          ),
        ),
      ],
    );
  }
}
