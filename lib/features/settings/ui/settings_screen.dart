import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permission_matrix.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../../core/widgets/maslaki_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import 'pages/settings_account_screen.dart';
import 'pages/settings_activity_screen.dart';
import 'pages/settings_appearance_screen.dart';
import 'pages/settings_cache_screen.dart';
import 'pages/settings_language_screen.dart';
import 'pages/settings_support_screen.dart';
import 'pages/settings_usage_guide_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final permissions = ref.watch(appPermissionMatrixProvider);
    final settings = ref.watch(appSettingsControllerProvider);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    Future<void> open(Widget page) {
      return Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => page));
    }

    final l10n = context.l10n;

    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: context.maslakiTokens.backgroundPrimary,
      endDrawer: const MaslakiUserDrawer(),
      appBar: MaslakiTopBar(
        title: l10n.commonSettings,
        subtitle: context.lt(
          ar: 'اللغة والمظهر والأمان والدعم في مكان واحد.',
          en: 'Language, appearance, security, and support in one place.',
        ),
        leading: canPop
            ? IconButton(
                tooltip: l10n.commonBack,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : const MaslakiUserDrawerButton(),
        actions: [
          if (canPop) const MaslakiUserDrawerButton(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SettingsHeader(phone: auth.isAuthed ? auth.user?.phone : null),
          const SizedBox(height: 8),
          _SettingsQuickActions(
            canActivity: permissions.can(AppCapability.customerActivity),
            onOpenLanguage: () => open(const SettingsLanguageScreen()),
            onOpenAppearance: () => open(const SettingsAppearanceScreen()),
            onOpenAccount: () => open(const SettingsAccountScreen()),
            onOpenSupport: () => open(const SettingsSupportScreen()),
            onOpenActivity: () => open(const SettingsActivityScreen()),
            onOpenGuide: () => open(const SettingsUsageGuideScreen()),
            onOpenCache: () => open(const SettingsCacheScreen()),
            cacheLabel: isArabic ? 'الملفات المؤقتة' : 'Cached media',
            cacheSubtitle: isArabic
                ? 'حجم الوسائط المخزنة ومسح الكاش'
                : 'Cached size and clear controls',
          ),
          const SizedBox(height: 8),
          MaslakiCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.commonLanguage,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.settingsLanguageHint),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment<String>(
                        value: 'ar',
                        label: Text(l10n.commonArabic),
                        icon: const Icon(Icons.translate),
                      ),
                      ButtonSegment<String>(
                        value: 'en',
                        label: Text(l10n.commonEnglish),
                        icon: const Icon(Icons.language_rounded),
                      ),
                    ],
                    selected: {settings.locale.languageCode},
                    onSelectionChanged: (selection) {
                      final code = selection.first;
                      ref
                          .read(appSettingsControllerProvider.notifier)
                          .setLocale(Locale(code));
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => open(const SettingsLanguageScreen()),
                      icon: const Icon(Icons.tune_rounded),
                      label: Text(l10n.settingsMoreLanguageOptions),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _SettingsSectionCard(
            icon: Icons.menu_book_rounded,
            title: l10n.settingsGuide,
            subtitle: l10n.settingsInterfaceTutorials,
            onTap: () => open(const SettingsUsageGuideScreen()),
          ),
          _SettingsSectionCard(
            icon: Icons.palette_outlined,
            title: l10n.settingsAppearance,
            subtitle: l10n.settingsAppearanceHint,
            onTap: () => open(const SettingsAppearanceScreen()),
          ),
          _SettingsSectionCard(
            icon: Icons.security_outlined,
            title: l10n.settingsAccountSecurity,
            subtitle: auth.isAuthed
                ? l10n.settingsAccountSecurityHintAuthed
                : l10n.settingsLoginRequiredAccount,
            onTap: () => open(const SettingsAccountScreen()),
          ),
          if (permissions.can(AppCapability.customerActivity))
            _SettingsSectionCard(
              icon: Icons.history_rounded,
              title: l10n.settingsMyActivityLog,
              subtitle: l10n.settingsLatestEvents,
              onTap: () => open(const SettingsActivityScreen()),
            ),
          _SettingsSectionCard(
            icon: Icons.support_agent_rounded,
            title: l10n.settingsSupportAndSystem,
            subtitle: l10n.settingsSupportAndSystemHint,
            onTap: () => open(const SettingsSupportScreen()),
          ),
          _SettingsSectionCard(
            icon: Icons.photo_library_outlined,
            title: isArabic ? 'الملفات المؤقتة' : 'Cached media',
            subtitle: isArabic
                ? 'عرض حجم الكاش ومسحه'
                : 'View cache usage and clear it',
            onTap: () => open(const SettingsCacheScreen()),
          ),
        ],
      ),
    );
  }
}

