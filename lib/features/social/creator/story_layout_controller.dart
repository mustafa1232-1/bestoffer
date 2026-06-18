import 'package:flutter/foundation.dart';

import 'story_layout_models.dart';

/// Drives the sequential capture flow for Layout mode: tracks which tile is
/// active, accepts captured/imported images, and supports retake/delete/replace.
class StoryLayoutController extends ChangeNotifier {
  StoryLayoutTemplate _template;
  late List<StoryLayoutTile> _tiles;
  int _currentIndex = 0;

  StoryLayoutController({StoryLayoutTemplate? template})
      : _template = template ?? storyLayoutDuo {
    _resetTiles();
  }

  StoryLayoutTemplate get template => _template;

  List<StoryLayoutTile> get tiles => List<StoryLayoutTile>.unmodifiable(_tiles);

  int get currentIndex => _currentIndex;

  int get filledCount => _tiles.where((tile) => tile.hasImage).length;

  int get cellCount => _template.cellCount;

  bool get isComplete =>
      _tiles.isNotEmpty && _tiles.every((tile) => tile.hasImage);

  bool get isEmpty => _tiles.every((tile) => !tile.hasImage);

  /// All captured image paths in tile order. Only meaningful when [isComplete].
  List<String> get orderedImagePaths =>
      _tiles.map((tile) => tile.imagePath ?? '').toList(growable: false);

  /// Switch templates. Resets all tiles because the cell count changes.
  void selectTemplate(StoryLayoutTemplate template) {
    if (template == _template) return;
    _template = template;
    _resetTiles();
    _currentIndex = 0;
    notifyListeners();
  }

  /// Make [index] the active tile (e.g. user tapped a cell to replace it).
  void selectTile(int index) {
    if (index < 0 || index >= _tiles.length) return;
    if (index == _currentIndex) return;
    _currentIndex = index;
    notifyListeners();
  }

  /// Store an image into a specific tile, then auto-advance to the next empty.
  void setImageAt(int index, String path, StoryTileSource source) {
    if (index < 0 || index >= _tiles.length) return;
    if (path.trim().isEmpty) return;
    _tiles[index] = _tiles[index].copyWith(imagePath: path, source: source);
    _currentIndex = _nextEmptyIndex(after: index);
    notifyListeners();
  }

  /// Store an image into the currently active tile.
  void setCurrentImage(String path, StoryTileSource source) {
    setImageAt(_currentIndex, path, source);
  }

  /// Clear a tile and make it the active one so the user can re-shoot it.
  void deleteTile(int index) {
    if (index < 0 || index >= _tiles.length) return;
    _tiles[index] = StoryLayoutTile(index: index);
    _currentIndex = index;
    notifyListeners();
  }

  void reset() {
    _resetTiles();
    _currentIndex = 0;
    notifyListeners();
  }

  void _resetTiles() {
    _tiles = List<StoryLayoutTile>.generate(
      _template.cellCount,
      (index) => StoryLayoutTile(index: index),
      growable: false,
    );
  }

  /// First empty tile starting from [after]+1, wrapping; falls back to [after].
  int _nextEmptyIndex({required int after}) {
    for (var offset = 1; offset <= _tiles.length; offset++) {
      final candidate = (after + offset) % _tiles.length;
      if (!_tiles[candidate].hasImage) return candidate;
    }
    return after;
  }
}
