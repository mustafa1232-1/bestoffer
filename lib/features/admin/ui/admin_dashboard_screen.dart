import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/i18n/app_strings.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/report_printing.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../../auth/state/auth_controller.dart';
import '../../auth/ui/add_merchant_screen.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../models/pending_merchant_model.dart';
import '../models/pending_settlement_model.dart';
import '../models/period_metrics_model.dart';
import '../models/managed_merchant_model.dart';
import '../state/admin_controller.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(adminControllerProvider.notifier).bootstrap(),
    );
  }

  Future<void> _openCreateUserSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateUserSheet(),
    );
  }

  Future<void> _openCreateMerchant() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddMerchantScreen()));

    if (result == true && mounted) {
      await ref.read(adminControllerProvider.notifier).bootstrap();
    }
  }

  Future<void> _openAnalyticsDetails({
    required String title,
    required List<String> lines,
    required String reportPeriod,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              ...lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line, textDirection: TextDirection.rtl),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final raw = await ref
                        .read(adminApiProvider)
                        .ordersPrintReport(period: reportPeriod);
                    final orders = raw
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    await printOrdersReceiptReport(
                      title: title,
                      summaryLines: lines,
                      orders: orders,
                    );
                  } catch (e) {
                    try {
                      await printSimpleReport(title: title, lines: lines);
                    } catch (_) {}
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تعذر فتح واجهة الطباعة على هذا الجهاز. تم فتح تقرير بديل. ($e)',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('طباعة الوصل'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final raw = await ref
                        .read(adminApiProvider)
                        .ordersPrintReport(period: reportPeriod);
                    final orders = raw
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    await exportOrdersExcelReport(
                      title: title,
                      summaryLines: lines,
                      orders: orders,
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('فشل تصدير Excel. ($e)')),
                    );
                  }
                },
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('تصدير Excel مفصل'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final isAdmin = auth.isAdmin;
    final strings = ref.watch(appStringsProvider);

    ref.listen<AdminState>(adminControllerProvider, (prev, next) {
      final message = next.error ?? next.success;
      final prevMessage = prev?.error ?? prev?.success;
      if (message != null && message != prevMessage && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    final drawerItems = <AppUserDrawerItem>[
      AppUserDrawerItem(
        icon: Icons.dashboard_outlined,
        label: strings.t('drawerHome'),
      ),
      AppUserDrawerItem(
        icon: Icons.pending_actions_outlined,
        label: strings.t('drawerPendingApprovals'),
      ),
      AppUserDrawerItem(
        icon: Icons.account_balance_wallet_outlined,
        label: strings.t('drawerPendingSettlements'),
      ),
      AppUserDrawerItem(
        icon: Icons.refresh_rounded,
        label: strings.t('drawerRefresh'),
        onTap: (_) => ref.read(adminControllerProvider.notifier).bootstrap(),
      ),
      if (isAdmin)
        AppUserDrawerItem(
          icon: Icons.person_add_alt_1_outlined,
          label: strings.t('drawerCreateUser'),
          onTap: (_) => _openCreateUserSheet(),
        ),
      if (isAdmin)
        AppUserDrawerItem(
          icon: Icons.store_mall_directory_outlined,
          label: strings.t('drawerCreateMerchant'),
          onTap: (_) => _openCreateMerchant(),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isAdmin
              ? strings.t('adminDashboard')
              : strings.t('deputyAdminDashboard'),
        ),
        actions: const [NotificationsBellButton()],
      ),
      drawer: AppUserDrawer(
        title: isAdmin
            ? strings.t('adminDashboard')
            : strings.t('deputyAdminDashboard'),
        subtitle: isAdmin
            ? strings.t('drawerAdminSub')
            : strings.t('drawerDeputyAdminSub'),
        items: drawerItems,
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(adminControllerProvider.notifier).bootstrap(),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _AnalyticsSection(
                    day: state.day,
                    month: state.month,
                    year: state.year,
                    onOpenDetails:
                        ({
                          required title,
                          required lines,
                          required reportPeriod,
                        }) {
                          return _openAnalyticsDetails(
                            title: title,
                            lines: lines,
                            reportPeriod: reportPeriod,
                          );
                        },
                  ),
                  const SizedBox(height: 12),
                  _PendingSettlementsSection(
                    saving: state.saving,
                    canApprove: isAdmin,
                    settlements: state.pendingSettlements,
                    onApprove: (settlementId) async {
                      await ref
                          .read(adminControllerProvider.notifier)
                          .approveSettlement(settlementId);
                    },
                  ),
                  const SizedBox(height: 12),
                  _PendingMerchantsSection(
                    saving: state.saving,
                    canApprove: isAdmin,
                    merchants: state.pendingMerchants,
                    onApprove: (merchantId) async {
                      await ref
                          .read(adminControllerProvider.notifier)
                          .approveMerchant(merchantId);
                    },
                  ),
                  const SizedBox(height: 12),
                  _MerchantsStatusSection(
                    saving: state.saving,
                    canManage: isAdmin,
                    merchants: state.managedMerchants,
                    onToggleDisabled: (merchantId, nextDisabled) async {
                      await ref
                          .read(adminControllerProvider.notifier)
                          .toggleMerchantDisabled(
                            merchantId: merchantId,
                            isDisabled: nextDisabled,
                          );
                    },
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

class _AnalyticsSection extends StatelessWidget {
  final PeriodMetricsModel day;
  final PeriodMetricsModel month;
  final PeriodMetricsModel year;
  final Future<void> Function({
    required String title,
    required List<String> lines,
    required String reportPeriod,
  })
  onOpenDetails;

  const _AnalyticsSection({
    required this.day,
    required this.month,
    required this.year,
    required this.onOpenDetails,
  });

  List<String> _periodLines({
    required String label,
    required PeriodMetricsModel metric,
  }) {
    return [
      '$label:',
      'عدد الطلبات: ${metric.ordersCount}',
      'الطلبات المكتملة: ${metric.deliveredOrdersCount}',
      'الطلبات الملغية: ${metric.cancelledOrdersCount}',
      'إجمالي المبيعات: ${formatIqd(metric.totalAmount)}',
      'رسوم التوصيل: ${formatIqd(metric.deliveryFees)}',
      'عمولة التطبيق: ${formatIqd(metric.appFees)}',
      'تقييم الدلفري: ${metric.avgDeliveryRating.toStringAsFixed(1)}',
      'تقييم المتجر: ${metric.avgMerchantRating.toStringAsFixed(1)}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final deliveredRate = _safeRatio(
      year.deliveredOrdersCount,
      year.ordersCount,
    );
    final cancelledRate = _safeRatio(
      year.cancelledOrdersCount,
      year.ordersCount,
    );
    final appMargin = _safeRatio(year.appFees, year.totalAmount);

    return Column(
      children: [
        Card(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1D4F88).withValues(alpha: 0.72),
                  const Color(0xFF2E7AC6).withValues(alpha: 0.38),
                  const Color(0xFF0E2748).withValues(alpha: 0.82),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'نبض لوحة المتابعة',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _KpiStatCard(
                        title: 'إجمالي الطلبات',
                        value: '${year.ordersCount}',
                        icon: Icons.receipt_long_rounded,
                        tint: const Color(0xFF6EE7FF),
                        onTap: () {
                          onOpenDetails(
                            title: 'تفاصيل إجمالي الطلبات',
                            lines: [
                              ..._periodLines(label: 'اليوم', metric: day),
                              '',
                              ..._periodLines(label: 'الشهر', metric: month),
                              '',
                              ..._periodLines(label: 'السنة', metric: year),
                            ],
                            reportPeriod: 'year',
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _KpiStatCard(
                        title: 'إجمالي الإيرادات',
                        value: formatIqd(year.totalAmount),
                        icon: Icons.payments_rounded,
                        tint: const Color(0xFF8BFFC8),
                        onTap: () {
                          onOpenDetails(
                            title: 'تفاصيل الإيرادات',
                            lines: [
                              'اليوم: ${formatIqd(day.totalAmount)}',
                              'الشهر: ${formatIqd(month.totalAmount)}',
                              'السنة: ${formatIqd(year.totalAmount)}',
                              'عمولة التطبيق (السنة): ${formatIqd(year.appFees)}',
                            ],
                            reportPeriod: 'year',
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _KpiStatCard(
                title: 'طلبات اليوم',
                value: '${day.ordersCount}',
                icon: Icons.today_rounded,
                tint: const Color(0xFF9BD7FF),
                onTap: () {
                  onOpenDetails(
                    title: 'تفاصيل طلبات اليوم',
                    lines: _periodLines(label: 'اليوم', metric: day),
                    reportPeriod: 'day',
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiStatCard(
                title: 'أجور توصيل اليوم',
                value: formatIqd(day.deliveryFees),
                icon: Icons.local_shipping_rounded,
                tint: const Color(0xFFFFD28F),
                onTap: () {
                  onOpenDetails(
                    title: 'تفاصيل أجور التوصيل',
                    lines: [
                      'اليوم: ${formatIqd(day.deliveryFees)}',
                      'الشهر: ${formatIqd(month.deliveryFees)}',
                      'السنة: ${formatIqd(year.deliveryFees)}',
                    ],
                    reportPeriod: 'day',
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _KpiStatCard(
                title: 'عمولة التطبيق اليوم',
                value: formatIqd(day.appFees),
                icon: Icons.account_balance_wallet_rounded,
                tint: const Color(0xFF9EFBA5),
                onTap: () {
                  onOpenDetails(
                    title: 'تفاصيل عمولة التطبيق',
                    lines: [
                      'اليوم: ${formatIqd(day.appFees)}',
                      'الشهر: ${formatIqd(month.appFees)}',
                      'السنة: ${formatIqd(year.appFees)}',
                    ],
                    reportPeriod: 'day',
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiStatCard(
                title: 'متوسط التقييم',
                value:
                    '${year.avgDeliveryRating.toStringAsFixed(1)} / ${year.avgMerchantRating.toStringAsFixed(1)}',
                icon: Icons.star_rounded,
                tint: const Color(0xFFFFE48D),
                onTap: () {
                  onOpenDetails(
                    title: 'تفاصيل التقييم',
                    lines: [
                      'تقييم الدلفري - اليوم: ${day.avgDeliveryRating.toStringAsFixed(1)}',
                      'تقييم الدلفري - الشهر: ${month.avgDeliveryRating.toStringAsFixed(1)}',
                      'تقييم الدلفري - السنة: ${year.avgDeliveryRating.toStringAsFixed(1)}',
                      '',
                      'تقييم المتجر - اليوم: ${day.avgMerchantRating.toStringAsFixed(1)}',
                      'تقييم المتجر - الشهر: ${month.avgMerchantRating.toStringAsFixed(1)}',
                      'تقييم المتجر - السنة: ${year.avgMerchantRating.toStringAsFixed(1)}',
                    ],
                    reportPeriod: 'year',
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مؤشرات الأداء',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RingIndicator(
                        label: 'مكتمل',
                        percent: deliveredRate,
                        color: const Color(0xFF63E9B4),
                      ),
                    ),
                    Expanded(
                      child: _RingIndicator(
                        label: 'ملغي',
                        percent: cancelledRate,
                        color: const Color(0xFFFF8AA5),
                      ),
                    ),
                    Expanded(
                      child: _RingIndicator(
                        label: 'هامش التطبيق',
                        percent: appMargin,
                        color: const Color(0xFF7ED7FF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _RatingRow(
                  title: 'تقييم الدلفري',
                  value: year.avgDeliveryRating / 5,
                  color: const Color(0xFF8DDCFF),
                ),
                const SizedBox(height: 8),
                _RatingRow(
                  title: 'تقييم المتجر',
                  value: year.avgMerchantRating / 5,
                  color: const Color(0xFF9FF1B5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اتجاه الطلبات (يوم / شهر / سنة)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 138,
                  child: CustomPaint(
                    painter: _OrdersTrendPainter(
                      values: [
                        day.ordersCount.toDouble(),
                        month.ordersCount.toDouble(),
                        year.ordersCount.toDouble(),
                      ],
                      lineColor: const Color(0xFF76D8FF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مخطط الرسوم (التوصيل مقابل التطبيق)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 156,
                  child: CustomPaint(
                    painter: _FeesBarsPainter(
                      deliveryValues: [
                        day.deliveryFees,
                        month.deliveryFees,
                        year.deliveryFees,
                      ],
                      appValues: [day.appFees, month.appFees, year.appFees],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    _LegendDot(label: 'رسوم التوصيل', color: Color(0xFF78C9FF)),
                    SizedBox(width: 10),
                    _LegendDot(label: 'رسوم التطبيق', color: Color(0xFF8BF9B9)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;

  const _KpiStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardChild = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF102A4F).withValues(alpha: 0.66),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tint.withValues(alpha: 0.92)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ],
      ),
    );

    if (onTap == null) return cardChild;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: cardChild,
      ),
    );
  }
}

class _RingIndicator extends StatelessWidget {
  final String label;
  final double percent;
  final Color color;

  const _RingIndicator({
    required this.label,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 78,
          height: 78,
          child: CustomPaint(
            painter: _RingPainter(value: percent.clamp(0.0, 1.0), color: color),
            child: Center(
              child: Text(
                '${(percent * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _RatingRow extends StatelessWidget {
  final String title;
  final double value;
  final Color color;

  const _RatingRow({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            Text('${(normalized * 5).toStringAsFixed(1)} / 5'),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: normalized,
            valueColor: AlwaysStoppedAnimation(color),
            backgroundColor: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}

class _OrdersTrendPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;

  const _OrdersTrendPainter({required this.values, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = math.max(
      values.fold<double>(0, (p, e) => e > p ? e : p),
      1.0,
    );

    const left = 12.0;
    const right = 10.0;
    const top = 8.0;
    const bottom = 20.0;
    final chartRect = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = chartRect.top + chartRect.height * (i / 3);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x =
          chartRect.left +
          (chartRect.width * i / math.max(values.length - 1, 1));
      final y = chartRect.bottom - ((values[i] / maxValue) * chartRect.height);
      points.add(Offset(x, y));
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      linePath.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    linePath.lineTo(points.last.dx, points.last.dy);

    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, chartRect.bottom)
      ..lineTo(points.first.dx, chartRect.bottom)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.32),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(chartRect);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = lineColor;
    for (final point in points) {
      canvas.drawCircle(point, 3.2, dotPaint);
      canvas.drawCircle(
        point,
        6.2,
        Paint()..color = lineColor.withValues(alpha: 0.22),
      );
    }

    const labels = ['يوم', 'شهر', 'سنة'];
    for (var i = 0; i < labels.length; i++) {
      final x =
          chartRect.left +
          (chartRect.width * i / math.max(labels.length - 1, 1));
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - (tp.width / 2), chartRect.bottom + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _OrdersTrendPainter oldDelegate) {
    if (oldDelegate.lineColor != lineColor) return true;
    if (oldDelegate.values.length != values.length) return true;
    for (var i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) return true;
    }
    return false;
  }
}

class _FeesBarsPainter extends CustomPainter {
  final List<double> deliveryValues;
  final List<double> appValues;

  const _FeesBarsPainter({
    required this.deliveryValues,
    required this.appValues,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 14.0;
    const right = 12.0;
    const top = 8.0;
    const bottom = 22.0;
    final chartRect = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );

    final all = [...deliveryValues, ...appValues];
    final maxValue = math.max(
      all.fold<double>(0, (p, e) => e > p ? e : p),
      1.0,
    );

    final base = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(chartRect.left, chartRect.bottom),
      Offset(chartRect.right, chartRect.bottom),
      base,
    );

    final groups = math.min(deliveryValues.length, appValues.length);
    if (groups == 0) return;

    final slotWidth = chartRect.width / groups;
    const barWidth = 12.0;
    const labels = ['ي', 'ش', 'س'];

    for (var i = 0; i < groups; i++) {
      final xCenter = chartRect.left + (slotWidth * i) + (slotWidth / 2);

      final deliveryHeight =
          (deliveryValues[i] / maxValue).clamp(0.0, 1.0) * chartRect.height;
      final appHeight =
          (appValues[i] / maxValue).clamp(0.0, 1.0) * chartRect.height;

      final deliveryRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          xCenter - barWidth - 2,
          chartRect.bottom - deliveryHeight,
          barWidth,
          deliveryHeight,
        ),
        const Radius.circular(5),
      );
      final appRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          xCenter + 2,
          chartRect.bottom - appHeight,
          barWidth,
          appHeight,
        ),
        const Radius.circular(5),
      );

      canvas.drawRRect(
        deliveryRect,
        Paint()..color = const Color(0xFF78C9FF).withValues(alpha: 0.95),
      );
      canvas.drawRRect(
        appRect,
        Paint()..color = const Color(0xFF8BF9B9).withValues(alpha: 0.95),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i % labels.length],
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(xCenter - (tp.width / 2), chartRect.bottom + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _FeesBarsPainter oldDelegate) {
    if (oldDelegate.deliveryValues.length != deliveryValues.length) return true;
    if (oldDelegate.appValues.length != appValues.length) return true;
    for (var i = 0; i < deliveryValues.length; i++) {
      if (oldDelegate.deliveryValues[i] != deliveryValues[i]) return true;
    }
    for (var i = 0; i < appValues.length; i++) {
      if (oldDelegate.appValues[i] != appValues[i]) return true;
    }
    return false;
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;

  const _RingPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width / 2) - 6;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color;

    final startAngle = -math.pi / 2;
    final sweep = 2 * math.pi * value.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.color != color;
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

double _safeRatio(num part, num total) {
  if (total <= 0) return 0;
  final ratio = part / total;
  if (ratio.isNaN || ratio.isInfinite) return 0;
  return ratio.clamp(0, 1).toDouble();
}

class _PendingMerchantsSection extends StatelessWidget {
  final bool saving;
  final bool canApprove;
  final List<PendingMerchantModel> merchants;
  final Future<void> Function(int merchantId) onApprove;

  const _PendingMerchantsSection({
    required this.saving,
    required this.canApprove,
    required this.merchants,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'المتاجر بانتظار الموافقة',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (merchants.isEmpty)
              const Text(
                'لا توجد متاجر بانتظار الموافقة',
                textAlign: TextAlign.right,
              )
            else
              ...merchants.map((merchant) {
                return ListTile(
                  title: Text(
                    '${merchant.name} (${merchant.type})',
                    textDirection: TextDirection.rtl,
                  ),
                  subtitle: Text(
                    'المالك: ${merchant.ownerName ?? '-'} - ${merchant.ownerPhone ?? ''}',
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: ElevatedButton(
                    onPressed: saving || !canApprove
                        ? null
                        : () => onApprove(merchant.id),
                    child: const Text('موافقة'),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _PendingSettlementsSection extends StatelessWidget {
  final bool saving;
  final bool canApprove;
  final List<PendingSettlementModel> settlements;
  final Future<void> Function(int settlementId) onApprove;

  const _PendingSettlementsSection({
    required this.saving,
    required this.canApprove,
    required this.settlements,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'طلبات تسديد المستحقات',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (settlements.isEmpty)
              const Text(
                'لا توجد طلبات تسديد حالياً',
                textAlign: TextAlign.right,
              )
            else
              ...settlements.map((s) {
                return ListTile(
                  title: Text(
                    '${s.merchantName} - ${formatIqd(s.amount)}',
                    textDirection: TextDirection.rtl,
                  ),
                  subtitle: Text(
                    'صاحب المتجر: ${s.ownerName} - ${s.ownerPhone}',
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: ElevatedButton(
                    onPressed: saving || !canApprove
                        ? null
                        : () => onApprove(s.id),
                    child: const Text('مصادقة'),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _MerchantsStatusSection extends StatelessWidget {
  final bool saving;
  final bool canManage;
  final List<ManagedMerchantModel> merchants;
  final Future<void> Function(int merchantId, bool nextDisabled)
  onToggleDisabled;

  const _MerchantsStatusSection({
    required this.saving,
    required this.canManage,
    required this.merchants,
    required this.onToggleDisabled,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'إدارة حالة المتاجر',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (merchants.isEmpty)
              const Text('لا توجد متاجر', textAlign: TextAlign.right)
            else
              ...merchants.take(12).map((merchant) {
                final statusLabel = merchant.isDisabled ? 'معطل' : 'نشط';
                return ListTile(
                  title: Text(
                    '${merchant.name} (${merchant.type})',
                    textDirection: TextDirection.rtl,
                  ),
                  subtitle: Text(
                    'المالك: ${merchant.ownerFullName ?? '-'} - اليوم: ${merchant.todayOrdersCount} طلب - الحالة: $statusLabel',
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: Switch(
                    value: !merchant.isDisabled,
                    onChanged: !canManage || saving
                        ? null
                        : (value) => onToggleDisabled(merchant.id, !value),
                  ),
                );
              }),
            if (merchants.length > 12)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '... +${merchants.length - 12} متجر',
                  textDirection: TextDirection.rtl,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CreateUserSheet extends ConsumerStatefulWidget {
  const _CreateUserSheet();

  @override
  ConsumerState<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends ConsumerState<_CreateUserSheet> {
  final fullNameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final blockCtrl = TextEditingController(text: 'A');
  final buildingCtrl = TextEditingController(text: '1');
  final apartmentCtrl = TextEditingController(text: '1');
  LocalImageFile? userImageFile;
  String selectedRole = 'user';

  @override
  void dispose() {
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    pinCtrl.dispose();
    blockCtrl.dispose();
    buildingCtrl.dispose();
    apartmentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(adminControllerProvider).saving;
    final isAdmin = ref.watch(authControllerProvider).isAdmin;

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إنشاء حساب جديد',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fullNameCtrl,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'PIN'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('مستخدم عادي')),
                  DropdownMenuItem(value: 'owner', child: Text('صاحب متجر')),
                  DropdownMenuItem(value: 'delivery', child: Text('دلفري')),
                  DropdownMenuItem(
                    value: 'deputy_admin',
                    child: Text('نائب أدمن'),
                  ),
                  DropdownMenuItem(
                    value: 'call_center',
                    child: Text('كول سنتر'),
                  ),
                  DropdownMenuItem(value: 'admin', child: Text('أدمن')),
                ],
                onChanged: (v) => setState(() => selectedRole = v ?? 'user'),
                decoration: const InputDecoration(labelText: 'الدور'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: blockCtrl,
                      decoration: const InputDecoration(labelText: 'البلوك'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: buildingCtrl,
                      decoration: const InputDecoration(labelText: 'العمارة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: apartmentCtrl,
                      decoration: const InputDecoration(labelText: 'الشقة'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ImagePickerField(
                title: 'صورة الحساب (اختياري)',
                selectedFile: userImageFile,
                existingImageUrl: null,
                onPick: () async {
                  final picked = await pickImageFromDevice();
                  if (!mounted || picked == null) return;
                  setState(() => userImageFile = picked);
                },
                onClear: userImageFile == null
                    ? null
                    : () => setState(() => userImageFile = null),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: saving || !isAdmin
                    ? null
                    : () async {
                        await ref
                            .read(adminControllerProvider.notifier)
                            .createUser({
                              'fullName': fullNameCtrl.text,
                              'phone': phoneCtrl.text,
                              'pin': pinCtrl.text,
                              'block': blockCtrl.text,
                              'buildingNumber': buildingCtrl.text,
                              'apartment': apartmentCtrl.text,
                              'role': selectedRole,
                            }, imageFile: userImageFile);

                        if (!context.mounted) return;
                        final adminState = ref.read(adminControllerProvider);
                        if (adminState.error == null) {
                          Navigator.of(context).pop();
                        }
                      },
                child: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('إنشاء الحساب'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
