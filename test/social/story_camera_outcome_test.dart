import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/files/local_media_file.dart';
import 'package:maslaki/features/social/creator/creator_models.dart';
import 'package:maslaki/features/social/creator/social_camera_creator_screen.dart';

void main() {
  group('StoryCameraOutcome', () {
    CreatorPreviewDraft buildDraft() {
      return const CreatorPreviewDraft(
        mode: SocialCreatorMode.story,
        clip: RecordedClipDraft(
          mediaFile: LocalMediaFile(
            name: 'shot.jpg',
            path: '/tmp/shot.jpg',
            bytes: null,
            mimeType: 'image/jpeg',
          ),
          captureType: CreatorCaptureType.photo,
          duration: Duration.zero,
          mediaSize: null,
          captureSource: 'camera_photo',
          filterId: null,
          effectId: null,
          trackingSamples: <FaceTrackingSample>[],
          coverFrameMs: null,
        ),
      );
    }

    test('media outcome carries the draft and is not text mode', () {
      final outcome = StoryCameraOutcome.media(buildDraft());
      expect(outcome.textMode, isFalse);
      expect(outcome.mediaDraft, isNotNull);
      expect(outcome.mediaDraft!.clip.captureSource, 'camera_photo');
    });

    test('text outcome has no draft and flags text mode', () {
      const outcome = StoryCameraOutcome.text();
      expect(outcome.textMode, isTrue);
      expect(outcome.mediaDraft, isNull);
    });
  });

  group('Maslaki Mood registry', () {
    test('exposes the five curated mood keys in order', () {
      expect(kMaslakiMoodKeys, <String>[
        'quick_trip',
        'basmaya_morning',
        'daily_coffee',
        'on_the_way',
        'order_arrived',
      ]);
    });
  });
}
