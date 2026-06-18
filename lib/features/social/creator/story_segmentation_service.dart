import 'dart:io';

import 'package:video_player/video_player.dart';

import '../../../core/files/local_media_file.dart';
import 'creator_constants.dart';
import 'creator_models.dart';

class StorySegmentationService {
  Future<List<StorySegmentDraft>> buildSegments(LocalMediaFile mediaFile) async {
    if (!mediaFile.isVideo || (mediaFile.path ?? '').trim().isEmpty) {
      return const <StorySegmentDraft>[];
    }
    final controller = VideoPlayerController.file(File(mediaFile.path!));
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      if (duration <= Duration.zero) {
        return const <StorySegmentDraft>[];
      }
      final totalSeconds = duration.inMilliseconds / 1000.0;
      final segments = <StorySegmentDraft>[];
      var start = 0.0;
      var index = 0;
      while (start < totalSeconds) {
        final remaining = totalSeconds - start;
        final clipSeconds = remaining > storySegmentMaxSeconds
            ? storySegmentMaxSeconds
            : remaining;
        segments.add(
          StorySegmentDraft(
            index: index,
            startSec: double.parse(start.toStringAsFixed(3)),
            durationSec: double.parse(clipSeconds.toStringAsFixed(3)),
          ),
        );
        start += clipSeconds;
        index += 1;
      }
      return segments;
    } finally {
      await controller.dispose();
    }
  }
}
