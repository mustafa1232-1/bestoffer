import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../../../core/files/local_media_file.dart';
import 'creator_temp_media_service.dart';
import 'reel_export_arguments.dart';

class ReelExportService {
  final CreatorTempMediaService tempMediaService;

  const ReelExportService(this.tempMediaService);

  Future<LocalMediaFile> exportVideo({
    required LocalMediaFile sourceFile,
    required double maxDurationSeconds,
    required String? filterId,
    required String prefix,
    double startSeconds = 0,
    double speed = 1,
    double volume = 1,
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final inputPath = (sourceFile.path ?? '').trim();
    if (inputPath.isEmpty) {
      throw StateError('The recorded clip has no readable file path.');
    }
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final outputPath = await tempMediaService.newFilePath(
      prefix: prefix,
      extension: 'mp4',
    );
    final args = buildReelExportArguments(
      inputPath: inputPath,
      outputPath: outputPath,
      durationSeconds: maxDurationSeconds,
      startSeconds: startSeconds,
      speed: speed,
      volume: volume,
      filterId: filterId,
    );
    final complete = Completer<FFmpegSession>();
    var finished = false;
    try {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      final session = await FFmpegKit.executeWithArgumentsAsync(
        args,
        (session) {
          if (!complete.isCompleted) complete.complete(session);
        },
        null,
        (statistics) {
          if (!finished && cancelToken?.isCancelled != true) {
            onProgress?.call(
              (statistics.getTime() / (maxDurationSeconds * 1000 / speed))
                  .clamp(0.0, 1.0),
            );
          }
        },
      );
      final sessionId = session.getSessionId();
      // Never cancel without an id: that would terminate unrelated exports.
      if (cancelToken != null && sessionId != null) {
        unawaited(
          cancelToken.whenCancel
              .then((_) async {
                if (!finished) await FFmpegKit.cancel(sessionId);
              })
              .catchError((Object _) {}),
        );
      }
      final completedSession = await complete.future;
      final returnCode = await completedSession.getReturnCode();
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      if (!ReturnCode.isSuccess(returnCode)) {
        throw StateError(
          'Video export failed with code ${returnCode?.getValue()}.',
        );
      }
      onProgress?.call(1);
    } catch (_) {
      final output = File(outputPath);
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      finished = true;
    }
    return LocalMediaFile(
      name: File(outputPath).uri.pathSegments.last,
      path: outputPath,
      bytes: null,
      mimeType: 'video/mp4',
    );
  }
}
