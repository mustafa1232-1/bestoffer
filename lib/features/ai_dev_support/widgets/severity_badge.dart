import 'package:flutter/material.dart';

class SeverityBadge extends StatelessWidget {
  final String severity;

  const SeverityBadge({super.key, required this.severity});

  Color _color(BuildContext context) {
    switch (severity.toUpperCase()) {
      case 'SEV1':
      case 'CRITICAL':
        return const Color(0xFFC62828);
      case 'SEV2':
      case 'HIGH':
        return const Color(0xFFEF6C00);
      case 'SEV3':
      case 'MEDIUM':
        return const Color(0xFFF9A825);
      case 'LOW':
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF546E7A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Chip(
      label: Text(
        severity.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      backgroundColor: color.withValues(alpha: 0.18),
      side: BorderSide(color: color.withValues(alpha: 0.55)),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}
