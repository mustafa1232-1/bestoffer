import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/files/local_media_file.dart';
import 'package:maslaki/features/social/creator/creator_adapters.dart';
import 'package:maslaki/features/social/creator/creator_capabilities_service.dart';
import 'package:maslaki/features/social/creator/creator_models.dart';
import 'package:maslaki/features/social/models/social_story_document.dart';

void main() {
  group('social creator adapters', () {
    CreatorPreviewDraft buildPreview({
      SocialCreatorMode mode = SocialCreatorMode.story,
      String? filterId = 'royal_indigo',
      String? effectId = 'maslaki_glow',
      int? coverFrameMs = 1800,
    }) {
      return CreatorPreviewDraft(
        mode: mode,
        sequenceId: 'seq-1',
        storySegments: const <StorySegmentDraft>[
          StorySegmentDraft(index: 0, startSec: 0, durationSec: 30),
        ],
        clip: RecordedClipDraft(
          mediaFile: const LocalMediaFile(
            name: 'clip.mp4',
            path: '/tmp/clip.mp4',
            bytes: null,
            mimeType: 'video/mp4',
          ),
          captureType: CreatorCaptureType.video,
          duration: const Duration(seconds: 42, milliseconds: 250),
          mediaSize: null,
          captureSource: 'camera_video',
          filterId: filterId,
          effectId: effectId,
          trackingSamples: const <FaceTrackingSample>[],
          coverFrameMs: coverFrameMs,
        ),
      );
    }

    test('buildStoryDraftFromCreator preserves creator metadata', () {
      final preview = buildPreview();

      final draft = buildStoryDraftFromCreator(preview);

      expect(draft.mediaPath, '/tmp/clip.mp4');
      expect(draft.mediaName, 'clip.mp4');
      expect(draft.mediaMimeType, 'video/mp4');
      expect(draft.filterId, 'royal_indigo');
      expect(draft.effectId, 'maslaki_glow');
      expect(draft.captureSource, 'camera_video');
      expect(draft.mode, SocialStoryComposerMode.media);
    });

    test('buildReelStyleFromCreator emits additive reel metadata only', () {
      final preview = buildPreview(mode: SocialCreatorMode.reel);

      final style = buildReelStyleFromCreator(preview);

      expect(style['filterId'], 'royal_indigo');
      expect(style['effectId'], 'maslaki_glow');
      expect(style['captureSource'], 'camera_video');
      expect(style['durationSec'], 42.25);
      expect(style['coverFrameMs'], 1800);
    });

    test('creator capabilities gate video effects off when camera stack exists', () {
      final snapshot = CreatorCapabilitiesService().inspect(
        const <CameraDescription>[],
      );

      expect(snapshot.hasCamera, isFalse);
      expect(snapshot.supportsVideoEffects, isFalse);
      expect(snapshot.unsupportedReason, 'camera_unavailable');
    });
  });
}
