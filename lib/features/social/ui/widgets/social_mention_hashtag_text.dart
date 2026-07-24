import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../social_content_navigation.dart';
import '../social_hashtag_screen.dart';

class SocialMentionHashtagText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final void Function(String tag)? onOpenHashtag;
  final void Function(int userId, String displayName)? onOpenMention;

  const SocialMentionHashtagText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.onOpenHashtag,
    this.onOpenMention,
  });

  @override
  State<SocialMentionHashtagText> createState() =>
      _SocialMentionHashtagTextState();
}

class _SocialMentionHashtagTextState extends State<SocialMentionHashtagText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final baseStyle = widget.style ?? Theme.of(context).textTheme.bodyMedium;
    final accentStyle = baseStyle?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w800,
    );
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'@\[(.+?)\]\((\d+)\)|#([\p{L}\p{N}_]{2,64})',
      unicode: true,
    );
    var start = 0;
    for (final match in pattern.allMatches(widget.text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: widget.text.substring(start, match.start)));
      }
      final mentionName = match.group(1);
      final mentionUserId = int.tryParse(match.group(2) ?? '');
      final hashtag = match.group(3);
      if (mentionName != null && mentionUserId != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            if (widget.onOpenMention != null) {
              widget.onOpenMention!(mentionUserId, mentionName);
              return;
            }
            openSocialProfileGuarded(
              context,
              userId: mentionUserId,
              initialName: mentionName,
            );
          };
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: '@$mentionName',
            style: accentStyle,
            recognizer: recognizer,
          ),
        );
      } else if (hashtag != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            if (widget.onOpenHashtag != null) {
              widget.onOpenHashtag!(hashtag);
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SocialHashtagScreen(tag: hashtag),
              ),
            );
          };
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: '#$hashtag',
            style: accentStyle,
            recognizer: recognizer,
          ),
        );
      }
      start = match.end;
    }
    if (start < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(start)));
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textDirection: Directionality.of(context),
    );
  }
}
