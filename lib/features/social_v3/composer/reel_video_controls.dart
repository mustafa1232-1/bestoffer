import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../social/creator/creator_filter_registry.dart';
import 'reel_video_edits.dart';

enum ReelVideoTool { trim, speed, audio, filter }

String reelTime(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class ReelVideoControls extends StatelessWidget {
  const ReelVideoControls({
    super.key,
    required this.edits,
    required this.tool,
    required this.onEditStart,
    required this.onChanged,
  });

  final ReelVideoEdits edits;
  final ReelVideoTool tool;
  final VoidCallback onEditStart;
  final ValueChanged<ReelVideoEdits> onChanged;

  @override
  Widget build(BuildContext context) => switch (tool) {
    ReelVideoTool.trim => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reelTime(edits.startMs),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      reelTime(edits.effectiveEndMs),
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              Text(
                '${reelTime(edits.outputDurationMs)} / ${reelTime(reelMaximumDurationMs)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        Directionality(
          textDirection: TextDirection.ltr,
          child: RangeSlider(
            values: RangeValues(
              edits.startMs.toDouble(),
              edits.effectiveEndMs.toDouble(),
            ),
            min: 0,
            max: edits.sourceDurationMs.toDouble(),
            labels: RangeLabels(
              reelTime(edits.startMs),
              reelTime(edits.effectiveEndMs),
            ),
            semanticFormatterCallback: (v) => reelTime(v.round()),
            onChangeStart: (_) => onEditStart(),
            onChanged: (range) {
              final changed = edits.copyWith(
                startMs: range.start.round(),
                endMs: range.end.round(),
              );
              if (changed.isValid) onChanged(changed);
            },
          ),
        ),
      ],
    ),
    ReelVideoTool.speed => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SegmentedButton<double>(
        segments: [
          for (final speed in reelPlaybackSpeeds)
            ButtonSegment(
              value: speed,
              label: Text('${speed}x'),
              enabled: edits.copyWith(speed: speed).isValid,
            ),
        ],
        selected: {edits.speed},
        showSelectedIcon: false,
        onSelectionChanged: (value) {
          onEditStart();
          onChanged(edits.copyWith(speed: value.single));
        },
      ),
    ),
    ReelVideoTool.audio => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            tooltip: context.lt(
              ar: 'كتم الصوت الأصلي',
              en: 'Mute original audio',
            ),
            icon: Icon(edits.volume == 0 ? Icons.volume_off : Icons.volume_up),
            onPressed: () {
              onEditStart();
              onChanged(edits.copyWith(volume: edits.volume == 0 ? 1 : 0));
            },
          ),
          Expanded(
            child: Slider(
              value: edits.volume,
              label: '${(edits.volume * 100).round()}%',
              semanticFormatterCallback: (v) => '${(v * 100).round()}%',
              onChangeStart: (_) => onEditStart(),
              onChanged: (v) => onChanged(edits.copyWith(volume: v)),
            ),
          ),
          SizedBox(width: 44, child: Text('${(edits.volume * 100).round()}%')),
        ],
      ),
    ),
    ReelVideoTool.filter => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (final id in [
            'none',
            'warm_window',
            'blue_breeze',
            'deep_alley',
            'urban_soft',
            'monochrome',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(
                  context.lt(
                    ar: resolveCreatorFilterPreset(id).arabicName,
                    en: resolveCreatorFilterPreset(id).englishName,
                  ),
                ),
                selected: edits.filterId == id,
                onSelected: (_) {
                  onEditStart();
                  onChanged(edits.copyWith(filterId: id));
                },
              ),
            ),
        ],
      ),
    ),
  };
}
