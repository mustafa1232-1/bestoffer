import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_strings.dart';
import '../../../../core/settings/app_settings_controller.dart';

class SettingsAppearanceScreen extends ConsumerWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final settings = ref.watch(appSettingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('appearance'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.animationsEnabled,
                  title: Text(strings.t('animation')),
                  subtitle: Text(strings.t('animationHint')),
                  onChanged: (value) {
                    ref
                        .read(appSettingsControllerProvider.notifier)
                        .setAnimationsEnabled(value);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: settings.weatherEffectsEnabled,
                  title: Text(strings.t('weatherFx')),
                  subtitle: Text(strings.t('weatherFxHint')),
                  onChanged: (value) {
                    ref
                        .read(appSettingsControllerProvider.notifier)
                        .setWeatherEffectsEnabled(value);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: Text(strings.t('resetVisual')),
                  subtitle: Text(strings.t('resetVisualHint')),
                  onTap: () async {
                    await ref
                        .read(appSettingsControllerProvider.notifier)
                        .resetVisualDefaults();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
