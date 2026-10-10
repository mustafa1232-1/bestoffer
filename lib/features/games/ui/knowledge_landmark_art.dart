import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// One decoded transparent atlas is shared by every region, not eleven decodes
// per snapshot. Cropping is in the renderer; the original asset stays intact.
class KnowledgeLandmarkArt extends StatelessWidget {
  const KnowledgeLandmarkArt({super.key, required this.index});
  final int index;
  static Future<ui.Image>? _atlas;
  static ui.Image? _decoded;
  static Future<ui.Image> preload() => _atlas ??= _load();
  static Future<ui.Image> _load() async {
    final bytes = await rootBundle.load(
      'assets/games/knowledge/landmarks-v1.png',
    );
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    try {
      return _decoded = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: _decoded != null
        ? _paint(_decoded!)
        : FutureBuilder<ui.Image>(
            future: preload(),
            builder: (context, snapshot) => snapshot.hasData
                ? _paint(snapshot.data!)
                : const SizedBox.expand(),
          ),
  );
  Widget _paint(ui.Image image) => SizedBox.expand(
    child: CustomPaint(painter: _LandmarkPainter(image, index)),
  );
}

class _LandmarkPainter extends CustomPainter {
  const _LandmarkPainter(this.atlas, this.index);
  final ui.Image atlas;
  final int index;
  @override
  void paint(Canvas canvas, Size size) {
    final cell = Size(atlas.width / 4, atlas.height / 3);
    final src = Rect.fromLTWH(
      (index % 4) * cell.width,
      (index ~/ 4) * cell.height,
      cell.width,
      cell.height,
    );
    final fit = applyBoxFit(BoxFit.contain, cell, size);
    canvas.drawImageRect(
      atlas,
      src,
      Alignment.center.inscribe(fit.destination, Offset.zero & size),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_LandmarkPainter old) =>
      old.atlas != atlas || old.index != index;
}
