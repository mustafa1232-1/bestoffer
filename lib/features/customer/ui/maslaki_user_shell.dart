import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:core_design_system/core_design_system.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../auth/state/auth_controller.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../../social/ui/social_shell_screen.dart';
import 'customer_account_hub_screen.dart';
import 'customer_home_selector_screen.dart';

class MaslakiUserShell extends ConsumerStatefulWidget {
  final int initialIndex;

  const MaslakiUserShell({super.key, this.initialIndex = 0});

  @override
  ConsumerState<MaslakiUserShell> createState() => _MaslakiUserShellState();
}

class MaslakiUserShellController {
  final int currentIndex;
  final bool Function() popCurrentNavigator;
  final void Function({bool resetStack}) goHome;
  final void Function(int tabIndex, {bool resetStack}) goToTab;

  const MaslakiUserShellController({
    required this.currentIndex,
    required this.popCurrentNavigator,
    required this.goHome,
    required this.goToTab,
  });
}

class _MaslakiUserShellState extends ConsumerState<MaslakiUserShell> {
  late final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
        5,
        (index) =>
            GlobalKey<NavigatorState>(debugLabel: 'user_shell_tab_$index'),
      );
  late final List<_ShellTabObserver> _observers =
      List<_ShellTabObserver>.generate(
        5,
        (index) => _ShellTabObserver(onChanged: _scheduleRouteSync),
      );
  late final List<Widget?> _tabNavigators = List<Widget?>.filled(
    _navigatorKeys.length,
    null,
    growable: false,
  );
  int _index = 0;
  bool _showBottomBar = true;
  bool _routeSyncScheduled = false;

  int get currentIndex => _index;

  void _scheduleRouteSync() {
    if (!mounted || _routeSyncScheduled) return;
    _routeSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeSyncScheduled = false;
      if (!mounted) return;
      _handleRouteChanged();
    });
  }

  void _handleRouteChanged() {
    if (!mounted) return;
    final currentNavigator = _navigatorKeys[_index].currentState;
    final canPop = currentNavigator?.canPop() ?? false;
    final nextShowBottomBar = !canPop;
    if (_showBottomBar == nextShowBottomBar) return;
    setState(() {
      _showBottomBar = nextShowBottomBar;
    });
  }

  bool _handleBackNavigation() {
    if (_popCurrentNavigator()) return false;
    if (_index != 0) {
      _goToTab(0, resetStack: true);
      return false;
    }
    return true;
  }

  bool _popCurrentNavigator() {
    final currentNavigator = _navigatorKeys[_index].currentState;
    if (currentNavigator?.canPop() ?? false) {
      currentNavigator!.pop();
      _scheduleRouteSync();
      return true;
    }
    return false;
  }

  void _resetTabStack(int index) {
    final navigator = _navigatorKeys[index].currentState;
    while (navigator?.canPop() ?? false) {
      navigator!.pop();
    }
  }

  void _goToTab(int nextIndex, {bool resetStack = false}) {
    final resolvedIndex = nextIndex.clamp(0, _navigatorKeys.length - 1);
    if (resetStack) {
      _resetTabStack(resolvedIndex);
    }
    if (_index == resolvedIndex) {
      _scheduleRouteSync();
      return;
    }
    setState(() {
      _index = resolvedIndex;
      _showBottomBar =
          !(_navigatorKeys[resolvedIndex].currentState?.canPop() ?? false);
    });
  }

  bool _isGuestRestrictedTab(int index) {
    return <int>{1, 3, 4}.contains(index);
  }

  void _selectTab(int nextIndex) {
    unawaited(_selectTabAsync(nextIndex));
  }

  Future<void> _selectTabAsync(int nextIndex) async {
    final resolvedIndex = nextIndex.clamp(0, _navigatorKeys.length - 1);
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed && _isGuestRestrictedTab(resolvedIndex)) {
      await requireAuthBeforeAction(
        context,
        featureArabic: switch (resolvedIndex) {
          1 => 'الطلبات الشخصية',
          3 => 'الرسائل',
          _ => 'الحساب',
        },
        featureEnglish: switch (resolvedIndex) {
          1 => 'my orders',
          3 => 'messages',
          _ => 'account',
        },
      );
      return;
    }
    _goToTab(resolvedIndex, resetStack: true);
  }

  void goHome({bool resetStack = true}) => _goToTab(0, resetStack: resetStack);

  void goToTab(int tabIndex, {bool resetStack = false}) =>
      _goToTab(tabIndex, resetStack: resetStack);

  Route<dynamic> _buildRouteForIndex(int index) {
    switch (index) {
      case 0:
        return MaterialPageRoute(
          builder: (_) => const CustomerHomeSelectorScreen(),
        );
      case 1:
        return MaterialPageRoute(builder: (_) => const CustomerOrdersScreen());
      case 2:
        return MaterialPageRoute(
          builder: (_) => const SocialShellScreen(
            initialTab: SocialShellTab.home,
            showBottomNavigation: false,
          ),
        );
      case 3:
        return MaterialPageRoute(
          builder: (_) => const SocialShellScreen(
            initialTab: SocialShellTab.messages,
            showBottomNavigation: false,
          ),
        );
      case 4:
      default:
        return MaterialPageRoute(
          builder: (_) => const CustomerAccountHubScreen(),
        );
    }
  }

  Widget _navigatorForIndex(int index) {
    return _tabNavigators[index] ??= Navigator(
      key: _navigatorKeys[index],
      observers: [_observers[index]],
      onGenerateRoute: (_) => _buildRouteForIndex(index),
    );
  }

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    final requested = widget.initialIndex.clamp(0, _navigatorKeys.length - 1);
    _index = !auth.isAuthed && _isGuestRestrictedTab(requested)
        ? 0
        : requested;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shellController = MaslakiUserShellController(
      currentIndex: _index,
      popCurrentNavigator: _popCurrentNavigator,
      goHome: ({bool resetStack = true}) =>
          goHome(resetStack: resetStack),
      goToTab: (int tabIndex, {bool resetStack = false}) =>
          goToTab(tabIndex, resetStack: resetStack),
    );

    return MaslakiUserShellScope(
      controller: shellController,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          final shouldExit = _handleBackNavigation();
          if (shouldExit) {
            Navigator.of(context).maybePop();
          }
        },
        child: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: List<Widget>.generate(_navigatorKeys.length, (index) {
              final isActive = index == _index;
              final navigator = _tabNavigators[index];
              if (!isActive && navigator == null) {
                return const SizedBox.shrink();
              }
              return Offstage(
                offstage: !isActive,
                child: TickerMode(
                  enabled: isActive,
                  child: _navigatorForIndex(index),
                ),
              );
            }),
          ),
          bottomNavigationBar: MaslakiBottomNavShell(
            visible: _showBottomBar,
            currentIndex: _index,
            onTap: _selectTab,
            items: [
              MaslakiBottomNavItem(
                label: l10n.customerHomeTitle,
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
              ),
              MaslakiBottomNavItem(
                label: l10n.commonOrders,
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long_rounded,
              ),
              MaslakiBottomNavItem(
                label: l10n.socialBasmayaCommunity,
                icon: Icons.groups_outlined,
                activeIcon: Icons.groups_rounded,
              ),
              MaslakiBottomNavItem(
                label: l10n.socialShellMessages,
                icon: Icons.chat_bubble_outline_rounded,
                activeIcon: Icons.chat_bubble_rounded,
              ),
              MaslakiBottomNavItem(
                label: l10n.settingsAccount,
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MaslakiUserShellScope extends InheritedWidget {
  final MaslakiUserShellController controller;

  const MaslakiUserShellScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static MaslakiUserShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MaslakiUserShellScope>();
  }

  @override
  bool updateShouldNotify(MaslakiUserShellScope oldWidget) {
    return oldWidget.controller.currentIndex != controller.currentIndex;
  }
}

class MaslakiHomeNavigator {
  static Future<void> goHome(
    BuildContext context, {
    bool resetStack = true,
  }) {
    return goToTab(context, 0, resetStack: resetStack);
  }

  static Future<void> goToTab(
    BuildContext context,
    int tabIndex, {
    bool resetStack = false,
  }) async {
    final shellScope = MaslakiUserShellScope.maybeOf(context);
    if (shellScope != null) {
      shellScope.controller.goToTab(tabIndex, resetStack: resetStack);
      return;
    }
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    await rootNavigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => MaslakiUserShell(initialIndex: tabIndex),
      ),
      (route) => false,
    );
  }

  static Future<void> maybePopOrGoHome(
    BuildContext context, {
    int fallbackTabIndex = 0,
  }) async {
    final navigator = Navigator.maybeOf(context);
    if (navigator?.canPop() ?? false) {
      await navigator!.maybePop();
      return;
    }
    final shellScope = MaslakiUserShellScope.maybeOf(context);
    if (shellScope != null) {
      if (shellScope.controller.popCurrentNavigator()) {
        return;
      }
      shellScope.controller.goToTab(fallbackTabIndex, resetStack: true);
      return;
    }
    await goToTab(context, fallbackTabIndex, resetStack: true);
  }
}

class _ShellTabObserver extends NavigatorObserver {
  final VoidCallback onChanged;

  _ShellTabObserver({required this.onChanged});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    onChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    onChanged();
  }
}
