import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/auth_controller.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../i18n/app_strings.dart';

class AppUserDrawerItem {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Future<void> Function(BuildContext context)? onTap;

  const AppUserDrawerItem({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
  });
}

class AppUserDrawer extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final List<AppUserDrawerItem> items;
  final bool showSettings;

  const AppUserDrawer({
    super.key,
    required this.title,
    this.subtitle,
    this.items = const [],
    this.showSettings = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final userName = auth.user?.fullName.trim();
    final userPhone = auth.user?.phone.trim();

    Future<void> openSettings() async {
      Navigator.of(context).pop();
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    }

    Future<void> runItem(AppUserDrawerItem item) async {
      Navigator.of(context).pop();
      await item.onTap?.call(context);
    }

    return Drawer(
      child: SafeArea(
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
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  if (subtitle?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!),
                  ],
                  if (userName?.isNotEmpty == true || userPhone?.isNotEmpty == true)
                    const SizedBox(height: 8),
                  if (userName?.isNotEmpty == true) Text(userName!),
                  if (userPhone?.isNotEmpty == true) Text(userPhone!),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in items)
                    ListTile(
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      subtitle: item.subtitle == null ? null : Text(item.subtitle!),
                      onTap: item.onTap == null ? null : () => runItem(item),
                    ),
                  if (showSettings)
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: Text(strings.t('settings')),
                      onTap: openSettings,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(strings.t('logout')),
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(authControllerProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}
