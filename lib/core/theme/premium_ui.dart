import 'package:flutter/material.dart';

import 'app_theme.dart';

class PremiumPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Color? glowColor;

  const PremiumPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.glowColor,
  });

  @override
  State<PremiumPressable> createState() => _PremiumPressableState();
}

class _PremiumPressableState extends State<PremiumPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.992 : 1,
      curve: Curves.easeOutCubic,
      duration: const Duration(milliseconds: 90),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          child: widget.child,
        ),
      ),
    );
  }
}

class PremiumGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? accent;
  final List<Color>? gradient;
  final bool elevated;

  const PremiumGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.accent,
    this.gradient,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    final tokens = context.maslakiTokens;
    final accentColor = accent ?? visual.accentBlue;
    final surface =
        ((gradient != null && gradient!.isNotEmpty)
            ? gradient!.first.withValues(alpha: 0.24)
            : null) ??
        tokens.cardPrimary.withValues(alpha: 0.84);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: surface,
        border: Border.all(color: accentColor.withValues(alpha: 0.26)),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: tokens.glowPrimary.withValues(alpha: 0.14),
                  blurRadius: 14,
                  spreadRadius: 0.5,
                  offset: const Offset(0, 6),
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: child,
    );
  }
}

class PremiumHeroSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color>? gradient;
  final List<Widget> actions;

  const PremiumHeroSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.gradient,
    this.actions = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return PremiumGlassCard(
      borderRadius: BorderRadius.circular(26),
      accent: tokens.secondaryAccent,
      gradient:
          gradient ??
          <Color>[
            tokens.cardElevated.withValues(alpha: 0.92),
            tokens.surfacePrimary.withValues(alpha: 0.92),
          ],
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.surfaceSecondary.withValues(alpha: 0.62),
              border: Border.all(
                color: tokens.borderSubtle.withValues(alpha: 0.9),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}

class PremiumQuickActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? accent;

  const PremiumQuickActionChip({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    final tokens = context.maslakiTokens;
    final chipAccent = accent ?? visual.accentCyan;
    return PremiumPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      glowColor: chipAccent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: tokens.surfaceSecondary.withValues(alpha: 0.62),
          border: Border.all(
            color: tokens.borderSubtle.withValues(alpha: 0.86),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: chipAccent),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.94),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PremiumSearchBar extends StatelessWidget {
  final String hint;
  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;
  final bool readOnly;
  final IconData icon;

  const PremiumSearchBar({
    super.key,
    required this.hint,
    this.onTap,
    this.onSubmitted,
    this.controller,
    this.readOnly = false,
    this.icon = Icons.search_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return PremiumGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      borderRadius: BorderRadius.circular(18),
      elevated: false,
      accent: tokens.primaryAccent,
      child: TextField(
        controller: controller,
        onTap: onTap,
        onSubmitted: onSubmitted,
        readOnly: readOnly,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

class PremiumStaggeredReveal extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration initialDelay;
  final Duration stepDelay;

  const PremiumStaggeredReveal({
    super.key,
    required this.child,
    required this.index,
    this.initialDelay = const Duration(milliseconds: 60),
    this.stepDelay = const Duration(milliseconds: 85),
  });

  @override
  State<PremiumStaggeredReveal> createState() => _PremiumStaggeredRevealState();
}

class _PremiumStaggeredRevealState extends State<PremiumStaggeredReveal> {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class PremiumSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const PremiumSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<PremiumSkeleton> createState() => _PremiumSkeletonState();
}

class _PremiumSkeletonState extends State<PremiumSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final tokens = context.maslakiTokens;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + (2.0 * t), 0),
              end: Alignment(1.0 + (2.0 * t), 0),
              colors: [
                tokens.surfaceSecondary.withValues(alpha: 0.42),
                tokens.primaryAccent.withValues(alpha: 0.28),
                tokens.surfaceSecondary.withValues(alpha: 0.42),
              ],
            ),
          ),
        );
      },
    );
  }
}
