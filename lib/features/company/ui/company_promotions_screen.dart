import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../data/company_api.dart';
import '../models/company_models.dart';
import 'widgets/company_promotion_dialogs.dart';
import 'widgets/company_ui.dart';

class CompanyPromotionsScreen extends StatefulWidget {
  final CompanyApi api;
  final int companyId;

  const CompanyPromotionsScreen({
    super.key,
    required this.api,
    required this.companyId,
  });

  @override
  State<CompanyPromotionsScreen> createState() =>
      _CompanyPromotionsScreenState();
}

class _CompanyPromotionsScreenState extends State<CompanyPromotionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  Future<_CompanyPromotionsPayload>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant CompanyPromotionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _future = _load();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<_CompanyPromotionsPayload> _load() async {
    final results = await Future.wait<dynamic>([
      widget.api.branches(widget.companyId),
      widget.api.coupons(widget.companyId),
      widget.api.campaigns(widget.companyId),
    ]);
    return _CompanyPromotionsPayload(
      branches: results[0] as List<CompanyBranch>,
      coupons: results[1] as List<CompanyCoupon>,
      campaigns: results[2] as List<CompanyCampaign>,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _showCreateCoupon(List<CompanyBranch> branches) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => CompanyCreateCouponDialog(
        api: widget.api,
        companyId: widget.companyId,
        branches: branches,
      ),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  Future<void> _showCreateCampaign(List<CompanyBranch> branches) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => CompanyCreateCampaignDialog(
        api: widget.api,
        companyId: widget.companyId,
        branches: branches,
      ),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  String _discountTypeLabel(BuildContext context, String type) {
    final l10n = context.l10n;
    switch (type) {
      case 'fixed':
        return l10n.companyPromotionsDiscountFixed;
      case 'percent':
        return l10n.companyPromotionsDiscountPercent;
      default:
        return type;
    }
  }

  String _couponStatusLabel(BuildContext context, String status) {
    final normalized = status.trim().toLowerCase();
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    switch (normalized) {
      case 'active':
        return ar ? 'ساري' : 'Active';
      case 'scheduled':
        return ar ? 'مجدول' : 'Scheduled';
      case 'expired':
        return ar ? 'منتهي' : 'Expired';
      case 'inactive':
        return ar ? 'غير مفعل' : 'Inactive';
      case 'exhausted':
        return ar ? 'مستنفد' : 'Exhausted';
      default:
        return status.isEmpty ? (ar ? 'غير معروف' : 'Unknown') : status;
    }
  }

  Color _couponStatusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'active':
        return Colors.greenAccent;
      case 'scheduled':
        return Colors.orangeAccent;
      case 'expired':
        return Colors.redAccent;
      case 'inactive':
        return Colors.blueGrey;
      case 'exhausted':
        return Colors.deepOrangeAccent;
      default:
        return Colors.white70;
    }
  }

  String? _couponValidUntilText(CompanyCoupon coupon) {
    final raw = coupon.validUntil?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _campaignTypeLabel(BuildContext context, String type) {
    final l10n = context.l10n;
    switch (type) {
      case 'percentage':
        return l10n.companyPromotionsCampaignPercentage;
      case 'fixed_amount':
        return l10n.companyPromotionsCampaignFixedAmount;
      case 'buy_x_get_y':
        return l10n.companyPromotionsCampaignBuyXGetY;
      default:
        return type;
    }
  }

  String _campaignStatusLabel(BuildContext context, String status) {
    final l10n = context.l10n;
    switch (status) {
      case 'draft':
        return l10n.companyPromotionsStatusDraft;
      case 'scheduled':
        return l10n.companyPromotionsStatusScheduled;
      case 'active':
        return l10n.companyPromotionsStatusActive;
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<_CompanyPromotionsPayload>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CompanyEmptyState(
            icon: Icons.local_offer_outlined,
            title: l10n.companyPromotionsLoadFailed,
            description: '${snapshot.error}',
            action: FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.commonRetry),
            ),
          );
        }
        final payload = snapshot.data;
        if (payload == null) {
          return CompanyEmptyState(
            icon: Icons.local_offer_outlined,
            title: l10n.companyPromotionsEmptyTitle,
            description: l10n.companyPromotionsEmptyDescription,
          );
        }
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
                      title: l10n.companyPromotionsTitle,
                      subtitle: l10n.companyPromotionsSubtitle,
                      actions: [
                        OutlinedButton.icon(
                          onPressed: () => _showCreateCoupon(payload.branches),
                          icon: const Icon(Icons.confirmation_number_outlined),
                          label: Text(l10n.companyPromotionsCouponAction),
                        ),
                        FilledButton.icon(
                          onPressed: () =>
                              _showCreateCampaign(payload.branches),
                          icon: const Icon(Icons.campaign_outlined),
                          label: Text(l10n.companyPromotionsCampaignAction),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TabBar(
                      controller: _tabController,
                      tabs: [
                        Tab(text: l10n.companyPromotionsCouponsTab),
                        Tab(text: l10n.companyPromotionsCampaignsTab),
                      ],
                    ),
                    SizedBox(
                      height: 560,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          payload.coupons.isEmpty
                              ? CompanyEmptyState(
                                  icon: Icons.confirmation_number_outlined,
                                  title: l10n.companyPromotionsNoCouponsTitle,
                                  description: l10n
                                      .companyPromotionsNoCouponsDescription,
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.only(top: 16),
                                  itemCount: payload.coupons.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final coupon = payload.coupons[index];
                                    return CompanySectionCard(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            coupon.code,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
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
                                                label: _couponStatusLabel(
                                                  context,
                                                  coupon.status,
                                                ),
                                                color: _couponStatusColor(
                                                  coupon.status,
                                                ),
                                              ),
                                              CompanyStatusChip(
                                                label: _discountTypeLabel(
                                                  context,
                                                  coupon.discountType,
                                                ),
                                                color: Colors.lightBlueAccent,
                                              ),
                                              CompanyStatusChip(
                                                label:
                                                    coupon.appliesToAllBranches
                                                    ? l10n.companyPromotionsAllBranches
                                                    : l10n.companyPromotionsTargetBranchesCount(
                                                        '${coupon.targets.length}',
                                                      ),
                                                color:
                                                    Colors.greenAccent.shade400,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            l10n.companyPromotionsDiscountValueSummary(
                                              '${coupon.discountValue}',
                                            ),
                                          ),
                                          if (_couponValidUntilText(coupon) != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: Text(
                                                Localizations.localeOf(context)
                                                            .languageCode ==
                                                        'ar'
                                                    ? 'ينتهي في: ${_couponValidUntilText(coupon)}'
                                                    : 'Valid until: ${_couponValidUntilText(coupon)}',
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.72),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                          payload.campaigns.isEmpty
                              ? CompanyEmptyState(
                                  icon: Icons.campaign_outlined,
                                  title: l10n.companyPromotionsNoCampaignsTitle,
                                  description: l10n
                                      .companyPromotionsNoCampaignsDescription,
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.only(top: 16),
                                  itemCount: payload.campaigns.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final campaign = payload.campaigns[index];
                                    return CompanySectionCard(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  campaign.title,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  l10n.companyPromotionsTypeStatusSummary(
                                                    _campaignTypeLabel(
                                                      context,
                                                      campaign.offerType,
                                                    ),
                                                    _campaignStatusLabel(
                                                      context,
                                                      campaign.status,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          CompanyStatusChip(
                                            label: l10n
                                                .companyPromotionsTargetBranchesCount(
                                                  '${campaign.targets.length}',
                                                ),
                                            color: Colors.lightBlueAccent,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ],
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

class _CompanyPromotionsPayload {
  final List<CompanyBranch> branches;
  final List<CompanyCoupon> coupons;
  final List<CompanyCampaign> campaigns;

  const _CompanyPromotionsPayload({
    required this.branches,
    required this.coupons,
    required this.campaigns,
  });
}
