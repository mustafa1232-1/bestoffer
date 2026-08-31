import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_core/local_media_file.dart';
import 'package:video_player/video_player.dart';

import '../../social/models/social_story_document.dart';
import '../../social/state/social_controller.dart';
import '../../social/state/social_story_draft_controller.dart';
import '../../social/ui/social_content_navigation.dart';
import '../../social/ui/widgets/social_story_canvas.dart';
import '../../social/ui/widgets/social_story_tool_panels.dart';
import '../media/social_safe_image.dart';
import '../pickers/social_media_picker_v3.dart';
import 'story_composer_source.dart';
import 'story_media_type_picker.dart';

/// Backwards-compatible marker persisted inside storyStyle for the base media.
/// Existing Story documents need no database migration: x/y/scale/rotation are
/// carried by the existing layer schema and [text] stores `contain` / `cover`.
const String kStoryBaseMediaTransformLayerId = '__base_media_transform_v1__';

/// Keep rotations inside the backend Story-style contract (-6.4..6.4) while
/// preserving the visually equivalent angle. Normalizing to -pi..pi also keeps
/// repeated rotate gestures/buttons from growing the persisted value forever.
double _normalizeStoryRotation(double value) =>
    math.atan2(math.sin(value), math.cos(value));

class StoryComposerV3 extends ConsumerStatefulWidget {
  const StoryComposerV3({
    super.key,
    required this.source,
    this.scope = StoryComposerScope.global,
    this.audienceScopeSupported = kStoryAudienceScopeSupported,
    this.onPublish,
    this.onSaveDraft,
  });

  final StoryComposerSource source;
  final StoryComposerScope scope;
  final bool audienceScopeSupported;
  final Future<bool> Function(String caption, StoryComposerScope scope)? onPublish;
  final void Function(String caption)? onSaveDraft;

  static Route<void> route(
    StoryComposerSource source, {
    StoryComposerScope scope = StoryComposerScope.global,
    bool audienceScopeSupported = kStoryAudienceScopeSupported,
    Future<bool> Function(String caption, StoryComposerScope scope)? onPublish,
    void Function(String caption)? onSaveDraft,
  }) {
    return MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StoryComposerV3(
        source: source,
        scope: scope,
        audienceScopeSupported: audienceScopeSupported,
        onPublish: onPublish,
        onSaveDraft: onSaveDraft,
      ),
    );
  }

  @override
  ConsumerState<StoryComposerV3> createState() => _StoryComposerV3State();
}

class _StoryComposerV3State extends ConsumerState<StoryComposerV3> {
  late final TextEditingController _captionController;
  bool _publishing = false;

  StoryComposerScope get _scope => widget.scope;

  bool get _scopedPublishBlocked =>
      _scope.scope != StoryAudienceScope.global &&
      !widget.audienceScopeSupported;

