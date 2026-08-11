import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/app_permission_matrix.dart';
import '../utils/parsers.dart';
import '../../features/auth/state/auth_controller.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../../features/social/models/social_models.dart';
import '../../features/social/state/social_controller.dart';
import '../../features/social/ui/social_activity_screen.dart';
import '../../features/social/ui/social_community_screen.dart';
import '../../features/social/ui/social_profile_screen.dart';
import '../../features/social/ui/social_relation_requests_screen.dart';
import '../../features/social/ui/social_reported_posts_screen.dart';
import '../../features/social/ui/social_search_screen.dart';
import '../../features/social/ui/social_shell_screen.dart';
import '../../features/support/models/support_context.dart';
import '../../features/support/ui/support_request_sheet.dart';
import '../i18n/app_localizations_context.dart';
import '../i18n/locale_text.dart';

String _drawerText(String? value) => normalizeText((value ?? '').trim());

final _drawerCommunityScopesProvider =
    FutureProvider.autoDispose<List<SocialCommunityScopeInfo>>((ref) async {
      final out = await ref.read(socialApiProvider).listCommunityScopes();
      final raw = List<dynamic>.from(out['scopes'] as List? ?? const []);
      return raw
          .map(
            (item) => SocialCommunityScopeInfo.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
    });

class AppUserDrawerItem {
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? group;
  final int? badgeCount;
  final Widget? trailing;
  final Future<void> Function(BuildContext context)? onTap;

  const AppUserDrawerItem({
    required this.icon,
    required this.label,
    this.subtitle,
    this.group,
    this.badgeCount,
    this.trailing,
    this.onTap,
  });
}

class AppUserDrawer extends ConsumerStatefulWidget {
  final String title;
  final String? subtitle;
  final List<AppUserDrawerItem> items;
  final bool showSettings;
  final bool embedded;
  final bool showProfileButton;
  final bool showCommunitySection;
  final bool enableItemSearch;
  final bool enableGroupCollapse;
  final bool collapseGroupsByDefault;
  final String? searchHintText;

  const AppUserDrawer({
    super.key,
    required this.title,
    this.subtitle,
    this.items = const [],
    this.showSettings = true,
    this.embedded = false,
    this.showProfileButton = true,
    this.showCommunitySection = true,
    this.enableItemSearch = false,
    this.enableGroupCollapse = false,
    this.collapseGroupsByDefault = false,
    this.searchHintText,
  });

  @override
  ConsumerState<AppUserDrawer> createState() => _AppUserDrawerState();
}

class _AppUserDrawerState extends ConsumerState<AppUserDrawer> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _collapsedGroups = <String>{};
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizeForSearch(String value) =>
      normalizeText(value).trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final subtitle = widget.subtitle;
    final showSettings = widget.showSettings;
    final embedded = widget.embedded;
    final showProfileButton = widget.showProfileButton;
    final showCommunitySection = widget.showCommunitySection;
    final enableItemSearch = widget.enableItemSearch;
    final enableGroupCollapse = widget.enableGroupCollapse;
    final collapseGroupsByDefault = widget.collapseGroupsByDefault;
    final searchHintText = widget.searchHintText;
    final auth = ref.watch(authControllerProvider);
    final currentUserId = auth.user?.id;
    final permissions = ref.watch(appPermissionMatrixProvider);
    final l10n = context.l10n;
    final textDirection = Directionality.of(context);
    final userName = auth.user?.fullName.trim();
    final userPhone = auth.user?.phone.trim();
    final canUseCommunityScopes = permissions.can(
      AppCapability.socialCommunityScopes,
    );
    final communityScopesAsync = canUseCommunityScopes
        ? ref.watch(_drawerCommunityScopesProvider)
        : const AsyncValue<List<SocialCommunityScopeInfo>>.data(
            <SocialCommunityScopeInfo>[],
          );

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

    final remoteScopes = communityScopesAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <SocialCommunityScopeInfo>[],
    );
    SocialCommunityScopeInfo? remoteScopeByType(String scopeType) {
      for (final scope in remoteScopes) {
        if (scope.scopeType.trim().toLowerCase() == scopeType) return scope;
      }
      return null;
    }

    final blockScope = remoteScopeByType('block');
    final compoundScope = remoteScopeByType('compound');
    final buildingScope = remoteScopeByType('building');

    final blockScopeCode = canUseCommunityScopes
        ? (blockScope?.scopeCode ?? resolveBlockScopeCode())
        : null;
    final compoundScopeCode = canUseCommunityScopes
        ? (compoundScope?.scopeCode ?? resolveCompoundScopeCode())
        : null;
    final buildingScopeCode = canUseCommunityScopes
        ? (buildingScope?.scopeCode ?? resolveBuildingScopeCode())
        : null;
    final allowManualCommunityScopeSelection = auth.isBackoffice;
    final isCommunityCatalogMode = auth.isBackoffice && remoteScopes.length > 6;
    final isCustomerProfile =
        auth.isAuthed &&
        !auth.isBackoffice &&
        !auth.isOwner &&
        !auth.isDelivery &&
        !auth.isTaxiCaptain &&
        !auth.isHr &&
        !auth.isAccountant;
    final canOpenCommunitySection =
        isCustomerProfile || allowManualCommunityScopeSelection;
    final shouldShowCommunitySection =
        showCommunitySection &&
        canOpenCommunitySection &&
        (allowManualCommunityScopeSelection ||
            isCommunityCatalogMode ||
            blockScopeCode != null ||
            compoundScopeCode != null ||
            buildingScopeCode != null);
    final canOpenSocialTools =
        isCustomerProfile &&
        (permissions.can(AppCapability.socialFeed) ||
            permissions.can(AppCapability.socialChats) ||
            permissions.can(AppCapability.socialCommunityScopes) ||
            auth.isSuperAdmin);
    final drawerItems = widget.items;
    final socialGroup = l10n.drawerGroupSocial;
    final communityGroup = l10n.drawerGroupCommunity;
    final settingsGroup = l10n.commonSettings;

    bool hasDrawerItem(String label) {
      final normalized = normalizeText(label).trim().toLowerCase();
      if (normalized.isEmpty) return false;
      for (final item in drawerItems) {
        if (normalizeText(item.label).trim().toLowerCase() == normalized) {
          return true;
        }
      }
      return false;
    }

    Future<void> openProfile() async {
      final userId = currentUserId;
      if (userId == null) return;
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => SocialProfileScreen(
            userId: userId,
            initialName: auth.user?.fullName,
          ),
        ),
      );
    }

    Future<void> openSettings() async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute(
          // Non-customer surfaces (e.g. delivery) hide the community section;
          // they must also open settings WITHOUT the customer/community side
          // drawer so settings can't become a doorway back into the user shell.
          builder: (_) => SettingsScreen(showUserDrawer: showCommunitySection),
        ),
      );
    }

    Future<void> runItem(AppUserDrawerItem item) async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await item.onTap?.call(navigator.context);
    }

    Widget? buildDrawerTrailing(AppUserDrawerItem item) {
      if (item.trailing != null) return item.trailing;
      final badgeCount = item.badgeCount;
      if (badgeCount == null) return null;
      final scheme = Theme.of(context).colorScheme;
      final hasItems = badgeCount > 0;
      final color = hasItems ? scheme.error : scheme.outline;
      return Container(
        constraints: const BoxConstraints(minWidth: 30),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: hasItems ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$badgeCount',
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      );
    }

    Future<void> openSocialSearch() async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => const SocialSearchScreen()),
      );
    }

    Future<void> openNotifications() async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => const SocialActivityScreen()),
      );
    }

    Future<void> openFriendRequests() async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const SocialRelationRequestsScreen(),
        ),
      );
    }

    Future<void> openSocialChats() async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const SocialShellScreen(initialTab: SocialShellTab.messages),
        ),
      );
    }

    Future<void> openReportedPosts() async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const SocialReportedPostsScreen(),
        ),
      );
    }

    Future<void> openCommunityScope({
      required String scopeType,
      required String scopeCode,
      required String title,
    }) async {
      final navigator = Navigator.of(context);
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => SocialCommunityScreen(
            scopeType: scopeType,
            scopeCode: scopeCode,
            title: title,
          ),
        ),
      );
    }

    Future<void> openCommunityScopePrompt({
      required String scopeType,
      required String titleLabel,
      required String hintText,
    }) async {
      final codeCtrl = TextEditingController();
      final navigator = Navigator.of(context);
      final approved = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(titleLabel, textDirection: textDirection),
          content: TextField(
            controller: codeCtrl,
            textDirection: textDirection,
            decoration: InputDecoration(
              hintText: hintText,
              hintTextDirection: textDirection,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.commonOpen),
            ),
          ],
        ),
      );
      final scopeCode = codeCtrl.text.trim().toUpperCase();
      codeCtrl.dispose();
      if (approved != true || scopeCode.isEmpty) return;
      if (!embedded) navigator.pop();
      await navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              SocialCommunityScreen(scopeType: scopeType, scopeCode: scopeCode),
        ),
      );
    }

    final resolvedItems = <AppUserDrawerItem>[
      ...drawerItems,
      AppUserDrawerItem(
        icon: Icons.support_agent_rounded,
        label: context.lt(ar: 'الدعم / مشكلة', en: 'Support'),
        subtitle: context.lt(
          ar: 'أرسل مشكلة أو استفساراً للدعم',
          en: 'Send a problem or question to support',
        ),
        onTap: (ctx) async {
          await showSupportRequestSheet(
            ctx,
            supportContext: const SupportContext.general(),
          );
        },
      ),
      if (canOpenSocialTools && !hasDrawerItem(l10n.drawerNotifications))
        AppUserDrawerItem(
          icon: Icons.notifications_outlined,
          label: l10n.drawerNotifications,
          subtitle: l10n.drawerNotificationsSub,
          group: socialGroup,
          onTap: (_) => openNotifications(),
        ),
      if (canOpenSocialTools && !hasDrawerItem(l10n.drawerUserSearch))
        AppUserDrawerItem(
          icon: Icons.person_search_rounded,
          label: l10n.drawerUserSearch,
          subtitle: l10n.drawerUserSearchSub,
          group: socialGroup,
          onTap: (_) => openSocialSearch(),
        ),
      if (canOpenSocialTools && !hasDrawerItem(l10n.drawerFriendRequests))
        AppUserDrawerItem(
          icon: Icons.person_add_alt_1_rounded,
          label: l10n.drawerFriendRequests,
          subtitle: l10n.drawerFriendRequestsSub,
          group: socialGroup,
          onTap: (_) => openFriendRequests(),
        ),
      if (canOpenSocialTools && !hasDrawerItem(l10n.drawerMessages))
        AppUserDrawerItem(
          icon: Icons.chat_bubble_outline_rounded,
          label: l10n.drawerMessages,
          subtitle: l10n.drawerMessagesSub,
          group: socialGroup,
          onTap: (_) => openSocialChats(),
        ),
      if (canOpenSocialTools && !hasDrawerItem(l10n.drawerReportedPosts))
        AppUserDrawerItem(
          icon: Icons.flag_outlined,
          label: l10n.drawerReportedPosts,
          subtitle: l10n.drawerReportedPostsSub,
          group: socialGroup,
          onTap: (_) => openReportedPosts(),
        ),
      if (shouldShowCommunitySection &&
          (blockScopeCode != null || allowManualCommunityScopeSelection))
        AppUserDrawerItem(
          icon: Icons.account_tree_outlined,
          label: l10n.drawerBlockCommunity,
          subtitle: (isCommunityCatalogMode || blockScopeCode == null)
              ? l10n.drawerManualSelection
              : blockScopeCode,
          group: communityGroup,
          onTap: (_) => (isCommunityCatalogMode || blockScopeCode == null)
              ? openCommunityScopePrompt(
                  scopeType: 'block',
                  titleLabel: l10n.drawerEnterBlockCode,
                  hintText: l10n.drawerBlockCodeHint,
                )
              : openCommunityScope(
                  scopeType: 'block',
                  scopeCode: blockScopeCode,
                  title: '${l10n.drawerBlockCommunity} $blockScopeCode',
                ),
        ),
      if (shouldShowCommunitySection &&
          (compoundScopeCode != null || allowManualCommunityScopeSelection))
        AppUserDrawerItem(
          icon: Icons.groups_2_outlined,
          label: l10n.drawerCompoundCommunity,
          subtitle: (isCommunityCatalogMode || compoundScopeCode == null)
              ? l10n.drawerManualSelection
              : compoundScopeCode,
          group: communityGroup,
          onTap: (_) => (isCommunityCatalogMode || compoundScopeCode == null)
              ? openCommunityScopePrompt(
                  scopeType: 'compound',
                  titleLabel: l10n.drawerEnterCompoundCode,
                  hintText: l10n.drawerCompoundCodeHint,
                )
              : openCommunityScope(
                  scopeType: 'compound',
                  scopeCode: compoundScopeCode,
                  title: '${l10n.drawerCompoundCommunity} $compoundScopeCode',
                ),
        ),
      if (shouldShowCommunitySection &&
          (buildingScopeCode != null || allowManualCommunityScopeSelection))
        AppUserDrawerItem(
          icon: Icons.apartment_rounded,
          label: l10n.drawerBuildingCommunity,
          subtitle: (isCommunityCatalogMode || buildingScopeCode == null)
              ? l10n.drawerManualSelection
              : buildingScopeCode,
          group: communityGroup,
          onTap: (_) => (isCommunityCatalogMode || buildingScopeCode == null)
              ? openCommunityScopePrompt(
                  scopeType: 'building',
                  titleLabel: l10n.drawerEnterBuildingCode,
                  hintText: l10n.drawerBuildingCodeHint,
                )
              : openCommunityScope(
                  scopeType: 'building',
                  scopeCode: buildingScopeCode,
                  title: '${l10n.drawerBuildingCommunity} $buildingScopeCode',
                ),
        ),
      if (showSettings)
        AppUserDrawerItem(
          icon: Icons.settings_outlined,
          label: l10n.commonSettings,
          group: settingsGroup,
          onTap: (_) => openSettings(),
        ),
    ];

    final normalizedQuery = _normalizeForSearch(_searchQuery);
    final visibleItems = normalizedQuery.isEmpty
        ? resolvedItems
        : resolvedItems
              .where((item) {
                final haystack =
                    '${item.label} ${item.subtitle ?? ''} ${item.group ?? ''}';
                return _normalizeForSearch(haystack).contains(normalizedQuery);
              })
              .toList(growable: false);

    final groupedItems = <String, List<AppUserDrawerItem>>{};
    for (final item in visibleItems) {
      final group = (item.group ?? '').trim().isEmpty
          ? l10n.commonOperations
          : item.group!.trim();
      groupedItems.putIfAbsent(group, () => <AppUserDrawerItem>[]).add(item);
    }

    if (enableGroupCollapse && collapseGroupsByDefault) {
      for (final group in groupedItems.keys) {
        _collapsedGroups.add(group);
      }
    }

    final content = SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _drawerText(title),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (subtitle?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(_drawerText(subtitle)),
                ],
                if (userName?.isNotEmpty == true ||
                    userPhone?.isNotEmpty == true)
                  const SizedBox(height: 8),
                if (userName?.isNotEmpty == true) Text(userName!),
                if (userPhone?.isNotEmpty == true) Text(userPhone!),
                if (showProfileButton && currentUserId != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OutlinedButton.icon(
                      onPressed: openProfile,
                      icon: const Icon(Icons.person_outline_rounded),
                      label: Text(l10n.drawerProfile),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (enableItemSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: searchHintText ?? l10n.commonSearch,
                  suffixIcon: _searchQuery.trim().isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...() {
                  final widgets = <Widget>[];
                  if (groupedItems.isEmpty) {
                    widgets.add(
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                        child: Text(
                          l10n.commonNoResults,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    );
                    return widgets;
                  }
                  for (final entry in groupedItems.entries) {
                    final group = entry.key;
                    final isCollapsed = _collapsedGroups.contains(group);
                    final items = entry.value;
                    widgets.add(
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                        child: ListTile(
                          dense: true,
                          leading: enableGroupCollapse
                              ? Icon(
                                  isCollapsed
                                      ? Icons.chevron_right_rounded
                                      : Icons.expand_more_rounded,
                                )
                              : null,
                          title: Text(
                            _drawerText(group),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.92),
                                ),
                          ),
                          trailing: Text(
                            '${items.length}',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          onTap: enableGroupCollapse
                              ? () {
                                  setState(() {
                                    if (isCollapsed) {
                                      _collapsedGroups.remove(group);
                                    } else {
                                      _collapsedGroups.add(group);
                                    }
                                  });
                                }
                              : null,
                        ),
                      ),
                    );
                    if (enableGroupCollapse && isCollapsed) {
                      continue;
                    }
                    for (final item in items) {
                      widgets.add(
                        ListTile(
                          leading: Icon(item.icon),
                          title: Text(_drawerText(item.label)),
                          subtitle: item.subtitle == null
                              ? null
                              : Text(_drawerText(item.subtitle)),
                          trailing: buildDrawerTrailing(item),
                          onTap: item.onTap == null
                              ? null
                              : () => runItem(item),
                        ),
                      );
                    }
                  }
                  return widgets;
                }(),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.commonLogout),
            onTap: () async {
              if (!embedded) {
                Navigator.of(context).pop();
              }
              await ref.read(authControllerProvider.notifier).logout();
            },
          ),
        ],
      ),
    );

    if (embedded) {
      return Material(
        color: Theme.of(context).drawerTheme.backgroundColor,
        child: content,
      );
    }

    return Drawer(child: content);
  }
}
