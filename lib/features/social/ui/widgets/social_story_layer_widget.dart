import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/social_story_document.dart';

class SocialStoryLayerWidget extends StatefulWidget {
  final SocialStoryLayer layer;
  final bool selected;
  final Size canvasSize;
  final Widget child;
  final ValueChanged<SocialStoryLayer> onChanged;
  final VoidCallback? onTap;

  const SocialStoryLayerWidget({
    super.key,
    required this.layer,
    required this.selected,
    required this.canvasSize,
    required this.child,
    required this.onChanged,
    this.onTap,
  });

  @override
  State<SocialStoryLayerWidget> createState() => _SocialStoryLayerWidgetState();
}

class _SocialStoryLayerWidgetState extends State<SocialStoryLayerWidget> {
  late Offset _startFocalPoint;
  late double _startX;
  late double _startY;
  late double _startScale;
  late double _startRotation;

  @override
  Widget build(BuildContext context) {
    final width = widget.canvasSize.width;
    final height = widget.canvasSize.height;
    final left = (widget.layer.x * width) - (width * 0.18);
    final top = (widget.layer.y * height) - 28;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: widget.onTap,
        onScaleStart: widget.layer.locked
            ? null
            : (details) {
                _startFocalPoint = details.focalPoint;
                _startX = widget.layer.x;
                _startY = widget.layer.y;
                _startScale = widget.layer.scale;
                _startRotation = widget.layer.rotation;
              },
        onScaleUpdate: widget.layer.locked
            ? null
            : (details) {
                final delta = details.focalPoint - _startFocalPoint;
                final nextX = _startX + (delta.dx / width);
                final nextY = _startY + (delta.dy / height);
                widget.onChanged(
                  widget.layer.copyWith(
                    x: nextX.clamp(0.08, 0.92),
                    y: nextY.clamp(0.08, 0.92),
                    // Wider range so pinch-to-resize feels real (tiny → large).
                    // Capped at 4.0 to match the backend storyStyle validator.
                    scale: (_startScale * details.scale).clamp(0.3, 4.0),
                    rotation: _startRotation + details.rotation,
                  ),
                );
              },
        child: Transform.rotate(
          angle: widget.layer.rotation,
          child: Transform.scale(
            scale: widget.layer.scale,
            child: DecoratedBox(
              decoration: widget.selected
                  ? BoxDecoration(
                      border: Border.all(color: Colors.white, width: 1.4),
                      borderRadius: BorderRadius.circular(18),
                    )
                  : const BoxDecoration(),
              child: Padding(
                padding: EdgeInsets.all(widget.selected ? 6 : 0),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color colorFromHex(String? value, {Color fallback = Colors.white}) {
  final raw = (value ?? '').trim();
  if (!raw.startsWith('#')) return fallback;
  final hex = raw.substring(1);
  if (hex.length == 6) {
    final parsed = int.tryParse('FF$hex', radix: 16);
    if (parsed != null) return Color(parsed);
  }
  if (hex.length == 8) {
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) return Color(parsed);
  }
  return fallback;
}

TextAlign textAlignFromStoryValue(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'left':
      return TextAlign.left;
    case 'right':
      return TextAlign.right;
    default:
      return TextAlign.center;
  }
}

FontWeight fontWeightFromStoryValue(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'normal':
      return FontWeight.w500;
    case 'heavy':
      return FontWeight.w900;
    default:
      return FontWeight.w700;
  }
}

String? fontFamilyFromStoryValue(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'system') return null;
  return normalized;
}

double normalizedRotation(double value) {
  if (value == 0) return 0;
  const fullTurn = math.pi * 2;
  var next = value % fullTurn;
  if (next > math.pi) next -= fullTurn;
  if (next < -math.pi) next += fullTurn;
  return next;
}
