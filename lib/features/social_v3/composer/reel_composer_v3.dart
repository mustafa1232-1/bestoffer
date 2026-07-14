import 'package:flutter/material.dart';

import '../pickers/social_media_picker_v3.dart';
import 'reel_composer_state.dart';

/// Reel editor + publish screen (§1). Opens *after* the native video gallery
/// has already returned a video. Shows caption/audience/toggles, then drives
/// [ReelComposerController] through upload → processing → published with a live
/// progress UI (`ReelUploadProgressV3` states are folded in here).
class ReelComposerV3 extends StatefulWidget {
  const ReelComposerV3({
    super.key,
    required this.video,
    required this.controller,
    this.onPublished,
  });

  final PickedSocialMedia video;
  final ReelComposerController controller;

  /// Called with the new reel id so the caller can open it in the V3 viewer.
  final void Function(int reelId)? onPublished;

  @override
  State<ReelComposerV3> createState() => _ReelComposerV3State();
}

class _ReelComposerV3State extends State<ReelComposerV3> {
  final _caption = TextEditingController();
  final String _audience = 'public';
  bool _comments = true;
  bool _sharing = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _caption.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final stage = widget.controller.stage;
    if (stage == ReelComposerStage.published) {
      final id = widget.controller.publishedReelId;
      if (id != null && id > 0) widget.onPublished?.call(id);
    }
    setState(() {});
  }

  Future<void> _publish() async {
    await widget.controller.publish(
      video: widget.video,
      caption: _caption.text.trim(),
      audience: _audience,
      commentsEnabled: _comments,
      sharingEnabled: _sharing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final busy = c.stage != ReelComposerStage.draft &&
        c.stage != ReelComposerStage.failed &&
        c.stage != ReelComposerStage.cancelled;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('ريل جديد'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 9 / 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Center(
                child: Icon(Icons.videocam_rounded, color: Colors.white38, size: 48),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _caption,
            enabled: !busy,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'اكتب وصفًا…  #وسم  @إشارة',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _comments,
            onChanged: busy ? null : (v) => setState(() => _comments = v),
            title: const Text('التعليقات', style: TextStyle(color: Colors.white)),
            activeThumbColor: const Color(0xFFE7B24B),
          ),
          SwitchListTile(
            value: _sharing,
            onChanged: busy ? null : (v) => setState(() => _sharing = v),
            title: const Text('المشاركة', style: TextStyle(color: Colors.white)),
            activeThumbColor: const Color(0xFFE7B24B),
          ),
          const SizedBox(height: 8),
          _StageView(controller: c),
          const SizedBox(height: 12),
          if (c.stage == ReelComposerStage.draft ||
              c.stage == ReelComposerStage.failed)
            FilledButton(
              onPressed: _publish,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE7B24B),
                foregroundColor: const Color(0xFF0D1B2A),
              ),
              child: Text(
                c.stage == ReelComposerStage.failed ? 'إعادة المحاولة' : 'نشر',
              ),
            ),
          if (c.stage == ReelComposerStage.uploading)
            OutlinedButton(
              onPressed: c.pauseUpload,
              child: const Text('إيقاف مؤقت'),
            ),
          if (c.stage == ReelComposerStage.paused)
            FilledButton(
              onPressed: c.resumeUpload,
              child: const Text('استئناف'),
            ),
        ],
      ),
    );
  }
}

class _StageView extends StatelessWidget {
  const _StageView({required this.controller});

  final ReelComposerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    switch (c.stage) {
      case ReelComposerStage.draft:
        return const SizedBox.shrink();
      case ReelComposerStage.creatingSession:
        return const _StatusLine(text: 'جاري تجهيز الرفع…');
      case ReelComposerStage.uploading:
      case ReelComposerStage.paused:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: c.progress,
              color: const Color(0xFFE7B24B),
              backgroundColor: Colors.white12,
            ),
            const SizedBox(height: 6),
            Text(
              '${(c.progress * 100).round()}%'
              '${c.stage == ReelComposerStage.paused ? ' (متوقف)' : ''}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        );
      case ReelComposerStage.processing:
        return const _StatusLine(text: 'جاري تجهيز الفيديو…');
      case ReelComposerStage.published:
        return const _StatusLine(text: 'تم النشر ✓', color: Color(0xFF4CAF50));
      case ReelComposerStage.failed:
        return _StatusLine(
          text: 'فشل: ${c.error ?? ''}',
          color: const Color(0xFFE53935),
        );
      case ReelComposerStage.cancelled:
        return const _StatusLine(text: 'أُلغي الرفع');
    }
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text, this.color = Colors.white70});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color))),
      ],
    );
  }
}
