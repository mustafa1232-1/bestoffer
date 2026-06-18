import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/media_picker_service.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/maslaki_back_button.dart';
import '../models/social_story_document.dart';
import '../state/social_story_draft_controller.dart';
import 'social_story_publish_screen.dart';
import 'widgets/social_story_canvas.dart';
import 'widgets/social_story_tool_panels.dart';

class SocialStoryComposerScreen extends ConsumerStatefulWidget {
  final SocialStoryComposerMode initialMode;
  final SocialStoryDraft? initialDraft;

  const SocialStoryComposerScreen({
    super.key,
    this.initialMode = SocialStoryComposerMode.text,
    this.initialDraft,
  });

  @override
  ConsumerState<SocialStoryComposerScreen> createState() =>
      _SocialStoryComposerScreenState();
}

class _SocialStoryComposerScreenState
    extends ConsumerState<SocialStoryComposerScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      final notifier = ref.read(socialStoryDraftControllerProvider.notifier);
      if (widget.initialDraft != null) {
        notifier.replaceDraft(widget.initialDraft!);
      } else {
        final draft = SocialStoryDraft.initialText().copyWith(
          mode: widget.initialMode,
        );
        notifier.replaceDraft(draft);
        if (widget.initialMode == SocialStoryComposerMode.text) {
          notifier.addTextLayer();
        }
      }
      if (widget.initialMode == SocialStoryComposerMode.media) {
        if (!mounted) return;
        await _pickMediaIfNeeded();
      }
    });
  }

  Future<void> _pickMediaIfNeeded() async {
    final notifier = ref.read(socialStoryDraftControllerProvider.notifier);
    final draft = ref.read(socialStoryDraftControllerProvider).draft;
    if ((draft.mediaPath ?? '').trim().isNotEmpty) return;
    final file = await pickGalleryMediaFromDevice();
    if (file == null || !mounted) return;
    notifier.setMedia(
      path: file.path,
      name: file.name,
      mimeType: file.mimeType,
    );
    notifier.setMode(SocialStoryComposerMode.media);
  }

  Future<void> _preview() async {
    final state = ref.read(socialStoryDraftControllerProvider);
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: SocialStoryCanvas(draft: state.draft),
      ),
    );
  }

  Future<void> _saveDraft() async {
    await ref.read(socialStoryDraftControllerProvider.notifier).saveDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.socialStoryComposerDraftSaved)),
    );
  }

  Future<void> _next() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SocialStoryPublishScreen(),
      ),
    );
    if (posted == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(socialStoryDraftControllerProvider);
    final draft = state.draft;
    final selectedLayer = state.selectedLayerId == null
        ? null
        : draft.layers
              .where((layer) => layer.id == state.selectedLayerId)
              .cast<SocialStoryLayer?>()
              .firstOrNull;
    final tool = switch (state.activeTool) {
      SocialStoryComposerTool.none => SocialStoryComposerToolView.none,
      SocialStoryComposerTool.text => SocialStoryComposerToolView.text,
      SocialStoryComposerTool.mention => SocialStoryComposerToolView.mention,
      SocialStoryComposerTool.stickers => SocialStoryComposerToolView.stickers,
      SocialStoryComposerTool.draw => SocialStoryComposerToolView.draw,
      SocialStoryComposerTool.media => SocialStoryComposerToolView.media,
    };

    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        leading: const MaslakiBackButton(
          fallbackTabIndex: 2,
          icon: Icons.close_rounded,
        ),
        title: Text(l10n.socialStoryComposerTitle),
        actions: [
          TextButton(onPressed: _saveDraft, child: Text(l10n.commonSave)),
          IconButton(
            onPressed: _preview,
            icon: const Icon(Icons.visibility_outlined),
          ),
          IconButton(
            onPressed: _next,
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SocialStoryCanvas(
                    draft: draft,
                    selectedLayerId: state.selectedLayerId,
                    drawEnabled:
                        state.activeTool == SocialStoryComposerTool.draw,
                    onSelectLayer: ref
                        .read(socialStoryDraftControllerProvider.notifier)
                        .selectLayer,
                    onLayerChanged: (layer) => ref
                        .read(socialStoryDraftControllerProvider.notifier)
                        .updateLayer(layer.id, layer),
                    onDrawStroke: ref
                        .read(socialStoryDraftControllerProvider.notifier)
                        .addDrawStroke,
                    onLayerTap: (layer) {
                      ref
                          .read(socialStoryDraftControllerProvider.notifier)
                          .selectLayer(layer.id);
                    },
                  ),
                ),
              ),
            ),
            _ComposerToolbar(
              onText: () {
                final notifier = ref.read(
                  socialStoryDraftControllerProvider.notifier,
                );
                if (selectedLayer == null ||
                    selectedLayer.type != SocialStoryLayerType.text) {
                  notifier.addTextLayer();
                }
                notifier.setTool(SocialStoryComposerTool.text);
              },
              onMention: () => ref
                  .read(socialStoryDraftControllerProvider.notifier)
                  .setTool(SocialStoryComposerTool.mention),
              onSticker: () => ref
                  .read(socialStoryDraftControllerProvider.notifier)
                  .setTool(SocialStoryComposerTool.stickers),
              onDraw: () => ref
                  .read(socialStoryDraftControllerProvider.notifier)
                  .setTool(SocialStoryComposerTool.draw),
              onMedia: () async {
                ref
                    .read(socialStoryDraftControllerProvider.notifier)
                    .setTool(SocialStoryComposerTool.media);
                await _pickMediaIfNeeded();
              },
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: tool == SocialStoryComposerToolView.none
                  ? const SizedBox(height: 12)
                  : SocialStoryToolPanels(
                      key: ValueKey(tool),
                      tool: tool,
                      selectedLayer: selectedLayer,
                      onTextChanged: (value) => ref
                          .read(socialStoryDraftControllerProvider.notifier)
                          .updateSelectedTextLayer(text: value),
                      onTextColorChanged: (value) => ref
                          .read(socialStoryDraftControllerProvider.notifier)
                          .updateSelectedTextLayer(color: value),
                      onTextBackgroundChanged: (value) => ref
                          .read(socialStoryDraftControllerProvider.notifier)
                          .updateSelectedTextLayer(
                            backgroundColor: value.trim().isEmpty
                                ? null
                                : value,
                          ),
                      onFontScaleChanged: (value) => ref
                          .read(socialStoryDraftControllerProvider.notifier)
                          .updateSelectedTextLayer(fontScale: value),
                      onMentionSelected: (userId, displayLabel) {
                        ref
                            .read(socialStoryDraftControllerProvider.notifier)
                            .addMentionLayer(
                              userId: userId,
                              displayLabel: displayLabel,
                            );
                        ref
                            .read(socialStoryDraftControllerProvider.notifier)
                            .setTool(SocialStoryComposerTool.none);
                      },
                      onStickerSelected: (value) => ref
                          .read(socialStoryDraftControllerProvider.notifier)
                          .addStickerLayer(value),
                      onReplaceMedia: _pickMediaIfNeeded,
                      onClearSelection: () => ref
                          .read(socialStoryDraftControllerProvider.notifier)
                          .setTool(SocialStoryComposerTool.none),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: selectedLayer == null
                      ? null
                      : ref
                            .read(socialStoryDraftControllerProvider.notifier)
                            .removeSelectedLayer,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(l10n.socialStoryComposerDeleteLayer),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerToolbar extends StatelessWidget {
  final VoidCallback onText;
  final VoidCallback onMention;
  final VoidCallback onSticker;
  final VoidCallback onDraw;
  final VoidCallback onMedia;

  const _ComposerToolbar({
    required this.onText,
    required this.onMention,
    required this.onSticker,
    required this.onDraw,
    required this.onMedia,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: _ToolButton(
              icon: Icons.text_fields_rounded,
              label: l10n.socialStoryComposerToolText,
              onTap: onText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ToolButton(
              icon: Icons.alternate_email_rounded,
              label: l10n.socialStoryComposerToolMention,
              onTap: onMention,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ToolButton(
              icon: Icons.emoji_emotions_outlined,
              label: l10n.socialStoryComposerToolStickers,
              onTap: onSticker,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ToolButton(
              icon: Icons.gesture_rounded,
              label: l10n.socialStoryComposerToolDraw,
              onTap: onDraw,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ToolButton(
              icon: Icons.photo_library_outlined,
              label: l10n.socialStoryComposerToolMedia,
              onTap: onMedia,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
