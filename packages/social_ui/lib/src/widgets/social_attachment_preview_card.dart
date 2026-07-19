import 'dart:io';

import 'package:flutter/material.dart';
import 'package:social_core/social_core.dart';

class SocialAttachmentPreviewCard extends StatelessWidget {
  final LocalMediaFile file;
  final VoidCallback onClear;

  const SocialAttachmentPreviewCard({
    super.key,
    required this.file,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final languageCode =
        Localizations.maybeLocaleOf(context)?.languageCode.toLowerCase() ??
        'ar';
    final isArabic = languageCode == 'ar';
    final scheme = Theme.of(context).colorScheme;
    final kindLabel = file.isImage
        ? (isArabic ? 'صورة' : 'Image')
        : file.isVideo
        ? (isArabic ? 'فيديو' : 'Video')
        : file.isAudio
        ? (isArabic ? 'رسالة صوتية' : 'Audio')
        : (isArabic ? 'ملف' : 'File');
    final sizeLabel = file.sizeBytes == null || file.sizeBytes! <= 0
        ? null
        : _formatBytes(file.sizeBytes!);
    final meta = <String>[
      kindLabel,
      if (sizeLabel != null) sizeLabel,
    ].join(' • ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.76),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AttachmentPreviewThumb(file: file),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isArabic ? 'إزالة' : 'Remove',
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreviewThumb extends StatelessWidget {
  final LocalMediaFile file;

  const _AttachmentPreviewThumb({required this.file});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (file.isImage && file.hasBytes) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          file.bytes!,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    final path = file.path?.trim();
    if (file.isImage && path != null && path.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          File(path),
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainer,
      ),
      child: Icon(
        file.isVideo
            ? Icons.videocam_rounded
            : file.isAudio
            ? Icons.mic_rounded
            : Icons.attach_file_rounded,
        color: scheme.primary,
        size: 30,
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
