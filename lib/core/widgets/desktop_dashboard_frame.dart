import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../platform/app_platform_capabilities.dart';

class DesktopDashboardFrame extends StatelessWidget {
  final Widget sidebar;
  final Widget child;
  final String title;
  final String? subtitle;
  final List<Widget> quickActions;
  final double sidebarWidth;
  final String statusLabel;
  final IconData statusIcon;

  const DesktopDashboardFrame({
    super.key,
    required this.sidebar,
    required this.child,
    required this.title,
    this.subtitle,
    this.quickActions = const [],
    this.sidebarWidth = 320,
    this.statusLabel = 'Desktop Workspace',
    this.statusIcon = Icons.desktop_windows_rounded,
  });

  static bool shouldUse(BuildContext context) {
    return (appIsDesktop || kIsWeb) && MediaQuery.sizeOf(context).width >= 1180;
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldUse(context)) return child;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final shell = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: sidebarWidth,
          child: _GlassPanel(borderRadius: 30, child: sidebar),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: -180,
                right: -120,
                child: _GlowOrb(
                  size: 360,
                  color: scheme.primary.withValues(alpha: 0.20),
                ),
              ),
              Positioned(
                bottom: -160,
                left: -90,
                child: _GlowOrb(
                  size: 300,
                  color: scheme.tertiary.withValues(alpha: 0.16),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GlassPanel(
                    borderRadius: 30,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 280),
                                  child: Column(
                                    key: ValueKey('$title|$subtitle'),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.1,
                                            ),
                                      ),
                                      if (subtitle?.isNotEmpty == true) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          subtitle!,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: scheme.onSurface
                                                    .withValues(alpha: 0.76),
                                                height: 1.35,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              _DesktopStatusPill(
                                icon: statusIcon,
                                label: statusLabel,
                              ),
                            ],
                          ),
                          if (quickActions.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: quickActions
                                    .map(
                                      (action) => Padding(
                                        padding:
                                            const EdgeInsetsDirectional.only(
                                              end: 10,
                                            ),
                                        child: action,
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: _GlassPanel(
                      borderRadius: 32,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final slide = 20 * (1 - value);
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(0, slide), child: child),
        );
      },
      child: shell,
    );
  }
}

class DesktopQuickActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  const DesktopQuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected = false,
  });

  @override
  State<DesktopQuickActionButton> createState() =>
      _DesktopQuickActionButtonState();
}

class _DesktopQuickActionButtonState extends State<DesktopQuickActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final hovered = _hovered;
    final background = selected
        ? scheme.primary.withValues(alpha: 0.30)
        : hovered
        ? scheme.primary.withValues(alpha: 0.16)
        : scheme.surface.withValues(alpha: 0.58);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: hovered ? 1.02 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.70)
                  : Colors.white.withValues(alpha: 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: hovered ? 0.26 : 0.15),
                blurRadius: hovered ? 16 : 10,
                offset: Offset(0, hovered ? 7 : 4),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      size: 19,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: selected ? scheme.primary : scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final double borderRadius;

  const _GlassPanel({required this.child, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.surface.withValues(alpha: 0.80),
                scheme.surfaceContainerHighest.withValues(alpha: 0.46),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class _DesktopStatusPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DesktopStatusPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
