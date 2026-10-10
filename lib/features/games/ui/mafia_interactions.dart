import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

const mafiaCourtyardAsset = 'assets/games/mafia/courtyard.png';
const mafiaGiftsAsset = 'assets/games/mafia/gifts.png';

class MafiaInteraction {
  final int id;
  final int sender;
  final int? target;
  final String kind;
  final String senderName;
  final String targetName;
  final DateTime? createdAt;

  MafiaInteraction.fromJson(Map<String, dynamic> event)
    : id = _number(event['id']),
      sender = _number((event['payload'] as Map?)?['senderPlayerId']),
      target = _optionalNumber((event['payload'] as Map?)?['targetPlayerId']),
      kind = '${(event['payload'] as Map?)?['kind'] ?? ''}',
      senderName = '${(event['payload'] as Map?)?['senderName'] ?? ''}',
      targetName = '${(event['payload'] as Map?)?['targetName'] ?? ''}',
      createdAt = DateTime.tryParse('${event['createdAt'] ?? ''}');

  bool get isGift => const {'egg', 'rose', 'tea'}.contains(kind);
  String get label => switch (kind) {
    'egg' => 'بيضة',
    'rose' => 'وردة',
    'tea' => 'كأس شاي',
    'laugh' => 'يضحك',
    'happy' => 'سعيد',
    'angry' => 'غاضب',
    'surprised' => 'مندهش',
    'applause' => 'تصفيق',
    'mvp' => 'نجم الجولة',
    _ => 'تفاعل',
  };
}

/// Server receipts and snapshots can arrive out of order. Deduplicate by ID,
/// not by a high watermark, so a fast local acknowledgement cannot hide peers.
class MafiaInteractionController extends ChangeNotifier {
  final _seen = <int>{};
  final _active = <int, MafiaInteraction>{};
  final _expiry = <int, Timer>{};
  bool _disposed = false;
  List<MafiaInteraction> get active => List.unmodifiable(_active.values);

