import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../data/customer_support_api.dart';
import '../models/support_context.dart';

/// يفتح نموذج «طلب دعم / مشكلة» مهيّأً حسب السياق. يعيد true إذا أُنشئت تذكرة.
Future<bool> showSupportRequestSheet(
  BuildContext context, {
  SupportContext supportContext = const SupportContext.general(),
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SupportRequestSheet(supportContext: supportContext),
  );
  return result == true;
}

class _DomainOption {
  const _DomainOption(this.value, this.icon, this.ar, this.en);
  final String value;
  final IconData icon;
  final String ar;
  final String en;
}

const _domains = <_DomainOption>[
  _DomainOption('SHOPPING', Icons.shopping_bag_rounded, 'طلبات وتسوّق', 'Shopping'),
  _DomainOption('DELIVERY', Icons.delivery_dining_rounded, 'توصيل', 'Delivery'),
  _DomainOption('TAXI', Icons.local_taxi_rounded, 'تكسي', 'Taxi'),
  _DomainOption('SERVICES', Icons.handyman_rounded, 'خدمات', 'Services'),
  _DomainOption('REAL_ESTATE', Icons.apartment_rounded, 'عقارات', 'Real estate'),
  _DomainOption('CARS', Icons.directions_car_rounded, 'سيارات', 'Cars'),
  _DomainOption('JOBS', Icons.work_rounded, 'وظائف', 'Jobs'),
  _DomainOption('COMMUNITY', Icons.groups_rounded, 'المجتمع', 'Community'),
  _DomainOption('ACCOUNT', Icons.person_rounded, 'حسابي', 'My account'),
  _DomainOption('PAYMENTS', Icons.payments_rounded, 'المدفوعات', 'Payments'),
  _DomainOption('OTHER', Icons.help_outline_rounded, 'أخرى', 'Other'),
];

const _types = <_DomainOption>[
  _DomainOption('PROBLEM', Icons.report_problem_rounded, 'مشكلة', 'Problem'),
  _DomainOption('COMPLAINT', Icons.sentiment_dissatisfied_rounded, 'شكوى', 'Complaint'),
  _DomainOption('QUESTION', Icons.help_outline_rounded, 'استفسار', 'Question'),
  _DomainOption('SUGGESTION', Icons.lightbulb_outline_rounded, 'اقتراح', 'Suggestion'),
  _DomainOption('SAFETY', Icons.health_and_safety_rounded, 'بلاغ سلامة', 'Safety'),
  _DomainOption('REFUND', Icons.currency_exchange_rounded, 'استرجاع مبلغ', 'Refund'),
];

class _SupportRequestSheet extends ConsumerStatefulWidget {
  const _SupportRequestSheet({required this.supportContext});
  final SupportContext supportContext;

  @override
  ConsumerState<_SupportRequestSheet> createState() =>
      _SupportRequestSheetState();
}

class _SupportRequestSheetState extends ConsumerState<_SupportRequestSheet> {
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  late String? _domain = widget.supportContext.domain;
  late String _type = widget.supportContext.defaultType;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _label(BuildContext context, _DomainOption o) =>
      context.lt(ar: o.ar, en: o.en);

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    if (_domain == null || _domain!.isEmpty) {
      setState(() => _error = context.lt(
            ar: 'اختر نوع الخدمة أولاً.',
            en: 'Choose a service first.',
          ));
      return;
    }
    if (subject.isEmpty) {
      setState(() => _error = context.lt(
            ar: 'اكتب عنواناً مختصراً للمشكلة.',
            en: 'Write a short subject.',
          ));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ctx = widget.supportContext;
      final ticket = await ref.read(customerSupportApiProvider).createTicket(
            domain: _domain!,
            type: _type,
            subject: subject,
            description: _descCtrl.text,
            priority: _domain == 'TAXI' && _type == 'SAFETY' ? 'urgent' : 'normal',
            entityType: ctx.entityType,
            entityId: ctx.entityId,
            entityLabel: ctx.entityLabel,
          );
      if (!mounted) return;
      final number = '${ticket['ticket_number'] ?? ticket['ticketNumber'] ?? ''}';
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(
              ar: 'تم إرسال طلب الدعم. رقم التذكرة: $number',
              en: 'Support request sent. Ticket: $number',
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = context.lt(
          ar: 'تعذّر إرسال الطلب، حاول مرة أخرى.',
          en: 'Could not send the request, please try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.supportContext;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.support_agent_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.lt(ar: 'طلب دعم', en: 'Get support'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (ctx.entityLabel != null && ctx.entityLabel!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.lt(
                          ar: 'بخصوص: ${ctx.entityLabel}',
                          en: 'About: ${ctx.entityLabel}',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            // اختيار القسم (الوضع العام فقط).
            if (ctx.isAskMode) ...[
              Text(
                context.lt(ar: 'ما هي المشكلة؟', en: 'What is it about?'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _domains.map((o) {
                  final selected = _domain == o.value;
                  return ChoiceChip(
                    avatar: Icon(o.icon, size: 18),
                    label: Text(_label(context, o)),
                    selected: selected,
                    onSelected: (_) => setState(() => _domain = o.value),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              context.lt(ar: 'نوع الطلب', en: 'Type'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _types.map((o) {
                final selected = _type == o.value;
                return ChoiceChip(
                  avatar: Icon(o.icon, size: 18),
                  label: Text(_label(context, o)),
                  selected: selected,
                  onSelected: (_) => setState(() => _type = o.value),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _subjectCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.lt(ar: 'عنوان المشكلة', en: 'Subject'),
                hintText: context.lt(
                  ar: 'مثال: لم يصل طلبي',
                  en: 'e.g. My order did not arrive',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: context.lt(
                  ar: 'اشرح المشكلة (اختياري)',
                  en: 'Describe the problem (optional)',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: scheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(context.lt(ar: 'إرسال الطلب', en: 'Send request')),
            ),
          ],
        ),
      ),
    );
  }
}
