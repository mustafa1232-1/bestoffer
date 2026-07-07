import 'package:flutter/material.dart';

import '../../../../core/utils/currency.dart';
import '../../models/owner_merchant_model.dart';
import '../../state/owner_controller.dart';
import '../../../orders/models/order_model.dart';

class OwnerDashboardOverviewPanel extends StatelessWidget {
  final OwnerState state;
  final bool saving;
  final Future<void> Function({required String period, required String title})
  onOpenPeriodReport;
  final VoidCallback onOpenCurrentOrders;
  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenAddProduct;
  final VoidCallback onOpenKpis;
  final VoidCallback onOpenReceivables;
  final VoidCallback onOpenCouriers;
  final VoidCallback onOpenHr;
  final VoidCallback onOpenPrinterSettings;
  final Future<void> Function() onRequestSettlement;

  const OwnerDashboardOverviewPanel({
    super.key,
    required this.state,
    required this.saving,
    required this.onOpenPeriodReport,
    required this.onOpenCurrentOrders,
    required this.onOpenCatalog,
    required this.onOpenAddProduct,
    required this.onOpenKpis,
    required this.onOpenReceivables,
    required this.onOpenCouriers,
    required this.onOpenHr,
    required this.onOpenPrinterSettings,
    required this.onRequestSettlement,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = OwnerDashboardMetrics.fromState(state);
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.98, end: 1),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Opacity(opacity: scale, child: child),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OwnerHeroPanel(
            metrics: metrics,
            onOpenKpis: onOpenKpis,
            onOpenReceivables: onOpenReceivables,
            onOpenPeriodReport: onOpenPeriodReport,
            onRequestSettlement: onRequestSettlement,
            saving: saving,
          ),
          const SizedBox(height: 14),
          _PanelSectionCard(
            title: 'أهم الأرقام',
            subtitle: 'لقطة سريعة من الأداء الفعلي للمحل',
            child: _MetricsGrid(metrics: metrics),
          ),
          const SizedBox(height: 14),
          _PanelSectionCard(
            title: 'اختصارات تنفيذية',
            subtitle: 'انتقل مباشرة إلى أكثر المهام استخدامًا',
            child: _QuickActionsGrid(
              onOpenCurrentOrders: onOpenCurrentOrders,
              onOpenCatalog: onOpenCatalog,
              onOpenAddProduct: onOpenAddProduct,
              onOpenKpis: onOpenKpis,
              onOpenReceivables: onOpenReceivables,
              onOpenCouriers: onOpenCouriers,
              onOpenHr: onOpenHr,
              onOpenPrinterSettings: onOpenPrinterSettings,
            ),
          ),
          const SizedBox(height: 14),
          _PanelSectionCard(
            title: 'تقارير الفترات',
            subtitle: 'اضغط على أي فترة لفتح التفاصيل والطباعة وExcel',
            child: _PeriodGrid(onOpenPeriodReport: onOpenPeriodReport),
          ),
          const SizedBox(height: 14),
          _PanelSectionCard(
            title: 'اتجاه الحركة',
            subtitle: 'مقارنة مرئية بين اليوم والشهر والسنة والإجمالي',
            child: _TrendMiniChart(points: metrics.trendPoints),
          ),
          const SizedBox(height: 14),
          _PanelSectionCard(
            title: 'أفضل المنتجات',
            subtitle: 'حسب الكمية المباعة والعائد',
            child: _RankedRows(
              rows: metrics.topProducts,
              emptyText: 'لا توجد منتجات مباعة حتى الآن',
              valueLabelBuilder: (row) => formatIqd(row.grossAmount),
            ),
          ),
          const SizedBox(height: 14),
          _PanelSectionCard(
            title: 'أفضل التصنيفات',
            subtitle: 'أعلى التصنيفات أداءً خلال الفترة الحالية',
            child: _RankedRows(
              rows: metrics.topCategories,
              emptyText: 'لا توجد تصنيفات مباعة حتى الآن',
              valueLabelBuilder: (row) => formatIqd(row.grossAmount),
            ),
          ),
          const SizedBox(height: 14),
          _PanelSectionCard(
            title: 'المستحقات',
            subtitle: 'المرئي الآن من رصيدك المستحق وجدولة السداد',
            child: _ReceivablesSummaryCard(
              metrics: metrics,
              saving: saving,
              onRequestSettlement: onRequestSettlement,
            ),
          ),
        ],
      ),
    );
  }
}

