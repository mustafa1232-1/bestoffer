import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      body: _loading
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
                        label: context.lt(ar: 'مكتمل اليوم', en: 'Done today'),
                        value: '${_int(_data?['completedTodayCount'])}',
                      ),
                      _MetricChip(
                        label: context.lt(ar: 'مكتمل الشهر', en: 'Done month'),
                        value: '${_int(_data?['completedMonthCount'])}',
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
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${_str(row['customerName']) ?? '-'} · ${_str(row['deliveredAt']) ?? ''}',
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
      body: _loading
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
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            _str(row['comment']) ??
                                context.lt(ar: 'بدون تعليق', en: 'No comment'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
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
