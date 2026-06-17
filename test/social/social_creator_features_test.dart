import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/files/local_media_file.dart';
import 'package:maslaki/features/social/creator/creator_adapters.dart';
import 'package:maslaki/features/social/creator/creator_constants.dart';
import 'package:maslaki/features/social/creator/creator_filter_registry.dart';
import 'package:maslaki/features/social/creator/creator_models.dart';
import 'package:maslaki/features/social/models/social_story_document.dart';

void main() {
  // ── Time Mood ──────────────────────────────────────────────────────────────
  group('resolveTimeMoodKeyFromHour', () {
    test('returns morning for hour 4–7', () {
      expect(resolveTimeMoodKeyFromHour(4), 'morning');
      expect(resolveTimeMoodKeyFromHour(7), 'morning');
    });

    test('returns forenoon for hour 8–11', () {
      expect(resolveTimeMoodKeyFromHour(8), 'forenoon');
      expect(resolveTimeMoodKeyFromHour(11), 'forenoon');
    });

    test('returns noon for hour 12–13', () {
      expect(resolveTimeMoodKeyFromHour(12), 'noon');
      expect(resolveTimeMoodKeyFromHour(13), 'noon');
    });

    test('returns afternoon for hour 14–16', () {
      expect(resolveTimeMoodKeyFromHour(14), 'afternoon');
      expect(resolveTimeMoodKeyFromHour(16), 'afternoon');
    });

    test('returns sunset for hour 17–18', () {
      expect(resolveTimeMoodKeyFromHour(17), 'sunset');
      expect(resolveTimeMoodKeyFromHour(18), 'sunset');
    });

    test('returns evening for hour 19–21', () {
      expect(resolveTimeMoodKeyFromHour(19), 'evening');
      expect(resolveTimeMoodKeyFromHour(21), 'evening');
    });

    test('returns night for hour 22–23', () {
      expect(resolveTimeMoodKeyFromHour(22), 'night');
      expect(resolveTimeMoodKeyFromHour(23), 'night');
    });

    test('returns late_night for hour 0–3', () {
      expect(resolveTimeMoodKeyFromHour(0), 'late_night');
      expect(resolveTimeMoodKeyFromHour(1), 'late_night');
      expect(resolveTimeMoodKeyFromHour(3), 'late_night');
    });

    test('resolveTimeMoodKey (live) returns a non-empty known key', () {
      const keys = {
        'morning', 'forenoon', 'noon', 'afternoon',
        'sunset', 'evening', 'night', 'late_night',
      };
      expect(keys, contains(resolveTimeMoodKey()));
    });
  });

  // ── Filter registry ────────────────────────────────────────────────────────
  group('creatorFilterPresets', () {
    test('no-filter preset resolves for null input', () {
      final preset = resolveCreatorFilterPreset(null);
      expect(preset.id, creatorNoFilter.id);
    });

    test('no-filter preset resolves for unknown id', () {
      final preset = resolveCreatorFilterPreset('does_not_exist');
      expect(preset.id, creatorNoFilter.id);
    });

    test('all preset matrices are 4x5 (20 doubles)', () {
      for (final preset in creatorFilterPresets) {
        expect(
          preset.previewMatrix.length,
          20,
          reason: '${preset.id} matrix should have 20 values',
        );
      }
    });

    test('known filter id resolves correctly', () {
      final preset = resolveCreatorFilterPreset('desert_honey');
      expect(preset.id, 'desert_honey');
      expect(preset.arabicName, 'عسل الصحراء');
    });

    test('label returns Arabic name when languageCode is ar', () {
      final preset = resolveCreatorFilterPreset('neon_souq');
      expect(preset.label('ar'), 'سوق نيون');
      expect(preset.label('en'), 'Neon Souq');
    });
  });

  // ── RecordedClipDraft Maslaki feature fields ───────────────────────────────
  group('RecordedClipDraft unique features', () {
    RecordedClipDraft buildClip({
      String? timeMoodKey,
      String? placePulseLabel,
      bool hasMaslakiSeal = false,
    }) {
      return RecordedClipDraft(
        mediaFile: const LocalMediaFile(
          name: 'test.mp4',
          path: '/tmp/test.mp4',
          bytes: null,
          mimeType: 'video/mp4',
        ),
        captureType: CreatorCaptureType.video,
        duration: const Duration(seconds: 30),
        mediaSize: null,
        captureSource: 'camera_video',
        filterId: null,
        effectId: null,
        trackingSamples: const <FaceTrackingSample>[],
        coverFrameMs: null,
        timeMoodKey: timeMoodKey,
        placePulseLabel: placePulseLabel,
        hasMaslakiSeal: hasMaslakiSeal,
      );
    }

    test('defaults to no seal, no place, no mood', () {
      final clip = buildClip();
      expect(clip.hasMaslakiSeal, isFalse);
      expect(clip.timeMoodKey, isNull);
      expect(clip.placePulseLabel, isNull);
    });

    test('stores all three Maslaki feature values', () {
      final clip = buildClip(
        timeMoodKey: 'evening',
        placePulseLabel: 'بسمّاية',
        hasMaslakiSeal: true,
      );
      expect(clip.timeMoodKey, 'evening');
      expect(clip.placePulseLabel, 'بسمّاية');
      expect(clip.hasMaslakiSeal, isTrue);
    });
  });

  // ── Creator adapters pass-through ─────────────────────────────────────────
  group('creator adapters with Maslaki features', () {
    CreatorPreviewDraft buildPreview({
      String? timeMoodKey,
      String? placePulseLabel,
      bool hasMaslakiSeal = false,
    }) {
      return CreatorPreviewDraft(
        mode: SocialCreatorMode.story,
        clip: RecordedClipDraft(
          mediaFile: const LocalMediaFile(
            name: 'clip.jpg',
            path: '/tmp/clip.jpg',
            bytes: null,
            mimeType: 'image/jpeg',
          ),
          captureType: CreatorCaptureType.photo,
          duration: Duration.zero,
          mediaSize: null,
          captureSource: 'camera_photo',
          filterId: 'basmaya_glow',
          effectId: null,
          trackingSamples: const <FaceTrackingSample>[],
          coverFrameMs: null,
          timeMoodKey: timeMoodKey,
          placePulseLabel: placePulseLabel,
          hasMaslakiSeal: hasMaslakiSeal,
        ),
      );
    }

    test('buildStoryDraftFromCreator carries timeMoodKey', () {
      final draft = buildStoryDraftFromCreator(
        buildPreview(timeMoodKey: 'sunset'),
      );
      expect(draft.timeMoodKey, 'sunset');
    });

    test('buildStoryDraftFromCreator carries placePulseLabel', () {
      final draft = buildStoryDraftFromCreator(
        buildPreview(placePulseLabel: 'بسمّاية'),
      );
      expect(draft.placePulseLabel, 'بسمّاية');
    });

    test('buildStoryDraftFromCreator carries hasMaslakiSeal', () {
      final draftOn = buildStoryDraftFromCreator(
        buildPreview(hasMaslakiSeal: true),
      );
      final draftOff = buildStoryDraftFromCreator(
        buildPreview(hasMaslakiSeal: false),
      );
      expect(draftOn.hasMaslakiSeal, isTrue);
      expect(draftOff.hasMaslakiSeal, isFalse);
    });

    test('buildReelStyleFromCreator emits timeMoodKey when set', () {
      const preview = CreatorPreviewDraft(
        mode: SocialCreatorMode.reel,
        clip: RecordedClipDraft(
          mediaFile: LocalMediaFile(
            name: 'reel.mp4',
            path: '/tmp/reel.mp4',
            bytes: null,
            mimeType: 'video/mp4',
          ),
          captureType: CreatorCaptureType.video,
          duration: Duration(seconds: 45),
          mediaSize: null,
          captureSource: 'camera_video',
          filterId: null,
          effectId: null,
          trackingSamples: <FaceTrackingSample>[],
          coverFrameMs: 5000,
          timeMoodKey: 'night',
          placePulseLabel: 'المنصور',
          hasMaslakiSeal: true,
        ),
      );
      final style = buildReelStyleFromCreator(preview);
      expect(style['timeMoodKey'], 'night');
      expect(style['placePulseLabel'], 'المنصور');
      expect(style['hasMaslakiSeal'], isTrue);
    });

    test('buildReelStyleFromCreator omits optional keys when not set', () {
      const preview = CreatorPreviewDraft(
        mode: SocialCreatorMode.reel,
        clip: RecordedClipDraft(
          mediaFile: LocalMediaFile(
            name: 'reel.mp4',
            path: '/tmp/reel.mp4',
            bytes: null,
            mimeType: 'video/mp4',
          ),
          captureType: CreatorCaptureType.video,
          duration: Duration(seconds: 30),
          mediaSize: null,
          captureSource: 'camera_video',
          filterId: null,
          effectId: null,
          trackingSamples: <FaceTrackingSample>[],
          coverFrameMs: null,
        ),
      );
      final style = buildReelStyleFromCreator(preview);
      expect(style.containsKey('timeMoodKey'), isFalse);
      expect(style.containsKey('placePulseLabel'), isFalse);
      expect(style.containsKey('hasMaslakiSeal'), isFalse);
    });
  });

  // ── SocialStoryDraft serialization ────────────────────────────────────────
  group('SocialStoryDraft Maslaki feature serialization', () {
    test('toJson includes timeMoodKey and placePulseLabel when set', () {
      final draft = SocialStoryDraft.initialText().copyWith(
        timeMoodKey: 'morning',
        placePulseLabel: 'الكرادة',
        hasMaslakiSeal: true,
      );
      final json = draft.toJson();
      expect(json['timeMoodKey'], 'morning');
      expect(json['placePulseLabel'], 'الكرادة');
      expect(json['hasMaslakiSeal'], isTrue);
    });

    test('toJson omits hasMaslakiSeal when false', () {
      final draft = SocialStoryDraft.initialText().copyWith(
        hasMaslakiSeal: false,
      );
      expect(draft.toJson().containsKey('hasMaslakiSeal'), isFalse);
    });

    test('fromJson round-trips Maslaki feature fields', () {
      final original = SocialStoryDraft.initialText().copyWith(
        timeMoodKey: 'sunset',
        placePulseLabel: 'حي العدالة',
        hasMaslakiSeal: true,
      );
      final restored = SocialStoryDraft.fromJson(original.toJson());
      expect(restored.timeMoodKey, 'sunset');
      expect(restored.placePulseLabel, 'حي العدالة');
      expect(restored.hasMaslakiSeal, isTrue);
    });

    test('copyWith does not lose unrelated fields', () {
      final base = SocialStoryDraft.initialText().copyWith(
        timeMoodKey: 'noon',
        hasMaslakiSeal: true,
      );
      final updated = base.copyWith(placePulseLabel: 'الجادرية');
      expect(updated.timeMoodKey, 'noon');
      expect(updated.hasMaslakiSeal, isTrue);
      expect(updated.placePulseLabel, 'الجادرية');
    });
  });

  // ── Story segmentation ────────────────────────────────────────────────────
  group('StorySegmentDraft model', () {
    test('segment stores start and duration correctly', () {
      const segment = StorySegmentDraft(
        index: 0,
        startSec: 0.0,
        durationSec: 60.0,
      );
      expect(segment.startSec + segment.durationSec, 60.0);
    });

    test('multiple segments cover full duration without overlap', () {
      const totalSec = 130.0;
      final segments = <StorySegmentDraft>[];
      var start = 0.0;
      var index = 0;
      while (start < totalSec) {
        final remaining = totalSec - start;
        final clipSec = remaining > storySegmentMaxSeconds
            ? storySegmentMaxSeconds
            : remaining;
        segments.add(
          StorySegmentDraft(
            index: index,
            startSec: start,
            durationSec: clipSec,
          ),
        );
        start += clipSec;
        index++;
      }
      expect(segments.length, 3); // 60 + 60 + 10
      expect(segments.last.durationSec, closeTo(10.0, 0.001));
      // Verify coverage is contiguous
      for (var i = 1; i < segments.length; i++) {
        expect(
          segments[i].startSec,
          closeTo(
            segments[i - 1].startSec + segments[i - 1].durationSec,
            0.001,
          ),
        );
      }
    });
  });
}
