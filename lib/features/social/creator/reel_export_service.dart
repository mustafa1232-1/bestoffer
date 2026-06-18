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
    final args = <String>[
      '-y',
      '-i',
      inputPath,
      '-t',
      maxDurationSeconds.toStringAsFixed(3),
      if (preset.id != creatorNoFilter.id) ...['-vf', preset.ffmpegFilterGraph],
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '22',
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
