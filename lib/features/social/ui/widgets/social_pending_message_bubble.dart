import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/social_pending_message.dart';

class SocialPendingMessageBubble extends StatelessWidget {
  final LocalPendingMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  const SocialPendingMessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bubbleColor = scheme.primary.withValues(alpha: 0.12);
    final borderColor = scheme.primary.withValues(alpha: 0.22);
    final isFailed = message.status == LocalPendingMessageStatus.failed;
    final isCancelled = message.status == LocalPendingMessageStatus.cancelled;
    final statusLabel = switch (message.status) {
      LocalPendingMessageStatus.queued => 'Queued',
      LocalPendingMessageStatus.uploading => 'Uploading',
      LocalPendingMessageStatus.sent => 'Sent',
      LocalPendingMessageStatus.failed => 'Failed',
      LocalPendingMessageStatus.cancelled => 'Cancelled',
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PendingKindThumb(message: message),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kindLabel(message),
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (message.status == LocalPendingMessageStatus.queued ||
                      message.status == LocalPendingMessageStatus.uploading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: scheme.primary,
                      ),
                    )
                  else
                    Icon(
                      isFailed
                          ? Icons.error_outline_rounded
                          : isCancelled
                          ? Icons.cancel_outlined
                          : Icons.check_circle_outline_rounded,
                      color: isFailed
                          ? scheme.error
                          : isCancelled
                          ? scheme.onSurfaceVariant
                          : scheme.primary,
                    ),
                ],
              ),
              if (_shouldShowBody(message)) ...[
                const SizedBox(height: 10),
                Text(
                  message.body.trim(),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
              if (message.uploadProgress > 0 &&
                  message.uploadProgress < 1 &&
                  message.status != LocalPendingMessageStatus.sent) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: message.uploadProgress.clamp(0.0, 1.0),
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
                  ),
                ),
              ],
              if ((isFailed || message.status == LocalPendingMessageStatus.queued) &&
                  (onRetry != null || onCancel != null)) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onRetry != null)
                      OutlinedButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                      ),
                    if (onCancel != null)
                      TextButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Cancel'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingKindThumb extends StatelessWidget {
  final LocalPendingMessage message;

  const _PendingKindThumb({required this.message});

  @override
  Widget build(BuildContext context) {
    final kind = message.kind.trim().toLowerCase();
    final localFile = message.localFile;
    final borderRadius = BorderRadius.circular(12);
    final scheme = Theme.of(context).colorScheme;

    if (kind == 'image' && localFile != null) {
      if (localFile.hasBytes) {
        return ClipRRect(
          borderRadius: borderRadius,
          child: Image.memory(
            localFile.bytes!,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      }
      final path = localFile.path?.trim();
      if (path != null && path.isNotEmpty) {
        return ClipRRect(
          borderRadius: borderRadius,
          child: Image.file(
            File(path),
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      }
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: scheme.primary.withValues(alpha: 0.14),
      ),
      child: Icon(
        switch (kind) {
          'audio' => Icons.mic_rounded,
          'video' => Icons.videocam_rounded,
          'image' => Icons.image_rounded,
          'text' => Icons.chat_bubble_outline_rounded,
          _ => Icons.insert_drive_file_outlined,
        },
        color: scheme.primary,
      ),
    );
  }
}

String _kindLabel(LocalPendingMessage message) {
  if (message.isAudio) return 'Audio';
  if (message.isImage) return 'Image';
  if (message.isVideo) return 'Video';
  if (message.isText) return 'Message';
  return 'File';
}

bool _shouldShowBody(LocalPendingMessage message) {
  final body = message.body.trim();
  if (body.isEmpty) return false;
  return message.isText || message.isAudio || message.isImage || message.isVideo;
}
