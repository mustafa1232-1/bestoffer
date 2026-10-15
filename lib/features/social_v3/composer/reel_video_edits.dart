import 'package:flutter/foundation.dart';

const reelMaximumDurationMs = 3600 * 1000;
const reelPlaybackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Times are source-video milliseconds. Convert the cover only at publication.
@immutable
class ReelVideoEdits {
  const ReelVideoEdits({
    required this.sourceDurationMs,
    this.startMs = 0,
    this.endMs,
    this.speed = 1,
    this.volume = 1,
    this.filterId = 'none',
  });

  final int sourceDurationMs;
  final int startMs;
  final int? endMs;
  final double speed;
  final double volume;
  final String filterId;

  int get effectiveEndMs => endMs ?? sourceDurationMs;
  int get selectedDurationMs => effectiveEndMs - startMs;
  int get outputDurationMs => (selectedDurationMs / speed).ceil();
  bool get isValid =>
      sourceDurationMs > 0 &&
      startMs >= 0 &&
      effectiveEndMs <= sourceDurationMs &&
      selectedDurationMs > 0 &&
      reelPlaybackSpeeds.contains(speed) &&
      volume.isFinite &&
      volume >= 0 &&
      volume <= 1 &&
      outputDurationMs <= reelMaximumDurationMs;

  bool get requiresExport =>
      startMs != 0 ||
      effectiveEndMs != sourceDurationMs ||
      speed != 1 ||
      volume != 1 ||
      filterId != 'none';

  int outputFrameMs(int sourceFrameMs) =>
      ((sourceFrameMs.clamp(startMs, effectiveEndMs - 1) - startMs) / speed)
          .floor();

  ReelVideoEdits copyWith({
    int? startMs,
    int? endMs,
    double? speed,
    double? volume,
    String? filterId,
  }) => ReelVideoEdits(
    sourceDurationMs: sourceDurationMs,
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    speed: speed ?? this.speed,
    volume: volume ?? this.volume,
    filterId: filterId ?? this.filterId,
  );

  Map<String, Object> toJson() => {
    'sourceDurationMs': sourceDurationMs,
    'startMs': startMs,
    'endMs': effectiveEndMs,
    'speed': speed,
    'volume': volume,
    'filterId': filterId,
  };

  @override
  bool operator ==(Object other) =>
      other is ReelVideoEdits &&
      sourceDurationMs == other.sourceDurationMs &&
      startMs == other.startMs &&
      effectiveEndMs == other.effectiveEndMs &&
      speed == other.speed &&
      volume == other.volume &&
      filterId == other.filterId;

  @override
  int get hashCode => Object.hash(
    sourceDurationMs,
    startMs,
    effectiveEndMs,
    speed,
    volume,
    filterId,
  );
}
