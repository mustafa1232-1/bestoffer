import 'package:flutter/material.dart';

import '../models/social_models.dart';

Future<void> showSocialStoryQuickViewer({
  required BuildContext context,
  required SocialStoryGroup group,
  int? initialStoryId,
  ValueChanged<int>? onStoryViewed,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SocialStoryQuickViewerSheet(
      group: group,
      initialStoryId: initialStoryId,
      onStoryViewed: onStoryViewed,
    ),
  );
}

class _SocialStoryQuickViewerSheet extends StatefulWidget {
  final SocialStoryGroup group;
  final int? initialStoryId;
  final ValueChanged<int>? onStoryViewed;

  const _SocialStoryQuickViewerSheet({
    required this.group,
    this.initialStoryId,
    this.onStoryViewed,
  });

  @override
  State<_SocialStoryQuickViewerSheet> createState() =>
      _SocialStoryQuickViewerSheetState();
}

class _SocialStoryQuickViewerSheetState
    extends State<_SocialStoryQuickViewerSheet> {
  late final PageController _controller;
  late int _index;

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
    final story = widget.group.stories[index];
    widget.onStoryViewed?.call(story.id);
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stories = widget.group.stories;
    if (stories.isEmpty) {
      return const SafeArea(
        child: SizedBox(
          height: 260,
          child: Center(child: Text('لا توجد ستوري')),
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
                  final w = MediaQuery.of(context).size.width;
                  if (details.localPosition.dx < w / 2) {
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
                    return _StoryCanvas(story: story);
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
                        ? NetworkImage(widget.group.author.imageUrl!)
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

  const _StoryCanvas({required this.story});

  @override
  Widget build(BuildContext context) {
    final isImage =
        (story.mediaKind == 'image') &&
        (story.mediaUrl ?? '').trim().isNotEmpty;
    if (isImage) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Image.network(
          story.mediaUrl!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              const _StoryTextFallback(message: 'تعذر تحميل الصورة'),
        ),
      );
    }

    return _StoryTextCard(story: story);
  }
}

class _StoryTextCard extends StatelessWidget {
  final SocialStory story;
  const _StoryTextCard({required this.story});

  @override
  Widget build(BuildContext context) {
    final style = story.style;
    final bg = _hexToColor(style.backgroundColor, const Color(0xFF14315E));
    final fg = _hexToColor(style.textColor, Colors.white);
    final text = story.caption.trim();

    return Container(
      color: bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(22),
      child: Text(
        text.isEmpty ? '—' : text,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          height: 1.35,
          fontSize: 18 * style.fontScale.clamp(0.8, 2.4),
        ),
      ),
    );
  }
}

class _StoryTextFallback extends StatelessWidget {
  final String message;
  const _StoryTextFallback({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF14243E),
      alignment: Alignment.center,
      child: Text(
        message,
        textDirection: TextDirection.rtl,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _hexToColor(String value, Color fallback) {
  final hex = value.replaceAll('#', '').trim();
  if (hex.length == 6) {
    final parsed = int.tryParse('FF$hex', radix: 16);
    if (parsed != null) return Color(parsed);
  }
  if (hex.length == 8) {
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) return Color(parsed);
  }
  return fallback;
}
