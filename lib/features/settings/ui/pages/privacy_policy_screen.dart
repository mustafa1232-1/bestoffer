import 'package:flutter/material.dart';

import '../../../../core/constants/legal_links.dart';
import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/i18n/locale_text.dart';
import '../../../../core/platform/external_link_launcher.dart';

/// In-app, bilingual privacy policy. The hosted URL is also exposed so store
/// review and in-app legal links point to the same canonical source.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _HostedLinkCard(
        icon: Icons.public_rounded,
        title: context.lt(
          ar: 'فتح سياسة الخصوصية المنشورة',
          en: 'Open hosted privacy policy',
        ),
        subtitle: context.lt(
          ar: 'اعرض النسخة العامة من سياسة الخصوصية في المتصفح.',
          en: 'View the public privacy policy in your browser.',
        ),
        onTap: () => openExternalLink(
          context,
          kMaslakiPrivacyPolicyUrl,
          failureMessage: context.lt(
            ar: 'تعذر فتح رابط سياسة الخصوصية.',
            en: 'Unable to open the privacy policy link.',
          ),
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'نظرة عامة', en: 'Overview'),
        body: context.lt(
          ar: 'مسلكي تطبيق مجتمعي شامل للتسوق والطعام والتوصيل والتاكسي والميزات الاجتماعية. '
              'توضح هذه السياسة ما نجمعه ولماذا، والخيارات المتاحة لك.',
          en: 'Maslaki is a community super-app for shopping, food, delivery, '
              'taxi, and social features. This policy explains what we collect, '
              'why, and the choices you have.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'المعلومات التي نجمعها', en: 'Information we collect'),
        body: context.lt(
          ar: '• بيانات الحساب: الاسم ورقم الهاتف ومعلومات السكن التي تزودنا بها.\n'
              '• الموقع: لعرض المتاجر القريبة وتشغيل تتبع الرحلات والتوصيل فقط أثناء استخدامك لتلك الميزات.\n'
              '• الكاميرا والمايكروفون: للمكالمات داخل التطبيق والرسائل الصوتية والتقاط القصص والريلز والصور.\n'
              '• الصور والوسائط التي تختار رفعها.\n'
              '• الرسائل والمحتوى الاجتماعي الذي تنشره.\n'
              '• معلومات الجهاز: رمز الإشعارات وبصمة الجهاز لتأمين جلساتك.\n'
              '• بيانات الاستخدام والتشخيص (بموافقتك).',
          en: '• Account details: name, phone number, and residence info you provide.\n'
              '• Location: to show nearby merchants and to power trip and delivery tracking (only while you use those features).\n'
              '• Camera & microphone: for in-app calls, voice messages, and capturing stories, reels, and photos.\n'
              '• Photos & media you choose to upload.\n'
              '• Messages and social content you post.\n'
              '• Device information: push token and a device fingerprint used to secure your sessions.\n'
              '• Usage and diagnostics (with your consent).',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'كيف نستخدم بياناتك', en: 'How we use your data'),
        body: context.lt(
          ar: 'لتقديم الخدمات وتحسينها، وإتمام طلباتك ورحلاتك، وإرسال الإشعارات، وحماية الحسابات، ومنع الاحتيال وإساءة الاستخدام، وتقديم الدعم.',
          en: 'To provide and improve the services, complete your orders and trips, deliver notifications, keep accounts secure, prevent fraud and abuse, and offer support.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'مشاركة البيانات', en: 'Sharing'),
        body: context.lt(
          ar: 'نشارك البيانات فقط بالقدر اللازم لتشغيل الخدمة: مع المتاجر والسائقين لإتمام طلباتك ورحلاتك، ومع مزودين موثوقين للاستضافة والإشعارات وتقارير الأعطال. لا نبيع بياناتك الشخصية. وقد نفصح عن المعلومات عند الإلزام القانوني.',
          en: 'We share data only as needed to run the service: with merchants and drivers to fulfil your orders and trips, and with trusted providers for hosting, push notifications, and crash reporting. We do not sell your personal data. We may disclose information when required by law.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(
          ar: 'الاحتفاظ بالبيانات وحذفها',
          en: 'Data retention & deletion',
        ),
        body: context.lt(
          ar: 'يمكنك حذف حسابك نهائيًا في أي وقت من الإعدادات ← أمان الحساب ← حذف حسابي. يؤدي حذف الحساب إلى إزالة ملفك الشخصي وبياناتك المرتبطة، باستثناء ما يلزمنا الاحتفاظ به لأسباب قانونية.',
          en: 'You can permanently delete your account anytime from Settings → Account security → Delete my account. Deleting your account removes your profile and associated personal data, subject to records we must keep for legal reasons.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'الأمان', en: 'Security'),
        body: context.lt(
          ar: 'تُشفّر البيانات أثناء النقل (HTTPS)، وتُربط الجلسات بجهازك، والوصول مقيّد. لا توجد طريقة آمنة 100%، لكننا نعمل على حماية معلوماتك.',
          en: 'Traffic is encrypted in transit (HTTPS), sessions are bound to your device, and access is restricted. No method is 100% secure, but we work to protect your information.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'الأطفال', en: 'Children'),
        body: context.lt(
          ar: 'مسلكي غير موجّه للأطفال. إذا كنت تعتقد أن طفلًا زوّدنا ببيانات، تواصل معنا لإزالتها.',
          en: 'Maslaki is not directed to children. If you believe a child provided us data, contact us to remove it.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'خياراتك', en: 'Your choices'),
        body: context.lt(
          ar: 'يمكنك إدارة الأذونات (الموقع، الكاميرا، المايكروفون، الصور، الإشعارات) من إعدادات جهازك، وطلب الوصول إلى بياناتك أو تصحيحها أو حذفها.',
          en: 'You can manage permissions (location, camera, microphone, photos, notifications) from your device settings, and request access, correction, or deletion of your data.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'التواصل', en: 'Contact'),
        body: context.lt(
          ar: 'للأسئلة المتعلقة بالخصوصية أو طلبات البيانات، استخدم صفحة الدعم داخل التطبيق.',
          en: 'For privacy questions or data requests, reach us through Settings → Support inside the app.',
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsPrivacyPolicy)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) => items[index],
      ),
    );
  }
}

class _HostedLinkCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HostedLinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.open_in_new_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _PolicySectionCard extends StatelessWidget {
  final String title;
  final String body;

  const _PolicySectionCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.45,
              ),
        ),
      ],
    );
  }
}
