import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/settings/app_settings_controller.dart';

class SettingsAppearanceScreen extends ConsumerWidget {
  const SettingsAppearanceScreen({super.key});

  static bool _ar(BuildContext c) =>
      Localizations.localeOf(c).languageCode == 'ar';

  static String _themeName(BuildContext c, MaslakiTheme theme) {
    switch (theme) {
      case MaslakiTheme.original:
        return _ar(c) ? 'مسلكي الأصلي' : 'Maslaki Original';
      case MaslakiTheme.twilight:
        return _ar(c) ? 'شفق مسلكي' : 'Maslaki Twilight';
      case MaslakiTheme.coral:
        return _ar(c) ? 'مسلكي المرجاني' : 'Maslaki Coral';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAppearance)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.animationsEnabled,
                  title: Text(l10n.settingsAnimation),
                  subtitle: Text(l10n.settingsAnimationHint),
                  onChanged: (value) {
                    ref
                        .read(appSettingsControllerProvider.notifier)
                        .setAnimationsEnabled(value);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: settings.weatherEffectsEnabled,
                  title: Text(l10n.settingsWeatherEffects),
                  subtitle: Text(l10n.settingsWeatherEffectsHint),
                  onChanged: (value) {
                    ref
                        .read(appSettingsControllerProvider.notifier)
                        .setWeatherEffectsEnabled(value);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: Text(l10n.settingsResetVisual),
                  subtitle: Text(l10n.settingsResetVisualHint),
                  onTap: () async {
                    await ref
                        .read(appSettingsControllerProvider.notifier)
                        .resetVisualDefaults();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    l10n.settingsColorPresetTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _ar(context)
                        ? 'اختر أحد ثيمات مسلكي الرسمية الثلاثة. الشعار ثابت في كل الثيمات.'
                        : 'Choose one of the three official Maslaki themes. The logo stays the same across all themes.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final theme in MaslakiTheme.values)
                  _ThemeOption(
                    theme: theme,
                    label: _themeName(context, theme),
                    selected: settings.maslakiTheme == theme,
                    onTap: () => ref
                        .read(appSettingsControllerProvider.notifier)
                        .setMaslakiTheme(theme),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.theme,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final MaslakiTheme theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokensForTheme(theme);
    return ListTile(
      onTap: onTap,
      leading: _Preview(tokens: tokens),
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary)
          : const Icon(Icons.circle_outlined),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.tokens});

  final MaslakiThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: tokens.backgroundPrimary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot(tokens.primaryAccent),
          const SizedBox(width: 4),
          dot(tokens.secondaryAccent),
        ],
      ),
    );
  }
}
