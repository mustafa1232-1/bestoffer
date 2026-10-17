import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Moods of Mimo, the Maslaki mascot (see the "مسلكي – الشخصية" design
/// canvas). Every mood is a target pose; the widget morphs between poses with
/// a springy transition so reactions never "jump".
enum MimoMood {
  idle,
  down,
  happy,
  shocked,
  angry,
  relieved,
  scared,
  closed,
  love,
  thinking,
  sad,
  sleepy,
  laughing,
}

/// Animated Mimo. Size it with a parent box of ~130x139 (the design's sitting
/// size); the drawing keeps its aspect ratio. When [sitting] the legs dangle
/// below the box (painted outside its bounds on purpose, over the card ledge).
class MimoCharacter extends StatefulWidget {
  const MimoCharacter({
    super.key,
    required this.mood,
    this.lookX = 0,
    this.sitting = true,
    this.animate = true,
    this.nudgeTick = 0,
    this.shakeTick = 0,
    this.running = false,
    this.semanticLabel,
  });

  final MimoMood mood;

  /// Horizontal gaze while looking down at a field, -1 (left) .. 1 (right).
  final double lookX;
  final bool sitting;

  /// When false (reduced motion) poses switch instantly and idle motion
  /// (legs, breathing, blinking) is off.
  final bool animate;

  /// Bump to make Mimo give a tiny nod (e.g. on every keystroke).
  final int nudgeTick;

  /// Bump to make Mimo shake his head (e.g. on a failed login).
  final int shakeTick;

  /// Legs pedal fast and the body bobs, as if Mimo is running around.
  final bool running;
  final String? semanticLabel;

  @override
  State<MimoCharacter> createState() => _MimoCharacterState();
}

class _MimoCharacterState extends State<MimoCharacter>
    with TickerProviderStateMixin {
  final _frame = _MimoFrame();
  late final AnimationController _poseCtrl;
  late final AnimationController _nudgeCtrl;
  late final AnimationController _shakeCtrl;
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  final _rand = math.Random();

  late _MimoPose _from;
  late _MimoPose _to;
  Curve _curve = Curves.easeOutBack;

  double _time = 0;
  double _legPhase = 0;
  double _nextBlinkAt = 2.4;
  double _run = 0;

  @override
  void initState() {
    super.initState();
    _to = _MimoPose.forMood(widget.mood, widget.lookX, widget.sitting);
    _from = _to;
    _poseCtrl = AnimationController(vsync: this, value: 1)
      ..addListener(_syncFrame);
    _nudgeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(_syncFrame);
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    )..addListener(_syncFrame);
    _syncFrame();
    _updateTicker();
  }

  @override
  void didUpdateWidget(covariant MimoCharacter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moodChanged =
        oldWidget.mood != widget.mood || oldWidget.sitting != widget.sitting;
    final lookChanged = (oldWidget.lookX - widget.lookX).abs() > 0.001;
    if (moodChanged || lookChanged) {
      _from = _currentPose();
      _to = _MimoPose.forMood(widget.mood, widget.lookX, widget.sitting);
      if (!widget.animate) {
        _poseCtrl.value = 1;
      } else {
        _curve = moodChanged ? Curves.easeOutBack : Curves.easeOutCubic;
        _poseCtrl.duration = Duration(milliseconds: moodChanged ? 460 : 170);
        _poseCtrl.forward(from: 0);
      }
    }
    if (widget.animate && oldWidget.nudgeTick != widget.nudgeTick) {
      _nudgeCtrl.forward(from: 0);
    }
    if (widget.animate && oldWidget.shakeTick != widget.shakeTick) {
      _shakeCtrl.forward(from: 0);
    }
    if (oldWidget.animate != widget.animate) _updateTicker();
    _syncFrame();
  }

  void _updateTicker() {
    if (widget.animate) {
      _ticker ??= createTicker(_onTick);
      if (!_ticker!.isActive) {
        _lastElapsed = Duration.zero;
        _ticker!.start();
      }
    } else {
      _ticker?.stop();
      _time = 0;
      _legPhase = 0;
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    _time += dt;
    final pose = _currentPose();
    // Ease in/out of running so the legs never snap.
    final runTarget = widget.running ? 1.0 : 0.0;
    _run += (runTarget - _run) * math.min(1, dt * 10);
    _legPhase += dt / (pose.legSpeed + (0.26 - pose.legSpeed) * _run);
    _syncFrame();
  }

  _MimoPose _currentPose() {
    final t = _curve.transform(_poseCtrl.value.clamp(0.0, 1.0));
    return _MimoPose.lerp(_from, _to, t);
  }

  void _syncFrame() {
    final pose = _currentPose();
    var blink = 1.0;
    if (widget.animate) {
      if (_time >= _nextBlinkAt + 0.16) {
        _nextBlinkAt = _time + 2.4 + _rand.nextDouble() * 2.6;
      }
      if (_time >= _nextBlinkAt) {
        final p = ((_time - _nextBlinkAt) / 0.16).clamp(0.0, 1.0);
        blink = 1 - math.sin(p * math.pi) * 0.9;
      }
    }
    final n = _nudgeCtrl.value;
    final s = _shakeCtrl.value;
    _frame.update(
      pose: pose,
      sitting: widget.sitting,
      time: widget.animate ? _time : 0,
      legPhase: _legPhase,
      run: widget.animate ? _run : 0,
      blink: blink,
      nod: _nudgeCtrl.isAnimating ? math.sin(n * math.pi) : 0,
      shakeDx: _shakeCtrl.isAnimating
          ? math.sin(s * math.pi * 7) * (1 - s) * 9
          : 0,
    );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _poseCtrl.dispose();
    _nudgeCtrl.dispose();
    _shakeCtrl.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: RepaintBoundary(
        child: CustomPaint(painter: _MimoPainter(_frame), size: Size.infinite),
      ),
    );
  }
}