class _SettingsQuickActions extends StatelessWidget {
  final bool canActivity;
  final Future<void> Function() onOpenLanguage;
  final Future<void> Function() onOpenAppearance;
  final Future<void> Function() onOpenAccount;
  final Future<void> Function() onOpenSupport;
  final Future<void> Function() onOpenActivity;
  final Future<void> Function() onOpenGuide;
  final Future<void> Function() onOpenCache;
  final String cacheLabel;
  final String cacheSubtitle;

  const _SettingsQuickActions({
    required this.canActivity,
    required this.onOpenLanguage,
    required this.onOpenAppearance,
    required this.onOpenAccount,
    required this.onOpenSupport,
    required this.onOpenActivity,
    required this.onOpenGuide,
    required this.onOpenCache,
    required this.cacheLabel,
    required this.cacheSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cards = <Widget>[
      _SettingsQuickCard(
        icon: Icons.language_rounded,
        title: l10n.commonLanguage,
        subtitle: '${l10n.commonArabic} / ${l10n.commonEnglish}',
        onTap: onOpenLanguage,
      ),
      _SettingsQuickCard(
        icon: Icons.palette_outlined,
        title: l10n.settingsAppearance,
        subtitle: l10n.settingsThemeAndFonts,
        onTap: onOpenAppearance,
      ),
      _SettingsQuickCard(
        icon: Icons.security_outlined,
        title: l10n.settingsAccount,
        subtitle: l10n.settingsSecurityAndPrivacy,
        onTap: onOpenAccount,
      ),
      if (canActivity)
        _SettingsQuickCard(
          icon: Icons.history_rounded,
          title: l10n.settingsMyActivityLog,
          subtitle: l10n.settingsLatestEvents,
          onTap: onOpenActivity,
        ),
      _SettingsQuickCard(
        icon: Icons.menu_book_rounded,
        title: l10n.settingsGuide,
        subtitle: l10n.settingsInterfaceTutorials,
        onTap: onOpenGuide,
      ),
      _SettingsQuickCard(
        icon: Icons.support_agent_rounded,
        title: l10n.settingsSupport,
        subtitle: l10n.settingsSystemHelp,
        onTap: onOpenSupport,
      ),
      _SettingsQuickCard(
        icon: Icons.photo_library_outlined,
        title: cacheLabel,
        subtitle: cacheSubtitle,
        onTap: onOpenCache,
      ),
    ];

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => cards[index],
      ),
    );
  }
}

class _SettingsQuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;

  const _SettingsQuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          width: 176,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primary.withValues(alpha: 0.18),
                child: Icon(icon, size: 17, color: scheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  final String? phone;

  const _SettingsHeader({required this.phone});

  @override
  Widget build(BuildContext context) {
    return MaslakiCard(
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
                phone == null || phone!.isEmpty ? context.l10n.appName : phone!,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MaslakiCard(
        padding: EdgeInsets.zero,
        child: ListTile(
        onTap: onTap,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
      ),
    );
  }
}
