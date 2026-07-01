import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/legal_links.dart';
import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/i18n/locale_text.dart';
import '../../../../core/platform/external_link_launcher.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_use_screen.dart';

class SettingsSupportScreen extends ConsumerWidget {
  const SettingsSupportScreen({super.key});

  static const _supportPhone = '07701234567';
  static const _supportWhatsApp = '07701234567';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    Future<void> copy(String value) async {
      await Clipboard.setData(ClipboardData(text: value));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.commonCopied)));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSupportAndSystem)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: Text(
                    context.lt(ar: 'صفحة الدعم الرسمية', en: 'Official support page'),
                  ),
                  subtitle: const Text(kMaslakiSupportUrl),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => openExternalLink(
                    context,
                    kMaslakiSupportUrl,
                    failureMessage: context.lt(
                      ar: 'تعذر فتح صفحة الدعم.',
                      en: 'Unable to open the support page.',
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.phone_in_talk_rounded),
                  title: Text(l10n.commonCall),
                  subtitle: const Text(_supportPhone),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => copy(_supportPhone),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded),
                  title: const Text('WhatsApp'),
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
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(l10n.settingsPrivacyPolicy),
                  subtitle: Text(l10n.settingsPrivacyPolicyHint),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.gavel_rounded),
                  title: Text(
                    context.lt(ar: 'شروط الاستخدام', en: 'Terms of Use'),
                  ),
                  subtitle: Text(
                    context.lt(
                      ar: 'راجع الحقوق والالتزامات وسياسة الإلغاء',
                      en: 'Review rights, obligations, and deletion policy',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TermsOfUseScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                context.lt(
                  ar: 'للطلبات أو المشاكل أو طلبات حذف الحساب، استخدم صفحة الدعم أو الإعدادات ← أمان الحساب ← حذف حسابي.',
                  en: 'For orders, issues, or account deletion requests, use the support page or Settings → Account security → Delete my account.',
                ),
                textAlign: TextAlign.start,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
