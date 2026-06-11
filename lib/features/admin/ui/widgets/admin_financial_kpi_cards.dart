import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/utils/currency.dart';
import '../../models/admin_financial_kpi_model.dart';

class AdminFinancialKpiCards extends StatelessWidget {
  final AdminFinancialKpiModel kpi;
  final VoidCallback onOpenSales;
  final VoidCallback onOpenCollections;
  final VoidCallback onOpenReceivables;

  const AdminFinancialKpiCards({
    super.key,
    required this.kpi,
    required this.onOpenSales,
    required this.onOpenCollections,
    required this.onOpenReceivables,
  });

  Widget _card({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required String hint,
    required VoidCallback onTap,
    String? secondary,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.24),
            ),
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              if ((secondary ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  secondary!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final totals = kpi.totals;
    return Column(
      children: [
        Row(
          children: [
            _card(
              context: context,
              icon: Icons.shopping_bag_outlined,
              title: l10n.adminFinancialKpiTotalSales,
              value: formatIqd(totals.totalSales),
              hint: l10n.adminFinancialKpiTotalSalesHint,
              onTap: onOpenSales,
            ),
            const SizedBox(width: 8),
            _card(
              context: context,
              icon: Icons.account_balance_wallet_outlined,
              title: l10n.adminFinancialKpiTotalCollected,
              value: formatIqd(totals.totalCollected),
              hint: l10n.adminFinancialKpiTotalCollectedHint,
              onTap: onOpenCollections,
            ),
            const SizedBox(width: 8),
            _card(
              context: context,
              icon: Icons.calculate_outlined,
              title: l10n.adminFinancialKpiTotalReceivables,
              value: formatIqd(totals.netReceivables),
              secondary: l10n.adminFinancialKpiOutstanding(
                formatIqd(totals.outstandingToCollect),
              ),
              hint: l10n.adminFinancialKpiTotalReceivablesHint,
              onTap: onOpenReceivables,
            ),
          ],
        ),
      ],
    );
  }
}
