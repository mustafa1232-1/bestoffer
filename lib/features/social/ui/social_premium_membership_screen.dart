import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../paid_upgrades/models/paid_upgrade_models.dart';
import '../../paid_upgrades/state/paid_upgrades_summary_provider.dart';
import '../../paid_upgrades/ui/paid_upgrades_home_screen.dart';

class SocialPremiumMembershipScreen extends ConsumerWidget {
  const SocialPremiumMembershipScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(myPaidUpgradesSummaryProvider);
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(title: const Text('اشتراك بريميوم')),
        body: summaryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'تعذر تحميل بيانات الاشتراك الآن.\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (summary) => _MembershipBody(summary: summary),
        ),
      ),
    );
  }
}

class _MembershipBody extends StatelessWidget {
  final PaidUpgradesSummaryModel summary;

  const _MembershipBody({required this.summary});

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString().padLeft(4, '0');
    return '$year/$month/$day';
  }

  String _remaining(DateTime? value) {
    if (value == null) return 'غير محدد';
    final diff = value.toLocal().difference(DateTime.now());
    if (diff.isNegative || diff.inSeconds <= 0) return 'منتهي';
    if (diff.inDays >= 1) return 'متبقي ${diff.inDays} يوم';
    final hours = diff.inHours > 0 ? diff.inHours : 1;
    return 'متبقي $hours ساعة';
  }

  DateTime? _premiumExpiry() {
    for (final sub in summary.activeSubscriptions) {
      if (sub.planCode == 'premium_monthly') return sub.expiresAt;
    }
    return summary.premiumBadgeExpiresAt;
  }

  @override
  Widget build(BuildContext context) {
    final active = summary.premiumMonthly || summary.premiumBadgeActive;
    final expiry = _premiumExpiry();
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: scheme.surfaceContainerHighest,
            border: Border.all(
              color: active
                  ? const Color(0xFF16A34A).withValues(alpha: 0.35)
                  : scheme.outline.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                textDirection: Directionality.of(context),
                children: [
                  Expanded(
                    child: Text(
                      active
                          ? 'عضوية بريميوم فعّالة'
                          : 'لا يوجد اشتراك بريميوم فعّال',
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.workspace_premium_rounded,
                    color: active ? const Color(0xFF16A34A) : scheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoLine(label: 'تاريخ الانتهاء', value: _formatDate(expiry)),
              const SizedBox(height: 8),
              _InfoLine(label: 'الوقت المتبقي', value: _remaining(expiry)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PaidUpgradesHomeScreen(),
              ),
            );
          },
          icon: Icon(active ? Icons.autorenew_rounded : Icons.upgrade_rounded),
          label: Text(active ? 'تجديد الاشتراك' : 'الاشتراك الآن'),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: Directionality.of(context),
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        const Spacer(),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
