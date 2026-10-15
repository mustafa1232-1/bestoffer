import 'package:flutter/material.dart';

import '../../../../core/i18n/locale_text.dart';
import 'social_mention_hashtag_text.dart';
import 'social_design_theme.dart';

class SocialPostCaption extends StatefulWidget {
  const SocialPostCaption({
    super.key,
    required this.username,
    required this.caption,
  });

  final String username;
  final String caption;

  @override
  State<SocialPostCaption> createState() => _SocialPostCaptionState();
}

class _SocialPostCaptionState extends State<SocialPostCaption> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant SocialPostCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caption != widget.caption) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(height: 1.5, color: SocialDesignTheme.ink);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.caption, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 3,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.username,
              style: style.copyWith(fontWeight: FontWeight.bold),
            ),
            SocialMentionHashtagText(
              text: widget.caption,
              style: style,
              maxLines: _expanded ? null : 3,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (overflows)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? context.lt(ar: 'عرض أقل', en: 'Show less')
                      : context.lt(ar: 'المزيد', en: 'More'),
                ),
              ),
          ],
        );
      },
    );
  }
}
