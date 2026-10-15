import 'package:flutter/material.dart';

import '../../../../core/i18n/locale_text.dart';
import 'social_design_theme.dart';

class SocialFeedTabs extends StatelessWidget {
  const SocialFeedTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tabs = {
      'for_you': context.lt(ar: 'لك', en: 'For you'),
      'following': context.lt(ar: 'المتابعون', en: 'Following'),
      'latest': context.lt(ar: 'الأحدث', en: 'Latest'),
    };
    return Row(
      children: tabs.entries.map((tab) {
        final active = selected == tab.key;
        return Expanded(
          child: Semantics(
            selected: active,
            button: true,
            child: InkWell(
              onTap: () => onSelected(tab.key),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: SocialDesignTheme.motion,
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tab.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? SocialDesignTheme.indigo
                            : SocialDesignTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    AnimatedContainer(
                      duration: SocialDesignTheme.motion,
                      width: 22,
                      height: 3,
                      decoration: BoxDecoration(
                        color: active
                            ? SocialDesignTheme.gold
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