  void ingest(
    Iterable<Map<String, dynamic>> events, {
    bool silent = false,
    DateTime? serverTime,
  }) {
    if (_disposed) return;
    var changed = false;
    for (final json in events) {
      if (json['type'] != 'player_interaction') continue;
      final event = MafiaInteraction.fromJson(json);
      if (event.id <= 0 || !_seen.add(event.id)) continue;
      if (_seen.length > 512) _seen.remove(_seen.first);
      if (silent ||
          event.sender <= 0 ||
          (serverTime != null &&
              event.createdAt != null &&
              serverTime.difference(event.createdAt!).inSeconds > 12)) {
        continue;
      }
      // Bounded visual work during bursts; expiry never affects server state.
      if (_active.length >= 32) _remove(_active.keys.first);
      _active[event.id] = event;
      _expiry[event.id] = Timer(const Duration(milliseconds: 2800), () {
        if (_disposed) return;
        _remove(event.id);
        notifyListeners();
      });
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _remove(int id) {
    _expiry.remove(id)?.cancel();
    _active.remove(id);
  }

  void clear() {
    for (final timer in _expiry.values) {
      timer.cancel();
    }
    _expiry.clear();
    _active.clear();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    super.dispose();
  }
}

/// The seats and effects share this geometry, including RTL and resize.
class MafiaSeatGeometry {
  final double width;
  final int count;
  final bool rtl;
  MafiaSeatGeometry({
    required this.width,
    required this.count,
    required this.rtl,
  });
  int get columns => width < 345
      ? 3
      : width < 700
      ? 4
      : 7;
  double get seatWidth => (width - (columns - 1) * 8) / columns;
  double get seatHeight => math.max(114, seatWidth / .8);
  double get height =>
      ((count + columns - 1) ~/ columns) * (seatHeight + 8) - 8;
  Rect seat(int index) {
    final column = index % columns;
    return Rect.fromLTWH(
      (rtl ? columns - 1 - column : column) * (seatWidth + 8),
      (index ~/ columns) * (seatHeight + 8),
      seatWidth,
      seatHeight,
    );
  }
}

Offset mafiaGiftPosition(Offset start, Offset end, double progress) {
  final t = progress.clamp(0.0, 1.0);
  final arc = math.min(66.0, (end - start).distance * .22);
  return Offset.lerp(start, end, t)! + Offset(0, -math.sin(t * math.pi) * arc);
}

/// Clips the original transparent atlas directly; no per-frame image decoding.
class MafiaGiftSprite extends StatelessWidget {
  final String kind;
  final double size;
  const MafiaGiftSprite({super.key, required this.kind, this.size = 64});
  @override
  Widget build(BuildContext context) {
    final alignment = switch (kind) {
      'rose' => Alignment.topRight,
      'tea' => Alignment.bottomLeft,
      'splat' => Alignment.bottomRight,
      _ => Alignment.topLeft,
    };
    return SizedBox.square(
      dimension: size,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: size * 2,
          maxHeight: size * 2,
          alignment: alignment,
          child: Image.asset(
            mafiaGiftsAsset,
            width: size * 2,
            height: size * 2,
            cacheWidth: 768,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}

class MafiaInteractionLayer extends StatelessWidget {
  final MafiaInteractionController controller;
  final Map<int, Rect> seats;
  const MafiaInteractionLayer({
    super.key,
    required this.controller,
    required this.seats,
  });

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final event in controller.active)
              if (seats.containsKey(event.sender) &&
                  (!event.isGift || seats.containsKey(event.target)))
                Positioned.fill(
                  key: ValueKey('mafia-effect-${event.id}'),
                  child: _CardInteraction(
                    event: event,
                    source: seats[event.sender]!,
                    destination: seats[event.target] ?? seats[event.sender]!,
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

class _CardInteraction extends StatefulWidget {
  final MafiaInteraction event;
  final Rect source;
  final Rect destination;
  const _CardInteraction({
    required this.event,
    required this.source,
    required this.destination,
  });
  @override
  State<_CardInteraction> createState() => _CardInteractionState();
}

class _CardInteractionState extends State<_CardInteraction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else if (!_motion.isAnimating && !_motion.isCompleted) {
      _motion.forward();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final event = widget.event;
    final label = event.isGift
        ? '${event.senderName} أرسل ${event.label} إلى ${event.targetName}'
        : '${event.senderName}: ${event.label}';
    return Semantics(
      label: label,
      liveRegion: true,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) {
          final t = reduced ? .52 : _motion.value;
          final flight = (t / .38).clamp(0.0, 1.0);
          final landing = ((t - .38) / .62).clamp(0.0, 1.0);
          final hit = reduced || flight >= 1;
          final start = widget.source.center.translate(0, -10);
          final end = widget.destination.center.translate(0, -10);
          final rawPoint = event.isGift
              ? (reduced
                    ? end
                    : mafiaGiftPosition(
                        start,
                        end,
                        Curves.easeInOut.transform(flight),
                      ))
              : start.translate(
                  0,
                  reduced ? -8 : -18 * Curves.easeOut.transform(t),
                );
          final size = event.isGift && event.kind == 'egg' && hit ? 92.0 : 64.0;
          // Keep a long cross-row arc inside the arena instead of clipping it
          // above the first row. Both endpoints remain on the actual cards.
          final point = Offset(rawPoint.dx, math.max(size / 2, rawPoint.dy));
          final fade = reduced ? 1.0 : (t > .80 ? (1 - t) / .20 : 1.0);
          final pop = reduced
              ? 1.0
              : hit && event.isGift
              ? 1 + math.sin(landing * math.pi * 3) * .18 * (1 - landing)
              : .8 + .2 * math.sin(flight * math.pi / 2);
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (event.isGift && hit && !reduced)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GiftArrivalPainter(
                        center: end,
                        kind: event.kind,
                        progress: landing,
                      ),
                    ),
                  ),
                Positioned(
                  key: ValueKey(
                    'mafia-${hit && event.isGift ? 'impact' : 'projectile'}-${event.id}',
                  ),
                  left: point.dx - size / 2,
                  top: point.dy - size / 2,
                  width: size,
                  height: size,
                  child: Transform.scale(
                    scale: pop,
                    child: Transform.rotate(
                      angle: !reduced && event.isGift && !hit
                          ? (event.kind == 'egg'
                                ? flight * math.pi * 2
                                : math.sin(flight * math.pi) * .35)
                          : 0,
                      child: event.isGift
                          ? MafiaGiftSprite(
                              kind: event.kind == 'egg' && hit
                                  ? 'splat'
                                  : event.kind,
                              size: size,
                            )
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: const Color(0xFFD2B46D),
                                  width: 2,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  _emoji(event.kind),
                                  style: const TextStyle(fontSize: 38),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GiftArrivalPainter extends CustomPainter {
  final Offset center;
  final String kind;
  final double progress;
  _GiftArrivalPainter({
    required this.center,
    required this.kind,
    required this.progress,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color =
          (kind == 'rose'
                  ? const Color(0xFFE55A7E)
                  : kind == 'egg'
                  ? const Color(0xFFFFD25D)
                  : Colors.white)
              .withValues(alpha: (1 - progress) * .9);
    for (var i = 0; i < (kind == 'tea' ? 3 : 9); i++) {
      if (kind == 'tea') {
        final x = center.dx + (i - 1) * 12;
        final y = center.dy - 17 - progress * 24;
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..cubicTo(x - 9, y - 8, x + 9, y - 15, x, y - 24),
          paint,
        );
      } else {
        final angle = i * math.pi * 2 / 9;
        final radius = 16 + progress * 56;
        final p =
            center +
            Offset(
              math.cos(angle) * radius,
              math.sin(angle) * radius + progress * progress * 16,
            );
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(angle + progress * 3);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: 7,
            height: kind == 'rose' ? 12 : 5,
          ),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_GiftArrivalPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.center != center ||
      oldDelegate.kind != kind;
}

String _emoji(String kind) => switch (kind) {
  'laugh' => '😂',
  'happy' => '😍',
  'angry' => '😠',
  'surprised' => '😮',
  'applause' => '👏',
  'mvp' => '🏆',
  _ => '✨',
};
int _number(dynamic value) => int.tryParse('$value') ?? 0;
int? _optionalNumber(dynamic value) => value == null ? null : _number(value);
