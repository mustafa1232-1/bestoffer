import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import 'social_design_theme.dart';

class SocialBottomNavigation extends StatelessWidget {
  const SocialBottomNavigation({
    super.key,
    required this.index,
    required this.onSelected,
    this.messagesUnread = 0,
    this.activityUnread = 0,
  });

  final int index;
  final ValueChanged<int> onSelected;
  final int messagesUnread;
  final int activityUnread;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = [
      (Icons.home_outlined, Icons.home_rounded, l10n.socialShellHome, 0),
      (
        Icons.travel_explore_outlined,
        Icons.travel_explore_rounded,
        l10n.socialShellExplore,
        0,
      ),
      (
        Icons.play_circle_outline,
        Icons.play_circle_filled,
        l10n.socialShellReels,
        0,
      ),
      (
        Icons.chat_bubble_outline,
        Icons.chat_bubble,
        l10n.socialShellMessages,
        messagesUnread,
      ),
      (
        Icons.favorite_border,
        Icons.favorite,
        l10n.socialShellActivity,
        activityUnread,
      ),
    ];
    return Material(
      color: Colors.white,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: SocialDesignTheme.muted.withValues(alpha: 0.14),
            ),
          ),
        ),
        child: Row(
          children: [
            for (var i = 0; i < entries.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: index == i,
                  label: entries[i].$4 > 0
                      ? '${entries[i].$3}, ${entries[i].$4}'
                      : entries[i].$3,
                  child: InkWell(
                    onTap: () => onSelected(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 2,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Badge(
                            isLabelVisible: entries[i].$4 > 0,
                            label: Text(
                              entries[i].$4 > 99 ? '99+' : '${entries[i].$4}',
                            ),
                            child: Icon(
                              index == i ? entries[i].$2 : entries[i].$1,
                              size: 24,
                              color: index == i
                                  ? SocialDesignTheme.indigo
                                  : SocialDesignTheme.muted,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            entries[i].$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: index == i
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: index == i
                                  ? SocialDesignTheme.indigo
                                  : SocialDesignTheme.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedContainer(
                            duration: SocialDesignTheme.motion,
                            width: 18,
                            height: 2,
                            color: index == i
                                ? SocialDesignTheme.gold
                                : Colors.transparent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
