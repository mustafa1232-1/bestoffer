import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/maslaki_brand_mark.dart';
import '../../../core/widgets/maslaki_wordmark.dart';

class MaslakiSplashScreen extends StatefulWidget {
  final String statusTitle;
  final String statusMessage;
  final String? errorDetails;
  final int attempts;
  final bool waiting;
  final VoidCallback? onRetry;

  const MaslakiSplashScreen({
    super.key,
    required this.statusTitle,
    required this.statusMessage,
    required this.attempts,
    required this.waiting,
    this.errorDetails,
    this.onRetry,
  });

  @override
  State<MaslakiSplashScreen> createState() => _MaslakiSplashScreenState();
}

class _MaslakiSplashScreenState extends State<MaslakiSplashScreen>
    with TickerProviderStateMixin {
  static const _featureSwitchEvery = Duration(milliseconds: 1800);

  late final AnimationController _introController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..forward();

  late final AnimationController _ambientController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 9000),
  )..repeat();

  Timer? _featureTimer;
  int _featureIndex = 0;

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

  static const List<_SplashFeatureDatum> _features = [
    _SplashFeatureDatum(
      icon: Icons.restaurant_menu_rounded,
      color: Color(0xFFFFB24C),
      kind: _SplashFeatureKind.restaurants,
    ),
    _SplashFeatureDatum(
      icon: Icons.shopping_bag_outlined,
      color: Color(0xFF63C6FF),
      kind: _SplashFeatureKind.shopping,
    ),
    _SplashFeatureDatum(
      icon: Icons.local_taxi_rounded,
      color: Color(0xFFFFD264),
      kind: _SplashFeatureKind.taxi,
    ),
    _SplashFeatureDatum(
      icon: Icons.work_outline_rounded,
      color: Color(0xFF7BE39B),
      kind: _SplashFeatureKind.jobs,
    ),
    _SplashFeatureDatum(
      icon: Icons.groups_rounded,
      color: Color(0xFFD29EFF),
      kind: _SplashFeatureKind.community,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _featureTimer = Timer.periodic(_featureSwitchEvery, (_) {
      if (!mounted) return;
      setState(() {
        _featureIndex = (_featureIndex + 1) % _features.length;
      });
    });
  }

  @override
  void dispose() {
    _featureTimer?.cancel();
    _introController.dispose();
    _ambientController.dispose();
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

  (String, String) _featureCopy(BuildContext context, _SplashFeatureKind kind) {
    final l10n = context.l10n;
    switch (kind) {
      case _SplashFeatureKind.restaurants:
        return (
          l10n.onboardingRestaurantsTitle,
          l10n.onboardingRestaurantsDescription,
        );
      case _SplashFeatureKind.shopping:
        return (
          l10n.onboardingShoppingTitle,
          l10n.onboardingShoppingDescription,
        );
      case _SplashFeatureKind.taxi:
        return (l10n.onboardingTaxiTitle, l10n.onboardingTaxiDescription);
      case _SplashFeatureKind.jobs:
        return (l10n.onboardingJobsTitle, l10n.onboardingJobsDescription);
      case _SplashFeatureKind.community:
        return (
          l10n.onboardingCommunityTitle,
          l10n.onboardingCommunityDescription,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_introController, _ambientController]),
        builder: (context, _) {
          final reveal = _introController.value;
          final ambient = _ambientController.value;
          final orbitDraw = Curves.easeOutCubic.transform(
            _stage(0.00, 0.22, reveal),
          );
          final orbitTravel = reveal < 0.68
              ? Curves.easeInOut.transform(_stage(0.14, 0.60, reveal))
              : ambient;
          final logoReveal = Curves.easeOutExpo.transform(
            _stage(0.14, 0.48, reveal),
          );
          final pinReveal = Curves.easeOutBack.transform(
            _stage(0.40, 0.64, reveal),
          );
          final iconsMerge = Curves.easeInOutCubic.transform(
            _stage(0.62, 0.92, reveal),
          );
          final contentReveal = Curves.easeOutCubic.transform(
            _stage(0.40, 0.82, reveal),
          );
          final contentLift = lerpDouble(18, 0, contentReveal)!;
          final ambientWave = math.sin(ambient * math.pi * 2);
          final zoom = lerpDouble(
            1.08,
            1.00,
            Curves.easeOutCubic.transform(reveal),
          )!;

          return LayoutBuilder(
            builder: (context, constraints) {
              final maxStageSize = math.min(
                constraints.maxWidth * 0.82,
                constraints.maxHeight * 0.42,
              );
              final stageSize = maxStageSize.clamp(240.0, 360.0);

              return Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF071224),
                          Color(0xFF112741),
                          Color(0xFF183454),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.26,
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
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(
                              lerpDouble(-0.48, 0.12, ambient)!,
                              lerpDouble(-0.56, -0.10, reveal)!,
                            ),
                            radius: 0.95,
                            colors: [
                              const Color(0xFFE1BF8A).withValues(alpha: 0.16),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(
                              lerpDouble(0.55, -0.18, reveal)!,
                              lerpDouble(0.50, 0.16, ambient)!,
                            ),
                            radius: 0.92,
                            colors: [
                              const Color(0xFF5C7CA7).withValues(alpha: 0.18),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                      child: Column(
                        children: [
                          Transform.translate(
                            offset: Offset(0, contentLift),
                            child: Opacity(
                              opacity: contentReveal,
                              child: const Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: _BrandPill(),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Center(
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
                                            glowPulse: ambient,
                                          ),
                                        ),
                                      ),
                                      ..._buildServiceIcons(
                                        context: context,
                                        stageSize: stageSize,
                                        progress: reveal,
                                        mergeProgress: iconsMerge,
                                        ambientWave: ambientWave,
                                      ),
                                      Center(
                                        child: Opacity(
                                          opacity: logoReveal,
                                          child: Transform.translate(
                                            offset: Offset(
                                              0,
                                              lerpDouble(18, 0, logoReveal)!,
                                            ),
                                            child: SizedBox(
                                              width: stageSize * 0.58,
                                              height: stageSize * 0.58,
                                              child: MaslakiBrandMark(
                                                size: stageSize * 0.58,
                                                shape: MaslakiBrandShape.circle,
                                                revealProgress: logoReveal,
                                                dashPhase: ambient * 1.8,
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
                                                width: 46,
                                                height: 46,
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
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.62,
                                                        ),
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      blurRadius: 24,
                                                      color: const Color(
                                                        0xFFE1BF8A,
                                                      ).withValues(alpha: 0.18),
                                                    ),
                                                  ],
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
                          ),
                          Transform.translate(
                            offset: Offset(0, contentLift),
                            child: Opacity(
                              opacity: contentReveal,
                              child: _SplashBottomPanel(
                                feature: _features[_featureIndex],
                                copy: _featureCopy(
                                  context,
                                  _features[_featureIndex].kind,
                                ),
                                featureCount: _features.length,
                                featureIndex: _featureIndex,
                                waiting: widget.waiting,
                                statusTitle: widget.statusTitle,
                                statusMessage: widget.statusMessage,
                                errorDetails: widget.errorDetails,
                                attempts: widget.attempts,
                                onRetry: widget.onRetry,
                              ),
                            ),
                          ),
                        ],
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
    required double ambientWave,
  }) {
    final baseRadius = stageSize * 0.44;
    final center = stageSize / 2;
    final out = <Widget>[];
    for (var index = 0; index < _serviceIcons.length; index++) {
      final item = _serviceIcons[index];
      final appear = Curves.easeOutBack.transform(
        _stage(0.46 + index * 0.05, 0.62 + index * 0.05, progress),
      );
      if (appear <= 0) continue;
      final angle = item.angleDeg * math.pi / 180;
      final radius = lerpDouble(baseRadius, stageSize * 0.11, mergeProgress)!;
      final bob = math.sin((ambientWave + index) * 1.4) * 4;
      final x = center + math.cos(angle) * radius;
      final y = center + math.sin(angle) * radius + bob;
      final size = lerpDouble(18, 52, appear)!;
      final opacity = (appear * (1 - mergeProgress * 0.82)).clamp(0.0, 1.0);
      final labelOpacity = (opacity * (1 - mergeProgress * 0.88)).clamp(
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
              scale: lerpDouble(0.40, 1.0, appear)!,
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
                          item.color.withValues(alpha: 0.95),
                          item.color.withValues(alpha: 0.56),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 18,
                          color: item.color.withValues(alpha: 0.34),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: Icon(
                        item.icon,
                        color: Colors.white,
                        size: size * 0.50,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Opacity(
                    opacity: labelOpacity,
                    child: Text(
                      _serviceLabel(context, item.label),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
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

enum _SplashFeatureKind { restaurants, shopping, taxi, jobs, community }

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

class _SplashFeatureDatum {
  final IconData icon;
  final Color color;
  final _SplashFeatureKind kind;

  const _SplashFeatureDatum({
    required this.icon,
    required this.color,
    required this.kind,
  });
}

class _BrandPill extends StatelessWidget {
  const _BrandPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MaslakiBrandMark(size: 30, borderRadius: 10),
            SizedBox(width: 10),
            MaslakiWordmark(
              arabicSize: 18,
              latinSize: 7.8,
              latinLetterSpacing: 3.0,
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashBottomPanel extends StatelessWidget {
  final _SplashFeatureDatum feature;
  final (String, String) copy;
  final int featureCount;
  final int featureIndex;
  final bool waiting;
  final String statusTitle;
  final String statusMessage;
  final String? errorDetails;
  final int attempts;
  final VoidCallback? onRetry;

  const _SplashBottomPanel({
    required this.feature,
    required this.copy,
    required this.featureCount,
    required this.featureIndex,
    required this.waiting,
    required this.statusTitle,
    required this.statusMessage,
    required this.errorDetails,
    required this.attempts,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final (title, description) = copy;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.12),
              Colors.white.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              blurRadius: 28,
              color: Colors.black.withValues(alpha: 0.16),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MaslakiWordmark(
                arabicSize: 34,
                latinSize: 12,
                latinLetterSpacing: 5.0,
                arabicColor: Color(0xFFF8F0E2),
                latinColor: Color(0xFFE0BC88),
                crossAxisAlignment: CrossAxisAlignment.center,
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.splashTagline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFF7EFDF).withValues(alpha: 0.84),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.05, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  key: ValueKey(feature.kind),
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                      color: feature.color.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: feature.color.withValues(alpha: 0.18),
                          border: Border.all(
                            color: feature.color.withValues(alpha: 0.34),
                          ),
                        ),
                        child: Icon(
                          feature.icon,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.80),
                                fontSize: 12.8,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(featureCount, (index) {
                  final active = index == featureIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: active
                          ? const Color(0xFFE0BC88)
                          : Colors.white.withValues(alpha: 0.26),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  statusTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  statusMessage,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13.2,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (waiting) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(minHeight: 5),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.l10n.startupIntroAttempts(attempts),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ] else ...[
                if (errorDetails?.trim().isNotEmpty == true) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      errorDetails!,
                      style: TextStyle(
                        color: const Color(0xFFFFC8C8).withValues(alpha: 0.92),
                        fontSize: 12.4,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(context.l10n.commonRetry),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbitRoadPainter extends CustomPainter {
  final double drawProgress;
  final double travelProgress;
  final double glowPulse;

  const _OrbitRoadPainter({
    required this.drawProgress,
    required this.travelProgress,
    required this.glowPulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.44;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = Colors.white.withValues(alpha: 0.16);
    canvas.drawCircle(center, radius, basePaint);

    final glowAlpha = lerpDouble(
      0.16,
      0.28,
      (math.sin(glowPulse * math.pi) + 1) / 2,
    )!;
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD9B980).withValues(alpha: glowAlpha);

    final roadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFFDAB887), Color(0xFF6A87AC), Color(0xFF4A6D93)],
      ).createShader(rect);

    final effectiveDraw = drawProgress.clamp(0.0, 1.0);
    if (effectiveDraw > 0) {
      final sweep = math.pi * 2 * effectiveDraw;
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
        oldDelegate.travelProgress != travelProgress ||
        oldDelegate.glowPulse != glowPulse;
  }
}
