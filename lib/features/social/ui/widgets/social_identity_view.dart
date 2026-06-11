import 'package:flutter/material.dart';

import '../../models/social_models.dart';

String socialPrimaryIdentityLabel(SocialAuthor author) {
  final username = (author.username ?? '').trim();
  if (username.isNotEmpty) return '@$username';
  return author.fullName.trim().isNotEmpty ? author.fullName.trim() : 'مستخدم';
}

class SocialIdentityView extends StatelessWidget {
  final SocialAuthor author;
  final TextStyle? primaryStyle;
  final TextStyle? secondaryStyle;
  final int maxLines;
  final bool center;
  final bool showDisplayName;
  final bool showRoleFallback;

  const SocialIdentityView({
    super.key,
    required this.author,
    this.primaryStyle,
    this.secondaryStyle,
    this.maxLines = 1,
    this.center = false,
    this.showDisplayName = true,
    this.showRoleFallback = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usernameLabel = socialPrimaryIdentityLabel(author);
    final displayName = author.fullName.trim();
    final secondaryText = displayName.isNotEmpty && usernameLabel != displayName
        ? displayName
        : (showRoleFallback ? author.role : '');

    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                usernameLabel,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style:
                    primaryStyle ??
                    theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            if (author.isPremiumCreator) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.verified_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
        if (showDisplayName && secondaryText.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            secondaryText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                secondaryStyle ??
                theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}