class OwnerDashboardMetrics {
  final OwnerMerchantModel? merchant;
  final String merchantTypeLabel;
  final String merchantStatusLabel;
  final String? tagline;
  final double totalSales;
  final int totalOrders;
  final int completedOrders;
  final int cancelledOrders;
  final int activeOrders;
  final double avgOrderValue;
  final double outstandingAmount;
  final int outstandingOrdersCount;
  final int todayOrders;
  final int monthOrders;
  final int yearOrders;
  final int totalTrendOrders;
  final List<OwnerTrendPoint> trendPoints;
  final List<OwnerRankRow> topProducts;
  final List<OwnerRankRow> topCategories;

  const OwnerDashboardMetrics({
    required this.merchant,
    required this.merchantTypeLabel,
    required this.merchantStatusLabel,
    required this.tagline,
    required this.totalSales,
    required this.totalOrders,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.activeOrders,
    required this.avgOrderValue,
    required this.outstandingAmount,
    required this.outstandingOrdersCount,
    required this.todayOrders,
    required this.monthOrders,
    required this.yearOrders,
    required this.totalTrendOrders,
    required this.trendPoints,
    required this.topProducts,
    required this.topCategories,
  });

  factory OwnerDashboardMetrics.fromState(OwnerState state) {
    final merchant = state.merchant;
    final dashboardKpis = _mapOrNull(state.merchantDashboardV2['kpis']);
    final analyticsDay = _periodFromRaw(state.analytics['day']);
    final analyticsMonth = _periodFromRaw(state.analytics['month']);
    final analyticsYear = _periodFromRaw(state.analytics['year']);
    final outstandingSource = _mapOrNull(state.settlementSummary) ?? const {};
    final topProducts = state.merchantTopProductsV2
        .map(OwnerRankRow.fromProductJson)
        .where((row) => row.label.isNotEmpty)
        .toList(growable: false);
    final topCategories = state.merchantTopCategoriesV2
        .map(OwnerRankRow.fromCategoryJson)
        .where((row) => row.label.isNotEmpty)
        .toList(growable: false);

    final totalOrders = _intValue(
      dashboardKpis?['totalOrders'] ??
          dashboardKpis?['total_orders'] ??
          analyticsYear.ordersCount,
    );
    final totalSales = _doubleValue(
      dashboardKpis?['grossSales'] ??
          dashboardKpis?['gross_sales'] ??
          dashboardKpis?['totalSales'] ??
          dashboardKpis?['total_sales'],
    );
    final completedOrders = _intValue(
      dashboardKpis?['completedOrders'] ??
          dashboardKpis?['completed_orders'] ??
          analyticsYear.ordersCount,
    );
    final cancelledOrders = _intValue(
      dashboardKpis?['cancelledOrders'] ??
          dashboardKpis?['cancelled_orders'] ??
          0,
    );
    final activeOrders = _intValue(
      dashboardKpis?['activeOrders'] ??
          dashboardKpis?['active_orders'] ??
          analyticsDay.ordersCount,
    );
    final avgOrderValue = _doubleValue(
      dashboardKpis?['avgOrderValue'] ?? dashboardKpis?['avg_order_value'] ?? 0,
    );
    final outstandingAmount = _doubleValue(
      outstandingSource['outstandingAmount'] ??
          outstandingSource['outstanding_amount'] ??
          0,
    );
    final outstandingOrdersCount = _intValue(
      outstandingSource['ordersCount'] ??
          outstandingSource['orders_count'] ??
          0,
    );
    final todayOrders = analyticsDay.ordersCount;
    final monthOrders = analyticsMonth.ordersCount;
    final yearOrders = analyticsYear.ordersCount;
    final totalTrendOrders = totalOrders > 0 ? totalOrders : yearOrders;
    final trendPoints = [
      OwnerTrendPoint('اليوم', todayOrders),
      OwnerTrendPoint('الشهر', monthOrders),
      OwnerTrendPoint('السنة', yearOrders),
      OwnerTrendPoint('الإجمالي', totalTrendOrders),
    ];

    return OwnerDashboardMetrics(
      merchant: merchant,
      merchantTypeLabel: _merchantTypeLabel(merchant),
      merchantStatusLabel: merchant?.isOpen == true ? 'مفتوح' : 'مغلق',
      tagline: merchant?.tagline?.trim().isNotEmpty == true
          ? merchant!.tagline!.trim()
          : merchant?.description?.trim(),
      totalSales: totalSales,
      totalOrders: totalOrders,
      completedOrders: completedOrders,
      cancelledOrders: cancelledOrders,
      activeOrders: activeOrders,
      avgOrderValue: avgOrderValue,
      outstandingAmount: outstandingAmount,
      outstandingOrdersCount: outstandingOrdersCount,
      todayOrders: todayOrders,
      monthOrders: monthOrders,
      yearOrders: yearOrders,
      totalTrendOrders: totalTrendOrders,
      trendPoints: trendPoints,
      topProducts: topProducts,
      topCategories: topCategories,
    );
  }
}

