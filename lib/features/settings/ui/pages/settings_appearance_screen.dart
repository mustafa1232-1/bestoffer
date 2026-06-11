import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/settings/app_settings_controller.dart';

class SettingsAppearanceScreen extends ConsumerWidget {
  const SettingsAppearanceScreen({super.key});

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
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded),
                  title: Text(l10n.settingsColorPresetTitle),
                  subtitle: Text(
                    Localizations.localeOf(context).languageCode == 'ar'
                        ? 'تم اعتماد الهوية البصرية الرسمية لمسلكي.'
                        : 'Maslaki official visual identity is now fixed.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