/// Mutable per-frame data shared with the painter; notifying it repaints
/// without rebuilding any widgets.
class _MimoFrame extends ChangeNotifier {
  _MimoPose pose = _MimoPose.forMood(MimoMood.idle, 0, true);
  bool sitting = true;
  double time = 0;
  double legPhase = 0;
  double blink = 1;
  double nod = 0;
  double shakeDx = 0;
  double run = 0;

  void update({
    required _MimoPose pose,
    required bool sitting,
    required double time,
    required double legPhase,
    required double blink,
    required double nod,
    required double shakeDx,
    required double run,
  }) {
    this.pose = pose;
    this.sitting = sitting;
    this.time = time;
    this.legPhase = legPhase;
    this.blink = blink;
    this.nod = nod;
    this.shakeDx = shakeDx;
    this.run = run;
    notifyListeners();
  }
}

/// A transform: translate (dx, dy) then rotate [rot] degrees about a pivot.
class _Tr {
  const _Tr([this.dx = 0, this.dy = 0, this.rot = 0]);
  final double dx;
  final double dy;
  final double rot;

  static _Tr lerp(_Tr a, _Tr b, double t) => _Tr(
    a.dx + (b.dx - a.dx) * t,
    a.dy + (b.dy - a.dy) * t,
    a.rot + (b.rot - a.rot) * t,
  );

  void apply(Canvas c, Offset pivot) {
    c.translate(dx, dy);
    if (rot != 0) {
      c.translate(pivot.dx, pivot.dy);
      c.rotate(rot * math.pi / 180);
      c.translate(-pivot.dx, -pivot.dy);
    }
  }
}

/// Every continuous value of a pose, so any two poses can be interpolated.
/// Mood-specific features (eye styles, mouths, effects) are cross-faded by
/// per-mood [weights].
class _MimoPose {
  const _MimoPose({
    required this.pin,
    required this.body,
    required this.bodyScale,
    required this.face,
    required this.eye,
    required this.handL,
    required this.handR,
    required this.blush,
    required this.shadowRx,
    required this.weights,
    required this.legSpeed,
    required this.stiff,
    required this.legsStill,
  });

  final _Tr pin;
  final _Tr body;
  final Offset bodyScale;
  final Offset face;
  final Offset eye;
  final _Tr handL;
  final _Tr handR;
  final double blush;
  final double shadowRx;
  final List<double> weights;
  final double legSpeed;
  final double stiff;
  final double legsStill;

  double w(MimoMood m) => weights[m.index];

  static const _hands = <MimoMood, List<_Tr>>{
    MimoMood.idle: [_Tr(), _Tr()],
    MimoMood.down: [_Tr(4, 6), _Tr(-4, 6)],
    MimoMood.happy: [_Tr(-6, -58), _Tr(6, -58)],
    MimoMood.shocked: [_Tr(8, -46, -20), _Tr(-8, -46, 20)],
    MimoMood.angry: [_Tr(8, 30), _Tr(-8, 30)],
    MimoMood.relieved: [_Tr(), _Tr(-34, -80, 30)],
    MimoMood.scared: [_Tr(34, -10, -28), _Tr(-34, -10, 28)],
    MimoMood.closed: [_Tr(), _Tr()],
    MimoMood.love: [_Tr(32, -16, -20), _Tr(-32, -16, 20)],
    MimoMood.thinking: [_Tr(), _Tr(-56, -6)],
    MimoMood.sad: [_Tr(6, 12), _Tr(-6, 12)],
    MimoMood.sleepy: [_Tr(4, 8), _Tr(-4, 8)],
    MimoMood.laughing: [_Tr(18, 22, -16), _Tr(-18, 22, 16)],
  };

  static const _pins = <MimoMood, _Tr>{
    MimoMood.idle: _Tr(),
    MimoMood.down: _Tr(0, 6, 8),
    MimoMood.happy: _Tr(0, -14),
    MimoMood.shocked: _Tr(0, -18, -14),
    MimoMood.angry: _Tr(4, 2, 16),
    MimoMood.relieved: _Tr(0, 2, -8),
    MimoMood.scared: _Tr(0, -22, 12),
    MimoMood.closed: _Tr(),
    MimoMood.love: _Tr(0, -10),
    MimoMood.thinking: _Tr(0, 0, -12),
    MimoMood.sad: _Tr(0, 8, -20),
    MimoMood.sleepy: _Tr(0, 6, 24),
    MimoMood.laughing: _Tr(0, -10, -10),
  };

  static const _standBodies = <MimoMood, _Tr>{
    MimoMood.down: _Tr(0, 3),
    MimoMood.happy: _Tr(0, -8),
    MimoMood.shocked: _Tr(0, -6),
    MimoMood.relieved: _Tr(0, 2),
    MimoMood.love: _Tr(0, -4),
    MimoMood.sad: _Tr(0, 3),
    MimoMood.sleepy: _Tr(0, 0, -4),
    MimoMood.laughing: _Tr(0, -4),
  };

  // Sitting: a smaller hop so he never leaves the ledge.
  static const _sitBodies = <MimoMood, _Tr>{
    MimoMood.happy: _Tr(0, -6),
    MimoMood.love: _Tr(0, -3),
    MimoMood.shocked: _Tr(0, -4),
    MimoMood.scared: _Tr(0, -3),
  };

