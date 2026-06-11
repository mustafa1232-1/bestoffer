import 'package:flutter/material.dart';

import '../branding/maslaki_brand_assets.dart';
import '../theme/app_theme.dart';

enum MaslakiBrandShape { rounded, circle }

class MaslakiBrandMark extends StatelessWidget {
  final double size;
  final double borderRadius;
  final MaslakiBrandShape shape;
  final bool showGlow;
  final double revealProgress;
  final double dashPhase;

  const MaslakiBrandMark({
    super.key,
    this.size = 56,
    this.borderRadius = 18,
    this.shape = MaslakiBrandShape.rounded,
    this.showGlow = true,
    this.revealProgress = 1,
    this.dashPhase = 0.16,
  });

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    final radius = shape == MaslakiBrandShape.circle ? size / 2 : borderRadius;
    final reveal = revealProgress.clamp(0.0, 1.0);

    final decorated = SizedBox(
      width: size,
      height: size,
      child: Opacity(
        opacity: reveal,
        child: Image.asset(
          MaslakiBrandAssets.uiMark,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.location_on_rounded,
            size: size * 0.62,
            color: visual.accentGold,
          ),
        ),
      ),
    );

    if (shape == MaslakiBrandShape.circle) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: showGlow
              ? [
                  BoxShadow(
                    color: visual.accentGold.withValues(alpha: 0.16),
                    blurRadius: size * 0.26,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        child: ClipOval(child: decorated),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: visual.accentGold.withValues(alpha: 0.14),
                  blurRadius: size * 0.24,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: decorated,
      ),
    );
  }
}
