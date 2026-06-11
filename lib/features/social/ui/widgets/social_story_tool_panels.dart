import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../models/social_story_document.dart';
import 'social_story_layer_widget.dart';
import 'social_story_mention_panel.dart';

class SocialStoryToolPanels extends StatelessWidget {
  const SocialStoryToolPanels({
    super.key,
    required this.tool,
    required this.selectedLayer,
    this.onTextChanged,
    this.onTextColorChanged,
    this.onTextBackgroundChanged,
    this.onFontScaleChanged,
    this.onStickerSelected,
    this.onMentionSelected,
    this.onReplaceMedia,
    this.onClearSelection,
  });

  final SocialStoryComposerToolView tool;
  final SocialStoryLayer? selectedLayer;
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<String>? onTextColorChanged;
  final ValueChanged<String>? onTextBackgroundChanged;
  final ValueChanged<double>? onFontScaleChanged;
  final ValueChanged<String>? onStickerSelected;
  final void Function(int userId, String displayLabel)? onMentionSelected;
  final VoidCallback? onReplaceMedia;
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    switch (tool) {
      case SocialStoryComposerToolView.text:
        return _TextToolPanel(
          selectedLayer: selectedLayer,
          onTextChanged: onTextChanged,
          onTextColorChanged: onTextColorChanged,
          onTextBackgroundChanged: onTextBackgroundChanged,
          onFontScaleChanged: onFontScaleChanged,
        );
      case SocialStoryComposerToolView.mention:
        return SocialStoryMentionPanel(onMentionSelected: onMentionSelected);
      case SocialStoryComposerToolView.stickers:
        return _StickerToolPanel(onStickerSelected: onStickerSelected);
      case SocialStoryComposerToolView.draw:
        return _InfoPanel(
          title: l10n.socialStoryToolDrawTitle,
          subtitle: l10n.socialStoryToolDrawBody,
          actionLabel: l10n.commonDone,
          onAction: onClearSelection,
        );
      case SocialStoryComposerToolView.media:
        return _InfoPanel(
          title: l10n.socialStoryToolReplaceMediaTitle,
          subtitle: l10n.socialStoryToolReplaceMediaBody,
          actionLabel: l10n.socialStoryToolChooseFile,
          onAction: onReplaceMedia,
        );
      case SocialStoryComposerToolView.none:
        return const SizedBox.shrink();
    }
  }
}

enum SocialStoryComposerToolView { none, text, mention, stickers, draw, media }

class _TextToolPanel extends StatefulWidget {
  const _TextToolPanel({
    required this.selectedLayer,
    this.onTextChanged,
    this.onTextColorChanged,
    this.onTextBackgroundChanged,
    this.onFontScaleChanged,
  });

  final SocialStoryLayer? selectedLayer;
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<String>? onTextColorChanged;
  final ValueChanged<String>? onTextBackgroundChanged;
  final ValueChanged<double>? onFontScaleChanged;

  @override
  State<_TextToolPanel> createState() => _TextToolPanelState();
}

class _TextToolPanelState extends State<_TextToolPanel> {
  late final TextEditingController _controller;
  static const _palette = <String>[
    '#FFFFFF',
    '#F8FAFC',
    '#FDE68A',
    '#FCA5A5',
    '#93C5FD',
    '#34D399',
    '#111827',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.selectedLayer?.text ?? '');
  }

  @override
  void didUpdateWidget(covariant _TextToolPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.selectedLayer?.text ?? '';
    if (_controller.text != next) {
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            maxLines: 3,
            minLines: 1,
            onChanged: widget.onTextChanged,
            decoration: InputDecoration(
              hintText: l10n.socialStoryToolWriteTextHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.socialStoryToolTextColor,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _palette
                .map(
                  (color) => _ColorDot(
                    color: colorFromHex(color),
                    onTap: () => widget.onTextColorChanged?.call(color),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.socialStoryToolTextBackground,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ColorDot(
                color: Colors.transparent,
                outlined: true,
                onTap: () => widget.onTextBackgroundChanged?.call(''),
              ),
              ..._palette
                  .take(6)
                  .map(
                    (color) => _ColorDot(
                      color: colorFromHex(color).withValues(alpha: 0.3),
                      onTap: () => widget.onTextBackgroundChanged?.call(color),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.socialStoryToolSize,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Slider(
            value: (widget.selectedLayer?.fontScale ?? 1.0).clamp(0.8, 2.0),
            min: 0.8,
            max: 2.0,
            onChanged: widget.onFontScaleChanged,
          ),
        ],
      ),
    );
  }
}

class _StickerToolPanel extends StatelessWidget {
  const _StickerToolPanel({this.onStickerSelected});

  final ValueChanged<String>? onStickerSelected;

  @override
  Widget build(BuildContext context) {
    const stickers = [
      '🔥',
      '✨',
      '📍',
      '❤️',
      '👏',
      '☕',
      '🎉',
      'بسماية',
      '🏠',
      '💬',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: stickers
            .map(
              (sticker) => InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onStickerSelected?.call(sticker),
                child: Ink(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(sticker, style: const TextStyle(fontSize: 28)),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, this.onTap, this.outlined = false});

  final Color color;
  final VoidCallback? onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          shape: BoxShape.circle,
          border: Border.all(
            color: outlined
                ? Theme.of(context).colorScheme.outline
                : Colors.white,
          ),
        ),
      ),
    );
  }
}
