import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/i18n/locale_text.dart';
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
            value: (widget.selectedLayer?.fontScale ?? 1.0).clamp(0.5, 3.0),
            min: 0.5,
            max: 3.0,
            onChanged: widget.onFontScaleChanged,
          ),
        ],
      ),
    );
  }
}

/// Maslaki sticker categories. Emoji + a few Arabic word stickers — all persist
/// as text stickers, so anything the user can type on their keyboard (including
/// the keyboard's own emoji/sticker panel) can be added too.
class _StickerCategory {
  final String key;
  final String emoji;
  final List<String> stickers;
  const _StickerCategory(this.key, this.emoji, this.stickers);
}

const List<_StickerCategory> _kStickerCategories = <_StickerCategory>[
  _StickerCategory('smileys', '😀', <String>[
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '🙂',
    '😉', '😍', '🥰', '😘', '😗', '😎', '🤩', '🥳', '😋', '😛',
    '😜', '🤪', '🤗', '🤔', '🤭', '🙃', '😏', '😴', '🤤', '😇',
    '🥺', '😢', '😭', '😤', '😡', '🤯', '😱', '🥹', '😬', '🙄',
  ]),
  _StickerCategory('love', '❤️', <String>[
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💖',
    '💗', '💓', '💕', '💞', '💘', '💝', '💟', '❣️', '💔', '♥️',
    '😍', '🥰', '😘', '💋', '💌',
  ]),
  _StickerCategory('hands', '👍', <String>[
    '👍', '👎', '👏', '🙌', '🙏', '👌', '✌️', '🤞', '🤟', '🤙',
    '💪', '👋', '🤝', '✊', '👊', '🫶', '🤲', '☝️', '👇', '👆',
  ]),
  _StickerCategory('animals', '🐶', <String>[
    '🐶', '🐱', '🦊', '🦁', '🐯', '🐰', '🐻', '🐼', '🐨', '🐵',
    '🦄', '🐝', '🦋', '🐢', '🐬', '🦅', '🐎', '🐪', '🦌', '🕊️',
  ]),
  _StickerCategory('food', '☕', <String>[
    '☕', '🍵', '🧃', '🥤', '🍰', '🍩', '🍪', '🍫', '🍓', '🍉',
    '🍇', '🍊', '🍕', '🍔', '🍟', '🌮', '🍦', '🍧', '🥙', '🧆',
  ]),
  _StickerCategory('places', '📍', <String>[
    '📍', '🏠', '🏡', '🕌', '🌆', '🌃', '🏙️', '🚗', '🚕', '✈️',
    '🛵', '⛽', '🛣️', '🌅', '🌙', '⭐', '🇮🇶',
  ]),
  _StickerCategory('fun', '🎉', <String>[
    '🎉', '🎊', '🎁', '🎈', '🔥', '✨', '⭐', '🌟', '💫', '💯',
    '📸', '🎬', '🎵', '🎶', '⚽', '🏀', '🎮', '🏆', '👑', '💎',
  ]),
  _StickerCategory('symbols', '✅', <String>[
    '✅', '❌', '❓', '❗', '💬', '💡', '🔔', '📌', '🆕', '🔝',
    '♻️', '➡️', '⬅️', '⬆️', '⬇️', '🔴', '🟢', '🟡', '🔵', '⚡',
  ]),
  _StickerCategory('words', '✍️', <String>[
    'بسماية', 'مسلكي', 'يلا', 'تم ✅', 'وصل الطلب', 'في الطريق',
    'صباح الخير', 'مساء الخير', 'مبروك', 'شكراً',
  ]),
];

class _StickerToolPanel extends StatefulWidget {
  const _StickerToolPanel({this.onStickerSelected});

  final ValueChanged<String>? onStickerSelected;

  @override
  State<_StickerToolPanel> createState() => _StickerToolPanelState();
}

class _StickerToolPanelState extends State<_StickerToolPanel> {
  final TextEditingController _customController = TextEditingController();
  int _category = 0;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _addCustom() {
    final value = _customController.text.trim();
    if (value.isEmpty) return;
    widget.onStickerSelected?.call(value);
    _customController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final stickers = _kStickerCategories[_category].stickers;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keyboard input: add any emoji/sticker/word straight from the
          // device keyboard (incl. its emoji panel). Persists as a text sticker.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.lt(
                      ar: 'اكتب أو الصق ستيكر/إيموجي…',
                      en: 'Type or paste a sticker/emoji…',
                    ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _addCustom(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _addCustom,
                icon: const Icon(Icons.add_rounded),
                tooltip: l10n.socialStoryComposerToolStickers,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Category selector.
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kStickerCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final selected = index == _category;
                return GestureDetector(
                  onTap: () => setState(() => _category = index),
                  child: Container(
                    width: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary.withValues(alpha: 0.18)
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? scheme.primary : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      _kStickerCategories[index].emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // Sticker grid for the active category.
          SizedBox(
            height: 188,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 60,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: stickers.length,
              itemBuilder: (context, index) {
                final sticker = stickers[index];
                final isWord = sticker.runes.length > 3;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => widget.onStickerSelected?.call(sticker),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          sticker,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: isWord ? 11 : 26),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
