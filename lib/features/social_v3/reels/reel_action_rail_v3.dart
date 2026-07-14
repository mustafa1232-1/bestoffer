import 'package:flutter/material.dart';

import '../domain/reel_view_data.dart';
import '../media/social_safe_image.dart';

/// Vertical action rail on the lower-right of a full-screen reel (§3).
///
/// Each control is at least 44×44 and pairs an icon with a count. The author
/// avatar is intentionally circular — the "no circular media" rule applies to
/// the reel video/poster, not to the avatar chip.
class ReelActionRailV3 extends StatelessWidget {
  const ReelActionRailV3({
    super.key,
    required this.reel,
    this.onLike,
    this.onComments,
    this.onShare,
    this.onSave,
    this.onMore,
    this.onAvatar,
  });

  final ReelV3ViewData reel;
  final VoidCallback? onLike;
  final VoidCallback? onComments;
  final VoidCallback? onShare;
  final VoidCallback? onSave;
  final VoidCallback? onMore;
  final VoidCallback? onAvatar;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _AvatarButton(
          avatarUrl: reel.authorAvatarUrl,
          onTap: onAvatar,
        ),
        const SizedBox(height: 20),
        _RailAction(
          icon: reel.isLiked ? Icons.favorite : Icons.favorite_border,
          activeColor: const Color(0xFFFF3B5C),
          isActive: reel.isLiked,
          count: reel.likesCount,
          onTap: onLike,
          semanticLabel: 'Like',
        ),
        _RailAction(
          icon: Icons.mode_comment_outlined,
          count: reel.commentsCount,
          onTap: onComments,
          semanticLabel: 'Comments',
        ),
        _RailAction(
          icon: reel.isSaved ? Icons.bookmark : Icons.bookmark_border,
          isActive: reel.isSaved,
          activeColor: const Color(0xFFE7B24B),
          count: reel.savesCount,
          onTap: onSave,
          semanticLabel: 'Save',
        ),
        _RailAction(
          icon: Icons.send_outlined,
          onTap: onShare,
          semanticLabel: 'Share',
        ),
        _RailAction(
          icon: Icons.more_horiz,
          onTap: onMore,
          semanticLabel: 'More',
        ),
      ],
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.avatarUrl, this.onTap});

  final String? avatarUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: SocialSafeImage(imageUrl: avatarUrl, fit: BoxFit.cover),
      ),
    );
  }
}

class _RailAction extends StatelessWidget {
  const _RailAction({
    required this.icon,
    required this.semanticLabel,
    this.count,
    this.onTap,
    this.isActive = false,
    this.activeColor,
  });

  final IconData icon;
  final String semanticLabel;
  final int? count;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isActive ? (activeColor ?? Colors.white) : Colors.white,
                  size: 30,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 6),
                  ],
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatCount(count!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact count formatting (1.2K, 3.4M).
String _formatCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final v = value / 1000;
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}K';
  }
  final v = value / 1000000;
  return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}M';
}
