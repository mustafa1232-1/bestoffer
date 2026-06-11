import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../data/company_api.dart';
import '../models/company_models.dart';
import 'company_branch_detail_screen.dart';
import 'widgets/company_ui.dart';

class CompanyInventoryScreen extends StatefulWidget {
  final CompanyApi api;
  final int companyId;

  const CompanyInventoryScreen({
    super.key,
    required this.api,
    required this.companyId,
  });

  @override
  State<CompanyInventoryScreen> createState() => _CompanyInventoryScreenState();
}

class _CompanyInventoryScreenState extends State<CompanyInventoryScreen> {
  Future<CompanyInventoryOverview>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.inventoryOverview(widget.companyId);
  }

  @override
  void didUpdateWidget(covariant CompanyInventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _future = widget.api.inventoryOverview(widget.companyId);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.api.inventoryOverview(widget.companyId);
    });
    await _future;
  }

  Future<void> _openBranchInventory(CompanyBranch branch) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompanyBranchDetailScreen(
          companyId: widget.companyId,
          merchantId: branch.id,
          branchName: branch.name,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<CompanyInventoryOverview>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CompanyEmptyState(
            icon: Icons.inventory_2_outlined,
            title: l10n.companyInventoryLoadFailed,
            description: '${snapshot.error}',
            action: FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.commonRetry),
            ),
          );
        }
        final overview = snapshot.data;
        if (overview == null) {
          return CompanyEmptyState(
            icon: Icons.inventory_2_outlined,
            title: l10n.companyInventoryEmptyTitle,
            description: l10n.companyInventoryEmptyDescription,
          );
        }
        final totals = overview.totals;
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
                      title: l10n.companyInventoryTitle,
                      subtitle: l10n.companyInventorySubtitle,
                    ),
                    const SizedBox(height: 18),
                    GridView.count(
                      crossAxisCount:
                          MediaQuery.of(context).size.width >= 1100 ? 4 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.32,
                      children: [
                        CompanyMetricTile(
                          label: l10n.companyInventoryTotalBranches,
                          value: '${totals['branchesCount'] ?? 0}',
                          icon: Icons.apartment_rounded,
                        ),
                        CompanyMetricTile(
                          label: l10n.companyInventoryEnabledBranches,
                          value: '${totals['inventoryEnabledBranches'] ?? 0}',
                          icon: Icons.inventory_2_outlined,
                          color: Colors.greenAccent.shade400,
                        ),
                        CompanyMetricTile(
                          label: l10n.companyInventoryLowStockItems,
                          value: '${totals['lowStockItems'] ?? 0}',
                          icon: Icons.trending_down_rounded,
                          color: Colors.orangeAccent,
                        ),
                        CompanyMetricTile(
                          label: l10n.companyInventoryStaleBranches,
                          value: '${totals['staleBranches'] ?? 0}',
                          icon: Icons.schedule_rounded,
                          color: Theme.of(context).colorScheme.error,
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
                      title: l10n.companyInventoryBranchStatusTitle,
                      subtitle: l10n.companyInventoryBranchStatusSubtitle,
                    ),
                    const SizedBox(height: 16),
                    if (overview.branches.isEmpty)
                      CompanyEmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: l10n.companyInventoryNoBranchRecordsTitle,
                        description: l10n.companyInventoryNoBranchRecordsDescription,
                      )
                    else
                      ...overview.branches.map(
                        (branch) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _openBranchInventory(branch),
                            child: Ink(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: Colors.white.withValues(alpha: 0.04),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            branch.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              CompanyStatusChip(
                                                label: branch.inventoryEnabled
                                                    ? l10n.companyInventoryEnabledLabel
                                                    : l10n.companyInventoryManualLabel,
                                                color: branch.inventoryEnabled
                                                    ? Colors.greenAccent.shade400
                                                    : Colors.orangeAccent,
                                              ),
                                              CompanyStatusChip(
                                                label: l10n.companyInventoryOutOfStock(
                                                  '${branch.outOfStockItems}',
                                                ),
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                              ),
                                              CompanyStatusChip(
                                                label: l10n.companyInventoryLowStock(
                                                  '${branch.lowStockItems}',
                                                ),
                                                color: Colors.orangeAccent,
                                              ),
                                              CompanyStatusChip(
                                                label: branch.staleDailyCheck
                                                    ? l10n.companyInventoryStaleToday
                                                    : l10n.companyInventoryUpdatedToday,
                                                color: branch.staleDailyCheck
                                                    ? Colors.deepOrangeAccent
                                                    : Colors.lightBlueAccent,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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
