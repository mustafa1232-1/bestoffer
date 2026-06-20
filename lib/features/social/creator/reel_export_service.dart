import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../../../core/files/local_media_file.dart';
import 'creator_filter_registry.dart';
import 'creator_temp_media_service.dart';

class ReelExportService {
  final CreatorTempMediaService tempMediaService;

  const ReelExportService(this.tempMediaService);

  Future<LocalMediaFile> exportVideo({
    required LocalMediaFile sourceFile,
    required double maxDurationSeconds,
    required String? filterId,
    required String prefix,
  }) async {
    final inputPath = (sourceFile.path ?? '').trim();
    if (inputPath.isEmpty) {
      throw StateError('The recorded clip has no readable file path.');
    }
    final preset = resolveCreatorFilterPreset(filterId);
    final outputPath = await tempMediaService.newFilePath(
      prefix: prefix,
      extension: 'mp4',
    );
    // Always normalise to 8-bit yuv420p. Phones that record 10-bit HEVC (or the
    // color filter chain) can otherwise produce a pixel format the Android /
    // video_player decoder cannot display — the video shows black while audio
    // still plays. Appending format=yuv420p to the filter graph (or -pix_fmt
    // when there is no graph) guarantees a universally decodable output.
    final hasFilter = preset.id != creatorNoFilter.id;
    final videoGraph = hasFilter
        ? '${preset.ffmpegFilterGraph},format=yuv420p'
        : 'format=yuv420p';
    final args = <String>[
      '-y',
      '-i',
      inputPath,
      '-t',
      maxDurationSeconds.toStringAsFixed(3),
      '-vf',
      videoGraph,
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '22',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-movflags',
      '+faststart',
      outputPath,
    ];
    final session = await FFmpegKit.executeWithArguments(args);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      throw StateError('Video export failed with code ${returnCode?.getValue()}.');
    }
    return LocalMediaFile(
      name: File(outputPath).uri.pathSegments.last,
      path: outputPath,
      bytes: null,
      mimeType: 'video/mp4',
    );
  }
}
