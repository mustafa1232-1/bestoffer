/// Models for the Maslaki story Layout mode — a familiar multi-shot grid that
/// composites several captures into a single story frame.
///
/// Template names are intentionally Maslaki-flavoured (not generic "Layout"):
/// ثنائي / يومي المصغر / أربع لقطات / شبكة اللحظات.
library;

enum StoryTileSource { camera, gallery }

class StoryLayoutTemplate {
  /// Stable id, also used to resolve the localized name.
  final String id;
  final int columns;
  final int rows;

  const StoryLayoutTemplate({
    required this.id,
    required this.columns,
    required this.rows,
  });

  int get cellCount => columns * rows;

  @override
  bool operator ==(Object other) =>
      other is StoryLayoutTemplate &&
      other.id == id &&
      other.columns == columns &&
      other.rows == rows;

  @override
  int get hashCode => Object.hash(id, columns, rows);
}

/// The supported Maslaki layout templates, ordered from simplest to richest.
const StoryLayoutTemplate storyLayoutDuo =
    StoryLayoutTemplate(id: 'duo', columns: 1, rows: 2); // ثنائي
const StoryLayoutTemplate storyLayoutTrio =
    StoryLayoutTemplate(id: 'trio', columns: 1, rows: 3); // يومي المصغر
const StoryLayoutTemplate storyLayoutQuad =
    StoryLayoutTemplate(id: 'quad', columns: 2, rows: 2); // أربع لقطات
const StoryLayoutTemplate storyLayoutGrid =
    StoryLayoutTemplate(id: 'grid', columns: 2, rows: 3); // شبكة اللحظات

const List<StoryLayoutTemplate> storyLayoutTemplates = <StoryLayoutTemplate>[
  storyLayoutDuo,
  storyLayoutTrio,
  storyLayoutQuad,
  storyLayoutGrid,
];

StoryLayoutTemplate resolveStoryLayoutTemplate(String? id) {
  return storyLayoutTemplates.firstWhere(
    (template) => template.id == (id ?? '').trim(),
    orElse: () => storyLayoutDuo,
  );
}

class StoryLayoutTile {
  final int index;
  final String? imagePath;
  final StoryTileSource? source;

  const StoryLayoutTile({
    required this.index,
    this.imagePath,
    this.source,
  });

  bool get hasImage => (imagePath ?? '').trim().isNotEmpty;

  StoryLayoutTile copyWith({
    String? imagePath,
    StoryTileSource? source,
    bool clear = false,
  }) {
    if (clear) {
      return StoryLayoutTile(index: index);
    }
    return StoryLayoutTile(
      index: index,
      imagePath: imagePath ?? this.imagePath,
      source: source ?? this.source,
    );
  }
}
