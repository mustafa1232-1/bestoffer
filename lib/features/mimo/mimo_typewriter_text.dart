import 'package:flutter/material.dart';

/// Text that types itself in letter by letter (Mimo talking). Reserves its
/// final size up front so the surrounding bubble never jitters.
class MimoTypewriterText extends StatefulWidget {
  const MimoTypewriterText({
    super.key,
    required this.text,
    required this.style,
    required this.animate,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final TextStyle style;
  final bool animate;
  final TextAlign textAlign;

  @override
  State<MimoTypewriterText> createState() => _MimoTypewriterTextState();
}

class _MimoTypewriterTextState extends State<MimoTypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 40 * widget.text.characters.length + 60),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters;
    return Semantics(
      liveRegion: true,
      label: widget.text,
      child: ExcludeSemantics(
        child: Stack(
          children: [
            Opacity(
              opacity: 0,
              child: Text(
                widget.text,
                style: widget.style,
                textAlign: widget.textAlign,
              ),
            ),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final count = (chars.length * _ctrl.value).ceil();
                final shown = chars.take(count).toString();
                final cursor = _ctrl.value < 1 ? '▍' : '';
                return Text.rich(
                  TextSpan(
                    text: shown,
                    children: [
                      TextSpan(
                        text: cursor,
                        style: TextStyle(
                          color: widget.style.color?.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  style: widget.style,
                  textAlign: widget.textAlign,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
