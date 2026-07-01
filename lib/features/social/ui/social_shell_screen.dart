import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/auth/auth_guard.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../../behavior/data/behavior_api.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/state/notifications_controller.dart';
import 'social_activity_screen.dart';
import 'social_chat_threads_screen.dart';
import 'social_explore_screen.dart';
import 'social_reels_screen.dart';
import 'social_feed_screen.dart';

enum SocialShellTab { home, explore, reels, messages, activity }

class SocialShellScreen extends ConsumerStatefulWidget {
  final SocialShellTab initialTab;
  final int? initialThreadId;
  final int? initialReelId;
  final bool showBottomNavigation;

  const SocialShellScreen({
    super.key,
    this.initialTab = SocialShellTab.home,
    this.initialThreadId,
    this.initialReelId,
    this.showBottomNavigation = true,
  });

  @override
  ConsumerState<SocialShellScreen> createState() => _SocialShellScreenState();
}

class _SocialShellScreenState extends ConsumerState<SocialShellScreen> {
  late int _currentIndex;
  int? _lastTrackedIndex;
  late final ValueNotifier<bool> _reelsPlaybackEnabled;
  late final List<Widget?> _pages = List<Widget?>.filled(
    SocialShellTab.values.length,
    null,
    growable: false,
  );

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    final requested = widget.initialTab.index;
    _currentIndex = !auth.isAuthed && _isGuestRestrictedTab(requested)
        ? SocialShellTab.home.index
        : requested;
    _reelsPlaybackEnabled = ValueNotifier<bool>(
      _currentIndex == SocialShellTab.reels.index,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trackCurrentTab();
    });
  }

  @override
  void dispose() {
    _reelsPlaybackEnabled.dispose();
    super.dispose();
  }

  String _tabRouteFor(int index) {
    return switch (SocialShellTab.values[index]) {
      SocialShellTab.home => 'community',
      SocialShellTab.explore => 'community/explore',
      SocialShellTab.reels => 'reels',
      SocialShellTab.messages => 'community/messages',
      SocialShellTab.activity => 'community/activity',
    };
  }

  String _tabLabelFor(BuildContext context, int index) {
    final l10n = context.l10n;
    return switch (SocialShellTab.values[index]) {
      SocialShellTab.home => l10n.socialShellHome,
      SocialShellTab.explore => l10n.socialShellExplore,
      SocialShellTab.reels => l10n.socialShellReels,
      SocialShellTab.messages => l10n.socialShellMessages,
      SocialShellTab.activity => l10n.socialShellActivity,
    };
  }

  bool _isGuestRestrictedTab(int index) {
    return <int>{
      SocialShellTab.messages.index,
      SocialShellTab.activity.index,
    }.contains(index);
  }

  void _selectTab(int index) {
    unawaited(_selectTabAsync(index));
  }

  Future<void> _selectTabAsync(int index) async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed && _isGuestRestrictedTab(index)) {
      await requireAuthBeforeAction(
        context,
        featureArabic: index == SocialShellTab.messages.index
            ? 'الرسائل'
            : 'النشاط الاجتماعي',
        featureEnglish: index == SocialShellTab.messages.index
            ? 'messages'
            : 'social activity',
      );
      return;
    }
    setState(() => _currentIndex = index);
    _reelsPlaybackEnabled.value = index == SocialShellTab.reels.index;
    _trackCurrentTab();
  }

  Future<void> _trackCurrentTab() async {
    if (!mounted || _lastTrackedIndex == _currentIndex) {
      return;
    }
    _lastTrackedIndex = _currentIndex;
    final label = _tabLabelFor(context, _currentIndex);
    await ref
        .read(behaviorApiProvider)
        .trackEvent(
          eventName: 'community.surface_open',
          category: 'community',
          action: 'open_tab',
          metadata: {
            'tab': SocialShellTab.values[_currentIndex].name,
            'route': _tabRouteFor(_currentIndex),
            'screenLabel': label,
            'recentTitle': 'كنت تتصفح $label',
            'recentSubtitle': 'اضغط للعودة إلى $label',
          },
        );
  }

  Widget _pageFor(int index) {
    return _pages[index] ??= switch (SocialShellTab.values[index]) {
      SocialShellTab.home => const SocialFeedScreen(),
      SocialShellTab.explore => const SocialExploreScreen(),
      SocialShellTab.reels => SocialReelsScreen(
        initialReelId: widget.initialReelId,
        playbackEnabledListenable: _reelsPlaybackEnabled,
      ),
      SocialShellTab.messages => SocialChatThreadsScreen(
        initialThreadId: widget.initialThreadId,
      ),
      SocialShellTab.activity => const SocialActivityScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final communitySection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.community, displayName: 'المجتمع');
    if (communitySection.isBlocked) {
      return SectionUnavailableScreen(entry: communitySection);
    }
    final l10n = context.l10n;
    ref.watch(authControllerProvider);
    final messagesUnread = ref.watch(socialMessagesUnreadCountProvider);
    final activityUnread = ref.watch(socialActivityUnreadCountProvider);

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        body: Stack(
          children: List<Widget>.generate(SocialShellTab.values.length, (
            index,
          ) {
            final isActive = index == _currentIndex;
            final page = _pages[index];
            if (!isActive && page == null) {
              return const SizedBox.shrink();
            }
            return Offstage(
              offstage: !isActive,
              child: TickerMode(enabled: isActive, child: _pageFor(index)),
            );
          }),
        ),
        bottomNavigationBar: widget.showBottomNavigation
            ? MaslakiBottomNavShell(
                currentIndex: _currentIndex,
                onTap: _selectTab,
                items: [
                  MaslakiBottomNavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: l10n.socialShellHome,
                  ),
                  MaslakiBottomNavItem(
                    icon: Icons.travel_explore_outlined,
                    activeIcon: Icons.travel_explore_rounded,
                    label: l10n.socialShellExplore,
                  ),
                  MaslakiBottomNavItem(
                    icon: Icons.play_circle_outline_rounded,
                    activeIcon: Icons.play_circle_fill_rounded,
                    label: l10n.socialShellReels,
                  ),
                  MaslakiBottomNavItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    activeIcon: Icons.chat_bubble_rounded,
                    label: l10n.socialShellMessages,
                    badgeCount: messagesUnread,
                  ),
                  MaslakiBottomNavItem(
                    icon: Icons.favorite_border_rounded,
                    activeIcon: Icons.favorite_rounded,
                    label: l10n.socialShellActivity,
                    badgeCount: activityUnread,
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
