import 'package:flutter/material.dart';

import 'social_design_theme.dart';

class SocialPostAction extends StatefulWidget {
  const SocialPostAction({
    super.key,
    required this.icon,
    required this.label,
    this.count,
    this.active = false,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final int? count;
  final bool active;
  final Future<void> Function()? onPressed;

  @override
  State<SocialPostAction> createState() => _SocialPostActionState();
}

class _SocialPostActionState extends State<SocialPostAction> {
  bool _busy = false;

  Future<void> _activate() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.count;
    final formatted = count == null
        ? null
        : count < 1000
        ? '$count'
        : count < 1000000
        ? '${(count / 1000).toStringAsFixed(1)}K'
        : '${(count / 1000000).toStringAsFixed(1)}M';
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? SocialDesignTheme.muted.withValues(alpha: 0.52)
        : widget.active
        ? SocialDesignTheme.gold
        : SocialDesignTheme.indigo;
    return Semantics(
      button: true,
      selected: widget.active,
      enabled: enabled,
      label: '${widget.label}${count == null ? '' : ', $count'}',
      child: Tooltip(
        message: widget.label,
        child: InkWell(
          onTap: !enabled || _busy ? null : _activate,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: _busy ? 1.15 : 1,
                    duration: SocialDesignTheme.motion,
                    child: Icon(widget.icon, color: color, size: 24),
                  ),
                  if (formatted != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      formatted,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
