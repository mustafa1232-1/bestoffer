import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:maslaki/features/social/creator/creator_temp_media_service.dart';
import 'package:maslaki/features/social/creator/story_layout_compositor.dart';
import 'package:maslaki/features/social/creator/story_layout_controller.dart';
import 'package:maslaki/features/social/creator/story_layout_models.dart';
import 'package:path/path.dart' as p;

void main() {
  // ── Templates ────────────────────────────────────────────────────────────
  group('StoryLayoutTemplate', () {
    test('cell counts match the requested grids (2, 3, 4, 6)', () {
      expect(storyLayoutDuo.cellCount, 2);
      expect(storyLayoutTrio.cellCount, 3);
      expect(storyLayoutQuad.cellCount, 4);
      expect(storyLayoutGrid.cellCount, 6);
    });

    test('registry exposes exactly the four Maslaki templates', () {
      expect(storyLayoutTemplates.map((t) => t.id), <String>[
        'duo',
        'trio',
        'quad',
        'grid',
      ]);
    });

    test('resolve falls back to duo for unknown ids', () {
      expect(resolveStoryLayoutTemplate('nope'), storyLayoutDuo);
      expect(resolveStoryLayoutTemplate(null), storyLayoutDuo);
      expect(resolveStoryLayoutTemplate('quad'), storyLayoutQuad);
    });
  });

  // ── Controller ───────────────────────────────────────────────────────────
  group('StoryLayoutController', () {
    test('starts empty with the right number of tiles', () {
      final controller = StoryLayoutController(template: storyLayoutQuad);
      expect(controller.tiles.length, 4);
      expect(controller.isEmpty, isTrue);
      expect(controller.isComplete, isFalse);
      expect(controller.filledCount, 0);
      expect(controller.currentIndex, 0);
    });

    test('sequential capture auto-advances to the next empty tile', () {
      final controller = StoryLayoutController(template: storyLayoutTrio);
      controller.setCurrentImage('/tmp/a.jpg', StoryTileSource.camera);
      expect(controller.currentIndex, 1);
      expect(controller.filledCount, 1);
      controller.setCurrentImage('/tmp/b.jpg', StoryTileSource.camera);
      expect(controller.currentIndex, 2);
      controller.setCurrentImage('/tmp/c.jpg', StoryTileSource.gallery);
      expect(controller.isComplete, isTrue);
    });

    test('orderedImagePaths preserves tile order', () {
      final controller = StoryLayoutController(template: storyLayoutDuo);
      controller.setImageAt(0, '/tmp/first.jpg', StoryTileSource.camera);
      controller.setImageAt(1, '/tmp/second.jpg', StoryTileSource.gallery);
      expect(
        controller.orderedImagePaths,
        <String>['/tmp/first.jpg', '/tmp/second.jpg'],
      );
    });

    test('deleteTile clears the tile and makes it active for re-shoot', () {
      final controller = StoryLayoutController(template: storyLayoutDuo);
      controller.setImageAt(0, '/tmp/a.jpg', StoryTileSource.camera);
      controller.setImageAt(1, '/tmp/b.jpg', StoryTileSource.camera);
      expect(controller.isComplete, isTrue);
      controller.deleteTile(0);
      expect(controller.tiles[0].hasImage, isFalse);
      expect(controller.currentIndex, 0);
      expect(controller.isComplete, isFalse);
    });

    test('replacing a selected tile keeps the other tiles intact', () {
      final controller = StoryLayoutController(template: storyLayoutTrio);
      controller.setImageAt(0, '/tmp/a.jpg', StoryTileSource.camera);
      controller.setImageAt(1, '/tmp/b.jpg', StoryTileSource.camera);
      controller.selectTile(0);
      expect(controller.currentIndex, 0);
      controller.setCurrentImage('/tmp/a2.jpg', StoryTileSource.gallery);
      expect(controller.tiles[0].imagePath, '/tmp/a2.jpg');
      expect(controller.tiles[0].source, StoryTileSource.gallery);
      expect(controller.tiles[1].imagePath, '/tmp/b.jpg');
    });

    test('selecting a new template resets tiles and count', () {
      final controller = StoryLayoutController(template: storyLayoutDuo);
      controller.setImageAt(0, '/tmp/a.jpg', StoryTileSource.camera);
      controller.selectTemplate(storyLayoutGrid);
      expect(controller.tiles.length, 6);
      expect(controller.isEmpty, isTrue);
      expect(controller.currentIndex, 0);
    });

    test('notifies listeners on capture', () {
      final controller = StoryLayoutController(template: storyLayoutDuo);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.setCurrentImage('/tmp/a.jpg', StoryTileSource.camera);
      expect(notifications, greaterThan(0));
    });

    test('ignores out-of-range tile operations', () {
      final controller = StoryLayoutController(template: storyLayoutDuo);
      controller.setImageAt(5, '/tmp/x.jpg', StoryTileSource.camera);
      controller.deleteTile(-1);
      expect(controller.isEmpty, isTrue);
    });
  });

  // ── Compositor ───────────────────────────────────────────────────────────
  group('StoryLayoutCompositor', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('maslaki_layout_test');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    /// Writes a solid-colour JPG and returns its path.
    Future<String> writeSolidImage(
      String name,
      int width,
      int height,
      img.Color color,
    ) async {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: color);
      final path = p.join(tempRoot.path, name);
      File(path).writeAsBytesSync(img.encodeJpg(image));
      return path;
    }

    test('composes a 1080x1920 PNG from a duo layout', () async {
      final compositor = StoryLayoutCompositor(
        CreatorTempMediaService(overrideRoot: tempRoot),
      );
      final a = await writeSolidImage('a.jpg', 400, 800, img.ColorRgb8(200, 30, 30));
      final b = await writeSolidImage('b.jpg', 800, 400, img.ColorRgb8(30, 30, 200));

      final output = await compositor.compose(
        template: storyLayoutDuo,
        imagePaths: <String>[a, b],
      );

      expect(await output.exists(), isTrue);
      final decoded = img.decodeImage(await output.readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, StoryLayoutCompositor.canvasWidth);
      expect(decoded.height, StoryLayoutCompositor.canvasHeight);
    });

    test('throws when image count does not match the template', () async {
      final compositor = StoryLayoutCompositor(
        CreatorTempMediaService(overrideRoot: tempRoot),
      );
      final a = await writeSolidImage('a.jpg', 100, 100, img.ColorRgb8(10, 10, 10));
      expect(
        () => compositor.compose(
          template: storyLayoutQuad,
          imagePaths: <String>[a],
        ),
        throwsArgumentError,
      );
    });
  });
}
