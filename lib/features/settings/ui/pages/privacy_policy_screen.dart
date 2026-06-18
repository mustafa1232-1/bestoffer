import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/i18n/locale_text.dart';

/// Optional hosted policy URL. When set (and url_launcher wired by the store
/// build), a "view online" affordance can point here. The store listing still
/// needs a public URL — this in-app screen satisfies the in-app requirement.
const String kMaslakiPrivacyPolicyUrl = '';

/// In-app, bilingual privacy policy. Kept self-contained so the app always has
/// a readable policy even before a hosted page exists.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = <_PolicySection>[
      _PolicySection(
        title: context.lt(en: 'Overview', ar: 'نظرة عامة'),
        body: context.lt(
          en: 'Maslaki is a community super-app for shopping, food, delivery, '
              'taxi, and social features. This policy explains what we collect, '
              'why, and the choices you have.',
          ar: 'مسلكي تطبيق مجتمعي شامل للتسوق والطعام والتوصيل والتاكسي '
              'والميزات الاجتماعية. توضّح هذه السياسة ما نجمعه ولماذا، '
              'والخيارات المتاحة لك.',
        ),
      ),
      _PolicySection(
        title: context.lt(en: 'Information we collect', ar: 'المعلومات التي نجمعها'),
        body: context.lt(
          en: '• Account details: name, phone number, and residence info you '
              'provide.\n'
              '• Location: to show nearby merchants and to power trip and '
              'delivery tracking (only while you use those features).\n'
              '• Camera & microphone: for in-app calls, voice messages, and '
              'capturing stories, reels, and photos.\n'
              '• Photos & media you choose to upload.\n'
              '• Messages and social content you post.\n'
              '• Device information: push token and a device fingerprint used '
              'to secure your sessions.\n'
              '• Usage and diagnostics (with your consent).',
          ar: '• بيانات الحساب: الاسم ورقم الهاتف ومعلومات السكن التي تزوّدنا بها.\n'
              '• الموقع: لعرض المتاجر القريبة وتشغيل تتبّع الرحلات والتوصيل '
              '(فقط أثناء استخدامك لتلك الميزات).\n'
              '• الكاميرا والمايكروفون: للمكالمات داخل التطبيق والرسائل الصوتية '
              'والتقاط القصص والريلز والصور.\n'
              '• الصور والوسائط التي تختار رفعها.\n'
              '• الرسائل والمحتوى الاجتماعي الذي تنشره.\n'
              '• معلومات الجهاز: رمز الإشعارات وبصمة الجهاز لتأمين جلساتك.\n'
              '• بيانات الاستخدام والتشخيص (بموافقتك).',
        ),
      ),
      _PolicySection(
        title: context.lt(en: 'How we use your data', ar: 'كيف نستخدم بياناتك'),
        body: context.lt(
          en: 'To provide and improve the services, complete your orders and '
              'trips, deliver notifications, keep accounts secure, prevent '
              'fraud and abuse, and offer support.',
          ar: 'لتقديم الخدمات وتحسينها، وإتمام طلباتك ورحلاتك، وإرسال الإشعارات، '
              'وحماية الحسابات، ومنع الاحتيال وإساءة الاستخدام، وتقديم الدعم.',
        ),
      ),
      _PolicySection(
        title: context.lt(en: 'Sharing', ar: 'مشاركة البيانات'),
        body: context.lt(
          en: 'We share data only as needed to run the service: with merchants '
              'and drivers to fulfil your orders and trips, and with trusted '
              'providers for hosting, push notifications, and crash reporting. '
              'We do not sell your personal data. We may disclose information '
              'when required by law.',
          ar: 'نشارك البيانات فقط بالقدر اللازم لتشغيل الخدمة: مع المتاجر '
              'والسائقين لإتمام طلباتك ورحلاتك، ومع مزوّدين موثوقين للاستضافة '
              'والإشعارات وتقارير الأعطال. لا نبيع بياناتك الشخصية. وقد نُفصح '
              'عن المعلومات عند الإلزام القانوني.',
        ),
      ),
      _PolicySection(
        title: context.lt(en: 'Data retention & deletion', ar: 'الاحتفاظ بالبيانات وحذفها'),
        body: context.lt(
          en: 'You can permanently delete your account anytime from '
              'Settings → Account security → Delete my account. Deleting your '
              'account removes your profile and associated personal data, '
              'subject to records we must keep for legal reasons.',
          ar: 'يمكنك حذف حسابك نهائيًا في أي وقت من '
              'الإعدادات ← أمان الحساب ← حذف حسابي. يؤدي حذف الحساب إلى إزالة '
              'ملفك الشخصي وبياناتك المرتبطة، باستثناء ما يلزمنا الاحتفاظ به '
              'لأسباب قانونية.',
        ),
      ),
      _PolicySection(
        title: context.lt(en: 'Security', ar: 'الأمان'),
        body: context.lt(
          en: 'Traffic is encrypted in transit (HTTPS), sessions are bound to '
              'your device, and access is restricted. No method is 100% secure, '
              'but we work to protect your information.',
          ar: 'تُشفَّر البيانات أثناء النقل (HTTPS)، وتُربط الجلسات بجهازك، '
              'والوصول مقيّد. لا توجد طريقة آمنة 100%، لكننا نعمل على حماية '
              'معلوماتك.',
        ),
      ),
      _PolicySection(
        title: context.lt(en: 'Children', ar: 'الأطفال'),
        body: context.lt(
          en: 'Maslaki is not directed to children. If you believe a child '
              'provided us data, contact us to remove it.',
          ar: 'مسلكي غير موجّه للأطفال. إذا كنت تعتقد أن طفلًا زوّدنا ببيانات، '
              'تواصل معنا لإزالتها.',
        ),
      ),
      _PolicySection(
        title: context.lt(en: 'Your choices', ar: 'خياراتك'),
        body: context.lt(
          en: 'You can manage permissions (location, camera, microphone, '
              'photos, notifications) from your device settings, and request '
              'access, correction, or deletion of your data.',
          ar: 'يمكنك إدارة الأذونات (الموقع، الكاميرا، المايكروفون، الصور، '
              'الإشعارات) من إعدادات جهازك، وطلب الوصول إلى بياناتك أو تصحيحها '
              'أو حذفها.',
        ),
      ),
      _PolicySection(
        title: context.lt(en: 'Contact', ar: 'التواصل'),
        body: context.lt(
          en: 'For privacy questions or data requests, reach us through '
              'Settings → Support inside the app.',
          ar: 'للأسئلة المتعلقة بالخصوصية أو طلبات البيانات، تواصل معنا عبر '
              'الإعدادات ← الدعم داخل التطبيق.',
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsPrivacyPolicy)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final section = sections[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                section.body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PolicySection {
  final String title;
  final String body;
  const _PolicySection({required this.title, required this.body});
}