  static _MimoPose forMood(MimoMood m, double lookX, bool sitting) {
    final lx = lookX.clamp(-1.0, 1.0);
    final down = m == MimoMood.down;
    final weights = List<double>.filled(MimoMood.values.length, 0);
    weights[m.index] = 1;
    final hands = _hands[m]!;
    final speed = switch (m) {
      MimoMood.happy => 0.8,
      MimoMood.laughing => 0.5,
      MimoMood.love => 0.9,
      MimoMood.relieved => 1.6,
      MimoMood.sleepy => 2.6,
      MimoMood.sad => 2.4,
      MimoMood.down => 1.5,
      _ => 1.3,
    };
    return _MimoPose(
      pin: _pins[m]!,
      body: (sitting ? _sitBodies[m] : _standBodies[m]) ?? const _Tr(),
      bodyScale: !sitting && m == MimoMood.scared
          ? const Offset(0.96, 0.97)
          : const Offset(1, 1),
      face: down
          ? Offset(lx * 3, 7)
          : (m == MimoMood.idle ? Offset.zero : const Offset(0, -4)),
      eye: down
          ? Offset(lx * 4, 5)
          : m == MimoMood.thinking
          ? const Offset(4, -4)
          : m == MimoMood.sad
          ? const Offset(0, 3)
          : Offset.zero,
      handL: hands[0],
      handR: hands[1],
      blush: (m == MimoMood.angry || m == MimoMood.love) ? 0.9 : 0.55,
      shadowRx: (m == MimoMood.happy || m == MimoMood.shocked) ? 56 : 68,
      weights: weights,
      legSpeed: speed,
      stiff: (m == MimoMood.shocked || m == MimoMood.scared) ? 1 : 0,
      legsStill: m == MimoMood.angry ? 1 : 0,
    );
  }

  static _MimoPose lerp(_MimoPose a, _MimoPose b, double t) {
    if (t == 1) return b;
    double l(double x, double y) => x + (y - x) * t;
    // Weights must never go negative / over 1 even with an overshooting curve.
    final wt = t.clamp(0.0, 1.0);
    return _MimoPose(
      pin: _Tr.lerp(a.pin, b.pin, t),
      body: _Tr.lerp(a.body, b.body, t),
      bodyScale: Offset.lerp(a.bodyScale, b.bodyScale, t)!,
      face: Offset.lerp(a.face, b.face, t)!,
      eye: Offset.lerp(a.eye, b.eye, t)!,
      handL: _Tr.lerp(a.handL, b.handL, t),
      handR: _Tr.lerp(a.handR, b.handR, t),
      blush: l(a.blush, b.blush).clamp(0.0, 1.0),
      shadowRx: l(a.shadowRx, b.shadowRx),
      weights: [
        for (var i = 0; i < a.weights.length; i++)
          a.weights[i] + (b.weights[i] - a.weights[i]) * wt,
      ],
      legSpeed: b.legSpeed,
      stiff: a.stiff + (b.stiff - a.stiff) * wt,
      legsStill: a.legsStill + (b.legsStill - a.legsStill) * wt,
    );
  }
}

// ---------------------------------------------------------------------------
// Painting. Coordinates follow the design's SVG viewBox "0 -14 200 214".
// ---------------------------------------------------------------------------

const _navy = Color(0xFF0B2440);
const _brown = Color(0xFF7A4A12);
const _tearFill = Color(0xFF8FD0F0);
const _tearStroke = Color(0xFF4FA3D1);
const _heartRed = Color(0xFFE0393E);
const _gold = Color(0xFFB8893F);

class _P {
  static final pinShape = svgPath(
    'M100 44 C93 36 84 29 84 20 A16 16 0 1 1 116 20 C116 29 107 36 100 44 Z',
  );
  static final pinHighlight = svgPath('M88 12 A12 12 0 0 1 98 6');
  static final side = svgPath(
    'M47 189 L47 67 L75 57 L107 87 L139 57 L167 67 L167 189 Q167 193 163 193 '
    'L117 193 L107 145 L97 193 L51 193 Q47 193 47 189 Z',
  );
  static final front = svgPath(
    'M40 182 L40 60 L68 50 L100 80 L132 50 L160 60 L160 182 Q160 186 156 186 '
    'L110 186 L100 138 L90 186 L44 186 Q40 186 40 182 Z',
  );
  static final band = svgPath('M86 196 Q102 154 130 126 L164 76');
  static final bandShine = svgPath('M90 186 Q104 152 128 128 L156 86');
  static final collar = svgPath('M87 66 L100 81 L113 66');
  static final crotch = svgPath('M90 186 L100 138 L110 186');
  static final rimL = svgPath('M43 96 L43 62 L67 54 L96 80');
  static final rimR = svgPath('M104 79 L132 54 L138 56');
  static final shockBrows = svgPath(
    'M74 98 Q84 92 94 97 M102 97 Q112 92 122 98',
  );
  static final scareBrows = svgPath('M72 100 L94 92 M102 92 L124 100');
  static final scareLines = svgPath(
    'M90 82 L90 92 M98 80 L98 92 M106 82 L106 92',
  );
  static final scareTear = svgPath('M79 129 Q76 134 79 138');
  static final heartL = svgPath(
    'M84 126 C70 116 72 104 79 104 C82 104 84 107 84 109 C84 107 86 104 89 104 '
    'C96 104 98 116 84 126 Z',
  );
  static final heartR = svgPath(
    'M112 126 C98 116 100 104 107 104 C110 104 112 107 112 109 C112 107 114 104 '
    '117 104 C124 104 126 116 112 126 Z',
  );
  static final closedEyes = svgPath(
    'M76 116 Q84 122 92 116 M104 116 Q112 122 120 116',
  );
  static final lashes = svgPath(
    'M78 118.5 L75.5 122 M90 118.5 L92.5 122 M106 118.5 L103.5 122 '
    'M118 118.5 L120.5 122',
  );
  static final sadBrows = svgPath('M74 104 L93 98 M103 98 L122 104');
  static final tear = svgPath(
    'M78 128 C76 132 75 134 75 136 A3 3 0 0 0 81 136 C81 134 80 132 78 128 Z',
  );
  static final angryLidL = svgPath('M74 106 L95 113 L95 104 L74 100 Z');
  static final angryLidR = svgPath('M122 106 L101 113 L101 104 L122 100 Z');
  static final angryBrows = svgPath('M73 104 L95 112 M123 104 L101 112');
  static final laughEyes = svgPath(
    'M77 109 L90 116 L77 123 M119 109 L106 116 L119 123',
  );
  static final happyEyes = svgPath(
    'M76 118 Q84 108 92 118 M104 118 Q112 108 120 118',
  );
  static final reliefBrows = svgPath(
    'M76 104 Q84 101 92 104 M104 104 Q112 101 120 104',
  );
  static final angerMark = svgPath(
    'M30 56 Q38 58 38 66 M48 56 Q40 58 40 66 M30 76 Q38 74 38 68 '
    'M48 76 Q40 74 40 68',
  );
  static final sweat = svgPath(
    'M168 52 C164 60 162 64 162 68 A6 6 0 0 0 174 68 C174 64 172 60 168 52 Z',
  );
  static final scareSweat = svgPath(
    'M32 60 C28 68 26 72 26 76 A6 6 0 0 0 38 76 C38 72 36 68 32 60 Z',
  );
  static final tremble = svgPath(
    'M24 118 Q18 126 24 134 M16 112 Q8 126 16 140 M176 118 Q182 126 176 134 '
    'M184 112 Q192 126 184 140',
  );
  static final alarm = svgPath('M86 6 L82 -4 M100 2 L100 -10 M114 6 L118 -4');
  static final loveHearts = svgPath(
    'M30 70 C22 64 23 57 27 57 C29 57 30 59 30 60 C30 59 31 57 33 57 C37 57 38 '
    '64 30 70 Z M172 50 C162 43 163 34 168 34 C170.5 34 172 36.5 172 38 C172 '
    '36.5 173.5 34 176 34 C181 34 182 43 172 50 Z M160 92 C155 88 155.5 84 158 '
    '84 C159 84 160 85 160 86 C160 85 161 84 162 84 C164.5 84 165 88 160 92 Z',
  );
  static final sparkles = svgPath(
    'M26 50 l3 8 8 3 -8 3 -3 8 -3 -8 -8 -3 8 -3z '
    'M176 30 l2.5 6 6 2.5 -6 2.5 -2.5 6 -2.5 -6 -6 -2.5 6 -2.5z',
  );

