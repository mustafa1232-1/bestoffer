import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:social_core/local_media_file.dart';

import '../../social/models/social_story_document.dart';
import '../../social/state/social_story_draft_controller.dart';
import '../../social/ui/social_content_navigation.dart';
import '../../social/ui/widgets/social_story_canvas.dart';
import '../../social/ui/widgets/social_story_tool_panels.dart';
import '../media/social_safe_image.dart';
import '../pickers/social_media_picker_v3.dart';
import 'story_composer_source.dart';

/// Full-screen Story Composer.
///
/// This screen owns the live draft state, renders the selected media in the
/// 9:16 canvas, and exposes the real text / mention / sticker / draw tools.
/// The publish callback receives the live caption plus scope, while the draft
/// provider keeps the media attachment and layer state authoritative.
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
  final Future<bool> Function(String caption, StoryComposerScope scope)?
      onPublish;
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
  bool _seeded = false;

  StoryComposerScope get _scope => widget.scope;

  bool get isScopedPublishBlocked =>
      _scope.scope != StoryAudienceScope.global && !widget.audienceScopeSupported;

  @override
  void initState() {
    super.initState();
    final draft = widget.source.buildInitialDraft();
    _captionController = TextEditingController(text: draft.caption);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(socialStoryDraftControllerProvider.notifier).replaceDraft(draft);
    });
    _seeded = true;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  String _scopeLabel(StoryComposerScope scope) {
    if (scope.label != null && scope.label!.trim().isNotEmpty) {
      return scope.label!.trim();
    }
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
    if (layerId == null) return null;
    for (final layer in draft.layers) {
      if (layer.id == layerId) return layer;
    }
    return null;
  }

  String _publishCaption(SocialStoryDraft draft) {
    final explicit = draft.caption.trim();
    if (explicit.isNotEmpty) return explicit;
    for (final layer in draft.layers) {
      if (layer.type == SocialStoryLayerType.text &&
          (layer.text ?? '').trim().isNotEmpty) {
        return layer.text!.trim();
      }
    }
    return '';
  }

  Future<void> _publish() async {
    if (_publishing) return;
    if (isScopedPublishBlocked) {
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
    final publishCaption = _publishCaption(draft);
    final media = draft.buildLocalMediaFile();
    if (publishCaption.isEmpty && media == null && draft.attachment == null) {
      widget.onSaveDraft?.call(_captionController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أضف نصاً أو وسائط قبل نشر القصة.'),
        ),
      );
      return;
    }

    setState(() {
      _publishing = true;
    });

    final ok = await (widget.onPublish?.call(publishCaption, _scope) ??
        Future.value(true));
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop(true);
      return;
    }
    setState(() {
      _publishing = false;
    });
  }

  Future<void> _openOriginalReel() async {
    final reel = widget.source.sharedReel;
    if (reel == null || reel.reelId <= 0) return;
    await openSocialReelsV3(context, reelId: reel.reelId);
  }

  Future<void> _replaceMedia() async {
    final picker = SocialMediaPickerV3();
    final picked = await picker.pickStoryImageOrVideo();
    if (picked == null || !mounted) return;
    final notifier = ref.read(socialStoryDraftControllerProvider.notifier);
    final current = ref.read(socialStoryDraftControllerProvider).draft;
    notifier.replaceDraft(
      current.copyWith(
        mode: SocialStoryComposerMode.media,
        mediaPath: picked.path,
        mediaName: picked.name,
        mediaMimeType: picked.mimeType,
        clearAttachment: true,
      ),
    );
  }

  Widget? _buildBaseMedia(SocialStoryDraft draft) {
    final source = widget.source;
    if (source.kind == StorySourceKind.sharedReel &&
        source.sharedReel != null) {
      return _SharedReelPreview(
        reel: source.sharedReel!,
        onOpenOriginalReel: _openOriginalReel,
      );
    }

    final media = draft.buildLocalMediaFile();
    if (media == null) {
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

    if (media.isVideo) {
      return _LocalVideoPreview(media: media);
    }
    return Image.file(
      File(media.path!),
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
        return SocialStoryComposerToolView.media;
      case SocialStoryComposerTool.none:
        return SocialStoryComposerToolView.none;
    }
  }

  void _setTool(SocialStoryComposerTool tool) {
    ref.read(socialStoryDraftControllerProvider.notifier).setTool(tool);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialStoryDraftControllerProvider);
    final draft = state.draft;
    final selectedLayer = _selectedLayer(draft, state.selectedLayerId);
    final toolView = _toolViewFor(state.activeTool);
    final padding = MediaQuery.of(context).padding;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final notifier = ref.read(socialStoryDraftControllerProvider.notifier);
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
                  if (layer.type == SocialStoryLayerType.mention &&
                      (layer.mentionedUserId ?? 0) > 0) {
                    return;
                  }
                  notifier.selectLayer(layer.id);
                },
                onAttachmentTap: widget.source.sharedReel != null
                    ? _openOriginalReel
                    : null,
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
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _RoundButton(
                      icon: Icons.text_fields_rounded,
                      onTap: () {
                        if (state.selectedLayerId == null ||
                            selectedLayer?.type != SocialStoryLayerType.text) {
                          notifier.addTextLayer(text: _captionController.text);
                        }
                        _setTool(SocialStoryComposerTool.text);
                      },
                    ),
                    _RoundButton(
                      icon: Icons.alternate_email_rounded,
                      onTap: () => _setTool(SocialStoryComposerTool.mention),
                    ),
                    _RoundButton(
                      icon: Icons.emoji_emotions_outlined,
                      onTap: () => _setTool(SocialStoryComposerTool.stickers),
                    ),
                    _RoundButton(
                      icon: Icons.brush_rounded,
                      onTap: () => _setTool(SocialStoryComposerTool.draw),
                    ),
                    if (widget.source.kind != StorySourceKind.sharedReel)
                      _RoundButton(
                        icon: Icons.photo_library_outlined,
                        onTap: _replaceMedia,
                      ),
                    if (widget.source.kind == StorySourceKind.sharedReel)
                      _RoundButton(
                        icon: Icons.open_in_new_rounded,
                        onTap: _openOriginalReel,
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
                    onReplaceMedia: _replaceMedia,
                    onClearSelection: () => _setTool(SocialStoryComposerTool.none),
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
                    onChanged: (value) => notifier.setCaption(value),
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'أضف وصفاً',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ScopeChip(
                      label: _scopeLabel(_scope),
                      official: _scope.isOfficial,
                      locked: _scope.locked,
                      onTap: null,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        widget.onSaveDraft?.call(_captionController.text.trim());
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم حفظ المسودة')),
                        );
                      },
                      child: const Text(
                        'مسودة',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PublishButton(onTap: _publishing ? null : _publish),
                  ],
                ),
              ],
            ),
          ),
          if ((_seeded && _captionController.text.trim().isNotEmpty &&
                  draft.layers.isEmpty &&
                  draft.mode == SocialStoryComposerMode.text) ||
              (_captionController.text.trim().isNotEmpty &&
                  draft.layers.isEmpty &&
                  draft.mode == SocialStoryComposerMode.media))
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _captionController.text.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LocalVideoPreview extends StatefulWidget {
  const _LocalVideoPreview({required this.media});

  final LocalMediaFile media;

  @override
  State<_LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

class _LocalVideoPreviewState extends State<_LocalVideoPreview> {
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
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _SharedReelPreview extends StatelessWidget {
  const _SharedReelPreview({
    required this.reel,
    required this.onOpenOriginalReel,
  });

  final SharedReelSource reel;
  final VoidCallback onOpenOriginalReel;

  @override
  Widget build(BuildContext context) {
    final presentation = reel.toPresentation();
    final topLeft = reel.authorName?.trim().isNotEmpty == true
        ? reel.authorName!.trim()
        : (reel.authorHandle?.trim().isNotEmpty == true
            ? reel.authorHandle!.trim()
            : 'Original reel');

    final media = presentation.isVertical
        ? SocialSafeImage(
            imageUrl: presentation.posterImageUrl,
            fit: BoxFit.cover,
            showVideoGlyph: true,
          )
        : Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: SocialSafeImage(
                  imageUrl: presentation.posterImageUrl,
                  fit: BoxFit.cover,
                  showVideoGlyph: true,
                ),
              ),
              Center(
                child: AspectRatio(
                  aspectRatio: presentation.aspectRatio ?? (16 / 9),
                  child: SocialSafeImage(
                    imageUrl: presentation.posterImageUrl,
                    fit: BoxFit.contain,
                    showVideoGlyph: true,
                  ),
                ),
              ),
            ],
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        media,
        Positioned(
          top: 18,
          left: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE7B24B)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.white12,
                  backgroundImage: (reel.authorAvatarUrl ?? '').trim().isEmpty
                      ? null
                      : NetworkImage(reel.authorAvatarUrl!),
                  child: (reel.authorAvatarUrl ?? '').trim().isEmpty
                      ? const Icon(Icons.person, color: Colors.white, size: 14)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  topLeft,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 18,
          child: ElevatedButton.icon(
            onPressed: onOpenOriginalReel,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('فتح الريل الأصلي'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE7B24B),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        if (!reel.available)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.36),
              alignment: Alignment.center,
              child: const Text(
                'الريل الأصلي غير متاح',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color(0x55000000),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.official,
    required this.locked,
    this.onTap,
  });

  final String label;
  final bool official;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: official ? const Color(0xFFE7B24B) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              official
                  ? Icons.verified_rounded
                  : (locked ? Icons.lock_outline : Icons.public),
              color: official ? const Color(0xFFE7B24B) : Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishButton extends StatelessWidget {
  const _PublishButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFE7B24B),
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      child: const Text(
        'نشر',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
