import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/settings/app_settings_controller.dart';

class SettingsLanguageScreen extends ConsumerWidget {
  const SettingsLanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.commonLanguage)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.settingsCurrentLanguage),
                  const SizedBox(height: 8),
                  Text(
                    settings.locale.languageCode == 'ar'
                        ? l10n.commonArabic
                        : l10n.commonEnglish,
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
            ),
          ),
        ],
      ),
    );
  }
}
