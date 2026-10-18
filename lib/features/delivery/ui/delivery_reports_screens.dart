import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../state/delivery_controller.dart';
import 'delivery_order_detail_screen.dart';

double _money(dynamic v) =>
    (v is num) ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
int _int(dynamic v) => (v is num) ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String? _str(dynamic v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty ? null : s;
}

List<Map<String, dynamic>> _rowsOf(Map<String, dynamic>? data) {
  final raw = data?['rows'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

void _openOrder(BuildContext context, int orderId) {
  if (orderId <= 0) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DeliveryOrderDetailScreen(orderId: orderId),
    ),
  );
}

/// ---------------------------------------------------------------------------
/// Earnings
/// ---------------------------------------------------------------------------
class DeliveryEarningsScreen extends ConsumerStatefulWidget {
  const DeliveryEarningsScreen({super.key});

  @override
  ConsumerState<DeliveryEarningsScreen> createState() =>
      _DeliveryEarningsScreenState();
}

class _DeliveryEarningsScreenState
    extends ConsumerState<DeliveryEarningsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(deliveryApiProvider).deliveryEarnings();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.lt(
          ar: 'تعذر تحميل الأرباح.',
          en: 'Failed to load earnings.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rowsOf(_data);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'أرباح التوصيل', en: 'Delivery earnings')),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorRetry(message: _error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetricChip(
                          label: context.lt(ar: 'أجور اليوم', en: 'Today'),
                          value: formatIqd(_money(_data?['todayEarnings'])),
                        ),
                        _MetricChip(
                          label: context.lt(ar: 'أجور الشهر', en: 'Month'),
                          value: formatIqd(_money(_data?['monthEarnings'])),
                        ),
                        _MetricChip(
                          label: context.lt(
                            ar: 'مكتمل اليوم',
                            en: 'Done today',
                          ),
                          value: '${_int(_data?['completedTodayCount'])}',
                        ),
                        _MetricChip(
                          label: context.lt(
                            ar: 'مكتمل الشهر',
                            en: 'Done month',
                          ),
                          value: '${_int(_data?['completedMonthCount'])}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetricChip(
                          label: context.lt(
                            ar: 'Ø±Ø³ÙˆÙ… Ø§Ù„Ø®Ø¯Ù…Ø©',
                            en: 'Service fee',
                          ),
                          value: formatIqd(_money(_data?['serviceFeeSum'])),
                        ),
                        _MetricChip(
                          label: context.lt(
                            ar: 'Ø°Ù…Ø© Ø§Ù„ØªØ·Ø¨ÙŠÙ‚',
                            en: 'App due',
                          ),
                          value: formatIqd(
                            _money(_data?['appDueFromDeliverySum']),
                          ),
                        ),
                        _MetricChip(
                          label: context.lt(
                            ar: 'Ø§Ù„ÙØ±ÙˆÙ‚Ø§Øª',
                            en: 'Differences',
                          ),
                          value: formatIqd(
                            _money(_data?['differenceAmountSum']),
                          ),
                        ),
                        _MetricChip(
                          label: context.lt(
                            ar: 'ØµØ§ÙÙŠ Ø§Ù„Ù…ØªØ¬Ø±',
                            en: 'Store net',
                          ),
                          value: formatIqd(
                            _money(_data?['storeNetReceivedAmountSum']),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (rows.isEmpty)
                      _EmptyState(
                        text: context.lt(
                          ar: 'لا توجد طلبات مكتملة بعد.',
                          en: 'No completed orders yet.',
                        ),
                      )
                    else
                      ...rows.map(
                        (row) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: () =>
                                _openOrder(context, _int(row['orderId'])),
                            title: Text(
                              '#${_int(row['orderNumber'])} · ${_str(row['merchantName']) ?? '-'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_str(row['customerName']) ?? '-'} · ${_str(row['deliveredAt']) ?? ''}',
                                ),
                                Text(
                                  '${context.lt(ar: "رسوم الخدمة", en: "Service fee")}: ${formatIqd(_money(row['serviceFee']))} · ${context.lt(ar: "ذمة التطبيق", en: "App due")}: ${formatIqd(_money(row['appDueFromDelivery']))} · ${context.lt(ar: "الفروقات", en: "Differences")}: ${formatIqd(_money(row['differenceAmount']))}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatIqd(_money(row['deliveryFee'])),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  context.lt(ar: 'أجور', en: 'fee'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Ratings
/// ---------------------------------------------------------------------------
class DeliveryRatingsScreen extends ConsumerStatefulWidget {
  const DeliveryRatingsScreen({super.key});

  @override
  ConsumerState<DeliveryRatingsScreen> createState() =>
      _DeliveryRatingsScreenState();
}

class _DeliveryRatingsScreenState extends ConsumerState<DeliveryRatingsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(deliveryApiProvider).deliveryRatings();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.lt(
          ar: 'تعذر تحميل التقييمات.',
          en: 'Failed to load ratings.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rowsOf(_data);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'تقييمات التوصيل', en: 'Delivery ratings')),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorRetry(message: _error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetricChip(
                          label: context.lt(ar: 'المتوسط', en: 'Average'),
                          value: _money(
                            _data?['averageRating'],
                          ).toStringAsFixed(1),
                        ),
                        _MetricChip(
                          label: context.lt(ar: 'عدد التقييمات', en: 'Count'),
                          value: '${_int(_data?['ratingCount'])}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (rows.isEmpty)
                      _EmptyState(
                        text: context.lt(
                          ar: 'لا توجد تقييمات بعد.',
                          en: 'No ratings yet.',
                        ),
                      )
                    else
                      ...rows.map(
                        (row) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: () =>
                                _openOrder(context, _int(row['orderId'])),
                            leading: _Stars(stars: _int(row['stars'])),
                            title: Text(
                              '#${_int(row['orderNumber'])} · ${_str(row['customerName']) ?? '-'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              _str(row['comment']) ??
                                  context.lt(
                                    ar: 'بدون تعليق',
                                    en: 'No comment',
                                  ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class DeliveryReconciliationScreen extends ConsumerStatefulWidget {
  const DeliveryReconciliationScreen({super.key});

  @override
  ConsumerState<DeliveryReconciliationScreen> createState() =>
      _DeliveryReconciliationScreenState();
}

class _DeliveryReconciliationScreenState
    extends ConsumerState<DeliveryReconciliationScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(deliveryApiProvider).reconciliationReport();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.lt(
          ar: 'تعذر تحميل تقرير الذمم. حاول مرة أخرى.',
          en: 'Failed to load reconciliation report. Try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = Map<String, dynamic>.from(
      _data?['summary'] as Map? ?? const {},
    );
    final rows = _rowsOf(_data);
    final appDue = _money(summary['app_due_total']);
    final courierDue = _money(summary['courier_due_total']);
    final net = appDue - courierDue;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.lt(ar: 'تقرير الذمم والفروقات', en: 'Cash reconciliation'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorRetry(message: _error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetricChip(
                          label: context.lt(ar: 'ذمة التطبيق', en: 'App due'),
                          value: formatIqd(appDue),
                        ),
                        _MetricChip(
                          label: context.lt(
                            ar: 'ذمة الدلفري',
                            en: 'Courier due',
                          ),
                          value: formatIqd(courierDue),
                        ),
                        _MetricChip(
                          label: context.lt(
                            ar: 'رسوم الخدمة',
                            en: 'Service fees',
                          ),
                          value: formatIqd(
                            _money(summary['service_fee_total']),
                          ),
                        ),
                        if (_money(summary['coupon_discount_total']) > 0)
                          _MetricChip(
                            label: context.lt(
                              ar: 'خصومات الكوبونات',
                              en: 'Coupon discounts',
                            ),
                            value: formatIqd(
                              _money(summary['coupon_discount_total']),
                            ),
                          ),
                        _MetricChip(
                          label: context.lt(
                            ar: 'قيد المراجعة',
                            en: 'Open review',
                          ),
                          value: '${_int(summary['open_review_count'])}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: net >= 0
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        net >= 0
                            ? context.lt(
                                ar: 'يجب عليك دفع ${formatIqd(net)} إلى التطبيق.',
                                en: 'You need to pay ${formatIqd(net)} to the app.',
                              )
                            : context.lt(
                                ar: 'يجب على التطبيق دفع ${formatIqd(net.abs())} لك.',
                                en: 'The app needs to pay you ${formatIqd(net.abs())}.',
                              ),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (rows.isEmpty)
                      _EmptyState(
                        text: context.lt(
                          ar: 'لا توجد تسويات مسجلة بعد.',
                          en: 'No reconciliations recorded yet.',
                        ),
                      )
                    else
                      ...rows.map((row) {
                        final noReceipt =
                            row['merchant_payment_without_receipt'] == true;
                        final orderId = _int(row['order_id']);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            onTap: () => _openOrder(context, orderId),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${context.lt(ar: 'الطلب', en: 'Order')} #$orderId · ${_str(row['customer_name']) ?? '-'}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        noReceipt
                                            ? Icons.receipt_long_outlined
                                            : Icons.verified_outlined,
                                        color: noReceipt
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.error
                                            : Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(_str(row['merchant_name']) ?? '-'),
                                  const Divider(height: 18),
                                  _ReportLine(
                                    label: context.lt(
                                      ar: 'قيمة المنتجات',
                                      en: 'Product value',
                                    ),
                                    value: formatIqd(
                                      _money(row['expected_store_amount']),
                                    ),
                                  ),
                                  _ReportLine(
                                    label: context.lt(
                                      ar: 'المدفوع للمتجر',
                                      en: 'Paid to store',
                                    ),
                                    value: formatIqd(
                                      _money(row['merchant_paid_actual']),
                                    ),
                                  ),
                                  _ReportLine(
                                    label: context.lt(
                                      ar: 'المستلم من الزبون',
                                      en: 'Received from customer',
                                    ),
                                    value: formatIqd(
                                      _money(
                                        row['customer_cash_received_actual'],
                                      ),
                                    ),
                                  ),
                                  _ReportLine(
                                    label: context.lt(
                                      ar: 'فرق الشراء',
                                      en: 'Purchase difference',
                                    ),
                                    value: formatIqd(
                                      _money(row['purchase_difference_amount']),
                                    ),
                                  ),
                                  _ReportLine(
                                    label: context.lt(
                                      ar: 'فرق التحصيل',
                                      en: 'Collection difference',
                                    ),
                                    value: formatIqd(
                                      _money(
                                        row['collection_difference_amount'],
                                      ),
                                    ),
                                  ),
                                  _ReportLine(
                                    label: context.lt(
                                      ar: 'رسوم الخدمة',
                                      en: 'Service fee',
                                    ),
                                    value: formatIqd(
                                      _money(row['service_fee']),
                                    ),
                                  ),
                                  if (_money(row['coupon_discount_total']) > 0)
                                    _ReportLine(
                                      label: context.lt(
                                        ar: 'خصم الكوبون',
                                        en: 'Coupon discount',
                                      ),
                                      value: formatIqd(
                                        _money(row['coupon_discount_total']),
                                      ),
                                    ),
                                  const Divider(height: 18),
                                  _ReportLine(
                                    label: context.lt(
                                      ar: 'للتطبيق',
                                      en: 'Due to app',
                                    ),
                                    value: formatIqd(
                                      _money(row['app_due_from_delivery']),
                                    ),
                                    strong: true,
                                  ),
                                  _ReportLine(
                                    label: context.lt(
                                      ar: 'للدلفري',
                                      en: 'Due to courier',
                                    ),
                                    value: formatIqd(
                                      _money(row['courier_due_from_app']),
                                    ),
                                    strong: true,
                                  ),
                                  if (noReceipt)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        context.lt(
                                          ar: 'بدون فاتورة: بانتظار مراجعة الإدارة',
                                          en: 'No receipt: awaiting admin review',
                                        ),
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  if (!noReceipt &&
                                      (_str(row['merchant_payment_receipt_url']) ??
                                              '')
                                          .isNotEmpty)
                                    Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: TextButton.icon(
                                        onPressed: () => launchUrl(
                                          Uri.parse(
                                            _str(
                                              row['merchant_payment_receipt_url'],
                                            )!,
                                          ),
                                          mode: LaunchMode.externalApplication,
                                        ),
                                        icon: const Icon(
                                          Icons.receipt_long_outlined,
                                        ),
                                        label: Text(
                                          context.lt(
                                            ar: 'عرض المرفق',
                                            en: 'View receipt',
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ReportLine extends StatelessWidget {
  const _ReportLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final int stars;

  const _Stars({required this.stars});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 16,
          color: i < stars ? Colors.amber : scheme.outline,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;

  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.lt(ar: 'إعادة المحاولة', en: 'Retry')),
            ),
          ],
        ),
      ),
    );
  }
}