class OwnerPeriodReportSummary {
  final int ordersCount;
  final int completedOrders;
  final int cancelledOrders;
  final int activeOrders;
  final double subtotal;
  final double serviceFee;
  final double deliveryFee;
  final double couponDiscount;
  final double grossSales;
  final double avgOrderValue;

  const OwnerPeriodReportSummary({
    required this.ordersCount,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.activeOrders,
    required this.subtotal,
    required this.serviceFee,
    required this.deliveryFee,
    required this.couponDiscount,
    required this.grossSales,
    required this.avgOrderValue,
  });

  factory OwnerPeriodReportSummary.fromOrders(List<OrderModel> orders) {
    var subtotal = 0.0;
    var serviceFee = 0.0;
    var deliveryFee = 0.0;
    var couponDiscount = 0.0;
    var grossSales = 0.0;
    var completedOrders = 0;
    var cancelledOrders = 0;
    var activeOrders = 0;

    for (final order in orders) {
      subtotal += order.subtotal;
      serviceFee += order.serviceFee;
      deliveryFee += order.deliveryFee;
      couponDiscount += order.couponDiscountTotal;
      grossSales += order.totalAmount;

      final status = order.status.toLowerCase();
      if (_completedStatuses.contains(status)) {
        completedOrders += 1;
      } else if (_cancelledStatuses.contains(status)) {
        cancelledOrders += 1;
      } else if (_activeStatuses.contains(status)) {
        activeOrders += 1;
      }
    }

    final count = orders.length;
    return OwnerPeriodReportSummary(
      ordersCount: count,
      completedOrders: completedOrders,
      cancelledOrders: cancelledOrders,
      activeOrders: activeOrders,
      subtotal: subtotal,
      serviceFee: serviceFee,
      deliveryFee: deliveryFee,
      couponDiscount: couponDiscount,
      grossSales: grossSales,
      avgOrderValue: count == 0 ? 0 : grossSales / count,
    );
  }

  List<String> get summaryLines => [
    'عدد الطلبات: $ordersCount',
    'إجمالي المبيعات: ${formatIqd(grossSales)}',
    'المجموع الفرعي: ${formatIqd(subtotal)}',
    'رسوم الخدمة المخزنة: ${formatIqd(serviceFee)}',
    'أجور التوصيل: ${formatIqd(deliveryFee)}',
    'خصم الكوبون: ${formatIqd(couponDiscount)}',
    'متوسط الطلب: ${formatIqd(avgOrderValue)}',
    'الطلبات المكتملة: $completedOrders',
    'الطلبات الملغاة: $cancelledOrders',
    'الطلبات النشطة: $activeOrders',
  ];
}

class OwnerTrendPoint {
  final String label;
  final int value;

  const OwnerTrendPoint(this.label, this.value);
}

class OwnerRankRow {
  final String label;
  final int quantity;
  final double grossAmount;

  const OwnerRankRow({
    required this.label,
    required this.quantity,
    required this.grossAmount,
  });

  factory OwnerRankRow.fromProductJson(Map<String, dynamic> raw) {
    return OwnerRankRow(
      label: _stringValue(
        raw['product_name'] ?? raw['productName'] ?? raw['name'],
      ),
      quantity: _intValue(raw['qty_sold'] ?? raw['quantity'] ?? raw['qtySold']),
      grossAmount: _doubleValue(
        raw['gross_amount'] ?? raw['grossAmount'] ?? raw['line_total'],
      ),
    );
  }

  factory OwnerRankRow.fromCategoryJson(Map<String, dynamic> raw) {
    return OwnerRankRow(
      label: _stringValue(
        raw['category_name'] ?? raw['categoryName'] ?? raw['name'],
      ),
      quantity: _intValue(raw['qty_sold'] ?? raw['quantity'] ?? raw['qtySold']),
      grossAmount: _doubleValue(
        raw['gross_amount'] ?? raw['grossAmount'] ?? raw['line_total'],
      ),
    );
  }
}

