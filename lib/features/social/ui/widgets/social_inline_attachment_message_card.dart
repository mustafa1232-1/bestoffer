import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/media/media_cache_models.dart';
import '../../models/social_models.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialInlineAttachmentMessageCard extends StatelessWidget {
  final SocialChatAttachment attachment;
  final VoidCallback onTap;
  final MediaCacheScope scope;
  final int? userId;

  const SocialInlineAttachmentMessageCard({
    super.key,
    required this.attachment,
    required this.onTap,
    this.scope = MediaCacheScope.public,
    this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = attachment.effectiveKind;
    final title = (attachment.name ?? '').trim().isNotEmpty
        ? attachment.name!.trim()
        : attachment.previewLabel;
    final meta = _metaLine(context, attachment);

    if (kind == 'image' || kind == 'video') {
      final previewUrl = attachment.resolvedPreviewUrl;
      final aspectRatio = _aspectRatioFor(attachment);
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.48),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: previewUrl == null
                      ? _InlineAttachmentPlaceholder(
                          attachment: attachment,
                          isVideo: kind == 'video',
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedAppImage(
                              imageUrl: previewUrl,
                              cacheIdentity:
                                  'social_inline_${attachment.traceId ?? attachment.url.hashCode}',
                              scope: scope,
                              userId: userId,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => _InlineAttachmentPlaceholder(
                                attachment: attachment,
                                isVideo: kind == 'video',
                              ),
                              errorWidget: (context, url, error) =>
                                  _InlineAttachmentPlaceholder(
                                attachment: attachment,
                                isVideo: kind == 'video',
                              ),
                            ),
                            if (kind == 'video')
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.black.withValues(alpha: 0.02),
                                      Colors.black.withValues(alpha: 0.22),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            if (kind == 'video')
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.42),
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),
                            if ((attachment.normalizedUploadState ?? '').isNotEmpty &&
                                attachment.normalizedUploadState != 'ready')
                              PositionedDirectional(
                                top: 8,
                                end: 8,
                                child: _StateChip(state: attachment.normalizedUploadState!),
                              ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.48),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: scheme.primary.withValues(alpha: 0.12),
              ),
              child: Icon(
                _kindIcon(kind),
                color: scheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  static double _aspectRatioFor(SocialChatAttachment attachment) {
    final width = attachment.width;
    final height = attachment.height;
    if (width != null &&
        height != null &&
        width > 0 &&
        height > 0) {
      final ratio = width / height;
      if (ratio.isFinite && ratio > 0.25 && ratio < 4) {
        return ratio;
      }
    }
    return attachment.isVideo ? 16 / 9 : 1.2;
  }

  static IconData _kindIcon(String kind) {
    switch (kind) {
      case 'image':
        return Icons.image_outlined;
      case 'video':
        return Icons.videocam_outlined;
      case 'audio':
        return Icons.mic_rounded;
      default:
        return Icons.attach_file_rounded;
    }
  }

  static String _metaLine(BuildContext context, SocialChatAttachment attachment) {
    final l10n = context.l10n;
    final parts = <String>[];
    switch (attachment.effectiveKind) {
      case 'image':
        parts.add(l10n.commonImage);
        break;
      case 'video':
        parts.add(l10n.commonVideo);
        break;
      case 'audio':
        parts.add(l10n.socialChatThreadVoiceMessageReady);
        break;
      default:
        parts.add(l10n.commonFile);
        break;
    }
    final sizeBytes = attachment.sizeBytes;
    if (sizeBytes != null && sizeBytes > 0) {
      parts.add(_formatBytes(sizeBytes));
    }
    final state = attachment.normalizedUploadState;
    if (state != null && state.isNotEmpty && state != 'ready') {
      parts.add(state.toUpperCase());
    }
    return parts.join(' • ');
  }
}

class _InlineAttachmentPlaceholder extends StatelessWidget {
  final SocialChatAttachment attachment;
  final bool isVideo;

  const _InlineAttachmentPlaceholder({
    required this.attachment,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.22),
            scheme.secondary.withValues(alpha: 0.12),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVideo ? Icons.play_circle_outline_rounded : Icons.image_outlined,
              color: scheme.primary,
              size: 42,
            ),
            const SizedBox(height: 6),
            Text(
              attachment.previewLabel,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final String state;

  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final label = state.trim().toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