  @override
  void initState() {
    super.initState();
    var draft = widget.source.buildInitialDraft();
    if (draft.buildLocalMediaFile() != null) {
      draft = _ensureMediaTransform(draft);
    }
    _captionController = TextEditingController(text: draft.caption);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(socialStoryDraftControllerProvider.notifier).replaceDraft(draft);
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  SocialStoryLayer _defaultMediaTransformLayer() => const SocialStoryLayer(
        id: kStoryBaseMediaTransformLayerId,
        type: SocialStoryLayerType.reelShare,
        x: 0.5,
        y: 0.5,
        scale: 1,
        rotation: 0,
        // Backend sanitizeLayer accepts -100..100. Reserve the lowest legal
        // z-index so this compatibility marker can never cover user layers.
        zIndex: -100,
        text: 'contain',
        color: null,
        backgroundColor: null,
        fontFamily: null,
        fontWeight: null,
        textAlign: null,
        fontScale: null,
        sticker: null,
        mentionedUserId: null,
        displayLabel: null,
        locked: true,
      );

  SocialStoryLayer? _mediaTransformLayer(SocialStoryDraft draft) {
    for (final layer in draft.layers) {
      if (layer.id == kStoryBaseMediaTransformLayerId) return layer;
    }
    return null;
  }

  SocialStoryDraft _ensureMediaTransform(SocialStoryDraft draft) {
    if (_mediaTransformLayer(draft) != null) return draft;
    return draft.copyWith(
      layers: <SocialStoryLayer>[
        ...draft.layers,
        _defaultMediaTransformLayer(),
      ],
    );
  }

  void _setMediaTransform({
    double? x,
    double? y,
    double? scale,
    double? rotation,
    String? fit,
    bool reset = false,
  }) {
    final notifier = ref.read(socialStoryDraftControllerProvider.notifier);
    var draft = ref.read(socialStoryDraftControllerProvider).draft;
    if (draft.buildLocalMediaFile() == null) return;
    draft = _ensureMediaTransform(draft);
    final current = _mediaTransformLayer(draft) ?? _defaultMediaTransformLayer();
    final next = reset
        ? _defaultMediaTransformLayer()
        : current.copyWith(
            x: (x ?? current.x).clamp(-0.25, 1.25).toDouble(),
            y: (y ?? current.y).clamp(-0.25, 1.25).toDouble(),
            // Backend validates Story layer scale at 0.2..4.
            scale: (scale ?? current.scale).clamp(0.5, 4.0).toDouble(),
            rotation: _normalizeStoryRotation(rotation ?? current.rotation),
            text: fit ?? current.text,
          );
    final layers = draft.layers
        .map(
          (layer) => layer.id == kStoryBaseMediaTransformLayerId ? next : layer,
        )
        .toList(growable: true);
    if (!layers.any((layer) => layer.id == kStoryBaseMediaTransformLayerId)) {
      layers.add(next);
    }
    notifier.replaceDraft(draft.copyWith(layers: layers));
  }

  void _toggleFit(SocialStoryDraft draft) {
    final current = (_mediaTransformLayer(draft)?.text ?? 'contain')
        .trim()
        .toLowerCase();
    _setMediaTransform(fit: current == 'cover' ? 'contain' : 'cover');
  }

  String _scopeLabel(StoryComposerScope scope) {
    if ((scope.label ?? '').trim().isNotEmpty) return scope.label!.trim();
    switch (scope.scope) {
      case StoryAudienceScope.global:
        return 'الجمهور: جميع المستخدمين';
      case StoryAudienceScope.closeFriends:
        return 'الأصدقاء المقرّبون';
      case StoryAudienceScope.followers:
        return 'المتابعون';
      case StoryAudienceScope.friends:
        return 'الأصدقاء';
      case StoryAudienceScope.area:
        return 'المنطقة';
      case StoryAudienceScope.compound:
        return 'المجمّع';
      case StoryAudienceScope.block:
        return 'القطعة';
      case StoryAudienceScope.building:
        return 'البناية';
      case StoryAudienceScope.custom:
        return 'مخصص';
    }
  }

  SocialStoryLayer? _selectedLayer(SocialStoryDraft draft, String? layerId) {
    if (layerId == null || layerId == kStoryBaseMediaTransformLayerId) {
      return null;
    }
    for (final layer in draft.layers) {
      if (layer.id == layerId) return layer;
    }
    return null;
  }

  String _publishCaption(SocialStoryDraft draft) {
    if (draft.caption.trim().isNotEmpty) return draft.caption.trim();
    for (final layer in draft.layers) {
      if (layer.id == kStoryBaseMediaTransformLayerId) continue;
      if (layer.type == SocialStoryLayerType.text &&
          (layer.text ?? '').trim().isNotEmpty) {
        return layer.text!.trim();
      }
    }
    return '';
  }

  Future<void> _publish() async {
    if (_publishing) return;
    if (_scopedPublishBlocked) {
      widget.onSaveDraft?.call(_captionController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'نشر القصص المخصصة للبناية غير متاح حالياً. تم حفظ المسودة.',
          ),
        ),
      );
      return;
    }

