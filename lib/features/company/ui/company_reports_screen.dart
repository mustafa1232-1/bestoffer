import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../data/company_api.dart';
import '../models/company_models.dart';
import 'widgets/company_ui.dart';

class CompanyReportsScreen extends StatefulWidget {
  final CompanyApi api;
  final int companyId;

  const CompanyReportsScreen({
    super.key,
    required this.api,
    required this.companyId,
  });

  @override
  State<CompanyReportsScreen> createState() => _CompanyReportsScreenState();
}

class _CompanyReportsScreenState extends State<CompanyReportsScreen> {
  Future<List<CompanyBranch>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.branches(widget.companyId);
  }

  @override
  void didUpdateWidget(covariant CompanyReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _future = widget.api.branches(widget.companyId);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.api.branches(widget.companyId);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<List<CompanyBranch>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CompanyEmptyState(
            icon: Icons.error_outline_rounded,
            title: l10n.companyReportsLoadFailed,
            description: '${snapshot.error}',
            action: FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.commonRetry),
            ),
          );
        }
        final branches = snapshot.data ?? const <CompanyBranch>[];
        if (branches.isEmpty) {
          return CompanyEmptyState(
            icon: Icons.bar_chart_rounded,
            title: l10n.companyReportsEmptyTitle,
            description: l10n.companyReportsEmptyDescription,
          );
        }
        final sortedBySales = [...branches]
          ..sort((a, b) => b.grossSales.compareTo(a.grossSales));
        final sortedByOutstanding = [...branches]
          ..sort((a, b) => b.outstandingAmount.compareTo(a.outstandingAmount));
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CompanySectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanySectionHeader(
                      title: l10n.companyReportsInsightsTitle,
                      subtitle: l10n.companyReportsInsightsSubtitle,
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        CompanyMetricTile(
                          label: l10n.companyReportsBestSalesBranch,
                          value: sortedBySales.first.name,
                          icon: Icons.emoji_events_outlined,
                          color: Colors.greenAccent.shade400,
                          subtitle: formatIqd(sortedBySales.first.grossSales),
                        ),
                        CompanyMetricTile(
                          label: l10n.companyReportsHighestOutstanding,
                          value: sortedByOutstanding.first.name,
                          icon: Icons.warning_amber_rounded,
                          color: Colors.orangeAccent,
                          subtitle:
                              formatIqd(sortedByOutstanding.first.outstandingAmount),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CompanySectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanySectionHeader(
                      title: l10n.companyReportsComparisonTitle,
                      subtitle: l10n.companyReportsComparisonSubtitle,
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          DataColumn(label: Text(l10n.companyReportsTableBranch)),
                          DataColumn(label: Text(l10n.companyReportsTableOrders)),
                          DataColumn(label: Text(l10n.companyReportsTableSales)),
                          DataColumn(
                            label: Text(l10n.companyReportsTableOutstanding),
                          ),
                          DataColumn(
                            label: Text(l10n.companyReportsTableCollected),
                          ),
                          DataColumn(
                            label: Text(l10n.companyReportsTableInventory),
                          ),
                        ],
                        rows: branches
                            .map(
                              (branch) => DataRow(
                                cells: [
                                  DataCell(Text(branch.name)),
                                  DataCell(Text('${branch.totalOrders}')),
                                  DataCell(Text(formatIqd(branch.grossSales))),
                                  DataCell(
                                    Text(formatIqd(branch.outstandingAmount)),
                                  ),
                                  DataCell(
                                    Text(formatIqd(branch.totalCollected)),
                                  ),
                                  DataCell(
                                    Text(
                                      '${branch.outOfStockItems}/${branch.trackedItems}',
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
