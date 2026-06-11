import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/maslaki_user_drawer.dart';
import '../../../../core/widgets/appbar_quick_actions.dart';
import '../../../auth/state/auth_controller.dart';
import '../../../notifications/state/notifications_controller.dart';
import '../../../notifications/ui/notifications_bell.dart';
import '../../models/social_models.dart';
import '../../state/social_controller.dart';
import '../social_community_screen.dart';
import '../social_relation_requests_screen.dart';
import '../social_reported_posts_screen.dart';
import '../social_profile_screen.dart';
import '../social_search_screen.dart';
import '../social_shell_screen.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class BasmayaTopAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onAddPost;
  final VoidCallback? onAddStory;
  final String addPostLabel;

  const BasmayaTopAppBar({
    super.key,
    required this.onAddPost,
    this.onAddStory,
    this.addPostLabel = '',
  });

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = addPostLabel.trim().isEmpty
        ? l10n.socialBasmayaAddPost
        : addPostLabel;
    final canPop = Navigator.of(context).canPop();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AppBar(
        toolbarHeight: 50,
        automaticallyImplyLeading: false,
        leading: canPop
            ? IconButton(
                tooltip: l10n.commonBack,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        leadingWidth: canPop ? 44 : null,
        centerTitle: false,
        titleSpacing: 8,
        title: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onAddPost,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.05,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (onAddStory != null)
                OutlinedButton.icon(
                  onPressed: onAddStory,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: Text(
                    l10n.socialBasmayaAddStory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.05,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: l10n.socialBasmayaMyReports,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SocialReportedPostsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.flag_outlined),
          ),
          IconButton(
            tooltip: l10n.socialBasmayaSearchTooltip,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SocialSearchScreen(),
                ),
              );
            },
            icon: const Icon(Icons.person_search_rounded),
          ),
          IconButton(
            tooltip: l10n.socialBasmayaFriendRequests,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SocialRelationRequestsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
          const AppBarQuickActions(compact: true, includeFriendRequests: false),
          Builder(
            builder: (context) => IconButton(
              tooltip: l10n.socialBasmayaMenu,
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class SocialHomeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback? onMenuTap;
  final VoidCallback? onOpenProfile;
  final String? titleOverride;

  const SocialHomeAppBar({
    super.key,
    this.onMenuTap,
    this.onOpenProfile,
    this.titleOverride,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.maslakiTokens;
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final name = user?.fullName.trim();
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final titleText = (titleOverride ?? '').trim().isNotEmpty
        ? titleOverride!.trim()
        : (isEnglish ? 'Shdysir Basmaya Home' : 'شديصير بسماية الرئيسية');

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 6,
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: l10n.socialBasmayaMenu,
          onPressed: onMenuTap ?? () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu_rounded),
        ),
      ),
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tokens.secondaryAccent, tokens.primaryAccent],
              ),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      actions: [
        const NotificationsBellButton(mode: NotificationInboxMode.general),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap:
                onOpenProfile ??
                () {
                  final userId = user?.id;
                  if (userId == null || userId <= 0) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SocialProfileScreen(
                        userId: userId,
                        initialName: name,
                      ),
                    ),
                  );
                },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: CircleAvatar(
                radius: 17,
                backgroundImage: (user?.imageUrl ?? '').trim().isNotEmpty
                    ? AppCachedImageProvider(user!.imageUrl!)
                    : null,
                child: (user?.imageUrl ?? '').trim().isEmpty
                    ? const Icon(Icons.person_outline_rounded)
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final basmayaScopeCodesProvider = FutureProvider.autoDispose<BasmayaScopeCodes>(
  (ref) async {
    final auth = ref.read(authControllerProvider);

    String normalizedCode(String? value) => (value ?? '').trim().toUpperCase();

    String? resolveBlockScopeCode() {
      final user = auth.user;
      if (user == null) return null;
      final block = normalizedCode(user.block);
      final building = normalizedCode(user.buildingNumber);
      if (RegExp(r'^[AB]$').hasMatch(block)) return block;
      if (RegExp(r'^[AB][1-9]$').hasMatch(block)) return block.substring(0, 1);
      if (RegExp(r'^[AB][1-9](0[1-9]|1[0-9]|2[0-2])$').hasMatch(building)) {
        return building.substring(0, 1);
      }
      return null;
    }

    String? resolveCompoundScopeCode() {
      final user = auth.user;
      if (user == null) return null;
      final block = normalizedCode(user.block);
      final building = normalizedCode(user.buildingNumber);
      if (RegExp(r'^[AB][1-9]$').hasMatch(block)) return block;
      if (RegExp(r'^[AB][1-9](0[1-9]|1[0-9]|2[0-2])$').hasMatch(building)) {
        return building.substring(0, 2);
      }
      return null;
    }

    String? resolveBuildingScopeCode() {
      final user = auth.user;
      if (user == null) return null;
      final building = normalizedCode(user.buildingNumber);
      if (RegExp(r'^[AB][1-9](0[1-9]|1[0-9]|2[0-2])$').hasMatch(building)) {
        return building;
      }
      return null;
    }

    String? block = resolveBlockScopeCode();
    String? compound = resolveCompoundScopeCode();
    String? building = resolveBuildingScopeCode();
    try {
      final out = await ref.read(socialApiProvider).listCommunityScopes();
      final rows = List<dynamic>.from(out['scopes'] as List? ?? const []);
      for (final row in rows) {
        final scope = SocialCommunityScopeInfo.fromJson(
          Map<String, dynamic>.from(row as Map),
        );
        switch (scope.scopeType.trim().toLowerCase()) {
          case 'block':
            block = scope.scopeCode;
            break;
          case 'compound':
            compound = scope.scopeCode;
            break;
          case 'building':
            building = scope.scopeCode;
            break;
        }
      }
    } catch (_) {
      // Keep derived fallback from user address.
    }
    return BasmayaScopeCodes(
      blockScopeCode: block,
      compoundScopeCode: compound,
      buildingScopeCode: building,
    );
  },
);

class BasmayaScopeCodes {
  final String? blockScopeCode;
  final String? compoundScopeCode;
  final String? buildingScopeCode;

  const BasmayaScopeCodes({
    required this.blockScopeCode,
    required this.compoundScopeCode,
    required this.buildingScopeCode,
  });
}

class MaslakiBasmayaDrawer extends ConsumerWidget {
  final bool embedded;
  final List<MaslakiDrawerSection> extraSections;

  const MaslakiBasmayaDrawer({
    super.key,
    this.embedded = false,
    this.extraSections = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final user = ref.watch(authControllerProvider).user;
    final scopes = ref.watch(basmayaScopeCodesProvider).valueOrNull;
    final blockCode = (scopes?.blockScopeCode ?? '').trim().toUpperCase();
    final compoundCode = (scopes?.compoundScopeCode ?? '').trim().toUpperCase();
    final buildingCode = (scopes?.buildingScopeCode ?? '').trim().toUpperCase();

    Future<void> open(Widget page) async {
      if (!embedded) {
        Navigator.of(context).pop();
      }
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }

    Future<void> openCommunity({
      required String scopeType,
      required String scopeCode,
    }) async {
      if (scopeCode.isEmpty) return;
      final title =
          '${l10n.socialBasmayaCommunity} ${_scopeTypeLabel(context, scopeType)} $scopeCode';
      await open(
        SocialCommunityScreen(
          scopeType: scopeType,
          scopeCode: scopeCode,
          title: title,
        ),
      );
    }

    final basmayaEntries = <MaslakiDrawerEntry>[
      if (user != null)
        MaslakiDrawerEntry(
          icon: Icons.account_circle_outlined,
          label: l10n.socialBasmayaProfile,
          onTap: () => open(
            SocialProfileScreen(userId: user.id, initialName: user.fullName),
          ),
        ),
      MaslakiDrawerEntry(
        icon: Icons.home_outlined,
        label: l10n.customerDiscoveryBasmayaFeed,
        onTap: () =>
            open(const SocialShellScreen(initialTab: SocialShellTab.home)),
      ),
      MaslakiDrawerEntry(
        icon: Icons.chat_bubble_outline_rounded,
        label: l10n.socialShellMessages,
        onTap: () =>
            open(const SocialShellScreen(initialTab: SocialShellTab.messages)),
      ),
      MaslakiDrawerEntry(
        icon: Icons.favorite_border_rounded,
        label: l10n.socialShellActivity,
        onTap: () =>
            open(const SocialShellScreen(initialTab: SocialShellTab.activity)),
      ),
      MaslakiDrawerEntry(
        icon: Icons.person_search_rounded,
        label: l10n.commonSearch,
        onTap: () => open(const SocialSearchScreen()),
      ),
      MaslakiDrawerEntry(
        icon: Icons.person_add_alt_1_rounded,
        label: l10n.socialBasmayaFriendRequests,
        onTap: () => open(const SocialRelationRequestsScreen()),
      ),
      if (blockCode.isNotEmpty)
        MaslakiDrawerEntry(
          icon: Icons.account_tree_outlined,
          label: '${l10n.commonBlock} $blockCode',
          onTap: () => openCommunity(scopeType: 'block', scopeCode: blockCode),
        ),
      if (compoundCode.isNotEmpty)
        MaslakiDrawerEntry(
          icon: Icons.groups_2_outlined,
          label: '${l10n.socialBasmayaCompound} $compoundCode',
          onTap: () =>
              openCommunity(scopeType: 'compound', scopeCode: compoundCode),
        ),
      if (buildingCode.isNotEmpty)
        MaslakiDrawerEntry(
          icon: Icons.apartment_rounded,
          label: '${l10n.socialBasmayaBuilding} $buildingCode',
          onTap: () =>
              openCommunity(scopeType: 'building', scopeCode: buildingCode),
        ),
    ];

    return MaslakiUserDrawer(
      embedded: embedded,
      extraSections: [
        MaslakiDrawerSection(
          title: l10n.customerDiscoveryBasmayaFeed,
          entries: basmayaEntries,
        ),
        ...extraSections,
      ],
    );
  }
}

class BasmayaBottomNavBar extends ConsumerWidget {
  final BasmayaNavKey current;

  const BasmayaBottomNavBar({super.key, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final notifications = ref
        .watch(notificationsControllerProvider)
        .notifications;
    final chatUnreadCount = notifications.where((n) {
      if (n.isRead) return false;
      final target = (n.target ?? '').trim().toLowerCase();
      if (target == 'social_chat') return true;
      return n.type.toLowerCase().startsWith('social.chat.');
    }).length;

    final scopes = ref.watch(basmayaScopeCodesProvider).valueOrNull;
    final blockCode = (scopes?.blockScopeCode ?? '').trim().toUpperCase();
    final compoundCode = (scopes?.compoundScopeCode ?? '').trim().toUpperCase();
    final buildingCode = (scopes?.buildingScopeCode ?? '').trim().toUpperCase();

    final homeAction = _BasmayaNavAction(
      key: BasmayaNavKey.home,
      label: l10n.socialBasmayaHome,
      icon: Icons.home_outlined,
      onTap: () {
        if (current == BasmayaNavKey.home) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const SocialShellScreen()),
        );
      },
    );
    final blockAction = _BasmayaNavAction(
      key: BasmayaNavKey.block,
      label: l10n.commonBlock,
      icon: Icons.account_tree_outlined,
      onTap: () => _openScope(
        context,
        current: current,
        target: BasmayaNavKey.block,
        scopeType: 'block',
        scopeCode: blockCode,
      ),
    );
    final compoundAction = _BasmayaNavAction(
      key: BasmayaNavKey.compound,
      label: l10n.socialBasmayaCompound,
      icon: Icons.groups_2_outlined,
      onTap: () => _openScope(
        context,
        current: current,
        target: BasmayaNavKey.compound,
        scopeType: 'compound',
        scopeCode: compoundCode,
      ),
    );
    final buildingAction = _BasmayaNavAction(
      key: BasmayaNavKey.building,
      label: l10n.socialBasmayaBuilding,
      icon: Icons.apartment_rounded,
      onTap: () => _openScope(
        context,
        current: current,
        target: BasmayaNavKey.building,
        scopeType: 'building',
        scopeCode: buildingCode,
      ),
    );
    final searchAction = _BasmayaNavAction(
      key: BasmayaNavKey.search,
      label: l10n.commonSearch,
      icon: Icons.person_search_rounded,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SocialSearchScreen()),
        );
      },
    );
    final messagesAction = _BasmayaNavAction(
      key: BasmayaNavKey.messages,
      label: l10n.socialBasmayaMessages,
      icon: Icons.chat_bubble_outline_rounded,
      badgeCount: chatUnreadCount,
      onTap: () {
        if (current == BasmayaNavKey.messages) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                const SocialShellScreen(initialTab: SocialShellTab.messages),
          ),
        );
      },
    );
    final profileAction = _BasmayaNavAction(
      key: BasmayaNavKey.profile,
      label: l10n.socialBasmayaProfile,
      icon: Icons.account_circle_outlined,
      onTap: () {
        if (user == null) return;
        if (current == BasmayaNavKey.profile) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SocialProfileScreen(
              userId: user.id,
              initialName: user.fullName,
            ),
          ),
        );
      },
    );

    final scopeActions = <_BasmayaNavAction>[
      if (blockCode.isNotEmpty) blockAction,
      if (compoundCode.isNotEmpty) compoundAction,
      if (buildingCode.isNotEmpty) buildingAction,
    ];

    final primaryCommunityAction = switch (current) {
      BasmayaNavKey.block => blockAction,
      BasmayaNavKey.compound => compoundAction,
      BasmayaNavKey.building => buildingAction,
      _ => scopeActions.isNotEmpty ? scopeActions.first : blockAction,
    };

    final visible = <_BasmayaNavAction>[
      homeAction,
      primaryCommunityAction,
      messagesAction,
      profileAction,
    ];

    final hidden = <_BasmayaNavAction>[
      for (final action in scopeActions)
        if (!visible.any((visibleAction) => visibleAction.key == action.key))
          action,
      searchAction,
    ];

    return Container(
      height: 72 + bottomInset,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.975),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.7,
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(8, 6, 8, 7 + bottomInset),
      child: Row(
        children: [
          for (final item in visible)
            Expanded(
              child: _BasmayaNavButton(
                action: item,
                active: current == item.key,
              ),
            ),
          if (hidden.isNotEmpty)
            Expanded(
              child: _BasmayaMoreButton(
                hidden: hidden,
                active: hidden.any((item) => item.key == current),
              ),
            ),
        ],
      ),
    );
  }

  void _openScope(
    BuildContext context, {
    required BasmayaNavKey current,
    required BasmayaNavKey target,
    required String scopeType,
    required String scopeCode,
  }) {
    if (scopeCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.socialBasmayaUnavailableScope)),
      );
      return;
    }
    if (current == target) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SocialCommunityScreen(
          scopeType: scopeType,
          scopeCode: scopeCode,
          title:
              '${context.l10n.socialBasmayaCommunity} ${_scopeTypeLabel(context, scopeType)} $scopeCode',
        ),
      ),
    );
  }
}

