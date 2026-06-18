import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'creator_temp_media_service.dart';
import 'story_layout_models.dart';

/// Stitches the captured Layout tiles into a single 9:16 story image.
class StoryLayoutCompositor {
  final CreatorTempMediaService tempMediaService;

  const StoryLayoutCompositor(this.tempMediaService);

  /// Canvas is a portrait 1080×1920 frame matching the story aspect ratio.
  static const int canvasWidth = 1080;
  static const int canvasHeight = 1920;
  static const int _gap = 14;

  /// Maslaki navy background that shows through the tile gaps.
  static final img.Color _background = img.ColorRgb8(13, 27, 42); // #0D1B2A

  Future<File> compose({
    required StoryLayoutTemplate template,
    required List<String> imagePaths,
  }) async {
    if (imagePaths.length != template.cellCount) {
      throw ArgumentError(
        'Expected ${template.cellCount} images, got ${imagePaths.length}.',
      );
    }
    final canvas = img.Image(
      width: canvasWidth,
      height: canvasHeight,
      numChannels: 4,
    );
    img.fill(canvas, color: _background);

    final cols = template.columns;
    final rows = template.rows;
    final cellWidth = ((canvasWidth - _gap * (cols + 1)) / cols).floor();
    final cellHeight = ((canvasHeight - _gap * (rows + 1)) / rows).floor();

    for (var i = 0; i < imagePaths.length; i++) {
      final path = imagePaths[i].trim();
      if (path.isEmpty) continue;
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) continue;

      final col = i % cols;
      final row = i ~/ cols;
      final dstX = _gap + col * (cellWidth + _gap);
      final dstY = _gap + row * (cellHeight + _gap);

      final cell = _coverCrop(decoded, cellWidth, cellHeight);
      img.compositeImage(canvas, cell, dstX: dstX, dstY: dstY);
    }

    final outputPath = await tempMediaService.newFilePath(
      prefix: 'story_layout',
      extension: 'png',
    );
    final encoded = img.encodePng(canvas);
    return File(outputPath)..writeAsBytesSync(encoded, flush: true);
  }

  /// Resize-then-center-crop so the image fully covers the cell (no distortion).
  img.Image _coverCrop(img.Image source, int targetWidth, int targetHeight) {
    final scale = math.max(
      targetWidth / source.width,
      targetHeight / source.height,
    );
    final resizedWidth = math.max(targetWidth, (source.width * scale).round());
    final resizedHeight =
        math.max(targetHeight, (source.height * scale).round());
    final resized = img.copyResize(
      source,
      width: resizedWidth,
      height: resizedHeight,
    );
    final cropX = ((resizedWidth - targetWidth) / 2).round().clamp(
          0,
          resizedWidth - targetWidth,
        );
    final cropY = ((resizedHeight - targetHeight) / 2).round().clamp(
          0,
          resizedHeight - targetHeight,
        );
    return img.copyCrop(
      resized,
      x: cropX,
      y: cropY,
      width: targetWidth,
      height: targetHeight,
    );
  }
}