class _OwnerHeroPanel extends StatelessWidget {
  final OwnerDashboardMetrics metrics;
  final VoidCallback onOpenKpis;
  final VoidCallback onOpenReceivables;
  final Future<void> Function({required String period, required String title})
  onOpenPeriodReport;
  final Future<void> Function() onRequestSettlement;
  final bool saving;

  const _OwnerHeroPanel({
    required this.metrics,
    required this.onOpenKpis,
    required this.onOpenReceivables,
    required this.onOpenPeriodReport,
    required this.onRequestSettlement,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            scheme.primary.withValues(alpha: 0.26),
            scheme.secondary.withValues(alpha: 0.18),
            scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metrics.merchant?.name ?? 'لوحة صاحب المتجر',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      metrics.tagline?.isNotEmpty == true
                          ? metrics.tagline!
                          : 'مراقبة المبيعات، التقارير، المستحقات، وأداء التشغيل من مكان واحد.',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.82),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Badge(
                    icon: Icons.storefront_outlined,
                    label: metrics.merchantTypeLabel,
                    accent: scheme.primary,
                  ),
                  const SizedBox(height: 8),
                  _Badge(
                    icon: metrics.merchant?.isOpen == true
                        ? Icons.check_circle_outline
                        : Icons.pause_circle_outline,
                    label: metrics.merchantStatusLabel,
                    accent: metrics.merchant?.isOpen == true
                        ? const Color(0xFF2AA876)
                        : const Color(0xFFD05A5A),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth > 900
                  ? (constraints.maxWidth - 24) / 4
                  : constraints.maxWidth > 600
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _HeroStatCard(
                      icon: Icons.point_of_sale_outlined,
                      label: 'إجمالي المبيعات',
                      value: formatIqd(metrics.totalSales),
                      accent: const Color(0xFF2AA876),
                      onTap: () => onOpenPeriodReport(
                        period: 'all',
                        title: 'الإجمالي',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _HeroStatCard(
                      icon: Icons.receipt_long_outlined,
                      label: 'الطلبات الحالية',
                      value: '${metrics.activeOrders}',
                      accent: const Color(0xFF3E7BFA),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _HeroStatCard(
                      icon: Icons.insights_outlined,
                      label: 'متوسط الطلب',
                      value: formatIqd(metrics.avgOrderValue),
                      accent: const Color(0xFFE97A2E),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _HeroStatCard(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'المستحقات الحالية',
                      value: formatIqd(metrics.outstandingAmount),
                      accent: const Color(0xFF9C4DCC),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _TrendMiniChart(points: metrics.trendPoints),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onOpenKpis,
                icon: const Icon(Icons.insert_chart_outlined_rounded),
                label: const Text('KPI'),
              ),
              FilledButton.tonalIcon(
                onPressed: onOpenReceivables,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('المستحقات'),
              ),
              OutlinedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        await onRequestSettlement();
                      },
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.request_page_outlined),
                label: const Text('طلب تسوية'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final OwnerDashboardMetrics metrics;

  const _MetricsGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth > 900
            ? (constraints.maxWidth - 36) / 4
            : constraints.maxWidth > 600
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                icon: Icons.local_fire_department_outlined,
                label: 'الطلبات المكتملة',
                value: '${metrics.completedOrders}',
                accent: const Color(0xFF2AA876),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                icon: Icons.block_outlined,
                label: 'الطلبات الملغاة',
                value: '${metrics.cancelledOrders}',
                accent: const Color(0xFFD05A5A),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                icon: Icons.today_outlined,
                label: 'طلبات اليوم',
                value: '${metrics.todayOrders}',
                accent: const Color(0xFF3E7BFA),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                icon: Icons.schedule_outlined,
                label: 'طلبات المستحقات',
                value: '${metrics.outstandingOrdersCount}',
                accent: const Color(0xFFE97A2E),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  final VoidCallback onOpenCurrentOrders;
  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenAddProduct;
  final VoidCallback onOpenKpis;
  final VoidCallback onOpenReceivables;
  final VoidCallback onOpenCouriers;
  final VoidCallback onOpenHr;
  final VoidCallback onOpenPrinterSettings;

  const _QuickActionsGrid({
    required this.onOpenCurrentOrders,
    required this.onOpenCatalog,
    required this.onOpenAddProduct,
    required this.onOpenKpis,
    required this.onOpenReceivables,
    required this.onOpenCouriers,
    required this.onOpenHr,
    required this.onOpenPrinterSettings,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(
        icon: Icons.receipt_long_outlined,
        label: 'الطلبات',
        onTap: onOpenCurrentOrders,
      ),
      _QuickAction(
        icon: Icons.inventory_2_outlined,
        label: 'المنتجات',
        onTap: onOpenCatalog,
      ),
      _QuickAction(
        icon: Icons.add_box_outlined,
        label: 'إضافة منتج',
        onTap: onOpenAddProduct,
      ),
      _QuickAction(
        icon: Icons.insert_chart_outlined_rounded,
        label: 'KPI',
        onTap: onOpenKpis,
      ),
      _QuickAction(
        icon: Icons.account_balance_wallet_outlined,
        label: 'المستحقات',
        onTap: onOpenReceivables,
      ),
      _QuickAction(
        icon: Icons.delivery_dining_outlined,
        label: 'السائقون',
        onTap: onOpenCouriers,
      ),
      _QuickAction(
        icon: Icons.badge_outlined,
        label: 'الموظفون',
        onTap: onOpenHr,
      ),
      _QuickAction(
        icon: Icons.print_outlined,
        label: 'الطباعة',
        onTap: onOpenPrinterSettings,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth > 900
            ? (constraints.maxWidth - 28) / 4
            : constraints.maxWidth > 600
            ? (constraints.maxWidth - 14) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: actions
              .map(
                (action) => SizedBox(
                  width: cardWidth,
                  child: _QuickActionTile(action: action),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _PeriodGrid extends StatelessWidget {
  final Future<void> Function({required String period, required String title})
  onOpenPeriodReport;

  const _PeriodGrid({required this.onOpenPeriodReport});

  @override
  Widget build(BuildContext context) {
    final periods = <_PeriodSpec>[
      const _PeriodSpec(
        period: 'day',
        title: 'تفاصيل اليوم',
        subtitle: 'طباعة / PDF / Excel',
        icon: Icons.wb_sunny_outlined,
        accent: Color(0xFF3E7BFA),
      ),
      const _PeriodSpec(
        period: 'week',
        title: 'تفاصيل الأسبوع',
        subtitle: 'طباعة / PDF / Excel',
        icon: Icons.view_week_outlined,
        accent: Color(0xFF2AA876),
      ),
      const _PeriodSpec(
        period: 'month',
        title: 'تفاصيل الشهر',
        subtitle: 'طباعة / PDF / Excel',
        icon: Icons.calendar_month_outlined,
        accent: Color(0xFFE97A2E),
      ),
      const _PeriodSpec(
        period: 'all',
        title: 'الإجمالي',
        subtitle: 'طباعة / PDF / Excel',
        icon: Icons.all_inclusive_rounded,
        accent: Color(0xFF9C4DCC),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth > 900
            ? (constraints.maxWidth - 36) / 4
            : constraints.maxWidth > 600
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: periods
              .map(
                (period) => SizedBox(
                  width: cardWidth,
                  child: _PeriodCard(
                    spec: period,
                    onTap: () => onOpenPeriodReport(
                      period: period.period,
                      title: period.title,
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _TrendMiniChart extends StatelessWidget {
  final List<OwnerTrendPoint> points;

  const _TrendMiniChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final maxValue = points.fold<int>(0, (max, point) {
      return point.value > max ? point.value : max;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'اتجاه الطلبات',
              textDirection: TextDirection.rtl,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              'آخر تحديث مباشر',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: points
                .map(
                  (point) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                height: maxValue <= 0
                                    ? 10
                                    : ((point.value / maxValue) * 84)
                                          .clamp(10, 84)
                                          .toDouble(),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Theme.of(context).colorScheme.primary,
                                      Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            point.label,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            point.value.toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _RankedRows extends StatelessWidget {
  final List<OwnerRankRow> rows;
  final String emptyText;
  final String Function(OwnerRankRow row) valueLabelBuilder;

  const _RankedRows({
    required this.rows,
    required this.emptyText,
    required this.valueLabelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          emptyText,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
        ),
      );
    }

    final maxQuantity = rows.fold<int>(0, (max, row) {
      return row.quantity > max ? row.quantity : max;
    });

    return Column(
      children: rows
          .take(5)
          .map((row) {
            final widthFactor = maxQuantity <= 0
                ? 0.0
                : row.quantity / maxQuantity;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.label,
                          textDirection: TextDirection.rtl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${row.quantity} • ${valueLabelBuilder(row)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: widthFactor.clamp(0, 1).toDouble(),
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _ReceivablesSummaryCard extends StatelessWidget {
  final OwnerDashboardMetrics metrics;
  final bool saving;
  final Future<void> Function() onRequestSettlement;

  const _ReceivablesSummaryCard({
    required this.metrics,
    required this.saving,
    required this.onRequestSettlement,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReceivableRow(
          label: 'إجمالي المبيعات',
          value: formatIqd(metrics.totalSales),
        ),
        _ReceivableRow(
          label: 'المستحقات الحالية',
          value: formatIqd(metrics.outstandingAmount),
        ),
        _ReceivableRow(
          label: 'طلبات المستحقات',
          value: '${metrics.outstandingOrdersCount}',
        ),
        const SizedBox(height: 6),
        ElevatedButton.icon(
          onPressed: saving || metrics.outstandingAmount <= 0
              ? null
              : () async {
                  await onRequestSettlement();
                },
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.request_page_outlined),
          label: const Text('طلب تسوية جديدة'),
        ),
      ],
    );
  }
}

class _ReceivableRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReceivableRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _PanelSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Directionality(textDirection: TextDirection.rtl, child: child),
        ],
      ),
    );
  }
}

class _HeroStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback? onTap;

  const _HeroStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: accent),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, size: 18, color: accent),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _Badge({required this.icon, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.16),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: accent.withValues(alpha: 0.16),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction action;

  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: scheme.primary.withValues(alpha: 0.16),
                ),
                child: Icon(action.icon, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  action.label,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(Icons.chevron_left_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodSpec {
  final String period;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _PeriodSpec({
    required this.period,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });
}

class _PeriodCard extends StatelessWidget {
  final _PeriodSpec spec;
  final VoidCallback onTap;

  const _PeriodCard({required this.spec, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                spec.accent.withValues(alpha: 0.24),
                Colors.white.withValues(alpha: 0.06),
              ],
            ),
            border: Border.all(color: spec.accent.withValues(alpha: 0.26)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(spec.icon, color: spec.accent),
                  const Spacer(),
                  Icon(Icons.open_in_new_rounded, size: 18, color: spec.accent),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                spec.title,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                spec.subtitle,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<String> buildOwnerPeriodSummaryLines(List<OrderModel> orders) {
  return OwnerPeriodReportSummary.fromOrders(orders).summaryLines;
}

OwnerPeriodReportSummary buildOwnerPeriodReportSummary(
  List<OrderModel> orders,
) {
  return OwnerPeriodReportSummary.fromOrders(orders);
}

const Set<String> _completedStatuses = {
  'completed',
  'delivered',
  'delivered_by_courier',
  'received_by_customer',
};

const Set<String> _cancelledStatuses = {
  'cancelled',
  'cancelled_by_store',
  'cancelled_by_admin',
  'cancelled_by_customer',
};

const Set<String> _activeStatuses = {
  'approved',
  'preparing',
  'ready_for_delivery',
  'on_the_way',
  'arrived',
};

Map<String, dynamic>? _mapOrNull(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

_PeriodStats _periodFromRaw(dynamic raw) {
  if (raw is! Map) return const _PeriodStats();
  final map = Map<String, dynamic>.from(raw);
  return _PeriodStats(
    ordersCount: _intValue(map['orders_count'] ?? map['ordersCount']),
    deliveryFees: _doubleValue(map['delivery_fees'] ?? map['deliveryFees']),
  );
}

String _merchantTypeLabel(OwnerMerchantModel? merchant) {
  if (merchant == null) return 'متجر';
  final type = merchant.type.toLowerCase();
  if (type == 'restaurant') return 'مطعم';
  if (type == 'pharmacy') return 'صيدلية';
  if (type == 'service') return 'خدمة';
  return 'متجر';
}

String _stringValue(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text;
}

double _doubleValue(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

int _intValue(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

class _PeriodStats {
  final int ordersCount;
  final double deliveryFees;

  const _PeriodStats({this.ordersCount = 0, this.deliveryFees = 0});
}