enum BasmayaNavKey {
  home,
  block,
  compound,
  building,
  search,
  messages,
  profile,
}

class _BasmayaNavAction {
  final BasmayaNavKey key;
  final String label;
  final IconData icon;
  final int badgeCount;
  final VoidCallback onTap;

  const _BasmayaNavAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });
}

class _BasmayaNavButton extends StatelessWidget {
  final _BasmayaNavAction action;
  final bool active;

  const _BasmayaNavButton({required this.action, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.8);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: action.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(action.icon, size: 20, color: color),
                if (action.badgeCount > 0)
                  Positioned(
                    right: -9,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        action.badgeCount > 99 ? '99+' : '${action.badgeCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: Directionality.of(context),
              style: TextStyle(
                fontSize: 10.4,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BasmayaMoreButton extends StatelessWidget {
  final List<_BasmayaNavAction> hidden;
  final bool active;

  const _BasmayaMoreButton({required this.hidden, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.8);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final item in hidden)
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(
                      item.label,
                      textDirection: Directionality.of(context),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      item.onTap();
                    },
                  ),
              ],
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.more_horiz_rounded, size: 20, color: color),
            const SizedBox(height: 2),
            Text(
              context.l10n.socialBasmayaMore,
              style: TextStyle(
                fontSize: 10.4,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _scopeTypeLabel(BuildContext context, String scopeType) {
  switch (scopeType.trim().toLowerCase()) {
    case 'block':
      return context.l10n.commonBlock;
    case 'compound':
      return context.l10n.socialBasmayaCompound;
    case 'building':
      return context.l10n.socialBasmayaBuilding;
    default:
      return scopeType;
  }
}
