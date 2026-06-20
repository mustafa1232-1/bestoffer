import 'dart:ui';

import '../../../core/files/local_media_file.dart';

enum SocialCreatorMode { story, reel }

enum CreatorPermissionState { checking, granted, denied, permanentlyDenied }

enum CreatorCaptureType { photo, video }

class CreatorCapabilitySnapshot {
  final bool hasCamera;
  final bool supportsPhotoCapture;
  final bool supportsVideoCapture;
  final bool supportsFrontCamera;
  final bool supportsRearCamera;
  final bool supportsFlash;
  final bool supportsFaceTracking;
  final bool supportsPhotoEffects;
  final bool supportsVideoEffects;
  final String? unsupportedReason;

  const CreatorCapabilitySnapshot({
    required this.hasCamera,
    required this.supportsPhotoCapture,
    required this.supportsVideoCapture,
    required this.supportsFrontCamera,
    required this.supportsRearCamera,
    required this.supportsFlash,
    required this.supportsFaceTracking,
    required this.supportsPhotoEffects,
    required this.supportsVideoEffects,
    required this.unsupportedReason,
  });
}

/// Filter families. `color` = global color grade; `beauty` = portrait-tuned
/// tone/light grade (NOT geometric face shaping — that needs a face mesh).
enum CreatorFilterCategory { color, beauty }

class CreatorFilterPreset {
  final String id;
  final String arabicName;
  final String englishName;
  final List<double> previewMatrix;
  final String ffmpegFilterGraph;
  final CreatorFilterCategory category;

  /// True only when the filter genuinely renders in live preview AND export.
  /// Never expose a non-working filter to the user.
  final bool supported;

  const CreatorFilterPreset({
    required this.id,
    required this.arabicName,
    required this.englishName,
    required this.previewMatrix,
    required this.ffmpegFilterGraph,
    this.category = CreatorFilterCategory.color,
    this.supported = true,
  });

  String label(String languageCode) =>
      languageCode == 'ar' ? arabicName : englishName;
}

class CreatorEffectPreset {
  final String id;
  final String arabicName;
  final String englishName;
  final bool supportsPhotoExport;
  final bool supportsVideoExport;

  /// AR face effects are only `supported` when backed by real anchored assets +
  /// a face mesh. Defaults to false so primitive/code-drawn effects are hidden
  /// from the user until professional assets land.
  final bool supported;

  const CreatorEffectPreset({
    required this.id,
    required this.arabicName,
    required this.englishName,
    this.supportsPhotoExport = true,
    this.supportsVideoExport = false,
    this.supported = false,
  });

  String label(String languageCode) =>
      languageCode == 'ar' ? arabicName : englishName;
}

class FaceTrackingSample {
  final Duration position;
  final Rect faceBounds;
  final double? roll;

  const FaceTrackingSample({
    required this.position,
    required this.faceBounds,
    required this.roll,
  });
}

class RecordedClipDraft {
  final LocalMediaFile mediaFile;
  final CreatorCaptureType captureType;
  final Duration duration;
  final Size? mediaSize;
  final String captureSource;
  final String? filterId;
  final String? effectId;
  final List<FaceTrackingSample> trackingSamples;
  final int? coverFrameMs;

  // ── Maslaki unique features ───────────────────────────────────────────────
  /// Time Mood key — one of: morning, forenoon, noon, afternoon, sunset, evening, night, late_night.
  final String? timeMoodKey;

  /// Place Pulse label — free-text location name confirmed by the user.
  final String? placePulseLabel;

  /// Whether the Maslaki Seal (gold watermark) should be applied to this clip.
  final bool hasMaslakiSeal;

  /// Maslaki Mood preset key — one of the curated mood cards
  /// (quick_trip, basmaya_morning, daily_coffee, on_the_way, order_arrived).
  final String? maslakiMoodKey;

  const RecordedClipDraft({
    required this.mediaFile,
    required this.captureType,
    required this.duration,
    required this.mediaSize,
    required this.captureSource,
    required this.filterId,
    required this.effectId,
    required this.trackingSamples,
    required this.coverFrameMs,
    this.timeMoodKey,
    this.placePulseLabel,
    this.hasMaslakiSeal = false,
    this.maslakiMoodKey,
  });
}

class StorySegmentDraft {
  final int index;
  final double startSec;
  final double durationSec;

  const StorySegmentDraft({
    required this.index,
    required this.startSec,
    required this.durationSec,
  });
}

class CreatorPreviewDraft {
  final SocialCreatorMode mode;
  final RecordedClipDraft clip;
  final List<StorySegmentDraft> storySegments;
  final String? sequenceId;

  const CreatorPreviewDraft({
    required this.mode,
    required this.clip,
    this.storySegments = const <StorySegmentDraft>[],
    this.sequenceId,
  });
}
