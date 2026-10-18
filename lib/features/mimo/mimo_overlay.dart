import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n/locale_text.dart';
import '../../core/settings/app_settings_controller.dart';
import '../orders/models/order_model.dart';
import '../orders/state/cart_controller.dart';
import '../orders/state/orders_controller.dart';
import 'chat/mimo_chat_api.dart';
import 'chat/mimo_chat_controller.dart';
import 'brain/mimo_offline_brain.dart';
import 'chat/mimo_chat_sheet.dart';
import 'guide/mimo_target.dart';
import 'mimo_character.dart';
import 'mimo_navigation.dart';
import 'mimo_perch.dart';
import 'mimo_typewriter_text.dart';
import 'mimo_voice.dart';

/// What Mimo is doing right now.
@visibleForTesting
enum MimoMode {
  off,

  /// Dropping in from the top after being switched on.
  entering,
  seated,

  /// Half-hidden at the left screen edge (no home perch on this screen).
  peeking,

  /// Jumping between two spots.
  hopping,

  /// Hanging from the user's finger.
  dragging,
  falling,
  climbing,

  /// Waving goodbye after being switched off.
  leaving,

  /// Walking the user through the app (guided tour).
  guiding,
}

/// Lives above [child] (the customer shell) and hosts Mimo: he sits on
/// perches/cards, peeks from the edge, can be carried with a long press,
/// swings and gets dizzy, falls with gravity onto the next card (or the floor
/// and then climbs back up), and goes home after playing.
class MimoOverlay extends ConsumerStatefulWidget {
  const MimoOverlay({
    super.key,
    required this.child,
    this.openChat = showMimoChat,
  });

  final Widget child;

  /// What a tap on Mimo opens (null = just a playful reaction).
  final Future<void> Function(BuildContext context)? openChat;

  static const double width = 58;
  static const double height = 62;

  @override
  ConsumerState<MimoOverlay> createState() => MimoOverlayState();
}

class _Seat {
  _Seat(this.box, this.localX, {this.perch});

  final RenderBox box;
  final double localX;
  final MimoPerchState? perch;
}

