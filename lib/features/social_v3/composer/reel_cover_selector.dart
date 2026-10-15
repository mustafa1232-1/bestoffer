import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/i18n/locale_text.dart';
import '../../social/ui/widgets/social_design_theme.dart';

class ReelCoverSelector extends StatefulWidget {
  const ReelCoverSelector({
    super.key,
    required this.controller,
    required this.initialFrameMs,
    this.startMs = 0,
    this.endMs,
  });
  final VideoPlayerController controller;
  final int initialFrameMs;
  final int startMs;
  final int? endMs;

  @override
  State<ReelCoverSelector> createState() => _ReelCoverSelectorState();
}

class _ReelCoverSelectorState extends State<ReelCoverSelector> {
  late double _frame;
  bool _seeking = false;
  double? _pendingSeek;

  double get _minimum => widget.startMs.toDouble();
  double get _maximum =>
      ((widget.endMs ?? widget.controller.value.duration.inMilliseconds) - 1)
          .clamp(
            widget.startMs,
            widget.controller.value.duration.inMilliseconds,
          )
          .toDouble();

  @override
  void initState() {
    super.initState();
    _frame = widget.initialFrameMs.toDouble().clamp(_minimum, _maximum);
    _seek(_frame);
  }

  Future<void> _seek(double frame) async {
    _pendingSeek = frame;
    if (_seeking) return;
    _seeking = true;
    try {
      await widget.controller.pause();
      while (mounted && _pendingSeek != null) {
        final next = _pendingSeek!;
        _pendingSeek = null;
        await widget.controller.seekTo(Duration(milliseconds: next.round()));
      }
    } finally {
      _seeking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    return Scaffold(
      backgroundColor: SocialDesignTheme.dark,
      appBar: AppBar(
        backgroundColor: SocialDesignTheme.dark,
        foregroundColor: Colors.white,
        title: Text(context.lt(ar: 'اختيار الغلاف', en: 'Choose cover')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: value.size.width,
                        height: value.size.height,
                        child: VideoPlayer(widget.controller),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                '${(_frame / 1000).toStringAsFixed(1)} s',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            Slider(
              value: _frame,
              min: _minimum,
              max: _maximum > _minimum ? _maximum : _minimum + 1,
              activeColor: SocialDesignTheme.gold,
              semanticFormatterCallback: (v) =>
                  '${(v / 1000).toStringAsFixed(1)} s',
              onChanged: _maximum <= _minimum
                  ? null
                  : (v) {
                      setState(() => _frame = v);
                      _seek(v);
                    },
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _frame.round()),
                  icon: const Icon(Icons.check),
                  label: Text(context.lt(ar: 'اعتماد الغلاف', en: 'Use cover')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
