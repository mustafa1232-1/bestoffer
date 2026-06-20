import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/creator/creator_effect_registry.dart';
import 'package:maslaki/features/social/creator/creator_filter_registry.dart';
import 'package:maslaki/features/social/creator/creator_models.dart';

void main() {
  group('Maslaki professional filter registry', () {
    test('exposes 30 color + 10 beauty grades (plus Original)', () {
      final color = creatorFiltersByCategory(CreatorFilterCategory.color);
      final beauty = creatorFiltersByCategory(CreatorFilterCategory.beauty);
      // "Original" (none) is a color-category preset that is also supported.
      expect(color.where((f) => f.id != 'none').length, 30);
      expect(beauty.length, 10);
      expect(creatorSupportedFilterPresets.length, 41); // 30 + 10 + none
    });

    test('every exposed filter is fully specified and supported', () {
      for (final f in creatorSupportedFilterPresets) {
        expect(f.id.trim(), isNotEmpty, reason: 'id');
        expect(f.arabicName.trim(), isNotEmpty, reason: '${f.id} ar');
        expect(f.englishName.trim(), isNotEmpty, reason: '${f.id} en');
        expect(f.supported, isTrue, reason: '${f.id} supported');
        expect(f.previewMatrix.length, 20, reason: '${f.id} matrix');
        expect(f.ffmpegFilterGraph.trim(), isNotEmpty, reason: '${f.id} ffmpeg');
      }
    });

    test('filter ids are unique', () {
      final ids = creatorFilterPresets.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('non-Original grades carry a real (non-identity) preview matrix', () {
      // Identity 4x5: diagonal 1s, everything else 0, offsets 0.
      const identity = <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ];
      for (final f in creatorSupportedFilterPresets.where((f) => f.id != 'none')) {
        var differs = false;
        for (var i = 0; i < 20; i++) {
          if ((f.previewMatrix[i] - identity[i]).abs() > 1e-6) {
            differs = true;
            break;
          }
        }
        expect(differs, isTrue, reason: '${f.id} must not be a no-op grade');
      }
    });

    test('every grade produces a distinct preview matrix', () {
      final seen = <String>{};
      for (final f in creatorSupportedFilterPresets) {
        final key = f.previewMatrix
            .map((v) => v.toStringAsFixed(4))
            .join(',');
        expect(seen.add(key), isTrue, reason: '${f.id} duplicates another grade');
      }
    });

    test('ffmpeg graph references eq + colorchannelmixer for grades', () {
      for (final f in creatorSupportedFilterPresets.where((f) => f.id != 'none')) {
        expect(f.ffmpegFilterGraph, contains('eq='));
        expect(f.ffmpegFilterGraph, contains('colorchannelmixer='));
      }
    });

    test('resolve falls back to Original for unknown/null ids', () {
      expect(resolveCreatorFilterPreset(null).id, 'none');
      expect(resolveCreatorFilterPreset('nope').id, 'none');
      expect(resolveCreatorFilterPreset('basmaya_glow').id, 'basmaya_glow');
    });
  });

  group('Face effects honesty gate', () {
    test('no primitive face effect is exposed as working', () {
      // Until real anchored assets + a face mesh land, every effect is hidden.
      expect(creatorEffectPresets.where((e) => e.supported), isEmpty);
    });

    test('effect presets are still fully described (engine-ready)', () {
      for (final e in creatorEffectPresets) {
        expect(e.id.trim(), isNotEmpty);
        expect(e.arabicName.trim(), isNotEmpty);
        expect(e.englishName.trim(), isNotEmpty);
      }
    });
  });
}
