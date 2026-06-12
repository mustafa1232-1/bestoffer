import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:core_design_system/core_design_system.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../../social/ui/social_shell_screen.dart';
import 'customer_account_hub_screen.dart';
import 'customer_home_selector_screen.dart';

class MaslakiUserShell extends ConsumerStatefulWidget {
  const MaslakiUserShell({super.key});

  @override
  ConsumerState<MaslakiUserShell> createState() => _MaslakiUserShellState();
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
    final currentNavigator = _navigatorKeys[_index].currentState;
    if (currentNavigator?.canPop() ?? false) {
      currentNavigator!.pop();
      return false;
    }
    return true;
  }

  void _selectTab(int nextIndex) {
    if (_index == nextIndex) {
      final navigator = _navigatorKeys[nextIndex].currentState;
      while (navigator?.canPop() ?? false) {
        navigator!.pop();
      }
      _scheduleRouteSync();
      return;
    }
    setState(() {
      _index = nextIndex;
      _showBottomBar =
          !(_navigatorKeys[nextIndex].currentState?.canPop() ?? false);
    });
  }

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
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return PopScope(
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
    );
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