@visibleForTesting
class MimoOverlayState extends ConsumerState<MimoOverlay>
    with SingleTickerProviderStateMixin
    implements MimoGuideHost {
  static const _w = MimoOverlay.width;
  static const _h = MimoOverlay.height;

  /// Body bottom line inside the box (the legs dangle below it).
  static const _sitLine = _h * 0.935;

  /// Where his hands grip the finger, inside the box.
  static const _grip = Offset(_w / 2, _h * 0.2);
  static const _gravity = 2600.0;

  final _childKey = GlobalKey();
  final _rand = math.Random();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  MimoMode _mode = MimoMode.off;
  Offset _pos = Offset.zero;
  double _angle = 0;
  double _angVel = 0;
  Offset _vel = Offset.zero;
  double _opacity = 1;
  double _squash = 0;

  _Seat? _seat;
  double _sinceCheck = 0;
  double _seatedFor = 0;
  bool _placedByUser = false;

  // Hop.
  Offset _hopFrom = Offset.zero;
  Offset _hopTo = Offset.zero;
  double _hopT = 0;
  double _hopAngleFrom = 0;
  double _hopAngleTo = 0;
  _Seat? _hopSeat;
  bool _hopToPeek = false;

  // Falling / climbing targets (feet line, overlay coords).
  double _landY = 0;
  _Seat? _landSeat;
  bool _landingOnFloor = false;
  double _climbToY = 0;
  _Seat? _climbSeat;

  // Dragging.
  Offset _finger = Offset.zero;
  Offset _fingerVel = Offset.zero;
  double _fingerAccX = 0;
  double _dizzy = 0;
  bool _saidDizzy = false;
  double _nextQuipAt = 0;

  // Mood & speech.
  MimoMood _mood = MimoMood.idle;
  MimoMood? _moodOverride;
  Timer? _moodTimer;
  String? _bubble;
  Timer? _bubbleTimer;

  /// When set, the current bubble is tappable (a proactive suggestion).
  VoidCallback? _bubbleTap;
  int _shakeTick = 0;
  double _clock = 0;
  double _lastInteraction = 0;
  double _nextGlanceAt = 14;
  bool _greetedChecked = false;

  bool get _animate =>
      ref.read(appSettingsControllerProvider).animationsEnabled &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @visibleForTesting
  MimoMode get mode => _mode;
  @visibleForTesting
  Offset get position => _pos;
  @visibleForTesting
  MimoMood get mood => _moodOverride ?? _mood;
  @visibleForTesting
  String? get bubble => _bubble;
  @visibleForTesting
  bool get bubbleTappable => _bubbleTap != null;

  @override
  void initState() {
    super.initState();
    MimoGuide.host = this;
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(appSettingsControllerProvider).mimoEnabled) _enter();
    });
  }

  final List<Timer> _timers = [];

  void _after(Duration d, VoidCallback fn) {
    _timers.removeWhere((t) => !t.isActive);
    _timers.add(Timer(d, fn));
  }

  @override
  void dispose() {
    if (MimoGuide.host == this) MimoGuide.host = null;
    _guideArrived?.complete();
    for (final t in _timers) {
      t.cancel();
    }
    _ticker.dispose();
    _moodTimer?.cancel();
    _bubbleTimer?.cancel();
    _cartIdleTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Geometry
  // ---------------------------------------------------------------------------

  RenderBox? get _overlayBox {
    final ro = context.findRenderObject();
    return ro is RenderBox && ro.hasSize ? ro : null;
  }

  RenderBox? get _childBox {
    final ro = _childKey.currentContext?.findRenderObject();
    return ro is RenderBox && ro.hasSize ? ro : null;
  }

  Size get _size => _overlayBox?.size ?? Size.zero;
  EdgeInsets get _pad => MediaQuery.paddingOf(context);
  double get _floorY => _size.height - _pad.bottom - 6;

  Offset _seatPos(Offset topEdge) =>
      Offset(topEdge.dx - _w / 2, topEdge.dy - _sitLine + 2);

  double get _feetY => _pos.dy + _sitLine;

  Offset _peekPos() => Offset(-_w * 0.4, _size.height * 0.58);

  /// Global top-edge point of a seat, in overlay coordinates.
  Offset? _seatTop(_Seat seat) {
    final overlay = _overlayBox;
    if (overlay == null || !seat.box.attached || !seat.box.hasSize) {
      return null;
    }
    final global = seat.box.localToGlobal(Offset(seat.localX, 0));
    return overlay.globalToLocal(global);
  }

  /// Is the seat's top edge really visible (not under another route, not
  /// scrolled away)?
  bool _seatVisible(_Seat seat) {
    final top = _seatTop(seat);
    if (top == null) return false;
    if (top.dy < _pad.top + 24 || top.dy > _floorY - 8) return false;
    if (seat.perch != null && !seat.perch!.isShowing) return false;
    final hits = _hitPath(Offset(top.dx, top.dy + 3));
    return hits.contains(seat.box);
  }

  List<RenderBox> _hitPath(Offset overlayPoint) {
    final child = _childBox;
    final overlay = _overlayBox;
    if (child == null || overlay == null) return const [];
    final result = BoxHitTestResult();
    final local = child.globalToLocal(overlay.localToGlobal(overlayPoint));
    child.hitTest(result, position: local);
    return [
      for (final e in result.path)
        if (e.target is RenderBox) e.target as RenderBox,
    ];
  }

  bool _cardLike(RenderBox box) {
    final s = box.size;
    if (s.width < 90 || s.height < 36) return false;
    if (s.height > _size.height * 0.75) return false;
    if (box is RenderPhysicalModel || box is RenderPhysicalShape) return true;
    if (box is RenderDecoratedBox) {
      final d = box.decoration;
      if (d is BoxDecoration) {
        return (d.color != null && d.color!.a > 0.05) ||
            d.border != null ||
            d.image != null ||
            d.gradient != null;
      }
      return d is ShapeDecoration;
    }
    return false;
  }

  /// First card-like top edge crossed when scanning from [fromY] towards
  /// [toY] (downwards when toY > fromY, else upwards) along [x].
  _Seat? _scanForSurface(double x, double fromY, double toY) {
    final overlay = _overlayBox;
    if (overlay == null) return null;
    const step = 6.0;
    final down = toY >= fromY;
    final minTop = _pad.top + 30;
    for (var y = fromY; down ? y <= toY : y >= toY; y += down ? step : -step) {
      for (final box in _hitPath(Offset(x, y))) {
        if (!_cardLike(box)) continue;
        final rect =
            overlay.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
        // The probe is inside the card, just below its top edge.
        final crossed = rect.top >= y - step - 0.5 && rect.top <= y + 0.5;
        if (crossed && rect.top > minTop && rect.top < _floorY - 10) {
          return _Seat(box, (x - rect.left).clamp(_w / 2, rect.width - _w / 2));
        }
      }
    }
    return null;
  }

  _Seat? _homeSeat() {
    for (final perch in MimoPerch.mounted) {
      if (!perch.isHome || !perch.isShowing) continue;
      final box = perch.box!;
      final x = (box.size.width * perch.alignX).clamp(
        _w / 2 + 2,
        box.size.width - _w / 2 - 2,
      );
      final seat = _Seat(box, x, perch: perch);
      if (_seatVisible(seat)) return seat;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Mode transitions
  // ---------------------------------------------------------------------------

  void _startTicker() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _enter() {
    _startTicker();
    final home = _homeSeat();
    final x = home != null ? _seatTop(home)!.dx : _size.width * 0.18;
    setState(() {
      _opacity = 1;
      _angle = 0;
      _pos = Offset(x - _w / 2, -_h - 20);
      _vel = Offset.zero;
      _mode = MimoMode.entering;
      _landSeat = home;
      _landY = home != null ? _seatTop(home)!.dy : _floorY;
      _landingOnFloor = home == null;
      _setMood(MimoMood.falling);
    });
    _maybeGreet();
    _after(const Duration(seconds: 9), _maybeNudge);
  }

  Future<void> _maybeGreet() async {
    if (_greetedChecked) return;
    _greetedChecked = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('mimo_greeted_v1') == true) return;
      await prefs.setBool('mimo_greeted_v1', true);
    } catch (_) {
      return;
    }
    _after(const Duration(milliseconds: 1400), () {
      if (!mounted || _mode == MimoMode.off) return;
      _react(
        MimoMood.waving,
        context.lt(
          ar: 'هلا! اني ميمو. اضغطني مطوّل وشيلني وين ما تريد',
          en: "Hi! I'm Mimo. Long-press to carry me anywhere",
        ),
        seconds: 4,
      );
    });
  }

  void _leave() {
    _react(MimoMood.waving, context.lt(ar: 'باي!', en: 'Bye!'), seconds: 1);
    setState(() => _mode = MimoMode.leaving);
  }

  void _goHome() {
    final home = _homeSeat();
    if (home != null) {
      _hopToTarget(_seatPos(_seatTop(home)!), seat: home);
    } else if (_mode != MimoMode.peeking) {
      _hopToTarget(_peekPos(), peek: true);
    }
  }

  void _hopToTarget(Offset target, {_Seat? seat, bool peek = false}) {
    setState(() {
      _hopFrom = _pos;
      _hopTo = target;
      _hopT = _animate ? 0 : 1;
      _hopAngleFrom = _angle;
      _hopAngleTo = peek ? 0.32 : 0;
      _hopSeat = seat;
      _hopToPeek = peek;
      _seat = null;
      _mode = MimoMode.hopping;
      if (_moodOverride == null) _mood = MimoMood.happy;
    });
  }

  void _sitOn(_Seat seat, {bool byUser = false}) {
    final top = _seatTop(seat);
    if (top == null) {
      _goHome();
      return;
    }
    setState(() {
      _seat = seat;
      _pos = _seatPos(top);
      _angle = 0;
      _mode = MimoMode.seated;
      _seatedFor = 0;
      _placedByUser = byUser;
      _squash = _animate ? 1 : 0;
      _mood = MimoMood.idle;
    });
  }

  void _peek() {
    setState(() {
      _seat = null;
      _pos = _peekPos();
      _angle = 0.32;
      _mode = MimoMode.peeking;
      _mood = MimoMood.curious;
    });
  }

  void _startFall({Offset velocity = Offset.zero}) {
    final x = _pos.dx + _w / 2;
    final surface = _scanForSurface(
      x.clamp(4, _size.width - 4),
      _feetY + 2,
      _floorY,
    );
    setState(() {
      _vel = Offset(
        velocity.dx.clamp(-900, 900),
        velocity.dy.clamp(-900, 1200),
      );
      _landSeat = surface;
      _landY = surface != null ? _seatTop(surface)!.dy : _floorY;
      _landingOnFloor = surface == null;
      _mode = MimoMode.falling;
      _seat = null;
    });
    if (!_animate) _land();
  }

  void _land() {
    _vel = Offset.zero;
    _angVel = 0;
    final dizzy = _dizzy > 1;
    if (_landingOnFloor) {
      setState(() {
        _pos = Offset(_pos.dx, _floorY - _sitLine);
        _angle = 0;
        _squash = _animate ? 1 : 0;
      });
      HapticFeedback.lightImpact();
      _shakeTick++;
      _react(
        dizzy ? MimoMood.dizzy : MimoMood.sad,
        context.lt(ar: 'آخ! وقعت', en: 'Ouch! I fell'),
        seconds: 1,
      );
      _after(const Duration(milliseconds: 900), () {
        if (mounted && _mode == MimoMode.falling) _startClimb();
      });
      return;
    }
    final seat = _landSeat!;
    _sitOn(seat, byUser: _mode == MimoMode.falling);
    HapticFeedback.selectionClick();
    if (dizzy) {
      _react(
        MimoMood.dizzy,
        context.lt(
          ar: 'الدنيا تدور... ههههه',
          en: 'The world is spinning... haha',
        ),
        seconds: 2,
      );
    } else if (_mode == MimoMode.seated && _placedByUser) {
      _react(MimoMood.happy, null, seconds: 1);
    }
    _dizzy = 0;
  }

  void _startClimb() {
    final x = (_pos.dx + _w / 2).clamp(4.0, _size.width - 4);
    final target = _scanForSurface(x, _floorY - 30, _pad.top + 60);
    if (target == null) {
      _goHome();
      return;
    }
    setState(() {
      _climbSeat = target;
      _climbToY = _seatTop(target)!.dy;
      _mode = MimoMode.climbing;
      _mood = MimoMood.climbing;
    });
    _react(
      MimoMood.climbing,
      context.lt(ar: 'لحظة أصعد!', en: 'Climbing up!'),
      seconds: 1,
    );
    if (!_animate) _sitOn(target, byUser: true);
  }

  // ---------------------------------------------------------------------------
  // Mood & speech
  // ---------------------------------------------------------------------------

  void _setMood(MimoMood mood) => _mood = mood;

  /// A short reaction: [mood] (and optionally a speech bubble) for a while.
  void _react(
    MimoMood mood,
    String? text, {
    double seconds = 1.6,
    VoidCallback? onTap,
  }) {
    if (!mounted) return;
    _moodTimer?.cancel();
    setState(() {
      _moodOverride = mood;
      if (text != null) {
        _bubble = mimoLisp(text);
        _bubbleTap = onTap;
      }
    });
    final d = Duration(milliseconds: (seconds * 1000).round());
    _moodTimer = Timer(d, () {
      if (mounted) setState(() => _moodOverride = null);
    });
    if (text != null) {
      _bubbleTimer?.cancel();
      _bubbleTimer = Timer(d + const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _bubble = null;
            _bubbleTap = null;
          });
        }
      });
    }
  }

  void _tapBubble() {
    final tap = _bubbleTap;
    if (tap == null) return;
    HapticFeedback.selectionClick();
    _bubbleTimer?.cancel();
    setState(() {
      _bubble = null;
      _bubbleTap = null;
    });
    tap();
  }

  void _touch() => _lastInteraction = _clock;

  // ---------------------------------------------------------------------------
  // Gestures
  // ---------------------------------------------------------------------------

  /// One tap: Mimo waves and opens his chat.
  void _onTap() {
    _touch();
    if (_mode != MimoMode.seated && _mode != MimoMode.peeking) return;
    _react(MimoMood.waving, null, seconds: 0.8);
    if (widget.openChat != null) {
      widget.openChat!(context);
      return;
    }
    _playfulReaction();
  }

  void _playfulReaction() {
    final options = <(MimoMood, String)>[
      (MimoMood.waving, context.lt(ar: 'هلا!', en: 'Hi!')),
      (MimoMood.wink, context.lt(ar: 'شلونك؟', en: "How's it going?")),
      (MimoMood.dancing, context.lt(ar: 'لا لا لا!', en: 'La la la!')),
      (MimoMood.laughing, context.lt(ar: 'تدغدغني!', en: 'That tickles!')),
    ];
    final pick = options[_rand.nextInt(options.length)];
    _react(pick.$1, pick.$2, seconds: 1.8);
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (_mode == MimoMode.off || _mode == MimoMode.leaving) return;
    _touch();
    HapticFeedback.mediumImpact();
    final local = _overlayBox!.globalToLocal(d.globalPosition);
    setState(() {
      _finger = local;
      _fingerVel = Offset.zero;
      _fingerAccX = 0;
      _mode = MimoMode.dragging;
      _seat = null;
      _angVel = 0;
      _dizzy = 0;
      _saidDizzy = false;
      _nextQuipAt = _clock + 0.6;
      _pos = local - _grip;
    });
    _react(
      MimoMood.laughing,
      context.lt(ar: 'وييي!', en: 'Wheee!'),
      seconds: 1,
    );
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (_mode != MimoMode.dragging) return;
    _finger = _overlayBox!.globalToLocal(d.globalPosition);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    if (_mode != MimoMode.dragging) return;
    _touch();
    _startFall(velocity: d.velocity.pixelsPerSecond * 0.35);
    if (_dizzy <= 1) {
      _react(MimoMood.falling, null, seconds: 0.6);
    }
  }

  // ---------------------------------------------------------------------------
  // Frame loop
  // ---------------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    _clock += dt;
    if (!mounted || _size == Size.zero) return;

    // Mimo's painter owns breathing, blinking and pose animation. The overlay
    // only needs a widget rebuild when his position or visible state changes.
    // This keeps a seated Mimo from rebuilding the whole shell every frame.
    final previousMode = _mode;
    final previousPosition = _pos;
    final previousAngle = _angle;
    final previousOpacity = _opacity;
    final previousSquash = _squash;
    final previousMood = _mood;
    if (_squash > 0) _squash = math.max(0, _squash - dt * 5);

    switch (_mode) {
      case MimoMode.off:
        _ticker.stop();
        return;
      case MimoMode.entering:
        _vel = Offset(0, _vel.dy + _gravity * dt);
        _pos += _vel * dt;
        if (_feetY >= _landY) {
          if (_landSeat != null) {
            _sitOn(_landSeat!);
            _react(MimoMood.happy, null, seconds: 0.8);
          } else {
            _peek();
          }
          return;
        }
      case MimoMode.leaving:
        _opacity = math.max(0, _opacity - dt * 1.4);
        if (_opacity == 0) {
          setState(() => _mode = MimoMode.off);
          return;
        }
      case MimoMode.seated:
        _tickSeated(dt);
      case MimoMode.peeking:
        _sinceCheck += dt;
        if (_sinceCheck > 0.5) {
          _sinceCheck = 0;
          if (_homeSeat() != null) _goHome();
        }
        _tickIdle();
      case MimoMode.hopping:
        _hopT = math.min(1, _hopT + dt / 0.55);
        final e = Curves.easeInOut.transform(_hopT);
        final arc = math.sin(_hopT * math.pi) * 46;
        _pos = Offset.lerp(_hopFrom, _hopTo, e)! - Offset(0, arc);
        _angle = _hopAngleFrom + (_hopAngleTo - _hopAngleFrom) * e;
        if (_hopT >= 1) {
          if (_hopToPeek) {
            _peek();
          } else if (_hopSeat != null) {
            _sitOn(_hopSeat!);
          }
          return;
        }
      case MimoMode.guiding:
        if (_guideT < 1) {
          _guideT = math.min(1, _guideT + dt / _guideSeconds);
          final e = Curves.easeOutCubic.transform(_guideT);
          final arc = math.sin(_guideT * math.pi) * 28;
          _pos = Offset.lerp(_guideFrom, _guideTo, e)! - Offset(0, arc);
          _angle += (-_angle) * math.min(1, dt * 10);
          if (_guideT >= 1) {
            _squash = _animate ? 0.6 : 0;
            final done = _guideArrived;
            _guideArrived = null;
            done?.complete();
          }
        }
      case MimoMode.dragging:
        _tickDrag(dt);
      case MimoMode.falling:
        if (_landingOnFloor && _feetY >= _floorY - 0.5 && _vel == Offset.zero) {
          break; // Sitting on the floor, waiting to climb.
        }
        _vel = Offset(_vel.dx * (1 - dt * 1.5), _vel.dy + _gravity * dt);
        _pos += _vel * dt;
        _pos = Offset(
          _pos.dx.clamp(-_w * 0.2, _size.width - _w * 0.8),
          _pos.dy,
        );
        _angle += (-_angle) * math.min(1, dt * 5);
        if (_vel.dy > 0 && _feetY >= _landY) {
          _land();
          return;
        }
      case MimoMode.climbing:
        _pos = Offset(_pos.dx, _pos.dy - 170 * dt);
        if (_feetY <= _climbToY) {
          final seat = _climbSeat!;
          _sitOn(seat, byUser: true);
          _react(
            MimoMood.happy,
            context.lt(ar: 'وصلت!', en: 'Made it!'),
            seconds: 1.2,
          );
          return;
        }
    }
    final visualChanged =
        previousMode != _mode ||
        previousPosition != _pos ||
        previousAngle != _angle ||
        previousOpacity != _opacity ||
        previousSquash != _squash ||
        previousMood != _mood;
    if (visualChanged) setState(() {});
  }

  void _tickSeated(double dt) {
    final seat = _seat;
    if (seat == null) return;
    final top = _seatTop(seat);
    if (top == null) {
      _goHome();
      return;
    }
    _pos = _seatPos(top);
    _seatedFor += dt;
    _sinceCheck += dt;
    if (_sinceCheck > 0.35) {
      _sinceCheck = 0;
      if (!_seatVisible(seat)) {
        _goHome();
        return;
      }
    }
    // After playing he wanders back home on his own.
    if (_placedByUser && seat.perch?.isHome != true && _seatedFor > 10) {
      _placedByUser = false;
      _goHome();
      return;
    }
    _tickIdle();
  }

  void _tickIdle() {
    final idleFor = _clock - _lastInteraction;
    if (_moodOverride != null) return;
    if (idleFor > 35) {
      _mood = MimoMood.sleepy;
    } else if (_clock >= _nextGlanceAt) {
      _nextGlanceAt = _clock + 14 + _rand.nextDouble() * 12;
      _react(MimoMood.curious, null, seconds: 1.4);
    } else if (_mode == MimoMode.seated) {
      _mood = MimoMood.idle;
    }
  }

  void _tickDrag(double dt) {
    final prevFinger = _pos + _grip;
    final fv = dt > 0 ? (_finger - prevFinger) / dt : Offset.zero;
    final ax = dt > 0 ? (fv.dx - _fingerVel.dx) / dt : 0.0;
    _fingerAccX += (ax - _fingerAccX) * 0.3;
    _fingerVel = fv;
    _pos = _finger - _grip;

    if (_animate) {
      // Pendulum hanging from the finger.
      const length = _h * 0.55;
      final acc =
          -(_gravity / length) * math.sin(_angle) -
          2.2 * _angVel -
          (_fingerAccX / length) * math.cos(_angle) * 0.6;
      _angVel = (_angVel + acc * dt).clamp(-24.0, 24.0);
      _angle = (_angle + _angVel * dt).clamp(-1.5, 1.5);
      _dizzy = math.max(0, _dizzy + _angVel.abs() * dt * 0.09 - dt * 0.12);
    }

    if (_dizzy > 1 && !_saidDizzy) {
      _saidDizzy = true;
      HapticFeedback.lightImpact();
      _react(
        MimoMood.dizzy,
        context.lt(ar: 'دخت! ههههههه', en: "I'm dizzy! hahaha"),
        seconds: 2,
      );
      _nextQuipAt = _clock + 3;
    } else if (_clock >= _nextQuipAt && fv.distance > 700) {
      _nextQuipAt = _clock + 2.4;
      final quips = [
        context.lt(ar: 'بعد! بعد!', en: 'More! More!'),
        context.lt(ar: 'ويييييي!', en: 'Wheeeee!'),
        context.lt(ar: 'ههههههه', en: 'Hahaha'),
      ];
      _react(
        _dizzy > 0.6 ? MimoMood.dizzy : MimoMood.laughing,
        quips[_rand.nextInt(quips.length)],
        seconds: 1.4,
      );
    } else if (_moodOverride == null) {
      _mood = _dizzy > 0.8 ? MimoMood.dizzy : MimoMood.laughing;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Cart reactions
  // ---------------------------------------------------------------------------

  int _maxStoresCommented = 1;
  bool _bigCartCommented = false;

  void _onCartChanged(CartState? prev, CartState next) {
    _watchForgottenCart(next);
    if (_mode == MimoMode.off || _mode == MimoMode.dragging) return;
    final before = prev?.totalItems ?? 0;
    final after = next.totalItems;
    final stores = next.storeIds.length;
    if (after == 0) {
      if (before > 0) {
        _bigCartCommented = false;
        _maxStoresCommented = 1;
        _react(
          MimoMood.sad,
          context.lt(ar: 'فرغت السلة؟ 🥲', en: 'Empty cart? 🥲'),
          seconds: 1.6,
        );
      }
      return;
    }
    if (after <= before) return;
    final bigJump = after - before >= 5;
    if ((after >= 8 && !_bigCartCommented) || bigJump) {
      _bigCartCommented = true;
      _react(
        MimoMood.shocked,
        context.lt(
          ar: 'واو! وحدك راح تاكل كل هذا!!!!!',
          en: 'Wow! Are you eating ALL of this alone?!',
        ),
        seconds: 1.4,
      );
      _shakeTick++;
      _after(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        _react(
          MimoMood.laughing,
          context.lt(ar: 'بالعافية! ههههه', en: 'Enjoy! hahaha'),
          seconds: 1.8,
        );
      });
      return;
    }
    if (stores > _maxStoresCommented && stores >= 2) {
      _maxStoresCommented = stores;
      _react(
        MimoMood.wink,
        context.lt(
          ar: 'تعرف؟ بس مسلكي عنده هاي الخدمة: تطلب من كذا محل بطلب واحد!',
          en: 'Fun fact: only Maslaki lets you order from several stores in one go!',
        ),
        seconds: 3,
      );
      return;
    }
    _react(MimoMood.yummy, null, seconds: 1);
  }

  // ---------------------------------------------------------------------------
  // Guided tour: Mimo walks to a section, taps it, scrolls to a store, reads
  // its name and opens it — all from the app's own screens, no AI.
  // ---------------------------------------------------------------------------

  bool _touring = false;
  Offset _guideFrom = Offset.zero;
  Offset _guideTo = Offset.zero;
  double _guideT = 1;
  Completer<void>? _guideArrived;
  Offset? _ripple;
  int _rippleId = 0;

  /// Fast on purpose: the whole tour should feel instant.
  double get _guideSeconds => 0.3;

  @visibleForTesting
  bool get touring => _touring;

  Rect get _screen {
    final box = _overlayBox;
    if (box == null) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  bool _comfortablyVisible(Rect r) {
    final s = _screen;
    final top = s.top + _pad.top + 8;
    final bottom = s.bottom - _pad.bottom - 70;
    return r.height > 0 && r.top >= top - 1 && r.bottom <= bottom + 1;
  }

  @override
  Future<bool> runTour(List<MimoTourStep> steps) async {
    if (_touring || !mounted) return false;
    final settings = ref.read(appSettingsControllerProvider);
    if (!settings.mimoEnabled ||
        _mode == MimoMode.off ||
        _mode == MimoMode.leaving ||
        _mode == MimoMode.dragging) {
      return false;
    }
    _touring = true;
    _touch();
    var ok = false;
    try {
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        if (step.say != null) {
          _react(MimoMood.happy, step.say, seconds: 1.4);
        }
        final target = await _seek(step.targetId);
        if (target == null || !mounted || _mode == MimoMode.dragging) {
          return false;
        }
        await _walkTo(target);
        if (!mounted || !target.mounted) return false;
        final expected = step.expectName;
        if (expected != null) {
          final label = target.label ?? '';
          if (!mimoSameName(label, expected)) {
            _react(
              MimoMood.shocked,
              context.lt(
                ar: 'مو هذا! هذا «$label» مو «$expected»',
                en: "That's «$label», not «$expected»",
              ),
              seconds: 2,
            );
            return false;
          }
          _react(
            MimoMood.happy,
            context.lt(ar: 'إي هذا «$label» ✅', en: "Yes, that's «$label» ✅"),
            seconds: 0.9,
          );
          await Future<void>.delayed(
            Duration(milliseconds: _animate ? 220 : 0),
          );
          if (!mounted || !target.mounted) return false;
        }
        await _pressOn(target);
        if (!mounted || !target.mounted) return false;
        target.tap();
        // Let the next screen start building.
        await Future<void>.delayed(Duration(milliseconds: _animate ? 240 : 16));
      }
      if (!mounted) return false;
      ok = true;
      _react(
        MimoMood.dancing,
        context.lt(ar: 'وصلنا! 🎉', en: "We're here! 🎉"),
        seconds: 1.4,
      );
      return true;
    } finally {
      _touring = false;
      _after(Duration(milliseconds: ok ? 1300 : 600), () {
        if (mounted && _mode == MimoMode.guiding) _goHome();
      });
    }
  }

  /// Finds the target, scrolling its list down when it isn't on screen yet.
  Future<MimoTargetState?> _seek(String id) async {
    // Budget counted from our own waits (works with paused/fake clocks too).
    var spentMs = 0;
    const budgetMs = 6000;
    final prefix = '${id.split(':').first}:';
    var said = false;
    var waited = 0;
    while (mounted && spentMs < budgetMs) {
      final t = MimoTargets.find(id, screen: _screen);
      final rect = t?.globalRect;
      if (t != null && rect != null) {
        if (_comfortablyVisible(rect)) return t;
        // Built but off-screen: bring it into view.
        final targetContext = t.context;
        if (!targetContext.mounted) continue;
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.35,
          duration: Duration(milliseconds: _animate ? 320 : 0),
          curve: Curves.easeOutCubic,
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));
        spentMs += 360;
        final again = t.globalRect;
        if (again != null && t.mounted) return t;
        continue;
      }
      // Not built yet: scroll the list its siblings live in.
      final sibling = MimoTargets.anyWithPrefix(prefix);
      final siblingContext = sibling?.context;
      final scrollable = siblingContext == null || !siblingContext.mounted
          ? null
          : Scrollable.maybeOf(siblingContext);
      final position = scrollable?.position;
      if (position != null &&
          waited >= 300 &&
          position.hasContentDimensions &&
          position.pixels < position.maxScrollExtent - 1) {
        if (!said && mounted) {
          said = true;
          _react(
            MimoMood.curious,
            context.lt(ar: 'لحظة أدوره… ⬇️', en: 'Looking for it… ⬇️'),
            seconds: 1.2,
          );
        }
        final next = math.min(
          position.maxScrollExtent,
          position.pixels + position.viewportDimension * 0.8,
        );
        if (_animate) {
          await position.animateTo(
            next,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
          );
        } else {
          position.jumpTo(next);
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
        spentMs += 290;
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      waited += 60;
      spentMs += 60;
    }
    return null;
  }

  /// Hops to just above [target] (fast).
  Future<void> _walkTo(MimoTargetState target) async {
    final box = _overlayBox;
    final rect = target.globalRect;
    if (box == null || rect == null) return;
    final local = box.globalToLocal(rect.topCenter);
    final size = _size;
    final dest = Offset(
      (local.dx - _w / 2).clamp(4.0, size.width - _w - 4),
      (local.dy - _h * 0.72).clamp(_pad.top, size.height - _h - _pad.bottom),
    );
    _guideArrived?.complete();
    final arrived = Completer<void>();
    setState(() {
      _seat = null;
      _guideFrom = _pos;
      _guideTo = dest;
      _guideT = _animate ? 0 : 1;
      _mode = MimoMode.guiding;
      _moodOverride ??= MimoMood.happy;
      if (!_animate) _pos = dest;
    });
    if (!_animate) return;
    _guideArrived = arrived;
    if (!_ticker.isActive) _ticker.start();
    await arrived.future.timeout(
      const Duration(milliseconds: 900),
      onTimeout: () {},
    );
  }

  /// Presses the target: a little squash, a ripple and a haptic tick.
  Future<void> _pressOn(MimoTargetState target) async {
    final box = _overlayBox;
    final rect = target.globalRect;
    HapticFeedback.selectionClick();
    if (box != null && rect != null) {
      setState(() {
        _ripple = box.globalToLocal(rect.center);
        _rippleId++;
        _squash = _animate ? 1 : 0;
      });
    }
    await Future<void>.delayed(Duration(milliseconds: _animate ? 170 : 0));
    _after(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _ripple = null);
    });
  }

  // ---------------------------------------------------------------------------
  // Proactive ("ميمو يبادر"): order updates, a daily tip, a forgotten cart.
  // ---------------------------------------------------------------------------

  bool get _canSpeakUp {
    final s = ref.read(appSettingsControllerProvider);
    return s.mimoEnabled &&
        s.mimoProactive &&
        _mode != MimoMode.off &&
        _mode != MimoMode.leaving &&
        _mode != MimoMode.dragging;
  }

  Map<int, String>? _orderStatus;

  /// Reacts when one of the user's orders moves to a new status.
  void _onOrdersChanged(OrdersState? prev, OrdersState next) {
    final known = _orderStatus ??= {
      for (final o in prev?.orders ?? const <OrderModel>[]) o.id: o.status,
    };
    OrderModel? changed;
    for (final o in next.orders) {
      final before = known[o.id];
      known[o.id] = o.status;
      if (before != null && before != o.status) changed = o;
    }
    if (changed == null || !_canSpeakUp) return;
    final line = mimoOrderStatusLine(
      changed.status,
      changed.merchantName,
      ar: ref.read(appSettingsControllerProvider).locale.languageCode != 'en',
    );
    if (line == null) return;
    final (mood, text) = line;
    final cancelled = changed.status.startsWith('cancelled');
    _react(
      mood,
      text,
      seconds: 4,
      onTap: cancelled ? () => widget.openChat?.call(context) : null,
    );
    if (mood == MimoMood.dancing || mood == MimoMood.love) _shakeTick++;
  }

  Timer? _cartIdleTimer;
  bool _cartReminded = false;

  /// After a few idle minutes with items in the cart, Mimo reminds once.
  void _watchForgottenCart(CartState cart) {
    _cartIdleTimer?.cancel();
    if (cart.totalItems == 0) {
      _cartReminded = false;
      return;
    }
    if (_cartReminded) return;
    _cartIdleTimer = Timer(mimoForgottenCartDelay, () {
      if (!mounted || !_canSpeakUp) return;
      final items = ref.read(cartControllerProvider).totalItems;
      if (items == 0) return;
      _cartReminded = true;
      _react(
        MimoMood.curious,
        context.lt(
          ar: 'نسيت السلة؟ بيها $items غرض ينتظرونك 👀 اضغطني',
          en: 'Forgot your cart? $items items are waiting 👀 tap me',
        ),
        seconds: 6,
        onTap: () => MimoNavigation.open(const MimoNavRequest.section('cart')),
      );
    });
  }

  bool _nudgeChecked = false;

  /// One server-picked tip per day (habit / expiring coupon / meal time).
  Future<void> _maybeNudge() async {
    if (_nudgeChecked || !mounted || !_canSpeakUp) return;
    _nudgeChecked = true;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (prefs.getString('mimo_nudge_day') == today) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final api = ref.read(mimoChatApiProvider);
    final lang = ref.read(appSettingsControllerProvider).locale.languageCode;
    final nudge = await api.nudge(lang);
    if (nudge == null || !mounted || !_canSpeakUp || _bubble != null) return;
    final text = '${nudge['text'] ?? ''}'.trim();
    if (text.isEmpty) return;
    await prefs.setString('mimo_nudge_day', today);
    if (!mounted) return;
    final id = '${nudge['id'] ?? ''}';
    final kind = '${nudge['kind'] ?? ''}';
    api.proactiveEvent(nudgeId: id, event: 'shown', kind: kind);
    final action = nudge['action'] is Map
        ? Map<String, dynamic>.from(nudge['action'] as Map)
        : const <String, dynamic>{};
    _react(
      MimoMood.values.asNameMap()['${nudge['mood']}'] ?? MimoMood.happy,
      text,
      seconds: 8,
      onTap: () {
        api.proactiveEvent(nudgeId: id, event: 'tapped', kind: kind);
        final section = '${action['section'] ?? ''}';
        final message = '${action['message'] ?? ''}'.trim();
        if (action['type'] == 'section' && section.isNotEmpty) {
          MimoNavigation.open(MimoNavRequest.section(section));
        } else if (message.isNotEmpty) {
          ref.read(mimoChatControllerProvider.notifier).send(message);
          widget.openChat?.call(context);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);
    final animate =
        settings.animationsEnabled &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    ref.listen<CartState>(cartControllerProvider, _onCartChanged);
    ref.listen<OrdersState>(ordersControllerProvider, _onOrdersChanged);
    ref.listen<bool>(
      appSettingsControllerProvider.select((s) => s.mimoEnabled),
      (prev, next) {
        if (next && (_mode == MimoMode.off || _mode == MimoMode.leaving)) {
          _enter();
        } else if (!next && _mode != MimoMode.off) {
          _leave();
        }
      },
    );

    final showMimo = _mode != MimoMode.off;
    final holding = _mode == MimoMode.dragging;
    final running =
        _mode == MimoMode.climbing || (_mode == MimoMode.hopping && _animate);
    final squashY = 1 - 0.18 * _squash;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        RepaintBoundary(key: _childKey, child: widget.child),
        if (showMimo)
          Positioned(
            left: _pos.dx,
            top: _pos.dy,
            width: _w,
            height: _h,
            child: Opacity(
              opacity: _opacity.clamp(0.0, 1.0),
              child: Transform(
                alignment: holding
                    ? const Alignment(0, -0.6)
                    : Alignment.bottomCenter,
                transform: Matrix4.identity()
                  ..rotateZ(_angle)
                  ..scaleByDouble(1 + 0.1 * _squash, squashY, 1, 1),
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: {
                    TapGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          TapGestureRecognizer
                        >(
                          () => TapGestureRecognizer(),
                          (r) => r.onTap = _onTap,
                        ),
                    LongPressGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          LongPressGestureRecognizer
                        >(
                          () => LongPressGestureRecognizer(
                            duration: const Duration(milliseconds: 280),
                          ),
                          (r) => r
                            ..onLongPressStart = _onLongPressStart
                            ..onLongPressMoveUpdate = _onLongPressMove
                            ..onLongPressEnd = _onLongPressEnd,
                        ),
                  },
                  child: Semantics(
                    button: true,
                    label: context.lt(
                      ar: 'ميمو. اضغط للتحية، واضغط مطوّلاً لحمله',
                      en: 'Mimo. Tap to say hi, long-press to carry him',
                    ),
                    child: MimoCharacter(
                      mood: mood,
                      sitting: true,
                      holding: holding,
                      running: running,
                      animate: animate,
                      shakeTick: _shakeTick,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_ripple != null)
          Positioned(
            left: _ripple!.dx - 28,
            top: _ripple!.dy - 28,
            width: 56,
            height: 56,
            child: IgnorePointer(
              child: _TapRipple(
                key: ValueKey(_rippleId),
                animate: settings.animationsEnabled,
              ),
            ),
          ),
        if (showMimo && _bubble != null)
          _BubbleAnchor(
            anchor: Offset(_pos.dx + _w / 2, _pos.dy - 4),
            screenWidth: _size.width,
            onTap: _bubbleTap == null ? null : _tapBubble,
            child: _MimoBubble(
              key: ValueKey(_bubble),
              text: _bubble!,
              animate: animate,
              tappable: _bubbleTap != null,
            ),
          ),
      ],
    );
  }
}

/// The ring Mimo leaves where he "taps".
class _TapRipple extends StatelessWidget {
  const _TapRipple({super.key, required this.animate});

  final bool animate;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? 0 : 1, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.4 + 0.8 * t,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x332F5E46),
              border: Border.all(color: const Color(0xFF2F5E46), width: 3),
            ),
          ),
        ),
      ),
    );
  }
}

