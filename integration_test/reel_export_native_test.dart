import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:maslaki/core/files/local_media_file.dart';
import 'package:maslaki/features/social/creator/creator_temp_media_service.dart';
import 'package:maslaki/features/social/creator/reel_export_service.dart';
import 'package:maslaki/features/social_v3/composer/reel_video_edits.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native export applies trim, speed, mute and monochrome to real media',
    (tester) async {
      final temp = await Directory.systemTemp.createTemp('maslaki-export-qa-');
      try {
        final sourcePath = '${temp.path}/source.mp4';
        final fixture = await FFmpegKit.executeWithArguments([
          '-y',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=180x320:rate=20:duration=4',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=1000:sample_rate=48000:duration=4',
          '-c:v',
          'libx264',
          '-pix_fmt',
          'yuv420p',
          '-c:a',
          'aac',
          '-shortest',
          sourcePath,
        ]);
        expect(
          ReturnCode.isSuccess(await fixture.getReturnCode()),
          isTrue,
          reason: await fixture.getAllLogsAsString(),
        );
        final exporter = ReelExportService(
          CreatorTempMediaService(overrideRoot: temp),
        );
        final source = LocalMediaFile(
          name: 'source.mp4',
          path: sourcePath,
          bytes: null,
          mimeType: 'video/mp4',
        );
        for (final speed in reelPlaybackSpeeds) {
          final progress = <double>[];
          final output = await exporter.exportVideo(
            sourceFile: source,
            maxDurationSeconds: 2,
            startSeconds: 1,
            speed: speed,
            volume: 0,
            filterId: 'monochrome',
            prefix: 'edited',
            onProgress: progress.add,
          );
          final infoSession = await FFprobeKit.getMediaInformation(
            output.path!,
          );
          final info = infoSession.getMediaInformation()!;
          expect(double.parse(info.getDuration()!), closeTo(2 / speed, 0.2));
          final video = info.getStreams().firstWhere(
            (stream) => stream.getType() == 'video',
          );
          expect(video.getWidth(), 180);
          expect(video.getHeight(), 320);
          expect(progress.last, 1);
          final player = VideoPlayerController.file(File(output.path!));
          try {
            await player.initialize().timeout(const Duration(seconds: 20));
            await player.seekTo(const Duration(milliseconds: 400));
            expect(player.value.isInitialized, isTrue);
            expect(player.value.hasError, isFalse);
            expect(player.value.size.width, 180);
            expect(player.value.size.height, 320);
          } finally {
            await player.dispose();
          }

          final audio = await FFmpegKit.executeWithArguments([
            '-i',
            output.path!,
            '-vn',
            '-af',
            'volumedetect',
            '-f',
            'null',
            '-',
          ]);
          expect(ReturnCode.isSuccess(await audio.getReturnCode()), isTrue);
          final logs = await audio.getAllLogsAsString() ?? '';
          final match = RegExp(r'mean_volume: (-?[\d.]+) dB').firstMatch(logs);
          expect(match, isNotNull, reason: logs);
          expect(double.parse(match!.group(1)!), lessThan(-80));

          final framePath = '${temp.path}/frame.rgb';
          final frame = await FFmpegKit.executeWithArguments([
            '-y',
            '-ss',
            '0.4',
            '-i',
            output.path!,
            '-frames:v',
            '1',
            '-pix_fmt',
            'rgb24',
            '-f',
            'rawvideo',
            framePath,
          ]);
          expect(ReturnCode.isSuccess(await frame.getReturnCode()), isTrue);
          final bytes = await File(framePath).readAsBytes();
          expect(bytes.length, 180 * 320 * 3);
          var nonBlack = 0;
          for (var i = 0; i < bytes.length; i += 3) {
            expect((bytes[i] - bytes[i + 1]).abs(), lessThanOrEqualTo(3));
            expect((bytes[i] - bytes[i + 2]).abs(), lessThanOrEqualTo(3));
            if (bytes[i] > 16) nonBlack++;
          }
          expect(nonBlack, greaterThan(1000));
        }
        final silentPath = '${temp.path}/silent.mp4';
        final silent = await FFmpegKit.executeWithArguments([
          '-y',
          '-i',
          sourcePath,
          '-an',
          '-c:v',
          'copy',
          silentPath,
        ]);
        expect(ReturnCode.isSuccess(await silent.getReturnCode()), isTrue);
        final silentOutput = await exporter.exportVideo(
          sourceFile: LocalMediaFile(
            name: 'silent.mp4',
            path: silentPath,
            bytes: null,
            mimeType: 'video/mp4',
          ),
          maxDurationSeconds: 2,
          startSeconds: 1,
          speed: 1.5,
          volume: 0.5,
          filterId: 'none',
          prefix: 'silent_edited',
        );
        final silentInfo = (await FFprobeKit.getMediaInformation(
          silentOutput.path!,
        )).getMediaInformation()!;
        expect(
          silentInfo.getStreams().where((s) => s.getType() == 'audio'),
          isEmpty,
        );

        final rotatedPath = '${temp.path}/rotated.mp4';
        final rotated = await FFmpegKit.executeWithArguments([
          '-y',
          '-display_rotation:v:0',
          '90',
          '-i',
          sourcePath,
          '-c',
          'copy',
          rotatedPath,
        ]);
        expect(ReturnCode.isSuccess(await rotated.getReturnCode()), isTrue);
        final rotatedSource = (await FFprobeKit.getMediaInformation(rotatedPath)).getMediaInformation()!;
        final sourceVideo = rotatedSource.getStreams().firstWhere((s) => s.getType() == 'video');
        final sideData = sourceVideo.getProperty('side_data_list') as List? ?? [];
        expect(sideData.any((entry) => entry is Map &&
          (num.tryParse('${entry['rotation']}')?.abs() == 90)), isTrue,
          reason: 'Rotation fixture must contain an actual display matrix');
        final rotatedOutput = await exporter.exportVideo(
          sourceFile: LocalMediaFile(
            name: 'rotated.mp4',
            path: rotatedPath,
            bytes: null,
            mimeType: 'video/mp4',
          ),
          maxDurationSeconds: 2,
          filterId: 'none',
          prefix: 'rotated_edited',
        );
        final rotatedInfo = (await FFprobeKit.getMediaInformation(
          rotatedOutput.path!,
        )).getMediaInformation()!;
        final rotatedVideo = rotatedInfo.getStreams().firstWhere(
          (s) => s.getType() == 'video',
        );
        expect(rotatedVideo.getWidth(), 320);
        expect(rotatedVideo.getHeight(), 180);
      } finally {
        await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
