import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:social_core/social_core.dart';
import 'social_voice_composer_controller.dart';

String formatSocialAudioDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999);
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class SocialAudioAttachmentBubble extends StatefulWidget {
  final SocialChatAttachment attachment;
  final Color? textColor;

  const SocialAudioAttachmentBubble({
    super.key,
    required this.attachment,
    this.textColor,
  });

  @override
  State<SocialAudioAttachmentBubble> createState() =>
      _SocialAudioAttachmentBubbleState();
}

class _SocialAudioAttachmentBubbleState
    extends State<SocialAudioAttachmentBubble> {
  static _SocialAudioAttachmentBubbleState? _activeOwner;

  late final AudioPlayer _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  bool _prepared = false;
  bool _playing = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(
      milliseconds: widget.attachment.durationMs?.clamp(0, 359999000) ?? 0,
    );
    _player = AudioPlayer();
    _positionSub = _player.onPositionChanged.listen((value) {
      if (!mounted) return;
      setState(() => _position = value);
    });
    _durationSub = _player.onDurationChanged.listen((value) {
      if (!mounted) return;
      setState(() => _duration = value);
    });
    _stateSub = _player.onPlayerStateChanged.listen((value) {
      if (!mounted) return;
      final playing = value == PlayerState.playing;
      if (!playing && _activeOwner == this) {
        _activeOwner = null;
      }
      setState(() => _playing = playing);
    });
  }

  @override
  void dispose() {
    if (_activeOwner == this) {
      _activeOwner = null;
    }
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _pauseFromExternal() async {
    if (_playing) {
      await _player.pause();
    }
  }

  Future<void> _togglePlayback() async {
    if (_loading) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_activeOwner != null && _activeOwner != this) {
      await _activeOwner!._pauseFromExternal();
    }
    _activeOwner = this;
    try {
      if (!_prepared) {
        setState(() => _loading = true);
        await _player.setSourceUrl(widget.attachment.url);
        _prepared = true;
      }
      await _player.resume();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        widget.textColor ?? Theme.of(context).colorScheme.onSurface;
    final total = _duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds;
    final progress = (_position.inMilliseconds / total).clamp(0.0, 1.0);
    return InkWell(
      onTap: _togglePlayback,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.black.withValues(alpha: 0.08),
          border: Border.all(color: textColor.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.14),
              ),
              child: IconButton(
                onPressed: _togglePlayback,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.attachment.previewLabel,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: progress,
                      backgroundColor: textColor.withValues(alpha: 0.16),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatSocialAudioDuration(_position)} / ${formatSocialAudioDuration(_duration)}',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.74),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SocialVoiceRecordingStatusCard extends StatelessWidget {
  final Duration duration;
  final bool locked;
  final String title;
  final String slideToLockLabel;
  final String lockedLabel;
  final String cancelLabel;
  final String stopLabel;
  final VoidCallback onCancel;
  final VoidCallback? onStop;

  const SocialVoiceRecordingStatusCard({
    super.key,
    required this.duration,
    required this.locked,
    required this.title,
    required this.slideToLockLabel,
    required this.lockedLabel,
    required this.cancelLabel,
    required this.stopLabel,
    required this.onCancel,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: locked
              ? scheme.primary.withValues(alpha: 0.28)
              : scheme.error.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            locked ? Icons.lock_rounded : Icons.mic_rounded,
            color: locked ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  locked ? lockedLabel : slideToLockLabel,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatSocialAudioDuration(duration),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          if (locked && onStop != null)
            IconButton(
              tooltip: stopLabel,
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(cancelLabel),
          ),
        ],
      ),
    );
  }
}

class SocialVoicePreviewCard extends StatefulWidget {
  final SocialVoiceRecordingDraft draft;
  final bool sending;
  final String title;
  final String playLabel;
  final String pauseLabel;
  final String deleteLabel;
  final String sendLabel;
  final VoidCallback onDelete;
  final Future<void> Function() onSend;

  const SocialVoicePreviewCard({
    super.key,
    required this.draft,
    required this.sending,
    required this.title,
    required this.playLabel,
    required this.pauseLabel,
    required this.deleteLabel,
    required this.sendLabel,
    required this.onDelete,
    required this.onSend,
  });

  @override
  State<SocialVoicePreviewCard> createState() => _SocialVoicePreviewCardState();
}

class _SocialVoicePreviewCardState extends State<SocialVoicePreviewCard> {
  static _SocialVoicePreviewCardState? _activeOwner;

  late final AudioPlayer _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loading = false;
  bool _playing = false;
  bool _prepared = false;

  @override
  void initState() {
    super.initState();
    _duration = widget.draft.duration;
    _player = AudioPlayer();
    _positionSub = _player.onPositionChanged.listen((value) {
      if (!mounted) return;
      setState(() => _position = value);
    });
    _durationSub = _player.onDurationChanged.listen((value) {
      if (!mounted) return;
      setState(() => _duration = value);
    });
    _stateSub = _player.onPlayerStateChanged.listen((value) {
      if (!mounted) return;
      final playing = value == PlayerState.playing;
      if (!playing && _activeOwner == this) {
        _activeOwner = null;
      }
      setState(() => _playing = playing);
    });
  }

  @override
  void dispose() {
    if (_activeOwner == this) {
      _activeOwner = null;
    }
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> pausePreview() async {
    if (_playing) {
      await _player.pause();
    }
  }

  Future<void> _togglePlayback() async {
    if (_loading || widget.draft.file.path == null) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_activeOwner != null && _activeOwner != this) {
      await _activeOwner!.pausePreview();
    }
    _activeOwner = this;
    try {
      if (!_prepared) {
        setState(() => _loading = true);
        await _player.setSourceDeviceFile(widget.draft.file.path!);
        _prepared = true;
      }
      await _player.resume();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds;
    final progress = (_position.inMilliseconds / total).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.14),
                ),
                child: IconButton(
                  tooltip: _playing ? widget.pauseLabel : widget.playLabel,
                  onPressed: _togglePlayback,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        value: progress,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.12),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatSocialAudioDuration(_position)} / ${formatSocialAudioDuration(_duration)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: widget.sending ? null : widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(widget.deleteLabel),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: widget.sending ? null : widget.onSend,
                icon: widget.sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(widget.sendLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
