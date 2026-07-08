import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';

/// Store-owner card that surfaces the merchant's monthly subscription debt.
///
/// Rendered ONLY when the merchant is billed by monthly subscription. For
/// percentage merchants (or when the caller lacks financial-report permission
/// and the summary is null) it collapses to nothing — the subscription debt is
/// never mixed with per-order cash settlement.
class MonthlySubscriptionCard extends StatelessWidget {
  const MonthlySubscriptionCard({super.key, required this.summary});

  final Map<String, dynamic>? summary;

  static String statusLabel(BuildContext context, String? status) {
    switch (status) {
      case 'paid':
        return context.lt(ar: 'مسدّدة', en: 'Paid');
      case 'partially_paid':
        return context.lt(ar: 'مسددة جزئياً', en: 'Partially paid');
      case 'waived':
        return context.lt(ar: 'معفاة', en: 'Waived');
      case 'overdue':
        return context.lt(ar: 'متأخرة', en: 'Overdue');
      case 'pending':
      default:
        return context.lt(ar: 'بانتظار السداد', en: 'Pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = summary;
    if (data == null || data['isMonthlySubscription'] != true) {
      return const SizedBox.shrink();
    }

    final invoice = data['currentInvoice'] is Map
        ? Map<String, dynamic>.from(data['currentInvoice'] as Map)
        : null;
    final report = data['report'] is Map
        ? Map<String, dynamic>.from(data['report'] as Map)
        : const <String, dynamic>{};

    num n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

    final subscriptionAmount = n(invoice?['subscriptionAmount']);
    final paidAmount = n(invoice?['paidAmount']);
    final remainingAmount = n(
      invoice?['remainingAmount'] ?? report['totalRemaining'],
    );
    final status = invoice?['status'] as String?;
    final billingMonth = invoice?['billingMonth']?.toString();
    final dueAt = invoice?['dueAt']?.toString();

    return Card(
      key: const Key('monthly_subscription_card'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.lt(ar: 'الاشتراك الشهري', en: 'Monthly subscription'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                _StatusChip(label: statusLabel(context, status), status: status),
              ],
            ),
            const SizedBox(height: 10),
            if (invoice == null)
              Text(
                context.lt(
                  ar: 'لا توجد فاتورة اشتراك للشهر الحالي بعد.',
                  en: 'No subscription invoice for the current month yet.',
                ),
              )
            else ...[
              if (billingMonth != null)
                _Row(
                  label: context.lt(ar: 'الشهر', en: 'Billing month'),
                  value: billingMonth,
                ),
              _Row(
                label: context.lt(ar: 'قيمة الاشتراك', en: 'Subscription amount'),
                value: formatIqd(subscriptionAmount),
              ),
              _Row(
                label: context.lt(ar: 'المدفوع', en: 'Paid'),
                value: formatIqd(paidAmount),
              ),
              _Row(
                label: context.lt(ar: 'المتبقي', en: 'Remaining'),
                value: formatIqd(remainingAmount),
                emphasize: remainingAmount > 0,
              ),
              if (dueAt != null)
                _Row(
                  label: context.lt(ar: 'تاريخ الاستحقاق', en: 'Due date'),
                  value: dueAt.split('T').first,
                ),
            ],
            const SizedBox(height: 4),
            Text(
              context.lt(
                ar: 'يُحصّل الاشتراك بشكل منفصل عن تسويات الطلبات النقدية.',
                en: 'Billed separately from per-order cash settlement.',
              ),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              color: emphasize ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.status});

  final String label;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color color;
    switch (status) {
      case 'paid':
        color = Colors.green;
        break;
      case 'waived':
        color = scheme.outline;
        break;
      case 'overdue':
        color = scheme.error;
        break;
      case 'partially_paid':
        color = Colors.orange;
        break;
      default:
        color = scheme.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
