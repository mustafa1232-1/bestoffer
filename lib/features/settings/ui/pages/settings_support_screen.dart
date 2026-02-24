import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_strings.dart';

class SettingsSupportScreen extends ConsumerWidget {
  const SettingsSupportScreen({super.key});

  static const _supportPhone = '07701234567';
  static const _supportWhatsApp = '07701234567';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);

    Future<void> copy(String value) async {
      await Clipboard.setData(ClipboardData(text: value));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.t('copied'))));
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('supportAndSystem'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_in_talk_rounded),
                  title: Text(strings.t('supportNumber')),
                  subtitle: const Text(_supportPhone),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => copy(_supportPhone),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded),
                  title: Text(strings.t('supportWhatsApp')),
                  subtitle: const Text(_supportWhatsApp),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => copy(_supportWhatsApp),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(strings.t('supportTips'), textAlign: TextAlign.start),
            ),
          ),
        ],
      ),
    );
  }
}
