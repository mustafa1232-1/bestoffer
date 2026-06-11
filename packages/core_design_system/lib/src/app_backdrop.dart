import 'package:flutter/material.dart';

import 'app_theme.dart';

class AppBackdrop extends StatelessWidget {
  final Widget child;
  final bool animationsEnabled;
  final bool weatherEffectsEnabled;

  const AppBackdrop({
    super.key,
    required this.child,
    this.animationsEnabled = true,
    this.weatherEffectsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    final tokens = context.maslakiTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokens.backgroundPrimary,
            tokens.backgroundSecondary,
            tokens.backgroundTertiary,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -1.0),
                  radius: 1.2,
                  colors: [
                    tokens.glowPrimary.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.85, 0.8),
                  radius: 0.82,
                  colors: [
                    visual.accentGold.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.0, -0.4),
                  radius: 1.0,
                  colors: [
                    visual.accentBlue.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Opacity(
              opacity: 0.18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.02),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.14),
                    ],
                    stops: const [0, 0.22, 1],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