  static const mx = 98.0, my = 134.0;
  static final mouths = <MimoMood, Path>{
    MimoMood.idle: svgPath('M${mx - 6} $my Q$mx ${my + 5} ${mx + 6} $my'),
    MimoMood.down: svgPath(
      'M${mx - 5} ${my + 1} Q$mx ${my + 4} ${mx + 5} ${my + 1}',
    ),
    MimoMood.happy: svgPath(
      'M${mx - 9} ${my - 1} Q$mx ${my + 12} ${mx + 9} ${my - 1} Z',
    ),
    MimoMood.shocked: svgPath(
      'M${mx - 5} ${my + 3} A5 6.5 0 1 0 ${mx + 5} ${my + 3} '
      'A5 6.5 0 1 0 ${mx - 5} ${my + 3} Z',
    ),
    MimoMood.angry: svgPath(
      'M${mx - 8} ${my + 5} Q$mx ${my - 3} ${mx + 8} ${my + 5}',
    ),
    MimoMood.relieved: svgPath('M${mx - 7} $my Q$mx ${my + 6} ${mx + 7} $my'),
    MimoMood.scared: svgPath(
      'M${mx - 10} ${my + 1} Q${mx - 7.5} ${my - 3} ${mx - 5} ${my + 1} '
      'Q${mx - 2.5} ${my + 5} $mx ${my + 1} Q${mx + 2.5} ${my - 3} ${mx + 5} '
      '${my + 1} Q${mx + 7.5} ${my + 5} ${mx + 10} ${my + 1} L${mx + 9} '
      '${my + 7} Q$mx ${my + 12} ${mx - 9} ${my + 7} Z',
    ),
    MimoMood.closed: svgPath('M${mx - 5} $my Q$mx ${my + 4} ${mx + 5} $my'),
    MimoMood.love: svgPath(
      'M${mx - 9} ${my - 1} Q$mx ${my + 12} ${mx + 9} ${my - 1} Z',
    ),
    MimoMood.thinking: svgPath('M${mx - 5} ${my + 3} L${mx + 6} $my'),
    MimoMood.sad: svgPath(
      'M${mx - 7} ${my + 5} Q$mx ${my - 1} ${mx + 7} ${my + 5}',
    ),
    MimoMood.laughing: svgPath(
      'M${mx - 12} ${my - 3} Q$mx ${my + 18} ${mx + 12} ${my - 3} Z',
    ),
    MimoMood.sleepy: svgPath(
      'M${mx - 3} ${my + 2} A3 3.5 0 1 0 ${mx + 3} ${my + 2} '
      'A3 3.5 0 1 0 ${mx - 3} ${my + 2} Z',
    ),
  };
  static const mouthFills = <MimoMood, Color>{
    MimoMood.happy: Color(0xFF7A2E3A),
    MimoMood.shocked: Color(0xFF7A2E3A),
    MimoMood.scared: Color(0xFF5A1E2A),
    MimoMood.love: Color(0xFF7A2E3A),
    MimoMood.sleepy: Color(0xFF7A2E3A),
    MimoMood.laughing: Color(0xFF7A2E3A),
  };
}

class _MimoPainter extends CustomPainter {
  _MimoPainter(this.frame) : super(repaint: frame);

  final _MimoFrame frame;

  static const _vbW = 200.0, _vbH = 214.0, _vbY = -14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    final p = f.pose;
    final s = math.min(size.width / _vbW, size.height / _vbH);
    canvas.save();
    canvas.translate(
      (size.width - _vbW * s) / 2 + f.shakeDx * s,
      (size.height - _vbH * s) / 2,
    );
    canvas.scale(s);
    canvas.translate(0, -_vbY);

    final standOp = f.sitting ? 0.0 : 1.0;
    final breath = math.sin(f.time * 2 * math.pi / 2.8) * 0.012;

