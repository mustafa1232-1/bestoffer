import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../state/admin_controller.dart';

class AdminCourierReconciliationScreen extends ConsumerStatefulWidget {
  const AdminCourierReconciliationScreen({super.key});

  @override
  ConsumerState<AdminCourierReconciliationScreen> createState() =>
      _AdminCourierReconciliationScreenState();
}

class _AdminCourierReconciliationScreenState
    extends ConsumerState<AdminCourierReconciliationScreen> {
  Map<String, dynamic> data = const {};
  bool loading = true;
  String? error;
  String? reviewStatus;
  final Set<int> reviewingOrders = <int>{};

  double _money(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final out = await ref
          .read(adminApiProvider)
          .courierReconciliation(reviewStatus: reviewStatus);
      if (!mounted) return;
      setState(() {
        data = out;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = context.lt(
          ar: 'تعذر تحميل تقرير تسويات الدلفري.',
          en: 'Failed to load courier reconciliation report.',
        );
      });
    }
  }

  Future<void> _review(int orderId, {required bool approved}) async {
    String? note;
    if (!approved) {
      final controller = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            context.lt(ar: 'سبب رفض التسوية', en: 'Rejection reason'),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: context.lt(
                ar: 'اكتب ما الذي يحتاج إلى تصحيح',
                en: 'Explain what needs to be corrected',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.lt(ar: 'إلغاء', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
              child: Text(context.lt(ar: 'رفض', en: 'Reject')),
            ),
          ],
        ),
      );
      controller.dispose();
      if (note == null || note.trim().isEmpty) return;
    }

    setState(() => reviewingOrders.add(orderId));
    try {
      await ref
          .read(adminApiProvider)
          .reviewCourierReconciliation(
            orderId,
            approved: approved,
            reviewNote: note,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? context.lt(
                    ar: 'تم اعتماد التسوية.',
                    en: 'Settlement approved.',
                  )
                : context.lt(
                    ar: 'تم رفض التسوية وإبلاغ الدلفري.',
                    en: 'Settlement rejected and courier notified.',
                  ),
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(
              ar: 'تعذر حفظ قرار المراجعة. حاول مرة أخرى.',
              en: 'Could not save the review decision. Try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => reviewingOrders.remove(orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = Map<String, dynamic>.from(
      data['summary'] as Map? ?? const {},
    );
    final rows = (data['rows'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final appDue = _money(summary['app_due_total']);
    final courierDue = _money(summary['courier_due_total']);
    final net = appDue - courierDue;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.lt(ar: 'تسويات الدلفري', en: 'Courier reconciliation'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            DropdownButtonFormField<String?>(
              initialValue: reviewStatus,
              decoration: InputDecoration(
                labelText: context.lt(ar: 'حالة المراجعة', en: 'Review status'),
                prefixIcon: const Icon(Icons.filter_list_rounded),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(context.lt(ar: 'الكل', en: 'All')),
                ),
                DropdownMenuItem<String?>(
                  value: 'pending',
                  child: Text(
                    context.lt(ar: 'بانتظار المراجعة', en: 'Pending'),
                  ),
                ),
                DropdownMenuItem<String?>(
                  value: 'needs_review',
                  child: Text(
                    context.lt(ar: 'تحتاج تدقيق', en: 'Needs review'),
                  ),
                ),
                DropdownMenuItem<String?>(
                  value: 'approved',
                  child: Text(context.lt(ar: 'معتمدة', en: 'Approved')),
                ),
                DropdownMenuItem<String?>(
                  value: 'rejected',
                  child: Text(context.lt(ar: 'مرفوضة', en: 'Rejected')),
                ),
              ],
              onChanged: (value) {
                reviewStatus = value;
                unawaited(_load());
              },
            ),
            const SizedBox(height: 12),
            if (loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (error != null)
              Center(child: Text(error!))
            else ...[
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.7,
                children: [
                  _AdminMetric(
                    title: context.lt(ar: 'ذمة التطبيق', en: 'App due'),
                    value: formatIqd(appDue),
                  ),
                  _AdminMetric(
                    title: context.lt(ar: 'ذمة الدلفري', en: 'Courier due'),
                    value: formatIqd(courierDue),
                  ),
                  _AdminMetric(
                    title: context.lt(ar: 'رسوم الخدمة', en: 'Service fees'),
                    value: formatIqd(_money(summary['service_fee_total'])),
                  ),
                  if (_money(summary['coupon_discount_total']) > 0)
                    _AdminMetric(
                      title: context.lt(
                        ar: 'خصومات الكوبونات',
                        en: 'Coupon discounts',
                      ),
                      value: formatIqd(
                        _money(summary['coupon_discount_total']),
                      ),
                    ),
                  _AdminMetric(
                    title: context.lt(ar: 'قيد التدقيق', en: 'Open review'),
                    value: '${summary['open_review_count'] ?? 0}',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Card(
                color: net >= 0
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    net >= 0
                        ? context.lt(
                            ar: 'الصافي المستحق للتطبيق: ${formatIqd(net)}',
                            en: 'Net due to app: ${formatIqd(net)}',
                          )
                        : context.lt(
                            ar: 'الصافي المستحق للدلفري: ${formatIqd(net.abs())}',
                            en: 'Net due to couriers: ${formatIqd(net.abs())}',
                          ),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ...rows.map((row) {
                final orderId = int.tryParse('${row['order_id']}') ?? 0;
                final status = '${row['reconciliation_review_status'] ?? ''}';
                final isComplete = row['customer_cash_received_actual'] != null;
                final canReview =
                    isComplete &&
                    (status == 'pending' || status == 'needs_review');
                final isReviewing = reviewingOrders.contains(orderId);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    leading: Icon(
                      row['merchant_payment_without_receipt'] == true
                          ? Icons.warning_amber_rounded
                          : Icons.receipt_long_outlined,
                    ),
                    title: Text(
                      '#${row['order_id']} · ${row['courier_name'] ?? '-'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${row['merchant_name'] ?? '-'} · ${row['customer_name'] ?? '-'}',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    children: [
                      _line(
                        context.lt(ar: 'قيمة المنتجات', en: 'Product value'),
                        row['expected_store_amount'],
                      ),
                      _line(
                        context.lt(ar: 'المدفوع للمتجر', en: 'Paid to store'),
                        row['merchant_paid_actual'],
                      ),
                      _line(
                        context.lt(
                          ar: 'المستلم من الزبون',
                          en: 'Customer received',
                        ),
                        row['customer_cash_received_actual'],
                      ),
                      _line(
                        context.lt(ar: 'فرق الشراء', en: 'Purchase difference'),
                        row['purchase_difference_amount'],
                      ),
                      _line(
                        context.lt(
                          ar: 'فرق التحصيل',
                          en: 'Collection difference',
                        ),
                        row['collection_difference_amount'],
                      ),
                      _line(
                        context.lt(ar: 'رسوم الخدمة', en: 'Service fee'),
                        row['service_fee'],
                      ),
                      if (_money(row['coupon_discount_total']) > 0)
                        _line(
                          context.lt(ar: 'خصم الكوبون', en: 'Coupon discount'),
                          row['coupon_discount_total'],
                        ),
                      const Divider(),
                      _line(
                        context.lt(ar: 'للتطبيق', en: 'Due to app'),
                        row['app_due_from_delivery'],
                        strong: true,
                      ),
                      _line(
                        context.lt(ar: 'للدلفري', en: 'Due to courier'),
                        row['courier_due_from_app'],
                        strong: true,
                      ),
                      if (row['merchant_payment_without_receipt'] == true)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            context.lt(
                              ar: 'بدون فاتورة: يلزم تدقيق يدوي',
                              en: 'No receipt: manual review required',
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      if (!isComplete)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              context.lt(
                                ar: 'بانتظار إكمال التسليم وتسجيل المبلغ المستلم من الزبون.',
                                en: 'Waiting for delivery and the customer cash amount.',
                              ),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      if (row['merchant_payment_without_receipt'] != true &&
                          '${row['merchant_payment_receipt_url'] ?? ''}'
                              .trim()
                              .isNotEmpty)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(
                                '${row['merchant_payment_receipt_url']}',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: Text(
                              context.lt(
                                ar: 'عرض صورة الفاتورة',
                                en: 'View receipt image',
                              ),
                            ),
                          ),
                        ),
                      if (canReview) ...[
                        const Divider(),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isReviewing
                                    ? null
                                    : () => _review(orderId, approved: false),
                                icon: const Icon(Icons.close_rounded),
                                label: Text(
                                  context.lt(ar: 'رفض', en: 'Reject'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: isReviewing
                                    ? null
                                    : () => _review(orderId, approved: true),
                                icon: isReviewing
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded),
                                label: Text(
                                  context.lt(ar: 'اعتماد', en: 'Approve'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(String label, dynamic amount, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          formatIqd(_money(amount)),
          style: TextStyle(
            fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _AdminMetric extends StatelessWidget {
  const _AdminMetric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
    ),
  );
}
