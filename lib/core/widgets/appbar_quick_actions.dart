import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/auth_controller.dart';
import '../../features/notifications/ui/notifications_bell.dart';
import '../../features/settings/ui/pages/settings_account_screen.dart';
import '../../features/social/ui/social_profile_screen.dart';
import '../../features/social/ui/social_relation_requests_screen.dart';
import '../../features/social/ui/social_shell_screen.dart';
import '../../features/support/models/support_context.dart';
import '../../features/support/ui/support_request_sheet.dart';
import '../auth/app_permission_matrix.dart';
import '../i18n/app_localizations_context.dart';
import '../i18n/locale_text.dart';

class AppBarQuickActions extends ConsumerWidget {
  final bool includeNotifications;
  final bool includeMessages;
  final bool includeProfile;
  final bool includeFriendRequests;
  final bool compact;

  const AppBarQuickActions({
    super.key,
    this.includeNotifications = true,
    this.includeMessages = true,
    this.includeProfile = true,
    this.includeFriendRequests = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final matrix = ref.watch(appPermissionMatrixProvider);
    final auth = ref.watch(authControllerProvider);
    final canUseSocial = matrix.can(AppCapability.socialChats);
    final user = auth.user;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (includeNotifications) const NotificationsBellButton(),
          PopupMenuButton<_QuickAction>(
            tooltip: l10n.appBarQuickActionsQuickAccess,
            onSelected: (value) {
              switch (value) {
                case _QuickAction.support:
                  showSupportRequestSheet(
                    context,
                    supportContext: const SupportContext.general(),
                  );
                  break;
                case _QuickAction.friendRequests:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SocialRelationRequestsScreen(),
                    ),
                  );
                  break;
                case _QuickAction.messages:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SocialShellScreen(
                        initialTab: SocialShellTab.messages,
                      ),
                    ),
                  );
                  break;
                case _QuickAction.profile:
                  if (user == null) return;
                  if (canUseSocial) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SocialProfileScreen(
                          userId: user.id,
                          initialName: user.fullName,
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsAccountScreen(),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<_QuickAction>(
                value: _QuickAction.support,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.support_agent_rounded),
                  title: Text(context.lt(ar: 'الدعم / مشكلة', en: 'Support')),
                ),
              ),
              if (includeFriendRequests && canUseSocial)
                PopupMenuItem<_QuickAction>(
                  value: _QuickAction.friendRequests,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_add_alt_1_rounded),
                    title: Text(l10n.socialBasmayaFriendRequests),
                  ),
                ),
              if (includeMessages && canUseSocial)
                PopupMenuItem<_QuickAction>(
                  value: _QuickAction.messages,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.chat_bubble_outline_rounded),
                    title: Text(l10n.socialShellMessages),
                  ),
                ),
              if (includeProfile && user != null)
                PopupMenuItem<_QuickAction>(
                  value: _QuickAction.profile,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(l10n.socialBasmayaProfile),
                  ),
                ),
            ],
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.lt(ar: 'الدعم / مشكلة', en: 'Support'),
          onPressed: () => showSupportRequestSheet(
            context,
            supportContext: const SupportContext.general(),
          ),
          icon: const Icon(Icons.support_agent_rounded),
        ),
        if (includeFriendRequests && canUseSocial)
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
        if (includeMessages && canUseSocial)
          IconButton(
            tooltip: l10n.socialShellMessages,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SocialShellScreen(
                    initialTab: SocialShellTab.messages,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded),
          ),
        if (includeNotifications) const NotificationsBellButton(),
        if (includeProfile && user != null)
          IconButton(
            tooltip: l10n.socialBasmayaProfile,
            onPressed: () {
              if (canUseSocial) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SocialProfileScreen(
                      userId: user.id,
                      initialName: user.fullName,
                    ),
                  ),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsAccountScreen(),
                ),
              );
            },
            icon: const Icon(Icons.account_circle_outlined),
          ),
      ],
    );
  }
}

enum _QuickAction { support, friendRequests, messages, profile }
