import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';

/// Shown when something tries to navigate a courier into a customer/community
/// surface (e.g. via a misrouted notification). The delivery app must never
/// turn into the user shell, so we surface a clear, dead-end message instead
/// of opening the customer/social screen.
class DeliveryRestrictedScreen extends StatelessWidget {
  const DeliveryRestrictedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'غير متاح', en: 'Not available')),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block_rounded, size: 56, color: scheme.outline),
              const SizedBox(height: 16),
              Text(
                context.lt(
                  ar: 'هذه الصفحة غير متاحة في تطبيق الدلفري',
                  en: 'This page is not available in the delivery app',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                context.lt(
                  ar: 'تطبيق الدلفري مخصّص لإدارة طلبات التوصيل فقط.',
                  en: 'The delivery app is dedicated to managing courier orders only.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(context.lt(ar: 'رجوع', en: 'Back')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
