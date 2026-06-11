import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';

enum AdminFinancialPeriod { day, week, month, year, custom }

String adminFinancialPeriodCode(AdminFinancialPeriod period) {
  switch (period) {
    case AdminFinancialPeriod.day:
      return 'day';
    case AdminFinancialPeriod.week:
      return 'week';
    case AdminFinancialPeriod.month:
      return 'month';
    case AdminFinancialPeriod.year:
      return 'year';
    case AdminFinancialPeriod.custom:
      return 'custom';
  }
}

class AdminFinancialFilterBar extends StatelessWidget {
  final AdminFinancialPeriod period;
  final String customRangeLabel;
  final ValueChanged<AdminFinancialPeriod> onPeriodChanged;
  final TextEditingController? searchController;
  final VoidCallback? onSearch;
  final VoidCallback? onPickCustomRange;

  const AdminFinancialFilterBar({
    super.key,
    required this.period,
    required this.customRangeLabel,
    required this.onPeriodChanged,
    this.searchController,
    this.onSearch,
    this.onPickCustomRange,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chips = <({AdminFinancialPeriod period, String label})>[
      (period: AdminFinancialPeriod.day, label: l10n.adminFinancialFilterToday),
      (period: AdminFinancialPeriod.week, label: l10n.adminFinancialFilterWeek),
      (
        period: AdminFinancialPeriod.month,
        label: l10n.adminFinancialFilterMonth,
      ),
      (period: AdminFinancialPeriod.year, label: l10n.adminFinancialFilterYear),
      (
        period: AdminFinancialPeriod.custom,
        label: l10n.adminFinancialFilterCustom,
      ),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in chips)
                  ChoiceChip(
                    selected: period == chip.period,
                    onSelected: (_) => onPeriodChanged(chip.period),
                    label: Text(chip.label),
                  ),
                if (period == AdminFinancialPeriod.custom)
                  OutlinedButton.icon(
                    onPressed: onPickCustomRange,
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text(customRangeLabel),
                  ),
              ],
            ),
            if (searchController != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      textDirection: Directionality.of(context),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l10n.adminFinancialFilterSearchMerchant,
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => onSearch?.call(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: onSearch,
                    child: Text(l10n.commonSearch),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
