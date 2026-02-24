import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_strings.dart';
import '../../auth/state/auth_controller.dart';
import 'pages/settings_account_screen.dart';
import 'pages/settings_appearance_screen.dart';
import 'pages/settings_language_screen.dart';
import 'pages/settings_support_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final auth = ref.watch(authControllerProvider);

    Future<void> open(Widget page) {
      return Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => page));
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (auth.isAuthed)
            _SettingsHeader(phone: auth.user?.phone)
          else
            _SettingsHeader(phone: null),
          const SizedBox(height: 8),
          _SettingsSectionCard(
            icon: Icons.language_rounded,
            title: strings.t('language'),
            subtitle: strings.t('languageHint'),
            onTap: () => open(const SettingsLanguageScreen()),
          ),
          _SettingsSectionCard(
            icon: Icons.palette_outlined,
            title: strings.t('appearance'),
            subtitle: strings.t('appearanceHint'),
            onTap: () => open(const SettingsAppearanceScreen()),
          ),
          _SettingsSectionCard(
            icon: Icons.security_outlined,
            title: strings.t('accountSecurity'),
            subtitle: auth.isAuthed
                ? strings.t('accountSecurityHintAuthed')
                : strings.t('loginRequiredAccount'),
            onTap: () => open(const SettingsAccountScreen()),
          ),
          _SettingsSectionCard(
            icon: Icons.support_agent_rounded,
            title: strings.t('supportAndSystem'),
            subtitle: strings.t('supportAndSystemHint'),
            onTap: () => open(const SettingsSupportScreen()),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  final String? phone;

  const _SettingsHeader({required this.phone});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              child: Icon(
                Icons.settings_suggest_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                phone == null || phone!.isEmpty ? 'BestOffer' : phone!,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsSectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
