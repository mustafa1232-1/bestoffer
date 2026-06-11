import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/maslaki_brand_mark.dart';
import '../../../core/widgets/maslaki_wordmark.dart';

class MaslakiSplashScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const MaslakiSplashScreen({super.key, required this.onFinished});

  @override
  State<MaslakiSplashScreen> createState() => _MaslakiSplashScreenState();
}

class _MaslakiSplashScreenState extends State<MaslakiSplashScreen>
    with SingleTickerProviderStateMixin {
  bool _animationCompleted = false;

  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 5200),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() => _animationCompleted = true);
        }
      });

  static const List<_ServiceIconDatum> _serviceIcons = [
    _ServiceIconDatum(
      icon: Icons.restaurant_rounded,
      color: Color(0xFFD4B07A),
      angleDeg: -94,
      label: _SplashServiceLabel.food,
    ),
    _ServiceIconDatum(
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFFE6C98A),
      angleDeg: -22,
      label: _SplashServiceLabel.shopping,
    ),
    _ServiceIconDatum(
      icon: Icons.local_taxi_rounded,
      color: Color(0xFFE1C38F),
      angleDeg: 48,
      label: _SplashServiceLabel.taxi,
    ),
    _ServiceIconDatum(
      icon: Icons.work_rounded,
      color: Color(0xFFC6A96D),
      angleDeg: 124,
      label: _SplashServiceLabel.jobs,
    ),
    _ServiceIconDatum(
      icon: Icons.groups_rounded,
      color: Color(0xFF9FB2C8),
      angleDeg: 196,
      label: _SplashServiceLabel.community,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _stage(double start, double end, double value) {
    if (value <= start) return 0;
    if (value >= end) return 1;
    return (value - start) / (end - start);
  }

  String _serviceLabel(BuildContext context, _SplashServiceLabel label) {
    final l10n = context.l10n;
    switch (label) {
      case _SplashServiceLabel.food:
        return l10n.splashServiceFood;
      case _SplashServiceLabel.shopping:
        return l10n.splashServiceShopping;
      case _SplashServiceLabel.taxi:
        return l10n.splashServiceTaxi;
      case _SplashServiceLabel.jobs:
        return l10n.splashServiceJobs;
      case _SplashServiceLabel.community:
        return l10n.splashServiceCommunity;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value;
          final orbitDraw = Curves.easeOutCubic.transform(
            _stage(0.00, 0.22, progress),
          );
          final orbitTravel = Curves.easeInOut.transform(
            _stage(0.12, 0.60, progress),
          );
          final logoReveal = Curves.easeOutExpo.transform(
            _stage(0.20, 0.58, progress),
          );
          final pinReveal = Curves.easeOutBack.transform(
            _stage(0.50, 0.72, progress),
          );
          final iconsMerge = Curves.easeInOutCubic.transform(
            _stage(0.76, 0.96, progress),
          );
          final titleReveal = Curves.easeOut.transform(
            _stage(0.84, 1.00, progress),
          );
          final zoom = lerpDouble(
            1.12,
            1.00,
            Curves.easeOutCubic.transform(progress),
          )!;

          return LayoutBuilder(
            builder: (context, constraints) {
              final maxStageSize = math.min(
                constraints.maxWidth * 0.86,
                constraints.maxHeight * 0.60,
              );
              final stageSize = maxStageSize.clamp(250.0, 400.0);

              return Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF102238),
                          Color(0xFF16314D),
                          Color(0xFF1F3D5C),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.34,
                        child: Lottie.asset(
                          'assets/lottie/splash_particles.json',
                          fit: BoxFit.cover,
                          repeat: true,
                          animate: true,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(
                                lerpDouble(-0.35, 0.20, progress)!,
                                lerpDouble(-0.38, 0.35, progress)!,
                              ),
                              radius: 0.95,
                              colors: const [
                                Color(0xFFE2C28F),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(
                                lerpDouble(0.42, -0.20, progress)!,
                                lerpDouble(0.46, -0.12, progress)!,
                              ),
                              radius: 0.88,
                              colors: const [
                                Color(0xFF45668D),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Transform.scale(
                      scale: zoom,
                      child: SizedBox(
                        width: stageSize,
                        height: stageSize,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _OrbitRoadPainter(
                                  drawProgress: orbitDraw,
                                  travelProgress: orbitTravel,
                                ),
                              ),
                            ),
                            ..._buildServiceIcons(
                              context: context,
                              stageSize: stageSize,
                              progress: progress,
                              mergeProgress: iconsMerge,
                            ),
                            Center(
                              child: Opacity(
                                opacity: logoReveal,
                                child: Transform.translate(
                                  offset: Offset(
                                    0,
                                    lerpDouble(24, 0, logoReveal)!,
                                  ),
                                  child: SizedBox(
                                    width: stageSize * 0.57,
                                    height: stageSize * 0.57,
                                    child: MaslakiBrandMark(
                                      size: stageSize * 0.57,
                                      shape: MaslakiBrandShape.circle,
                                      revealProgress: logoReveal,
                                      dashPhase: progress * 1.6,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: stageSize * 0.08,
                              left: 0,
                              right: 0,
                              child: Transform.scale(
                                scale: pinReveal.clamp(0.0, 1.0),
                                child: Opacity(
                                  opacity: pinReveal.clamp(0.0, 1.0),
                                  child: Center(
                                    child: Container(
                                      width: 45,
                                      height: 45,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.white.withValues(
                                              alpha: 0.24,
                                            ),
                                            Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.60,
                                          ),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.location_on_rounded,
                                        color: Colors.white,
                                        size: 25,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: math.max(40, constraints.maxHeight * 0.08),
                    child: Opacity(
                      opacity: titleReveal,
                      child: Transform.translate(
                        offset: Offset(0, lerpDouble(14, 0, titleReveal)!),
                        child: Column(
                          children: [
                            const MaslakiWordmark(
                              arabicSize: 42,
                              latinSize: 14,
                              latinLetterSpacing: 6.2,
                              arabicColor: Color(0xFFF8F0E2),
                              latinColor: Color(0xFFE0BC88),
                              crossAxisAlignment: CrossAxisAlignment.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              context.l10n.splashTagline,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: const Color(
                                  0xFFF7EFDF,
                                ).withValues(alpha: 0.86),
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 16),
                            AnimatedSlide(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                              offset: _animationCompleted
                                  ? Offset.zero
                                  : const Offset(0, 0.2),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                opacity: _animationCompleted ? 1 : 0,
                                child: IgnorePointer(
                                  ignoring: !_animationCompleted,
                                  child: FilledButton.icon(
                                    onPressed: widget.onFinished,
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                    ),
                                    label: Text(context.l10n.commonContinue),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _buildServiceIcons({
    required BuildContext context,
    required double stageSize,
    required double progress,
    required double mergeProgress,
  }) {
    final baseRadius = stageSize * 0.45;
    final center = stageSize / 2;
    final out = <Widget>[];
    for (var index = 0; index < _serviceIcons.length; index++) {
      final item = _serviceIcons[index];
      final appear = Curves.easeOutBack.transform(
        _stage(0.54 + index * 0.06, 0.70 + index * 0.06, progress),
      );
      if (appear <= 0) continue;
      final angle = item.angleDeg * math.pi / 180;
      final radius = lerpDouble(baseRadius, stageSize * 0.10, mergeProgress)!;
      final x = center + math.cos(angle) * radius;
      final y = center + math.sin(angle) * radius;
      final size = lerpDouble(20, 54, appear)!;
      final opacity = (appear * (1 - mergeProgress * 0.9)).clamp(0.0, 1.0);
      final labelOpacity = (opacity * (1 - mergeProgress * 0.82)).clamp(
        0.0,
        1.0,
      );

      out.add(
        Positioned(
          left: x - size / 2,
          top: y - size / 2,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: lerpDouble(0.38, 1.0, appear)!,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          item.color.withValues(alpha: 0.96),
                          item.color.withValues(alpha: 0.58),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 18,
                          color: item.color.withValues(alpha: 0.50),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: Icon(
                        item.icon,
                        color: Colors.white,
                        size: size * 0.52,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Opacity(
                    opacity: labelOpacity,
                    child: Text(
                      _serviceLabel(context, item.label),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }
}

enum _SplashServiceLabel { food, shopping, taxi, jobs, community }

class _ServiceIconDatum {
  final IconData icon;
  final Color color;
  final double angleDeg;
  final _SplashServiceLabel label;

  const _ServiceIconDatum({
    required this.icon,
    required this.color,
    required this.angleDeg,
    required this.label,
  });
}

class _OrbitRoadPainter extends CustomPainter {
  final double drawProgress;
  final double travelProgress;

  const _OrbitRoadPainter({
    required this.drawProgress,
    required this.travelProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.44;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..color = Colors.white.withValues(alpha: 0.17);
    canvas.drawCircle(center, radius, basePaint);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD9B980).withValues(alpha: 0.22);

    final roadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFFDAB887), Color(0xFF6A87AC), Color(0xFF4A6D93)],
      ).createShader(rect);

    if (drawProgress > 0) {
      final sweep = math.pi * 2 * drawProgress;
      canvas.drawArc(rect, -math.pi / 2, sweep, false, glowPaint);
      canvas.drawArc(rect, -math.pi / 2, sweep, false, roadPaint);
    }

    if (travelProgress > 0) {
      final angle = -math.pi / 2 + math.pi * 2 * travelProgress;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final dotGlow = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFE2C590).withValues(alpha: 0.35);
      final dot = Paint()..color = const Color(0xFFE4C692);
      canvas.drawCircle(point, 11.5, dotGlow);
      canvas.drawCircle(point, 4.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitRoadPainter oldDelegate) {
    return oldDelegate.drawProgress != drawProgress ||
        oldDelegate.travelProgress != travelProgress;
  }
}

// ignore: unused_element
class _LogoRoadPainter extends CustomPainter {
  final double revealProgress;
  final double dashPhase;

  const _LogoRoadPainter({
    required this.revealProgress,
    required this.dashPhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outerPath = _buildOuterMPath(size);
    final innerPath = _buildInnerRoadPath(size);

    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.205
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFFDAB887), Color(0xFF6885AA), Color(0xFF4A6D93)],
      ).createShader(bounds);

    _drawPathPortion(
      canvas: canvas,
      path: outerPath,
      paint: outerPaint,
      t: revealProgress,
    );

    if (revealProgress <= 0.05) return;

    final roadGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.043
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE9CE9F).withValues(alpha: 0.36);

    final roadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.027
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    _drawDashedPath(
      canvas: canvas,
      path: innerPath,
      paint: roadGlow,
      dashLength: size.width * 0.08,
      gapLength: size.width * 0.045,
      phase: dashPhase,
    );
    _drawDashedPath(
      canvas: canvas,
      path: innerPath,
      paint: roadPaint,
      dashLength: size.width * 0.056,
      gapLength: size.width * 0.048,
      phase: dashPhase,
    );
  }

  Path _buildOuterMPath(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0.15 * w, 0.84 * h)
      ..lineTo(0.15 * w, 0.22 * h)
      ..quadraticBezierTo(0.15 * w, 0.12 * h, 0.23 * w, 0.17 * h)
      ..lineTo(0.50 * w, 0.58 * h)
      ..lineTo(0.77 * w, 0.17 * h)
      ..quadraticBezierTo(0.85 * w, 0.12 * h, 0.85 * w, 0.22 * h)
      ..lineTo(0.85 * w, 0.84 * h);
  }

  Path _buildInnerRoadPath(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0.30 * w, 0.82 * h)
      ..lineTo(0.30 * w, 0.34 * h)
      ..quadraticBezierTo(0.30 * w, 0.30 * h, 0.34 * w, 0.35 * h)
      ..lineTo(0.50 * w, 0.56 * h)
      ..lineTo(0.66 * w, 0.35 * h)
      ..quadraticBezierTo(0.70 * w, 0.30 * h, 0.70 * w, 0.34 * h)
      ..lineTo(0.70 * w, 0.82 * h);
  }

  void _drawPathPortion({
    required Canvas canvas,
    required Path path,
    required Paint paint,
    required double t,
  }) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final totalLength = metrics.fold<double>(
      0,
      (sum, metric) => sum + metric.length,
    );
    var visible = (totalLength * t).clamp(0.0, totalLength);
    for (final metric in metrics) {
      if (visible <= 0) break;
      final end = math.min(metric.length, visible);
      canvas.drawPath(metric.extractPath(0, end), paint);
      visible -= end;
    }
  }

  void _drawDashedPath({
    required Canvas canvas,
    required Path path,
    required Paint paint,
    required double dashLength,
    required double gapLength,
    required double phase,
  }) {
    final cycle = dashLength + gapLength;
    final phaseOffset = cycle * phase;
    for (final metric in path.computeMetrics()) {
      var distance = -phaseOffset;
      while (distance < metric.length) {
        final start = math.max(0.0, distance);
        final end = math.min(metric.length, distance + dashLength);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), paint);
        }
        distance += cycle;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LogoRoadPainter oldDelegate) {
    return oldDelegate.revealProgress != revealProgress ||
        oldDelegate.dashPhase != dashPhase;
  }
}
