import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'creator_models.dart';
import 'creator_temp_media_service.dart';

class EffectPipelineService {
  final CreatorTempMediaService tempMediaService;

  const EffectPipelineService(this.tempMediaService);

  Future<File> exportPhoto({
    required File sourceImage,
    required CreatorEffectPreset effect,
    required Rect faceBounds,
  }) async {
    final bytes = await sourceImage.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Unable to decode captured image for effect export.');
    }
    final rendered = img.copyResize(decoded, width: decoded.width);
    _drawEffectOnImage(rendered, effect.id, faceBounds);
    final outputPath = await tempMediaService.newFilePath(
      prefix: 'story_photo_effect',
      extension: 'png',
    );
    final encoded = img.encodePng(rendered);
    return File(outputPath)..writeAsBytesSync(encoded, flush: true);
  }

  void _drawEffectOnImage(img.Image image, String effectId, Rect face) {
    switch (effectId) {
      case 'baghdadi_mustache':
        _drawMustacheOnImage(image, face);
        break;
      case 'souq_glasses':
        _drawGlassesOnImage(image, face);
        break;
      case 'golden_palm_crown':
        _drawCrownOnImage(image, face);
        break;
      case 'indigo_light_mask':
        _drawMaskOnImage(image, face);
        break;
      case 'date_stars':
        _drawStarsOnImage(image, face);
        break;
      case 'sand_rabbit':
        _drawRabbitOnImage(image, face);
        break;
      case 'desert_gazelle':
        _drawGazelleOnImage(image, face);
        break;
      case 'maslaki_glow':
      default:
        _drawGlowOnImage(image, face);
        break;
    }
  }

  void _drawGlassesOnImage(img.Image image, Rect face) {
    final frameColor = img.ColorRgba8(33, 44, 66, 220);
    final lensColor = img.ColorRgba8(212, 175, 55, 72);
    final lensWidth = face.width * 0.34;
    final lensHeight = face.height * 0.18;
    final top = face.top + face.height * 0.28;
    final leftLens = Rect.fromLTWH(
      face.left + face.width * 0.10,
      top,
      lensWidth,
      lensHeight,
    );
    final rightLens = Rect.fromLTWH(
      face.right - face.width * 0.10 - lensWidth,
      top,
      lensWidth,
      lensHeight,
    );
    img.fillRect(
      image,
      x1: leftLens.left.toInt(),
      y1: leftLens.top.toInt(),
      x2: leftLens.right.toInt(),
      y2: leftLens.bottom.toInt(),
      color: lensColor,
    );
    img.fillRect(
      image,
      x1: rightLens.left.toInt(),
      y1: rightLens.top.toInt(),
      x2: rightLens.right.toInt(),
      y2: rightLens.bottom.toInt(),
      color: lensColor,
    );
    img.drawRect(
      image,
      x1: leftLens.left.toInt(),
      y1: leftLens.top.toInt(),
      x2: leftLens.right.toInt(),
      y2: leftLens.bottom.toInt(),
      color: frameColor,
      thickness: (face.width * 0.03).clamp(2, 8).toInt(),
      radius: 12,
    );
    img.drawRect(
      image,
      x1: rightLens.left.toInt(),
      y1: rightLens.top.toInt(),
      x2: rightLens.right.toInt(),
      y2: rightLens.bottom.toInt(),
      color: frameColor,
      thickness: (face.width * 0.03).clamp(2, 8).toInt(),
      radius: 12,
    );
    img.drawLine(
      image,
      x1: leftLens.right.toInt(),
      y1: (leftLens.top + lensHeight * 0.45).toInt(),
      x2: rightLens.left.toInt(),
      y2: (rightLens.top + lensHeight * 0.45).toInt(),
      color: frameColor,
      thickness: (face.width * 0.018).clamp(2, 6).toInt(),
    );
  }

  void _drawMustacheOnImage(img.Image image, Rect face) {
    final color = img.ColorRgba8(39, 26, 18, 230);
    final centerY = face.top + face.height * 0.68;
    final width = face.width * 0.22;
    final height = face.height * 0.08;
    img.fillCircle(
      image,
      x: (face.center.dx - width * 0.45).toInt(),
      y: centerY.toInt(),
      radius: width.toInt(),
      color: color,
    );
    img.fillCircle(
      image,
      x: (face.center.dx + width * 0.45).toInt(),
      y: centerY.toInt(),
      radius: width.toInt(),
      color: color,
    );
    img.fillRect(
      image,
      x1: (face.center.dx - width * 0.16).toInt(),
      y1: (centerY - height * 0.28).toInt(),
      x2: (face.center.dx + width * 0.16).toInt(),
      y2: (centerY + height * 0.22).toInt(),
      color: color,
    );
  }

  void _drawMaskOnImage(img.Image image, Rect face) {
    final maskColor = img.ColorRgba8(34, 55, 96, 150);
    img.fillRect(
      image,
      x1: (face.left + face.width * 0.10).toInt(),
      y1: (face.top + face.height * 0.18).toInt(),
      x2: (face.right - face.width * 0.10).toInt(),
      y2: (face.top + face.height * 0.58).toInt(),
      color: maskColor,
      radius: 22,
    );
  }

  void _drawCrownOnImage(img.Image image, Rect face) {
    final gold = img.ColorRgba8(212, 175, 55, 230);
    final points = <img.Point>[
      img.Point((face.left + face.width * 0.10).toInt(), (face.top + face.height * 0.12).toInt()),
      img.Point((face.left + face.width * 0.22).toInt(), (face.top - face.height * 0.20).toInt()),
      img.Point((face.center.dx).toInt(), (face.top + face.height * 0.02).toInt()),
      img.Point((face.right - face.width * 0.22).toInt(), (face.top - face.height * 0.20).toInt()),
      img.Point((face.right - face.width * 0.10).toInt(), (face.top + face.height * 0.12).toInt()),
      img.Point((face.right - face.width * 0.10).toInt(), (face.top + face.height * 0.22).toInt()),
      img.Point((face.left + face.width * 0.10).toInt(), (face.top + face.height * 0.22).toInt()),
    ];
    img.fillPolygon(image, vertices: points, color: gold);
  }

  void _drawStarsOnImage(img.Image image, Rect face) {
    final gold = img.ColorRgba8(230, 201, 138, 235);
    final anchors = <Offset>[
      Offset(face.left + face.width * 0.18, face.top - face.height * 0.08),
      Offset(face.center.dx, face.top - face.height * 0.18),
      Offset(face.right - face.width * 0.18, face.top - face.height * 0.08),
    ];
    for (final anchor in anchors) {
      _fillStar(image, anchor, face.width * 0.08, gold);
    }
  }

  void _drawRabbitOnImage(img.Image image, Rect face) {
    final sand = img.ColorRgba8(234, 221, 199, 220);
    img.fillCircle(
      image,
      x: (face.left + face.width * 0.28).toInt(),
      y: (face.top - face.height * 0.18).toInt(),
      radius: (face.width * 0.10).toInt(),
      color: sand,
    );
    img.fillCircle(
      image,
      x: (face.right - face.width * 0.28).toInt(),
      y: (face.top - face.height * 0.18).toInt(),
      radius: (face.width * 0.10).toInt(),
      color: sand,
    );
    img.fillRect(
      image,
      x1: (face.left + face.width * 0.22).toInt(),
      y1: (face.top - face.height * 0.42).toInt(),
      x2: (face.left + face.width * 0.34).toInt(),
      y2: (face.top - face.height * 0.12).toInt(),
      color: sand,
      radius: 20,
    );
    img.fillRect(
      image,
      x1: (face.right - face.width * 0.34).toInt(),
      y1: (face.top - face.height * 0.42).toInt(),
      x2: (face.right - face.width * 0.22).toInt(),
      y2: (face.top - face.height * 0.12).toInt(),
      color: sand,
      radius: 20,
    );
  }

  void _drawGazelleOnImage(img.Image image, Rect face) {
    final sand = img.ColorRgba8(214, 175, 122, 210);
    img.drawLine(
      image,
      x1: (face.left + face.width * 0.28).toInt(),
      y1: (face.top + face.height * 0.06).toInt(),
      x2: (face.left + face.width * 0.18).toInt(),
      y2: (face.top - face.height * 0.36).toInt(),
      color: sand,
      thickness: (face.width * 0.03).clamp(2, 8).toInt(),
    );
    img.drawLine(
      image,
      x1: (face.right - face.width * 0.28).toInt(),
      y1: (face.top + face.height * 0.06).toInt(),
      x2: (face.right - face.width * 0.18).toInt(),
      y2: (face.top - face.height * 0.36).toInt(),
      color: sand,
      thickness: (face.width * 0.03).clamp(2, 8).toInt(),
    );
  }

  void _drawGlowOnImage(img.Image image, Rect face) {
    final center = face.center;
    final radius = (face.width * 0.64).toInt();
    final color = img.ColorRgba8(212, 175, 55, 68);
    img.fillCircle(
      image,
      x: center.dx.toInt(),
      y: (face.top + face.height * 0.42).toInt(),
      radius: radius,
      color: color,
    );
  }

  void _fillStar(img.Image image, Offset center, double radius, img.Color color) {
    final points = <img.Point>[];
    for (var i = 0; i < 10; i++) {
      final angle = (-90 + i * 36) * math.pi / 180;
      final pointRadius = i.isEven ? radius : radius * 0.45;
      points.add(
        img.Point(
          (center.dx + math.cos(angle) * pointRadius).toInt(),
          (center.dy + math.sin(angle) * pointRadius).toInt(),
        ),
      );
    }
    img.fillPolygon(image, vertices: points, color: color);
  }
}