    final draft = ref.read(socialStoryDraftControllerProvider).draft;
    final caption = _publishCaption(draft);
    if (caption.isEmpty &&
        draft.buildLocalMediaFile() == null &&
        draft.attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف نصاً أو وسائط قبل نشر القصة.')),
      );
      return;
    }

    setState(() => _publishing = true);
    final ok =
        await (widget.onPublish?.call(caption, _scope) ?? Future.value(true));
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop(true);
      return;
    }

    final err = ref.read(socialControllerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (err ?? '').trim().isNotEmpty
              ? err!.trim()
              : 'تعذّر نشر القصة. تحقّق من الاتصال وحاول مرة أخرى.',
        ),
      ),
    );
    setState(() => _publishing = false);
  }

  Future<void> _replaceMedia() async {
    final picker = SocialMediaPickerV3();
    final type = await pickStoryMediaType(context);
    if (type == null || !mounted) return;
    final picked = type == PickedMediaType.video
        ? await picker.pickStoryVideo()
        : await picker.pickStoryImage();
    if (picked == null || !mounted) return;

    final notifier = ref.read(socialStoryDraftControllerProvider.notifier);
    final current = ref.read(socialStoryDraftControllerProvider).draft;
    final layers = current.layers
        .where((layer) => layer.id != kStoryBaseMediaTransformLayerId)
        .toList(growable: true)
      ..add(_defaultMediaTransformLayer());
    notifier.replaceDraft(
      current.copyWith(
        mode: SocialStoryComposerMode.media,
        mediaPath: picked.path,
        mediaName: picked.name,
        mediaMimeType: picked.mimeType,
        clearAttachment: true,
        layers: layers,
      ),
    );
  }

  Future<void> _openOriginalReel() async {
    final reel = widget.source.sharedReel;
    if (reel == null || reel.reelId <= 0) return;
    await openSocialReelsV3(context, reelId: reel.reelId);
  }

  Widget? _buildBaseMedia(SocialStoryDraft draft) {
    final source = widget.source;
    if (source.kind == StorySourceKind.sharedReel && source.sharedReel != null) {
      return GestureDetector(
        onTap: _openOriginalReel,
        child: _SharedReelPreview(reel: source.sharedReel!),
      );
    }

    final media = draft.buildLocalMediaFile();
    if (media != null) {
      final transform =
          _mediaTransformLayer(draft) ?? _defaultMediaTransformLayer();
      return _EditableBaseMedia(
        media: media,
        transform: transform,
        onChanged: (next) => _setMediaTransform(
          x: next.x,
          y: next.y,
          scale: next.scale,
          rotation: next.rotation,
          fit: next.fit,
        ),
      );
    }

    if (draft.mode == SocialStoryComposerMode.text &&
        draft.caption.trim().isNotEmpty &&
        draft.layers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            draft.caption.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
            ),
          ),
        ),
      );
    }
    return null;
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
        return SocialStoryComposerToolView.media;
      case SocialStoryComposerTool.none:
        return SocialStoryComposerToolView.none;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialStoryDraftControllerProvider);
    final draft = state.draft;
    final notifier = ref.read(socialStoryDraftControllerProvider.notifier);
    final selectedLayer = _selectedLayer(draft, state.selectedLayerId);
    final mediaTransform = _mediaTransformLayer(draft);
    final fit = (mediaTransform?.text ?? 'contain').trim().toLowerCase();
    final hasEditableMedia = draft.buildLocalMediaFile() != null;
    final padding = MediaQuery.of(context).padding;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final showToolPanel = state.activeTool != SocialStoryComposerTool.none;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Center(
              child: SocialStoryCanvas(
                draft: draft,
                selectedLayerId: state.selectedLayerId,
                drawEnabled: state.activeTool == SocialStoryComposerTool.draw,
                active: true,
                borderRadius: BorderRadius.zero,
                baseMedia: _buildBaseMedia(draft),
                onSelectLayer: notifier.selectLayer,
                onLayerChanged: (layer) => notifier.updateLayer(layer.id, layer),
                onDrawStroke: notifier.addDrawStroke,
                onLayerTap: (layer) {
                  if (layer.id == kStoryBaseMediaTransformLayerId) return;
                  notifier.selectLayer(layer.id);
                },
                onAttachmentTap: widget.source.sharedReel != null
                    ? _openOriginalReel
                    : null,
              ),
            ),
          ),
          Positioned(
            top: padding.top + 8,
            left: 10,
            right: 10,
            child: Row(
              children: [
                _CircleButton(
                  icon: Icons.close_rounded,
                  tooltip: 'إغلاق',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                if (hasEditableMedia) ...[
                  _CircleButton(
                    icon: fit == 'cover'
                        ? Icons.fit_screen_rounded
                        : Icons.fullscreen_rounded,
                    tooltip: fit == 'cover'
                        ? 'إظهار الوسيط كاملاً'
                        : 'ملء الشاشة',
                    onTap: () => _toggleFit(draft),
                  ),
                  _CircleButton(
                    icon: Icons.rotate_90_degrees_cw_rounded,
                    tooltip: 'تدوير',
                    onTap: () => _setMediaTransform(
                      rotation: (mediaTransform?.rotation ?? 0) + math.pi / 2,
                    ),
                  ),
                  _CircleButton(
                    icon: Icons.restart_alt_rounded,
                    tooltip: 'إعادة الضبط',
                    onTap: () => _setMediaTransform(reset: true),
                  ),
                ],
                _CircleButton(
                  icon: Icons.text_fields_rounded,
                  tooltip: 'نص',
                  onTap: () {
                    if (selectedLayer?.type != SocialStoryLayerType.text) {
                      notifier.addTextLayer(text: _captionController.text);
                    }
                    notifier.setTool(SocialStoryComposerTool.text);
                  },
                ),
                _CircleButton(
                  icon: Icons.alternate_email_rounded,
                  tooltip: 'منشن',
                  onTap: () => notifier.setTool(SocialStoryComposerTool.mention),
                ),
                _CircleButton(
                  icon: Icons.emoji_emotions_outlined,
                  tooltip: 'ملصقات',
                  onTap: () => notifier.setTool(SocialStoryComposerTool.stickers),
                ),
                _CircleButton(
                  icon: Icons.brush_rounded,
                  tooltip: 'رسم',
                  onTap: () => notifier.setTool(SocialStoryComposerTool.draw),
                ),
                if (widget.source.kind != StorySourceKind.sharedReel)
                  _CircleButton(
                    icon: Icons.photo_library_outlined,
                    tooltip: 'استبدال الوسيط',
                    onTap: _replaceMedia,
                  ),
              ],
            ),
          ),
          if (hasEditableMedia)
            Positioned(
              top: padding.top + 62,
              left: 0,
              right: 0,
              child: const IgnorePointer(
                child: Center(
                  child: _HintPill(
                    text: 'اسحب للتعديل • قرّب بإصبعين • دوّر بإصبعين',
                  ),
                ),
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
                    tool: _toolViewFor(state.activeTool),
                    selectedLayer: selectedLayer,
                    onTextChanged: (value) {
                      notifier.setCaption(value);
                      notifier.updateSelectedTextLayer(text: value);
                    },
                    onTextColorChanged: (value) =>
                        notifier.updateSelectedTextLayer(color: value),
                    onTextBackgroundChanged: (value) =>
                        notifier.updateSelectedTextLayer(backgroundColor: value),
                    onFontScaleChanged: (value) =>
                        notifier.updateSelectedTextLayer(fontScale: value),
                    onStickerSelected: notifier.addStickerLayer,
                    onMentionSelected: (userId, label) =>
                        notifier.addMentionLayer(
                      userId: userId,
                      displayLabel: label,
                    ),
                    onReplaceMedia: _replaceMedia,
                    onClearSelection: () =>
                        notifier.setTool(SocialStoryComposerTool.none),
                  ),
                  const SizedBox(height: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0D1B2A),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x66E7B24B)),
                  ),
                  child: TextField(
                    controller: _captionController,
                    onChanged: notifier.setCaption,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'أضف وصفاً',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _HintPill(text: _scopeLabel(_scope)),
                    const Spacer(),
                    TextButton(
                      onPressed: _publishing
                          ? null
                          : () async {
                              await notifier.saveDraft();
                              if (!context.mounted) return;
                              widget.onSaveDraft?.call(
                                _captionController.text.trim(),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم حفظ المسودة')),
                              );
                            },
                      child: const Text('مسودة'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _publishing ? null : _publish,
                      icon: _publishing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(_publishing ? 'جارٍ النشر…' : 'نشر'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTransformValue {
  const _MediaTransformValue({
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.fit,
  });

  final double x;
  final double y;
  final double scale;
  final double rotation;
  final String fit;
}

class _EditableBaseMedia extends StatefulWidget {
  const _EditableBaseMedia({
    required this.media,
    required this.transform,
    required this.onChanged,
  });

  final LocalMediaFile media;
  final SocialStoryLayer transform;
  final ValueChanged<_MediaTransformValue> onChanged;

  @override
  State<_EditableBaseMedia> createState() => _EditableBaseMediaState();
}

class _EditableBaseMediaState extends State<_EditableBaseMedia> {
  late double _x;
  late double _y;
  late double _scale;
  late double _rotation;
  double _gestureScale = 1;
  double _gestureRotation = 0;
  Offset _gestureFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _EditableBaseMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transform != widget.transform) _sync();
  }

  void _sync() {
    _x = widget.transform.x;
    _y = widget.transform.y;
    _scale = widget.transform.scale;
    _rotation = _normalizeStoryRotation(widget.transform.rotation);
  }

  void _emit() {
    widget.onChanged(
      _MediaTransformValue(
        x: _x,
        y: _y,
        scale: _scale,
        rotation: _normalizeStoryRotation(_rotation),
        fit: (widget.transform.text ?? 'contain').trim().toLowerCase() == 'cover'
            ? 'cover'
            : 'contain',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fit = (widget.transform.text ?? 'contain').trim().toLowerCase() == 'cover'
        ? 'cover'
        : 'contain';
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onScaleStart: (details) {
            _gestureScale = _scale;
            _gestureRotation = _rotation;
            _gestureFocal = details.focalPoint;
          },
          onScaleUpdate: (details) {
            final delta = details.focalPoint - _gestureFocal;
            _gestureFocal = details.focalPoint;
            setState(() {
              _scale = (_gestureScale * details.scale).clamp(0.5, 4.0).toDouble();
              _rotation = _normalizeStoryRotation(
                _gestureRotation + details.rotation,
              );
              if (width > 0) {
                _x = (_x + delta.dx / width).clamp(-0.25, 1.25).toDouble();
              }
              if (height > 0) {
                _y = (_y + delta.dy / height).clamp(-0.25, 1.25).toDouble();
              }
            });
          },
          onScaleEnd: (_) => _emit(),
          child: ClipRect(
            child: Transform.translate(
              offset: Offset((_x - 0.5) * width, (_y - 0.5) * height),
              child: Transform.rotate(
                angle: _rotation,
                child: Transform.scale(
                  scale: _scale,
                  child: _MediaContent(media: widget.media, fit: fit),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MediaContent extends StatelessWidget {
  const _MediaContent({required this.media, required this.fit});

  final LocalMediaFile media;
  final String fit;

  @override
  Widget build(BuildContext context) {
    final boxFit = fit == 'cover' ? BoxFit.cover : BoxFit.contain;
    if (media.isVideo) {
      return _LocalVideoPreview(media: media, fit: boxFit);
    }
    final path = (media.path ?? '').trim();
    if (path.isEmpty) return const SizedBox.shrink();
    return SizedBox.expand(
      child: Image.file(
        File(path),
        fit: boxFit,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

class _LocalVideoPreview extends StatefulWidget {
  const _LocalVideoPreview({required this.media, required this.fit});

  final LocalMediaFile media;
  final BoxFit fit;

  @override
  State<_LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

class _LocalVideoPreviewState extends State<_LocalVideoPreview> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final path = (widget.media.path ?? '').trim();
      if (path.isEmpty) return;
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Color(0xFF0D1B2A),
        child: Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
      );
    }
    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) return const SizedBox.shrink();
    return SizedBox.expand(
      child: ClipRect(
        child: FittedBox(
          fit: widget.fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}

class _SharedReelPreview extends StatelessWidget {
  const _SharedReelPreview({required this.reel});

  final SharedReelSource reel;

  @override
  Widget build(BuildContext context) {
    final presentation = reel.toPresentation();
    final poster = (presentation.posterImageUrl ?? '').trim();
    final naturalAspect =
        presentation.aspectRatio ?? (reel.isVertical ? 9 / 16 : 16 / 9);

    Widget foreground() {
      if (poster.isEmpty) {
        return const ColoredBox(
          color: Color(0xFF0D1B2A),
          child: Center(
            child: Icon(
              Icons.play_circle_outline_rounded,
              color: Colors.white54,
              size: 72,
            ),
          ),
        );
      }
      return SocialSafeImage(
        imageUrl: poster,
        fit: reel.isVertical ? BoxFit.cover : BoxFit.contain,
        showVideoGlyph: true,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!reel.isVertical && poster.isNotEmpty) ...[
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: SocialSafeImage(
              imageUrl: poster,
              fit: BoxFit.cover,
              showVideoGlyph: true,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
          Center(
            child: AspectRatio(
              aspectRatio: naturalAspect,
              child: foreground(),
            ),
          ),
        ] else
          foreground(),
        Positioned(
          left: 16,
          right: 16,
          bottom: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (reel.authorName ?? reel.authorHandle ?? 'الريل الأصلي')
                          .trim(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.open_in_new_rounded,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!reel.available)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0x88000000),
              child: const Center(
                child: Text(
                  'الريل الأصلي غير متاح',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