    // Ground shadow (standing only): a radial gradient squashed to an ellipse.
    if (standOp > 0) {
      canvas.save();
      canvas.translate(102, 196);
      canvas.scale(1, 9 / p.shadowRx);
      final r = Rect.fromCircle(center: Offset.zero, radius: p.shadowRx);
      canvas.drawOval(
        r,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x520B2440), Color(0x000B2440)],
          ).createShader(r),
      );
      canvas.restore();
    }

    // Pin above the head.
    canvas.save();
    p.pin.apply(canvas, const Offset(100, 44));
    canvas.translate(0, -f.nod * 1.5);
    _drawPin(canvas);
    canvas.restore();

    // Body group.
    canvas.save();
    p.body.apply(canvas, const Offset(100, 190));
    final laughW = p.w(MimoMood.laughing).clamp(0.0, 1.0);
    final bounce =
        laughW * (math.sin(f.time * 2 * math.pi / 0.34)).abs() * 5 +
        f.run * (math.sin(f.legPhase * 2 * math.pi)).abs() * 4;
    canvas.translate(0, -bounce);
    _scaleAbout(
      canvas,
      const Offset(100, 190),
      p.bodyScale.dx,
      p.bodyScale.dy * (1 + breath),
    );

    if (standOp > 0) {
      _drawEllipse(canvas, const Offset(62, 189), 16, 8, _handShader);
      _drawEllipse(canvas, const Offset(140, 189), 16, 8, _handShader);
    } else {
      _drawLegs(canvas, f, p);
    }

    canvas.drawPath(_P.side, Paint()..shader = _sideShader);
    canvas.drawPath(_P.front, Paint()..shader = _frontShader);

    canvas.save();
    canvas.clipPath(_P.front);
    canvas.drawRect(
      const Rect.fromLTRB(140, 40, 170, 200),
      Paint()..shader = _navyShader,
    );
    canvas.drawLine(
      const Offset(141.5, 58),
      const Offset(141.5, 184),
      _stroke(const Color(0x995B8EC4), 2.2),
    );
    canvas.save();
    canvas.translate(3, 4);
    canvas.drawPath(_P.band, _stroke(const Color(0x595A370C), 17));
    canvas.restore();
    canvas.drawPath(_P.band, _stroke(Colors.white, 16)..shader = _bandShader);
    canvas.drawPath(_P.bandShine, _stroke(const Color(0xBFFFF2CF), 3));
    canvas.drawPath(
      _P.collar,
      _stroke(const Color(0x477A4A12), 6)..strokeJoin = StrokeJoin.miter,
    );
    canvas.drawRect(
      const Rect.fromLTWH(30, 40, 140, 160),
      Paint()..shader = _bottomShader,
    );
    canvas.drawPath(
      _P.crotch,
      _stroke(const Color(0x525A370C), 4)..strokeJoin = StrokeJoin.miter,
    );
    canvas.restore();

    canvas.drawPath(
      _P.rimL,
      _stroke(const Color(0xD9FFF2CF), 3.5)..strokeJoin = StrokeJoin.miter,
    );
    canvas.drawPath(
      _P.rimR,
      _stroke(const Color(0x99FFF2CF), 2.6)..strokeJoin = StrokeJoin.miter,
    );
    canvas.drawCircle(
      const Offset(54, 100),
      2.6,
      Paint()..color = const Color(0xD9FFFFFF),
    );
    canvas.drawPath(
      _P.front,
      _stroke(const Color(0x8C8A5719), 1.2)..strokeJoin = StrokeJoin.miter,
    );

    // Face.
    canvas.save();
    canvas.translate(p.face.dx, p.face.dy - 12 + f.nod * 2.5);
    _drawFace(canvas, f, p);
    canvas.restore();

    // Hands.
    canvas.save();
    p.handL.apply(canvas, const Offset(34, 132));
    _drawHand(canvas, const Offset(34, 132), const Offset(30, 126));
    canvas.restore();
    canvas.save();
    p.handR.apply(canvas, const Offset(166, 132));
    _drawHand(canvas, const Offset(166, 132), const Offset(162, 126));
    canvas.restore();

    canvas.restore(); // body

    _drawEffects(canvas, f, p);
    canvas.restore();
  }

  void _drawPin(Canvas canvas) {
    canvas.drawPath(_P.pinShape, Paint()..shader = _pinShader);
    canvas.drawCircle(const Offset(100, 20), 6, Paint()..color = _navy);
    canvas.drawPath(_P.pinHighlight, _stroke(const Color(0xFFFFF6DD), 3));
  }

  void _drawLegs(Canvas canvas, _MimoFrame f, _MimoPose p) {
    final swing = math.sin(f.legPhase * 2 * math.pi);
    final shake = math.sin(f.time * 2 * math.pi / 0.18);
    final calm = math.max((1 - p.stiff) * (1 - p.legsStill), f.run);
    final stiff = p.stiff * (1 - p.legsStill) * (1 - f.run);
    final amp = 13 + 15 * f.run;
    // Design: swingA 14°..-12°, swingB mirrored; stiff moods tremble ±3°.
    final aL = (1 + amp * swing) * calm + 3 * shake * stiff;
    final aR = (1 - amp * swing) * calm - 3 * shake * stiff;
    for (final (pivotX, angle) in [(70.0, aL), (130.0, aR)]) {
      canvas.save();
      canvas.translate(pivotX, 176);
      canvas.rotate(angle * math.pi / 180);
      canvas.translate(-pivotX, -176);
      final x = pivotX - 8.5;
      final legRect = Rect.fromLTWH(x, 166, 17, 62);
      canvas.drawRRect(
        RRect.fromRectAndRadius(legRect, const Radius.circular(8.5)),
        Paint()..shader = _radial(legRect, const Color(0xFF3A6EA4)),
      );
      canvas.drawLine(
        Offset(pivotX - 4, 182),
        Offset(pivotX - 4, 216),
        _stroke(const Color(0x805D8DC0), 3),
      );
      _drawEllipse(canvas, Offset(pivotX, 230), 14, 10, _handShader);
      final sole = Path()
        ..moveTo(pivotX - 13, 233)
        ..quadraticBezierTo(pivotX, 242, pivotX + 13, 233);
      canvas.drawPath(sole, _stroke(const Color(0xFFD9AE5F), 3.4));
      _fillEllipse(
        canvas,
        Offset(pivotX - 5, 226),
        4,
        2.6,
        const Color(0x995D8DC0),
      );
      canvas.restore();
    }
  }

  void _drawFace(Canvas canvas, _MimoFrame f, _MimoPose p) {
    double w(MimoMood m) => p.w(m).clamp(0.0, 1.0);

    final blush = Color.fromRGBO(242, 156, 142, p.blush);
    _fillEllipse(canvas, const Offset(74, 132), 8, 5, blush);
    _fillEllipse(canvas, const Offset(122, 132), 8, 5, blush);

    final openOp =
        (w(MimoMood.idle) +
                w(MimoMood.down) +
                w(MimoMood.thinking) +
                w(MimoMood.sad))
            .clamp(0.0, 1.0);
    if (openOp > 0.01) {
      canvas.save();
      canvas.translate(p.eye.dx, p.eye.dy);
      final navy = _navy.withValues(alpha: openOp);
      final ry = 9 * f.blink;
      _fillEllipse(canvas, const Offset(84, 116), 7, ry, navy);
      _fillEllipse(canvas, const Offset(112, 116), 7, ry, navy);
      if (f.blink > 0.5) {
        final white = Colors.white.withValues(alpha: openOp);
        canvas.drawCircle(
          const Offset(86.5, 112.5),
          2.8,
          Paint()..color = white,
        );
        canvas.drawCircle(
          const Offset(114.5, 112.5),
          2.8,
          Paint()..color = white,
        );
      }
      canvas.restore();
    }

    final shock = w(MimoMood.shocked);
    if (shock > 0.01) {
      for (final cx in [84.0, 112.0]) {
        canvas.drawCircle(
          Offset(cx, 115),
          11,
          Paint()..color = Colors.white.withValues(alpha: shock),
        );
        canvas.drawCircle(
          Offset(cx, 115),
          11,
          _stroke(_navy.withValues(alpha: shock), 2.4),
        );
        canvas.drawCircle(
          Offset(cx, 115),
          3.4,
          Paint()..color = _navy.withValues(alpha: shock),
        );
      }
      canvas.drawPath(
        _P.shockBrows,
        _stroke(_brown.withValues(alpha: shock), 2.6),
      );
    }

    final scare = w(MimoMood.scared);
    if (scare > 0.01) {
      for (final cx in [84.0, 112.0]) {
        canvas.drawCircle(
          Offset(cx, 115),
          11.5,
          Paint()..color = Colors.white.withValues(alpha: scare),
        );
        canvas.drawCircle(
          Offset(cx, 115),
          11.5,
          _stroke(_navy.withValues(alpha: scare), 2.4),
        );
        canvas.drawCircle(
          Offset(cx, 117),
          2.6,
          Paint()..color = _navy.withValues(alpha: scare),
        );
      }
      canvas.drawPath(
        _P.scareBrows,
        _stroke(_brown.withValues(alpha: scare), 2.8),
      );
      canvas.drawPath(
        _P.scareLines,
        _stroke(_navy.withValues(alpha: scare * 0.45), 2.2),
      );
      canvas.drawPath(
        _P.scareTear,
        _stroke(_tearFill.withValues(alpha: scare), 2.4),
      );
    }

    final love = w(MimoMood.love);
    if (love > 0.01) {
      final paint = Paint()..color = _heartRed.withValues(alpha: love);
      final beat = 1 + math.sin(f.time * 2 * math.pi / 0.7).abs() * 0.08;
      for (final (path, c) in [
        (_P.heartL, const Offset(84, 114)),
        (_P.heartR, const Offset(112, 114)),
      ]) {
        canvas.save();
        _scaleAbout(canvas, c, beat, beat);
        canvas.drawPath(path, paint);
        canvas.restore();
      }
      final white = Colors.white.withValues(alpha: love * 0.9);
      canvas.drawCircle(const Offset(79, 109), 2, Paint()..color = white);
      canvas.drawCircle(const Offset(107, 109), 2, Paint()..color = white);
    }

    final closed = (w(MimoMood.closed) + w(MimoMood.sleepy)).clamp(0.0, 1.0);
    if (closed > 0.01) {
      final c = _navy.withValues(alpha: closed);
      canvas.drawPath(_P.closedEyes, _stroke(c, 3.2));
      canvas.drawPath(_P.lashes, _stroke(c, 1.6));
    }

    final sad = w(MimoMood.sad);
    if (sad > 0.01) {
      canvas.drawPath(_P.sadBrows, _stroke(_brown.withValues(alpha: sad), 2.6));
      canvas.save();
      // The tear slowly rolls down and restarts.
      final roll = (f.time % 2.4) / 2.4;
      canvas.translate(0, roll * 6);
      final a = sad * (1 - roll * 0.6);
      canvas.drawPath(_P.tear, Paint()..color = _tearFill.withValues(alpha: a));
      canvas.drawPath(_P.tear, _stroke(_tearStroke.withValues(alpha: a), 1));
      canvas.restore();
    }

    final angry = w(MimoMood.angry);
    if (angry > 0.01) {
      final navy = _navy.withValues(alpha: angry);
      _fillEllipse(canvas, const Offset(84, 118), 7, 7.5, navy);
      _fillEllipse(canvas, const Offset(112, 118), 7, 7.5, navy);
      final white = Colors.white.withValues(alpha: angry);
      canvas.drawCircle(const Offset(86, 116), 2.2, Paint()..color = white);
      canvas.drawCircle(const Offset(114, 116), 2.2, Paint()..color = white);
      final lid = Paint()
        ..color = const Color(0xFFE1AE5E).withValues(alpha: angry);
      canvas.drawPath(_P.angryLidL, lid);
      canvas.drawPath(_P.angryLidR, lid);
      canvas.drawPath(_P.angryBrows, _stroke(navy, 3.6));
    }

    final laugh = w(MimoMood.laughing);
    if (laugh > 0.01) {
      final c = _navy.withValues(alpha: laugh);
      canvas.drawPath(_P.laughEyes, _stroke(c, 3.4));
      // Tears of joy squeezing out.
      final drop = (f.time % 1.1) / 1.1;
      for (final x in [70.0, 126.0]) {
        canvas.save();
        canvas.translate(x - 78, drop * 8 - 6);
        final a = laugh * (1 - drop * 0.8);
        canvas.drawPath(
          _P.tear,
          Paint()..color = _tearFill.withValues(alpha: a),
        );
        canvas.restore();
      }
    }

    final happy = w(MimoMood.happy);
    if (happy > 0.01) {
      canvas.drawPath(
        _P.happyEyes,
        _stroke(_navy.withValues(alpha: happy), 3.2),
      );
    }

    final relief = w(MimoMood.relieved);
    if (relief > 0.01) {
      canvas.drawPath(
        _P.closedEyes,
        _stroke(_navy.withValues(alpha: relief), 3.2),
      );
      canvas.drawPath(
        _P.reliefBrows,
        _stroke(_brown.withValues(alpha: relief), 2.2),
      );
    }

    // Mouths cross-fade between moods.
    for (final mood in MimoMood.values) {
      final a = w(mood);
      if (a <= 0.01) continue;
      final path = _P.mouths[mood]!;
      final fill = _P.mouthFills[mood];
      if (fill != null) {
        canvas.drawPath(path, Paint()..color = fill.withValues(alpha: a));
      }
      canvas.drawPath(
        path,
        _stroke(_navy.withValues(alpha: a), 2.8)..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _drawHand(Canvas canvas, Offset c, Offset shine) {
    final r = Rect.fromCenter(center: c, width: 22, height: 28);
    canvas.drawOval(r, Paint()..shader = _radial(r, const Color(0xFF3A6EA4)));
    _fillEllipse(canvas, shine, 3.2, 4.6, const Color(0x995D8DC0));
  }

  void _drawEffects(Canvas canvas, _MimoFrame f, _MimoPose p) {
    double w(MimoMood m) => p.w(m).clamp(0.0, 1.0);
    final t = f.time;

    final anger = w(MimoMood.angry);
    if (anger > 0.01) {
      canvas.save();
      final pulse = 1 + math.sin(t * 2 * math.pi / 0.6) * 0.12;
      _scaleAbout(canvas, const Offset(39, 66), pulse, pulse);
      canvas.drawPath(
        _P.angerMark,
        _stroke(const Color(0xFFD64545).withValues(alpha: anger), 3.4),
      );
      canvas.restore();
    }

    final sweat =
        (w(MimoMood.relieved) + w(MimoMood.shocked) + w(MimoMood.scared)).clamp(
          0.0,
          1.0,
        );
    if (sweat > 0.01) {
      canvas.save();
      canvas.translate(0, math.sin(t * 2 * math.pi / 1.4) * 1.5);
      canvas.drawPath(
        _P.sweat,
        Paint()..color = _tearFill.withValues(alpha: sweat),
      );
      canvas.drawPath(
        _P.sweat,
        _stroke(_tearStroke.withValues(alpha: sweat), 1.2),
      );
      canvas.restore();
    }

    final scare = w(MimoMood.scared);
    if (scare > 0.01) {
      canvas.drawPath(
        _P.scareSweat,
        Paint()..color = _tearFill.withValues(alpha: scare),
      );
      canvas.drawPath(
        _P.scareSweat,
        _stroke(_tearStroke.withValues(alpha: scare), 1.2),
      );
      canvas.drawPath(
        _P.tremble,
        _stroke(_navy.withValues(alpha: scare * 0.55), 2.6),
      );
      canvas.drawPath(_P.alarm, _stroke(_gold.withValues(alpha: scare), 2.6));
    }

    final relief = w(MimoMood.relieved);
    if (relief > 0.01) {
      // "Phew" puff drifting out.
      final drift = (t % 1.8) / 1.8;
      final a = relief * (1 - drift * 0.7);
      canvas.save();
      canvas.translate(drift * 8, -drift * 4);
      final fill = Paint()..color = Colors.white.withValues(alpha: a);
      final edge = _stroke(const Color(0xFFC9D6E2).withValues(alpha: a), 1.2);
      for (final (c, r) in [
        (const Offset(136, 148), 5.0),
        (const Offset(146, 152), 6.5),
        (const Offset(157, 149), 4.5),
      ]) {
        canvas.drawCircle(c, r, fill);
        canvas.drawCircle(c, r, edge);
      }
      canvas.restore();
    }

    final love = w(MimoMood.love);
    if (love > 0.01) {
      canvas.save();
      canvas.translate(0, -((t % 2.0) / 2.0) * 6);
      canvas.drawPath(
        _P.loveHearts,
        Paint()..color = _heartRed.withValues(alpha: love),
      );
      canvas.restore();
    }

    final think = w(MimoMood.thinking);
    if (think > 0.01) {
      final fill = Paint()..color = Colors.white.withValues(alpha: think);
      final edge = _stroke(
        const Color(0xFFC9B48A).withValues(alpha: think),
        1.5,
      );
      canvas.drawCircle(const Offset(150, 58), 4, fill);
      canvas.drawCircle(const Offset(150, 58), 4, edge);
      canvas.drawCircle(const Offset(162, 44), 6, fill);
      canvas.drawCircle(const Offset(162, 44), 6, edge);
      final cloud = Rect.fromCenter(
        center: const Offset(182, 22),
        width: 40,
        height: 28,
      );
      canvas.drawOval(cloud, fill);
      canvas.drawOval(cloud, edge);
      // Animated "typing" dots inside the thought cloud.
      for (var i = 0; i < 3; i++) {
        final phase = ((t * 1.6) - i * 0.18) % 1.0;
        final lift = math.sin(phase * math.pi).clamp(0.0, 1.0) * 3;
        canvas.drawCircle(
          Offset(174.0 + i * 8, 22 - lift),
          2.4,
          Paint()..color = _navy.withValues(alpha: think),
        );
      }
    }

    final sleepy = w(MimoMood.sleepy);
    if (sleepy > 0.01) {
      for (final (i, x, y, size) in [
        (0, 148.0, 54.0, 22.0),
        (1, 166.0, 36.0, 30.0),
        (2, 186.0, 14.0, 38.0),
      ]) {
        final phase = ((t / 2.4) + i / 3) % 1.0;
        final a = sleepy * math.sin(phase * math.pi);
        _drawText(
          canvas,
          'Z',
          Offset(x, y - size - phase * 6),
          size,
          _gold.withValues(alpha: a),
        );
      }
    }

    final happy = w(MimoMood.happy);
    if (happy > 0.01) {
      final twinkle = 0.75 + math.sin(t * 2 * math.pi / 0.9) * 0.25;
      canvas.drawPath(
        _P.sparkles,
        Paint()
          ..color = const Color(0xFFE7BF6C).withValues(alpha: happy * twinkle),
      );
    }
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset topLeft,
    double size,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w800,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, topLeft);
  }

  static void _scaleAbout(Canvas c, Offset o, double sx, double sy) {
    if (sx == 1 && sy == 1) return;
    c.translate(o.dx, o.dy);
    c.scale(sx, sy);
    c.translate(-o.dx, -o.dy);
  }

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static void _fillEllipse(
    Canvas c,
    Offset center,
    double rx,
    double ry,
    Color color,
  ) {
    c.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      Paint()..color = color,
    );
  }

  static void _drawEllipse(
    Canvas c,
    Offset center,
    double rx,
    double ry,
    Shader Function(Rect) shader,
  ) {
    final r = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    c.drawOval(r, Paint()..shader = shader(r));
  }

  static Shader _handShader(Rect r) => _radial(r, const Color(0xFF3A6EA4));

  static Shader _radial(Rect r, Color light) => RadialGradient(
    center: const Alignment(-0.32, -0.44),
    radius: 0.85,
    colors: [light, const Color(0xFF14365C), const Color(0xFF06111F)],
    stops: const [0, 0.55, 1],
  ).createShader(r);

  static final Shader _frontShader = const RadialGradient(
    center: Alignment(-0.4, -0.6),
    radius: 1.0,
    colors: [
      Color(0xFFFFE8B2),
      Color(0xFFEBBA67),
      Color(0xFFCB933F),
      Color(0xFFA06A27),
    ],
    stops: [0, 0.38, 0.78, 1],
  ).createShader(const Rect.fromLTRB(40, 50, 160, 186));

  static final Shader _sideShader = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF93601F), Color(0xFF5A370C)],
  ).createShader(const Rect.fromLTRB(47, 57, 167, 193));

  static final Shader _navyShader = const LinearGradient(
    colors: [Color(0xFF2E6197), Color(0xFF0F2D50), Color(0xFF050F1D)],
    stops: [0, 0.45, 1],
  ).createShader(const Rect.fromLTRB(140, 40, 170, 200));

  static final Shader _bandShader = const LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [Color(0xFFB07A2F), Color(0xFFF3CF86), Color(0xFFD9A44C)],
    stops: [0, 0.5, 1],
  ).createShader(const Rect.fromLTRB(78, 68, 172, 204));

  static final Shader _bottomShader = const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x005A370C), Color(0x615A370C)],
    stops: [0.55, 1],
  ).createShader(const Rect.fromLTWH(30, 40, 140, 160));

  static final Shader _pinShader = const RadialGradient(
    center: Alignment(-0.32, -0.48),
    radius: 0.85,
    colors: [Color(0xFFFFF0C8), Color(0xFFE5B05A), Color(0xFF94621F)],
    stops: [0, 0.45, 1],
  ).createShader(const Rect.fromLTRB(84, 4, 116, 44));

  @override
  bool shouldRepaint(covariant _MimoPainter oldDelegate) =>
      oldDelegate.frame != frame;
}