class CreatorEffectPreviewPainter extends CustomPainter {
  final CreatorEffectPreset? effect;
  final Rect? faceBounds;

  const CreatorEffectPreviewPainter({
    required this.effect,
    required this.faceBounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (effect == null || faceBounds == null) return;
    final face = Rect.fromLTWH(
      faceBounds!.left * size.width,
      faceBounds!.top * size.height,
      faceBounds!.width * size.width,
      faceBounds!.height * size.height,
    );
    switch (effect!.id) {
      case 'baghdadi_mustache':
        _drawMustache(canvas, face);
        break;
      case 'souq_glasses':
        _drawGlasses(canvas, face);
        break;
      case 'golden_palm_crown':
        _drawCrown(canvas, face);
        break;
      case 'indigo_light_mask':
        _drawMask(canvas, face);
        break;
      case 'date_stars':
        _drawStars(canvas, face);
        break;
      case 'sand_rabbit':
        _drawRabbit(canvas, face);
        break;
      case 'desert_gazelle':
        _drawGazelle(canvas, face);
        break;
      case 'maslaki_glow':
      default:
        _drawGlow(canvas, face);
        break;
    }
  }

  void _drawGlasses(Canvas canvas, Rect face) {
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = face.width * 0.04
      ..color = const Color(0xFF26324A);
    final lensPaint = Paint()..color = const Color(0x55D4AF37);
    final leftLens = Rect.fromLTWH(
      face.left + face.width * 0.10,
      face.top + face.height * 0.28,
      face.width * 0.34,
      face.height * 0.18,
    );
    final rightLens = Rect.fromLTWH(
      face.right - face.width * 0.44,
      face.top + face.height * 0.28,
      face.width * 0.34,
      face.height * 0.18,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(leftLens, const Radius.circular(12)), lensPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(rightLens, const Radius.circular(12)), lensPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(leftLens, const Radius.circular(12)), frame);
    canvas.drawRRect(RRect.fromRectAndRadius(rightLens, const Radius.circular(12)), frame);
    canvas.drawLine(
      Offset(leftLens.right, leftLens.top + leftLens.height * 0.45),
      Offset(rightLens.left, rightLens.top + rightLens.height * 0.45),
      frame,
    );
  }

  void _drawMustache(Canvas canvas, Rect face) {
    final paint = Paint()..color = const Color(0xFF2A1C12);
    final center = Offset(face.center.dx, face.top + face.height * 0.68);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - face.width * 0.10, center.dy),
        width: face.width * 0.28,
        height: face.height * 0.12,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + face.width * 0.10, center.dy),
        width: face.width * 0.28,
        height: face.height * 0.12,
      ),
      paint,
    );
  }

  void _drawMask(Canvas canvas, Rect face) {
    final paint = Paint()..color = const Color(0x7A27416E);
    final mask = Rect.fromLTWH(
      face.left + face.width * 0.10,
      face.top + face.height * 0.18,
      face.width * 0.80,
      face.height * 0.40,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(mask, const Radius.circular(18)), paint);
  }

  void _drawCrown(Canvas canvas, Rect face) {
    final paint = Paint()..color = const Color(0xFFD4AF37);
    final path = Path()
      ..moveTo(face.left + face.width * 0.10, face.top + face.height * 0.12)
      ..lineTo(face.left + face.width * 0.22, face.top - face.height * 0.20)
      ..lineTo(face.center.dx, face.top + face.height * 0.02)
      ..lineTo(face.right - face.width * 0.22, face.top - face.height * 0.20)
      ..lineTo(face.right - face.width * 0.10, face.top + face.height * 0.12)
      ..lineTo(face.right - face.width * 0.10, face.top + face.height * 0.22)
      ..lineTo(face.left + face.width * 0.10, face.top + face.height * 0.22)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawStars(Canvas canvas, Rect face) {
    final centers = <Offset>[
      Offset(face.left + face.width * 0.18, face.top - face.height * 0.08),
      Offset(face.center.dx, face.top - face.height * 0.18),
      Offset(face.right - face.width * 0.18, face.top - face.height * 0.08),
    ];
    for (final center in centers) {
      canvas.drawPath(
        _starPath(center, face.width * 0.08),
        Paint()..color = const Color(0xFFE6C98A),
      );
    }
  }

  void _drawRabbit(Canvas canvas, Rect face) {
    final paint = Paint()..color = const Color(0xFFEADDC7);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(face.left + face.width * 0.28, face.top - face.height * 0.24),
        width: face.width * 0.14,
        height: face.height * 0.34,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(face.right - face.width * 0.28, face.top - face.height * 0.24),
        width: face.width * 0.14,
        height: face.height * 0.34,
      ),
      paint,
    );
  }

  void _drawGazelle(Canvas canvas, Rect face) {
    final paint = Paint()
      ..color = const Color(0xFFD6AF7A)
      ..strokeWidth = face.width * 0.03
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(face.left + face.width * 0.28, face.top + face.height * 0.06),
      Offset(face.left + face.width * 0.18, face.top - face.height * 0.36),
      paint,
    );
    canvas.drawLine(
      Offset(face.right - face.width * 0.28, face.top + face.height * 0.06),
      Offset(face.right - face.width * 0.18, face.top - face.height * 0.36),
      paint,
    );
  }

  void _drawGlow(Canvas canvas, Rect face) {
    final glowPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0x55D4AF37),
          Color(0x11D4AF37),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: Offset(face.center.dx, face.top + face.height * 0.42), radius: face.width * 0.64),
      );
    canvas.drawCircle(
      Offset(face.center.dx, face.top + face.height * 0.42),
      face.width * 0.64,
      glowPaint,
    );
  }

  Path _starPath(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = (-90 + i * 36) * math.pi / 180;
      final pointRadius = i.isEven ? radius : radius * 0.45;
      final point = Offset(
        center.dx + math.cos(angle) * pointRadius,
        center.dy + math.sin(angle) * pointRadius,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant CreatorEffectPreviewPainter oldDelegate) {
    return oldDelegate.effect?.id != effect?.id ||
        oldDelegate.faceBounds != faceBounds;
  }
}
