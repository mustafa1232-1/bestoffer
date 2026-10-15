import 'creator_filter_registry.dart';

/// One encode for trimming, playback speed, sound and color. Input duration is
/// deliberately before -i: an output -t would truncate slow-motion audio/video.
List<String> buildReelExportArguments({
  required String inputPath,
  required String outputPath,
  required double durationSeconds,
  double startSeconds = 0,
  double speed = 1,
  double volume = 1,
  String? filterId,
}) {
  if (!durationSeconds.isFinite ||
      durationSeconds <= 0 ||
      !startSeconds.isFinite ||
      startSeconds < 0 ||
      !speed.isFinite ||
      speed < 0.5 ||
      speed > 2 ||
      !volume.isFinite ||
      volume < 0 ||
      volume > 1) {
    throw ArgumentError('Invalid video export range, speed or volume');
  }
  final preset = resolveCreatorFilterPreset(filterId);
  final videoGraph = [
    'setpts=(PTS-STARTPTS)/${speed.toStringAsFixed(3)}',
    if (preset.id != creatorNoFilter.id) preset.ffmpegFilterGraph,
    'format=yuv420p',
  ].join(',');
  return [
    '-y',
    '-ss',
    startSeconds.toStringAsFixed(3),
    '-t',
    durationSeconds.toStringAsFixed(3),
    '-i',
    inputPath,
    '-map',
    '0:v:0',
    '-map',
    '0:a:0?',
    '-vf',
    videoGraph,
    '-af',
    'asetpts=PTS-STARTPTS,atempo=${speed.toStringAsFixed(3)},volume=${volume.toStringAsFixed(3)}',
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
}
