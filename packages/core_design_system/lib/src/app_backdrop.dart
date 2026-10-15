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
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tokens.surfacePrimary.withValues(alpha: 0.58),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.36],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    visual.accentGold.withValues(alpha: 0.05),
                    tokens.glowPrimary.withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.46, 1],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Opacity(
              opacity: 0.11,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.20),
                      Colors.transparent,
                      tokens.textPrimary.withValues(alpha: 0.04),
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
