import 'dart:io';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/files/local_media_file.dart';
import 'package:maslaki/features/social/creator/creator_temp_media_service.dart';
import 'package:maslaki/features/social/creator/reel_export_service.dart';
import 'package:maslaki/features/social_v3/composer/reel_video_edits.dart';
import 'package:maslaki/features/social_v3/composer/reel_video_preparation.dart';
import 'package:maslaki/features/social_v3/pickers/social_media_picker_v3.dart';

class _Exporter extends ReelExportService {
  _Exporter(this.directory)
    : super(CreatorTempMediaService(overrideRoot: directory));
  final Directory directory;
  int calls = 0;
  final sourcePaths = <String?>[];
  Completer<void>? gate;

  @override
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
    calls++;
    sourcePaths.add(sourceFile.path);
    await gate?.future;
    final file = await File(
      '${directory.path}/export-$calls.mp4',
    ).writeAsBytes([1, 2, 3]);
    onProgress?.call(1);
    return LocalMediaFile(
      name: 'export-$calls.mp4',
      path: file.path,
      bytes: null,
      mimeType: 'video/mp4',
    );
  }
}

void main() {
  late Directory directory;
  late _Exporter exporter;
  late ReelVideoPreparation preparation;
  late PickedSocialMedia source;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('maslaki-reel-test-');
    final file = await File(
      '${directory.path}/original.mp4',
    ).writeAsBytes([9, 8, 7, 6]);
    source = PickedSocialMedia(
      path: file.path,
      name: 'original.mp4',
      mimeType: 'video/mp4',
      sizeBytes: 4,
      type: PickedMediaType.video,
      durationMs: 30000,
    );
    exporter = _Exporter(directory);
    preparation = ReelVideoPreparation(source, exporter: exporter);
  });
  tearDown(() async {
    await preparation.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'unchanged media is not compressed, retry reuses output, re-edit starts from original',
    () async {
      const initial = ReelVideoEdits(sourceDurationMs: 30000);
      expect(
        await preparation.prepare(initial, (_) {}, CancelToken()),
        same(source),
      );
      expect(exporter.calls, 0);
      final edits = initial.copyWith(startMs: 1000, endMs: 11000, speed: 2);
      final first = await preparation.prepare(edits, (_) {}, CancelToken());
      final retry = await preparation.prepare(edits, (_) {}, CancelToken());
      expect(retry.path, first.path);
      expect(first.durationMs, 5000);
      expect(first.sizeBytes, 3);
      expect(exporter.calls, 1);
      final next = await preparation.prepare(
        edits.copyWith(volume: 0),
        (_) {},
        CancelToken(),
      );
      expect(exporter.calls, 2);
      expect(exporter.sourcePaths, [source.path, source.path]);
      expect(await File(first.path).exists(), isFalse);
      await preparation.dispose();
      expect(await File(next.path).exists(), isFalse);
      expect(await File(source.path).exists(), isTrue);
    },
  );

  test(
    'closing the editor during export cleans late output without touching original',
    () async {
      exporter.gate = Completer<void>();
      final cancellation = CancelToken();
      final exporting = preparation.prepare(
        const ReelVideoEdits(sourceDurationMs: 30000, volume: 0),
        (_) {},
        cancellation,
      );
      final assertion = expectLater(exporting, throwsA(isA<DioException>()));
      await preparation.dispose();
      expect(cancellation.isCancelled, isTrue);
      exporter.gate!.complete();
      await assertion;
      expect(await File('${directory.path}/export-1.mp4').exists(), isFalse);
      expect(await File(source.path).exists(), isTrue);
    },
  );
}