/// Minimal SVG path-data parser (M L H V C Q A Z, absolute and relative,
/// with implicit command repetition) — enough for the mascot artwork.
@visibleForTesting
Path svgPath(String d) {
  final tokens = RegExp(
    r'[MmLlHhVvCcQqAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  ).allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0;
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (isCmd(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd == 'M') {
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        cx = ox + n();
        cy = oy + n();
        sx = cx;
        sy = cy;
        path.moveTo(cx, cy);
      case 'L':
        cx = ox + n();
        cy = oy + n();
        path.lineTo(cx, cy);
      case 'H':
        cx = ox + n();
        path.lineTo(cx, cy);
      case 'V':
        cy = oy + n();
        path.lineTo(cx, cy);
      case 'C':
        final x1 = ox + n(), y1 = oy + n(), x2 = ox + n(), y2 = oy + n();
        cx = ox + n();
        cy = oy + n();
        path.cubicTo(x1, y1, x2, y2, cx, cy);
      case 'Q':
        final x1 = ox + n(), y1 = oy + n();
        cx = ox + n();
        cy = oy + n();
        path.quadraticBezierTo(x1, y1, cx, cy);
      case 'A':
        final rx = n(), ry = n(), rot = n(), large = n(), sweep = n();
        cx = ox + n();
        cy = oy + n();
        path.arcToPoint(
          Offset(cx, cy),
          radius: Radius.elliptical(rx, ry),
          rotation: rot,
          largeArc: large != 0,
          clockwise: sweep != 0,
        );
      case 'Z':
        path.close();
        cx = sx;
        cy = sy;
      default:
        i++;
    }
  }
  return path;
}
