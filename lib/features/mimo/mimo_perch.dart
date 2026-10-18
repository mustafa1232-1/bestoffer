import 'package:flutter/widgets.dart';

/// Marks a widget as a place where Mimo likes to sit (on its top edge).
///
/// Mimo can land on any card-like surface, but perches are the spots a screen
/// *offers* him. The [home] perch is where he goes back to after playing; when
/// no home perch is on screen he peeks in from the side instead, so he never
/// covers content uninvited.
class MimoPerch extends StatefulWidget {
  const MimoPerch({
    super.key,
    required this.child,
    this.home = false,
    this.alignX = 0.5,
  });

  final Widget child;
  final bool home;

  /// Where along the top edge he sits, 0 = left .. 1 = right.
  final double alignX;

  /// Perches currently mounted anywhere in the app.
  static Iterable<MimoPerchState> get mounted => MimoPerchState._all;

  @override
  State<MimoPerch> createState() => MimoPerchState();
}

class MimoPerchState extends State<MimoPerch> {
  static final List<MimoPerchState> _all = [];

  ModalRoute<dynamic>? _route;
  bool _tickerEnabled = true;

  bool get isHome => widget.home;
  double get alignX => widget.alignX;

  RenderBox? get box {
    final ro = context.findRenderObject();
    return ro is RenderBox && ro.attached && ro.hasSize ? ro : null;
  }

  /// On the visible route of the visible tab (not merely mounted).
  bool get isShowing =>
      mounted && _tickerEnabled && (_route?.isCurrent ?? true) && box != null;

  @override
  void initState() {
    super.initState();
    _all.add(this);
  }

  @override
  void dispose() {
    _all.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _route = ModalRoute.of(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    return widget.child;
  }
}