/// Places a bubble centred above [anchor], kept inside the screen.
class _BubbleAnchor extends StatelessWidget {
  const _BubbleAnchor({
    required this.anchor,
    required this.screenWidth,
    required this.child,
    this.onTap,
  });

  final Offset anchor;
  final double screenWidth;
  final Widget child;
  final VoidCallback? onTap;

  static const _maxW = 190.0;

  @override
  Widget build(BuildContext context) {
    final width = math.min(_maxW, math.max(0.0, screenWidth - 16));
    if (width <= 0) return const SizedBox.shrink();
    final maxLeft = math.max(8.0, screenWidth - width - 8);
    final left = (anchor.dx - width / 2).clamp(8.0, maxLeft);
    final belowTop = anchor.dy < 110;
    return Positioned(
      left: left,
      width: width,
      top: belowTop ? anchor.dy + MimoOverlay.height + 10 : null,
      bottom: belowTop ? null : MediaQuery.sizeOf(context).height - anchor.dy,
      child: IgnorePointer(
        ignoring: onTap == null,
        child: Align(
          alignment: belowTop ? Alignment.topCenter : Alignment.bottomCenter,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _MimoBubble extends StatefulWidget {
  const _MimoBubble({
    super.key,
    required this.text,
    required this.animate,
    this.tappable = false,
  });

  final String text;
  final bool animate;
  final bool tappable;

  @override
  State<_MimoBubble> createState() => _MimoBubbleState();
}

class _MimoBubbleState extends State<_MimoBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _pop.forward();
    } else {
      _pop.value = 1;
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, child) => Opacity(
        opacity: Curves.easeOut.transform(_pop.value),
        child: Transform.scale(
          scale: 0.6 + 0.4 * Curves.easeOutBack.transform(_pop.value),
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD9C291)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MimoTypewriterText(
              text: widget.text,
              animate: widget.animate,
              style: const TextStyle(
                color: Color(0xFF0B2440),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
            if (widget.tappable)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.touch_app_rounded,
                  size: 16,
                  color: Color(0xFFB8893F),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// How long a non-empty cart sits untouched before Mimo reminds the user.
@visibleForTesting
Duration mimoForgottenCartDelay = const Duration(minutes: 3);

/// Mimo's line (mood + text) when an order reaches [status], or null.
@visibleForTesting
(MimoMood, String)? mimoOrderStatusLine(
  String status,
  String merchantName, {
  required bool ar,
}) {
  final name = merchantName.trim();
  final from = name.isEmpty ? '' : (ar ? ' من $name' : ' from $name');
  if (status.startsWith('cancelled')) {
    return (
      MimoMood.sad,
      ar
          ? 'انلغى طلبك$from 🥲 إذا تحتاج مساعدة اضغطني'
          : 'Your order$from was cancelled 🥲 tap me if you need help',
    );
  }
  return switch (status) {
    'approved' => (
      MimoMood.happy,
      ar
          ? 'المحل وافق على طلبك$from! 🎉'
          : 'The store accepted your order$from! 🎉',
    ),
    'preparing' => (
      MimoMood.yummy,
      ar
          ? 'طلبك$from دا يتحضر هسه 👨‍🍳'
          : 'Your order$from is being prepared 👨‍🍳',
    ),
    'courier_assigned' => (
      MimoMood.happy,
      ar ? 'انعين مندوب لطلبك وراح يجيبه 🛵' : 'A courier is on it 🛵',
    ),
    'ready_for_pickup' || 'ready_for_delivery' => (
      MimoMood.curious,
      ar
          ? 'طلبك جاهز وينتظر المندوب 📦'
          : 'Your order is ready for the courier 📦',
    ),
    'on_the_way' || 'picked_up' => (
      MimoMood.dancing,
      ar ? 'طلبك بالطريق! 🛵 حضّر نفسك' : 'Your order is on the way! 🛵',
    ),
    'arrived' => (
      MimoMood.waving,
      ar ? 'المندوب وصل! انزل استلم 🏃' : 'The courier has arrived! 🏃',
    ),
    'delivered_by_courier' => (
      MimoMood.love,
      ar
          ? 'المندوب سلّمك الطلب! بالعافية 😋 لا تنسى تأكد الاستلام'
          : 'Delivered! Enjoy 😋 please confirm you got it',
    ),
    'delivered' || 'completed' => (
      MimoMood.love,
      ar ? 'وصل طلبك! بالعافية 😋' : 'Delivered! Enjoy 😋',
    ),
    _ => null,
  };
}

/// Small header button that hides/shows Mimo.
class MimoToggleButton extends ConsumerWidget {
  const MimoToggleButton({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(
      appSettingsControllerProvider.select((s) => s.mimoEnabled),
    );
    return Tooltip(
      message: on
          ? context.lt(ar: 'إخفاء ميمو', en: 'Hide Mimo')
          : context.lt(ar: 'إظهار ميمو', en: 'Show Mimo'),
      child: Semantics(
        button: true,
        toggled: on,
        label: context.lt(ar: 'ميمو', en: 'Mimo'),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            ref
                .read(appSettingsControllerProvider.notifier)
                .setMimoEnabled(!on);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: size,
            height: size,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? const Color(0xFFF6E6D3) : const Color(0xFFE9E7E1),
              border: Border.all(
                color: on ? const Color(0xFFC9B48A) : const Color(0xFFC9C6BE),
              ),
            ),
            child: Opacity(
              opacity: on ? 1 : 0.45,
              child: MimoCharacter(
                mood: on ? MimoMood.happy : MimoMood.sleepy,
                sitting: false,
                animate: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
