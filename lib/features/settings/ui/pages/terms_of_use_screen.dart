import 'package:flutter/material.dart';

import '../../../../core/constants/legal_links.dart';
import '../../../../core/i18n/locale_text.dart';
import '../../../../core/platform/external_link_launcher.dart';

class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _HostedLinkCard(
        icon: Icons.public_rounded,
        title: context.lt(
          ar: 'فتح شروط الاستخدام المنشورة',
          en: 'Open hosted terms of use',
        ),
        subtitle: context.lt(
          ar: 'اعرض النسخة العامة من الشروط في المتصفح.',
          en: 'View the public terms page in your browser.',
        ),
        onTap: () => openExternalLink(
          context,
          kMaslakiTermsOfUseUrl,
          failureMessage: context.lt(
            ar: 'تعذر فتح رابط شروط الاستخدام.',
            en: 'Unable to open the terms of use link.',
          ),
        ),
      ),
      _HostedLinkCard(
        icon: Icons.support_agent_rounded,
        title: context.lt(ar: 'صفحة الدعم', en: 'Support page'),
        subtitle: context.lt(
          ar: 'اطلب المساعدة أو حذف الحساب من صفحة الدعم.',
          en: 'Get help or request account deletion from support.',
        ),
        onTap: () => openExternalLink(
          context,
          kMaslakiSupportUrl,
          failureMessage: context.lt(
            ar: 'تعذر فتح صفحة الدعم.',
            en: 'Unable to open the support page.',
          ),
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'النطاق', en: 'Scope'),
        body: context.lt(
          ar: 'مسلكي منصة خدمات رقمية تتيح التصفح والشراء والتوصيل والتاكسي والمجتمع والرسائل.',
          en: 'Maslaki is a digital services platform for browsing, shopping, delivery, taxi, community, and messaging.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'الاستخدام المسموح', en: 'Permitted use'),
        body: context.lt(
          ar: 'يمكنك استخدام التطبيق للتصفح بدون حساب. وتحتاج إلى تسجيل الدخول عند تنفيذ الأفعال الشخصية مثل الطلبات، الرسائل، النشر، أو التفاعل المرتبط بالحساب.',
          en: 'You may browse without an account. Sign in is required for personal actions such as orders, messages, publishing, or account-tied interactions.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'السلوك المحظور', en: 'Prohibited conduct'),
        body: context.lt(
          ar: 'يُمنع إساءة الاستخدام، الاحتيال، نسخ المحتوى، أو محاولة تعطيل الخدمة أو تجاوز القيود الأمنية.',
          en: 'Misuse, fraud, copying content, or attempting to disrupt service or bypass security controls is prohibited.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'البيانات والخصوصية', en: 'Data and privacy'),
        body: context.lt(
          ar: 'نستخدم البيانات لتشغيل الخدمة فقط، وللأمان والدعم وتحسين التجربة. يمكنك مراجعة سياسة الخصوصية داخل التطبيق.',
          en: 'We use data only to operate the service, maintain safety and support, and improve the experience. See the in-app privacy policy for details.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'إنهاء الحساب', en: 'Account termination'),
        body: context.lt(
          ar: 'يمكنك طلب حذف الحساب من الإعدادات أو من الدعم، مع الاحتفاظ بما يلزم قانونيًا أو تشغيليًا للطلبات والأمان.',
          en: 'You can request account deletion from settings or support, subject to records we must retain for orders, security, or legal obligations.',
        ),
      ),
      _PolicySectionCard(
        title: context.lt(ar: 'الدعم', en: 'Support'),
        body: context.lt(
          ar: 'للمساعدة أو الاعتراضات أو طلبات الحذف، استخدم صفحة الدعم داخل التطبيق.',
          en: 'For help, disputes, or deletion requests, use the in-app support page.',
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'شروط الاستخدام', en: 'Terms of Use')),
      ),
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
