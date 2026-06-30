import 'package:flutter/material.dart';

import '../../../../core/i18n/locale_text.dart';

class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = <_TermsSection>[
      _TermsSection(
        title: context.lt(ar: 'النطاق', en: 'Scope'),
        body: context.lt(
          ar: 'مسلكي منصة خدمات رقمية تتيح التصفح والشراء والتوصيل والتكسي والمجتمع والرسائل.',
          en: 'Maslaki is a digital services platform for browsing, shopping, delivery, taxi, community, and messaging.',
        ),
      ),
      _TermsSection(
        title: context.lt(ar: 'الاستخدام المسموح', en: 'Permitted use'),
        body: context.lt(
          ar: 'يمكنك استخدام التطبيق للتصفح بدون حساب. وتحتاج إلى تسجيل الدخول عند تنفيذ الأفعال الشخصية مثل الطلبات، الرسائل، النشر، أو التفاعل المرتبط بالحساب.',
          en: 'You may browse without an account. Sign in is required for personal actions such as orders, messages, publishing, or account-tied interactions.',
        ),
      ),
      _TermsSection(
        title: context.lt(ar: 'السلوك المحظور', en: 'Prohibited conduct'),
        body: context.lt(
          ar: 'يُمنع إساءة الاستخدام، الاحتيال، نسخ المحتوى، أو محاولة تعطيل الخدمة أو تجاوز القيود الأمنية.',
          en: 'Misuse, fraud, copying content, or attempting to disrupt service or bypass security controls is prohibited.',
        ),
      ),
      _TermsSection(
        title: context.lt(ar: 'البيانات والخصوصية', en: 'Data and privacy'),
        body: context.lt(
          ar: 'نستخدم البيانات لتشغيل الخدمة فقط، وللأمان والدعم وتحسين التجربة. يمكنك مراجعة سياسة الخصوصية داخل التطبيق.',
          en: 'We use data only to operate the service, maintain safety and support, and improve the experience. See the in-app privacy policy for details.',
        ),
      ),
      _TermsSection(
        title: context.lt(ar: 'إنهاء الحساب', en: 'Account termination'),
        body: context.lt(
          ar: 'يمكنك طلب حذف الحساب من الإعدادات أو من الدعم، مع الاحتفاظ بما يلزم قانونيًا أو تشغيليًا للطلبات والأمان.',
          en: 'You can request account deletion from settings or support, subject to records we must retain for orders, security, or legal obligations.',
        ),
      ),
      _TermsSection(
        title: context.lt(ar: 'الدعم', en: 'Support'),
        body: context.lt(
          ar: 'للمساعدة أو الاعتراضات أو طلبات الحذف، استخدم صفحة الدعم داخل التطبيق.',
          en: 'For help, disputes, or deletion requests, use the in-app support page.',
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(context.lt(ar: 'شروط الاستخدام', en: 'Terms of Use'))),
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

class _TermsSection {
  final String title;
  final String body;

  const _TermsSection({required this.title, required this.body});
}
