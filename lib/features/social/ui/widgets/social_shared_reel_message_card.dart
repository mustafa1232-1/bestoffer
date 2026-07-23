import 'package:flutter/material.dart';

import '../../../../core/media/cached_app_image.dart';
import '../../models/social_models.dart';

class SocialSharedReelMessageCard extends StatelessWidget {
  final SocialSharedEntity entity;
  final VoidCallback? onTap;
  final bool compact;

  const SocialSharedReelMessageCard({
    super.key,
    required this.entity,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final posterUrl = _trimmed(entity.imageUrl);
    final caption = _trimmed(entity.subtitle);
    final authorName = _trimmed(entity.authorDisplayName) ?? entity.title;
    final authorUsername = _trimmed(entity.authorUsername);
    final authorAvatarUrl = _trimmed(entity.authorAvatarUrl);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.68),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: compact ? 1.05 : 0.78,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterUrl != null)
                      Image(
                        image: AppCachedImageProvider(
                          posterUrl,
                          cacheIdentity: 'shared_reel_${entity.id}',
                        ),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _ReelPosterFallback(
                              color: scheme.primary.withValues(alpha: 0.16),
                            ),
                      )
                    else
                      _ReelPosterFallback(
                        color: scheme.primary.withValues(alpha: 0.16),
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.45),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.58),
                          ],
                          stops: const [0, 0.42, 1],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 10,
                      start: 10,
                      end: 10,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: Colors.white24,
                            backgroundImage: authorAvatarUrl == null
                                ? null
                                : AppCachedImageProvider(
                                    authorAvatarUrl,
                                    cacheIdentity:
                                        'shared_reel_author_${entity.id}',
                                  ),
                            child: authorAvatarUrl == null
                                ? const Icon(
                                    Icons.person_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              authorUsername == null
                                  ? authorName
                                  : '$authorName @$authorUsername',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PositionedDirectional(
                      bottom: 10,
                      start: 10,
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    PositionedDirectional(
                      bottom: 14,
                      end: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.36),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          child: Text(
                            entity.previewLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (caption != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Text(
                  caption,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ],
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                caption == null ? 10 : 6,
                12,
                12,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 17,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entity.previewLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
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

  String? _trimmed(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}

class _ReelPosterFallback extends StatelessWidget {
  final Color color;

  const _ReelPosterFallback({required this.color});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: const Center(
        child: Icon(Icons.play_circle_fill_rounded, size: 52),
      ),
    );
  }
}
