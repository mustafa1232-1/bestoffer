import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/files/local_media_file.dart';
import '../../social/creator/creator_temp_media_service.dart';
import '../../social/creator/reel_export_service.dart';
import '../pickers/social_media_picker_v3.dart';
import 'reel_video_edits.dart';

/// The editor owns exported temporary files. A retry reuses the previous encode;
/// a new edit always starts with the original, never an already compressed copy.
class ReelVideoPreparation {
  ReelVideoPreparation(
    this.source, {
    this.exporter = const ReelExportService(CreatorTempMediaService()),
  });

  final PickedSocialMedia source;
  final ReelExportService exporter;
  ReelVideoEdits? _cachedEdits;
  PickedSocialMedia? _cachedVideo;
  CancelToken? _activeCancellation;
  bool _disposed = false;

  Future<PickedSocialMedia> prepare(
    ReelVideoEdits edits,
    void Function(double) onProgress,
    CancelToken cancellation,
  ) async {
    if (_disposed) throw StateError('Editor is disposed');
    if (cancellation.isCancelled) throw cancellation.cancelError!;
    if (!edits.isValid) throw ArgumentError('Invalid reel edits');
    if (!edits.requiresExport) return source;
    if (kIsWeb) {
      throw UnsupportedError('Local video export is not available on web');
    }
    if (_cachedEdits == edits &&
        _cachedVideo != null &&
        await File(_cachedVideo!.path).exists()) {
      if (_disposed) throw StateError('Editor is disposed');
      if (cancellation.isCancelled) throw cancellation.cancelError!;
      onProgress(1);
      return _cachedVideo!;
    }
    _activeCancellation = cancellation;
    final output = await exporter.exportVideo(
      sourceFile: LocalMediaFile(
        name: source.name,
        path: source.path,
        bytes: null,
        mimeType: source.mimeType,
      ),
      maxDurationSeconds: edits.selectedDurationMs / 1000,
      startSeconds: edits.startMs / 1000,
      speed: edits.speed,
      volume: edits.volume,
      filterId: edits.filterId,
      prefix: 'reel_edited',
      onProgress: onProgress,
      cancelToken: cancellation,
    );
    final file = File(output.path!);
    if (_disposed || cancellation.isCancelled) {
      await file.delete();
      throw cancellation.cancelError ?? StateError('Editor is disposed');
    }
    final size = await file.length();
    if (_disposed || cancellation.isCancelled) {
      await _delete(file.path);
      throw cancellation.cancelError ?? StateError('Editor is disposed');
    }
    if (size <= 0) {
      await file.delete();
      throw StateError('Video export is empty');
    }
    final previous = _cachedVideo;
    _cachedEdits = edits;
    final prepared = PickedSocialMedia(
      path: file.path,
      name: output.name,
      mimeType: 'video/mp4',
      sizeBytes: size,
      type: PickedMediaType.video,
      durationMs: edits.outputDurationMs,
    );
    _cachedVideo = prepared;
    if (previous != null) await _delete(previous.path);
    if (_disposed) throw StateError('Editor is disposed');
    if (cancellation.isCancelled) throw cancellation.cancelError!;
    return prepared;
  }

  Future<void> dispose() async {
    _disposed = true;
    _activeCancellation?.cancel();
    final cached = _cachedVideo;
    _cachedVideo = null;
    if (cached != null) await _delete(cached.path);
  }

  Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      /* Already removed by cache cleanup. */
    }
  }
}
