import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/creator/reel_export_arguments.dart';
import 'package:maslaki/features/social/creator/creator_filter_registry.dart';
import 'package:maslaki/features/social_v3/composer/reel_video_edits.dart';

void main() {
  test(
    'unedited videos skip export; all content-changing controls require it',
    () {
      const source = ReelVideoEdits(sourceDurationMs: 30000);
      expect(source.isValid, isTrue);
      expect(source.requiresExport, isFalse);
      for (final edit in [
        source.copyWith(startMs: 1000),
        source.copyWith(endMs: 10000),
        source.copyWith(speed: 0.5),
        source.copyWith(volume: 0),
        source.copyWith(filterId: 'monochrome'),
      ]) {
        expect(edit.isValid, isTrue);
        expect(edit.requiresExport, isTrue);
      }
    },
  );

  test(
    'source cover is mapped through trim and speed, clamped inside output',
    () {
      const edits = ReelVideoEdits(
        sourceDurationMs: 30000,
        startMs: 5000,
        endMs: 15000,
        speed: 2,
      );
      expect(edits.outputDurationMs, 5000);
      expect(edits.outputFrameMs(9000), 2000);
      expect(edits.outputFrameMs(0), 0);
      expect(edits.outputFrameMs(30000), 4999);
    },
  );

  test(
    'invalid ranges, volume, speeds and slow-motion beyond server limit are rejected',
    () {
      const source = ReelVideoEdits(sourceDurationMs: 30000);
      for (final edit in [
        source.copyWith(startMs: -1),
        source.copyWith(endMs: 0),
        source.copyWith(endMs: 40000),
        source.copyWith(speed: double.nan),
        source.copyWith(volume: -1),
        source.copyWith(volume: double.infinity),
        const ReelVideoEdits(
          sourceDurationMs: reelMaximumDurationMs,
          speed: 0.5,
        ),
      ]) {
        expect(edit.isValid, isFalse);
      }
    },
  );

  for (final speed in reelPlaybackSpeeds) {
    test(
      'export applies ${speed}x to audio and video with input-range trim',
      () {
        final args = buildReelExportArguments(
          inputPath: '/video/source with spaces.mp4',
          outputPath: '/video/edited.mp4',
          durationSeconds: 10,
          startSeconds: 5,
          speed: speed,
          volume: 0.35,
          filterId: 'monochrome',
        );
        String option(String key) => args[args.indexOf(key) + 1];
        expect(option('-ss'), '5.000');
        expect(option('-t'), '10.000');
        expect(args.indexOf('-t'), lessThan(args.indexOf('-i')));
        expect(option('-i'), '/video/source with spaces.mp4');
        expect(
          option('-vf'),
          contains('setpts=(PTS-STARTPTS)/${speed.toStringAsFixed(3)}'),
        );
        expect(
          option('-vf'),
          contains(resolveCreatorFilterPreset('monochrome').ffmpegFilterGraph),
        );
        expect(
          option('-af'),
          contains('atempo=${speed.toStringAsFixed(3)},volume=0.350'),
        );
        expect(args, contains('0:a:0?'));
        expect(option('-pix_fmt'), 'yuv420p');
        expect(args.where((a) => a == '-c:v').length, 1);
        expect(args, isNot(contains('-s')));
      },
    );
  }

  test(
    'export rejects malformed numeric parameters before invoking FFmpeg',
    () {
      expect(
        () => buildReelExportArguments(
          inputPath: 'a',
          outputPath: 'b',
          durationSeconds: double.infinity,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildReelExportArguments(
          inputPath: 'a',
          outputPath: 'b',
          durationSeconds: 5,
          speed: 0,
        ),
        throwsArgumentError,
      );
    },
  );
}
