import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../company_portal_text.dart';
import '../data/company_api.dart';
import '../models/company_models.dart';
import 'widgets/company_ui.dart';

class CompanyDashboardScreen extends StatefulWidget {
  final CompanyApi api;
  final int companyId;
  final VoidCallback onOpenBranches;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenPromotions;
  final VoidCallback onOpenUsers;
  final VoidCallback onOpenSettings;

  const CompanyDashboardScreen({
    super.key,
    required this.api,
    required this.companyId,
    required this.onOpenBranches,
    required this.onOpenInventory,
    required this.onOpenPromotions,
    required this.onOpenUsers,
    required this.onOpenSettings,
  });

  @override
  State<CompanyDashboardScreen> createState() => _CompanyDashboardScreenState();
}

class _CompanyDashboardScreenState extends State<CompanyDashboardScreen> {
  Future<CompanyHomeData>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.dashboard(widget.companyId);
  }

  @override
  void didUpdateWidget(covariant CompanyDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _future = widget.api.dashboard(widget.companyId);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.api.dashboard(widget.companyId);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<CompanyHomeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CompanyEmptyState(
            icon: Icons.error_outline_rounded,
            title: l10n.companyDashboardLoadFailed,
            description: '${snapshot.error}',
            action: FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.commonRetry),
            ),
          );
        }
        final home = snapshot.data;
        if (home == null) {
          return CompanyEmptyState(
            icon: Icons.apartment_outlined,
            title: l10n.companyDashboardEmptyTitle,
            description: l10n.companyDashboardEmptyDescription,
          );
        }
        final dashboard = home.dashboard;
        final company = home.company;
        final policy = home.defaultPolicy;
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
                      title: company.brandName?.isNotEmpty == true
                          ? company.brandName!
                          : company.name,
                      subtitle: l10n.companyDashboardWorkspaceSubtitle,
                      actions: [
                        OutlinedButton.icon(
                          onPressed: widget.onOpenBranches,
                          icon: const Icon(Icons.store_mall_directory_rounded),
                          label: Text(l10n.companyNavBranches),
                        ),
                        FilledButton.icon(
                          onPressed: widget.onOpenSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(l10n.companyNavSettings),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (company.code.isNotEmpty)
                          CompanyStatusChip(
                            label: company.code.toUpperCase(),
                          ),
                        CompanyStatusChip(
                          label: companyStatusLabel(context, company.status),
                          color: company.status == 'active'
                              ? Colors.greenAccent.shade400
                              : Colors.orangeAccent,
                        ),
                        if (policy != null)
                          CompanyStatusChip(
                            label:
                                '${l10n.companyDashboardInventoryPolicy}: ${companyInventoryModeLabel(context, policy.inventoryUpdateMode)}',
                            color: Colors.lightBlueAccent,
                          ),
                        if (policy != null)
                          CompanyStatusChip(
                            label: policy.inventoryEnabled
                                ? l10n.companyDashboardInventoryEnabled
                                : l10n.companyDashboardInventoryDisabled,
                            color: policy.inventoryEnabled
                                ? Colors.greenAccent.shade400
                                : Colors.orangeAccent,
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: 280,
                          child: CompanyInfoTile(
                            label: l10n.companyDashboardCompanyName,
                            value: company.name,
                            icon: Icons.apartment_rounded,
                          ),
                        ),
                        if (company.legalName?.isNotEmpty == true)
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardLegalName,
                              value: company.legalName!,
                              icon: Icons.gavel_rounded,
                            ),
                          ),
                        if (company.primaryContactName?.isNotEmpty == true)
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardPrimaryContact,
                              value: company.primaryContactName!,
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                        if (company.contactPhone?.isNotEmpty == true)
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardContactPhone,
                              value: company.contactPhone!,
                              icon: Icons.phone_outlined,
                            ),
                          ),
                        if (company.supportPhone?.isNotEmpty == true)
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardSupportPhone,
                              value: company.supportPhone!,
                              icon: Icons.support_agent_rounded,
                            ),
                          ),
                        if (company.contactEmail?.isNotEmpty == true)
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardEmail,
                              value: company.contactEmail!,
                              icon: Icons.alternate_email_rounded,
                            ),
                          ),
                        if (company.headquartersAddress?.isNotEmpty == true)
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardHeadquarters,
                              value: company.headquartersAddress!,
                              icon: Icons.location_on_outlined,
                            ),
                          ),
                        if (company.registrationNumber?.isNotEmpty == true)
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardRegistrationNumber,
                              value: company.registrationNumber!,
                              icon: Icons.badge_outlined,
                            ),
                          ),
                        SizedBox(
                          width: 280,
                          child: CompanyInfoTile(
                            label: l10n.companyDashboardDefaultPolicy,
                            value: policy == null
                                ? l10n.companyDashboardNoDefaultPolicy
                                : l10n.companyDashboardPolicySummary(
                                    (policy.commissionRate ?? 0).toString(),
                                    policy.settlementCycle ?? 'weekly',
                                  ),
                            icon: Icons.account_balance_outlined,
                          ),
                        ),
                        if (company.summary?.isNotEmpty == true)
                          SizedBox(
                            width: 580,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardSummary,
                              value: company.summary!,
                              icon: Icons.notes_rounded,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width >= 1200 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.32,
                children: [
                  CompanyMetricTile(
                    label: l10n.companyNavBranches,
                    value: '${dashboard.branchesCount}',
                    icon: Icons.apartment_rounded,
                    onTap: widget.onOpenBranches,
                  ),
                  CompanyMetricTile(
                    label: l10n.companyDashboardTotalOrders,
                    value: '${dashboard.totalOrders}',
                    icon: Icons.receipt_long_rounded,
                    onTap: widget.onOpenBranches,
                  ),
                  CompanyMetricTile(
                    label: l10n.companyDashboardActiveOrders,
                    value: '${dashboard.activeOrders}',
                    icon: Icons.local_shipping_outlined,
                    color: Colors.lightBlueAccent,
                    onTap: widget.onOpenBranches,
                  ),
                  CompanyMetricTile(
                    label: l10n.companyDashboardCompleted,
                    value: '${dashboard.completedOrders}',
                    icon: Icons.task_alt_rounded,
                    color: Colors.greenAccent.shade400,
                    onTap: widget.onOpenBranches,
                  ),
                  CompanyMetricTile(
                    label: l10n.companyDashboardCancelled,
                    value: '${dashboard.cancelledOrders}',
                    icon: Icons.cancel_outlined,
                    color: Theme.of(context).colorScheme.error,
                    onTap: widget.onOpenBranches,
                  ),
                  CompanyMetricTile(
                    label: l10n.companyDashboardGrossSales,
                    value: formatIqd(dashboard.totalSales),
                    icon: Icons.payments_outlined,
                    color: Colors.greenAccent.shade400,
                    onTap: widget.onOpenBranches,
                  ),
                  CompanyMetricTile(
                    label: l10n.companyDashboardServiceFees,
                    value: formatIqd(dashboard.totalServiceFees),
                    icon: Icons.percent_rounded,
                    color: Colors.orangeAccent,
                    onTap: widget.onOpenSettings,
                  ),
                  CompanyMetricTile(
                    label: l10n.companyDashboardOutstanding,
                    value: formatIqd(dashboard.totalOutstanding),
                    icon: Icons.account_balance_wallet_outlined,
                    color: Colors.orangeAccent,
                    onTap: widget.onOpenSettings,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CompanySectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanySectionHeader(
                      title: l10n.companyDashboardQuickActions,
                      subtitle: l10n.companyDashboardQuickActionsDescription,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: widget.onOpenBranches,
                          icon: const Icon(Icons.storefront_outlined),
                          label: Text(l10n.companyDashboardOpenBranches),
                        ),
                        FilledButton.icon(
                          onPressed: widget.onOpenInventory,
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: Text(l10n.companyDashboardInventoryOverview),
                        ),
                        FilledButton.icon(
                          onPressed: widget.onOpenPromotions,
                          icon: const Icon(Icons.local_offer_outlined),
                          label: Text(l10n.companyDashboardPromotions),
                        ),
                        FilledButton.icon(
                          onPressed: widget.onOpenUsers,
                          icon: const Icon(Icons.groups_outlined),
                          label: Text(l10n.companyDashboardUsers),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CompanySectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CompanySectionHeader(
                            title: l10n.companyDashboardTopBranch,
                            subtitle: l10n.companyDashboardTopBranchDescription,
                          ),
                          const SizedBox(height: 14),
                          _BranchHighlightCard(data: dashboard.bestBranch),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: CompanySectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CompanySectionHeader(
                            title: l10n.companyDashboardNeedsAttention,
                            subtitle: l10n.companyDashboardNeedsAttentionDescription,
                          ),
                          const SizedBox(height: 14),
                          _BranchHighlightCard(data: dashboard.weakestBranch),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BranchHighlightCard extends StatelessWidget {
  final Map<String, dynamic>? data;

  const _BranchHighlightCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (data == null || data!.isEmpty) {
      return CompanyEmptyState(
        icon: Icons.analytics_outlined,
        title: l10n.companyDashboardNoBranchInsight,
        description: l10n.companyDashboardNoBranchInsightDescription,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${data!['name'] ?? l10n.companyDashboardBranchFallback}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              CompanyStatusChip(
                label: l10n.companyDashboardBranchOrders(
                  '${data!['totalOrders'] ?? data!['total_orders'] ?? 0}',
                ),
                color: Colors.lightBlueAccent,
              ),
              CompanyStatusChip(
                label: formatIqd(
                  (data!['grossSales'] ?? data!['gross_sales'] ?? 0) as num,
                ),
                color: Colors.greenAccent.shade400,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
