import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_strings.dart';
import '../../../../core/settings/app_settings_controller.dart';

class SettingsLanguageScreen extends ConsumerWidget {
  const SettingsLanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final settings = ref.watch(appSettingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('language'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(strings.t('currentLanguage')),
                  const SizedBox(height: 8),
                  Text(
                    settings.locale.languageCode == 'ar'
                        ? strings.t('arabic')
                        : strings.t('english'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment<String>(
                    value: 'ar',
                    label: Text(strings.t('arabic')),
                    icon: const Icon(Icons.translate),
                  ),
                  ButtonSegment<String>(
                    value: 'en',
                    label: Text(strings.t('english')),
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
            ),
          ),
        ],
      ),
    );
  }
}
