import 'package:flutter/widgets.dart';

/// Marks something Mimo can walk to and tap during a guided tour: a home
/// section, a shopping category card, a store card…
///
/// [id] examples: `section:shopping`, `shop-group:food`, `store:12`.
/// [label] is what's written on it — Mimo checks it before tapping a store.
class MimoTarget extends StatefulWidget {
  const MimoTarget({
    super.key,
    required this.id,
    required this.onTap,
    required this.child,
    this.label,
  });

  final String id;
  final String? label;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<MimoTarget> createState() => MimoTargetState();
}

class MimoTargetState extends State<MimoTarget> {
  String? _registeredId;

  String get id => widget.id;
  String? get label => widget.label;
  void tap() => widget.onTap();

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(MimoTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      MimoTargets._remove(oldWidget.id, this);
      _register();
    }
  }

  void _register() {
    _registeredId = widget.id;
    MimoTargets._add(widget.id, this);
  }

  @override
  void dispose() {
    final id = _registeredId;
    if (id != null) MimoTargets._remove(id, this);
    super.dispose();
  }

  /// On the screen the user is looking at (not a background tab/route).
  bool get isActive {
    if (!mounted) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  RenderBox? get box {
    if (!mounted) return null;
    final ro = context.findRenderObject();
    return ro is RenderBox && ro.attached && ro.hasSize ? ro : null;
  }

  /// Global rect, or null when not laid out.
  Rect? get globalRect {
    final b = box;
    if (b == null) return null;
    return b.localToGlobal(Offset.zero) & b.size;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Registry of the targets currently built.
class MimoTargets {
  MimoTargets._();

  static final Map<String, List<MimoTargetState>> _byId = {};

  static void _add(String id, MimoTargetState s) => (_byId[id] ??= []).add(s);

  static void _remove(String id, MimoTargetState s) {
    final list = _byId[id];
    list?.remove(s);
    if (list != null && list.isEmpty) _byId.remove(id);
  }

  /// The active target with [id] (most visible first), or null.
  static MimoTargetState? find(String id, {Rect? screen}) {
    final list = _byId[id];
    if (list == null) return null;
    MimoTargetState? best;
    var bestArea = -1.0;
    for (final t in list) {
      if (!t.isActive) continue;
      final r = t.globalRect;
      if (r == null) continue;
      final visible = screen == null ? r : r.intersect(screen);
      final area = visible.width > 0 && visible.height > 0
          ? visible.width * visible.height
          : 0.0;
      if (area > bestArea) {
        best = t;
        bestArea = area;
      }
    }
    return best;
  }

  /// Any active target whose id starts with [prefix] (its scroll view is the
  /// one to scroll when the wanted target isn't built yet).
  static MimoTargetState? anyWithPrefix(String prefix) {
    for (final e in _byId.entries) {
      if (!e.key.startsWith(prefix)) continue;
      for (final t in e.value) {
        if (t.isActive && t.box != null) return t;
      }
    }
    return null;
  }

  @visibleForTesting
  static int get count => _byId.values.fold(0, (a, l) => a + l.length);
}

/// One step of a guided tour: walk to [targetId] and tap it.
class MimoTourStep {
  const MimoTourStep(this.targetId, {this.expectName, this.say});

  final String targetId;

  /// When set, Mimo reads the card first and refuses a different name.
  final String? expectName;

  /// What Mimo says while walking there.
  final String? say;
}

/// The overlay registers itself here so any screen can start a tour.
abstract class MimoGuideHost {
  /// Runs the tour; true when every step was found, checked and tapped.
  Future<bool> runTour(List<MimoTourStep> steps);
}

class MimoGuide {
  MimoGuide._();

  static MimoGuideHost? host;

  static Future<bool> run(List<MimoTourStep> steps) async {
    final h = host;
    if (h == null || steps.isEmpty) return false;
    return h.runTour(steps);
  }
}
