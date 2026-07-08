import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../state/admin_subscriptions_controller.dart';
import 'monthly_subscription_card.dart';

/// Admin/accountant surface: "اشتراكات المتاجر الشهرية".
/// Lists every merchant monthly subscription invoice and lets an authorized
/// admin generate the month, receive (exact/partial) payments, or waive.
class AdminMerchantSubscriptionsScreen extends ConsumerStatefulWidget {
  const AdminMerchantSubscriptionsScreen({super.key});

  @override
  ConsumerState<AdminMerchantSubscriptionsScreen> createState() =>
      _AdminMerchantSubscriptionsScreenState();
}

class _AdminMerchantSubscriptionsScreenState
    extends ConsumerState<AdminMerchantSubscriptionsScreen> {
  bool _suppressTransientMessages = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(adminSubscriptionsControllerProvider.notifier).bootstrap(),
    );
  }

  Future<void> _showPaymentDialog(Map<String, dynamic> invoice) async {
    final invoiceId = (invoice['id'] as num).toInt();
    _suppressTransientMessages = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => _PaymentDialog(
          invoice: invoice,
          onSubmit: (amount, notes) async {
            await ref
                .read(adminSubscriptionsControllerProvider.notifier)
                .recordPayment(
                  invoiceId: invoiceId,
                  amount: amount,
                  notes: notes,
                );
            return ref.read(adminSubscriptionsControllerProvider).error == null;
          },
        ),
      );
    } finally {
      _suppressTransientMessages = false;
    }
  }

  Future<void> _showWaiveDialog(Map<String, dynamic> invoice) async {
    final invoiceId = (invoice['id'] as num).toInt();
    _suppressTransientMessages = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => _WaiveDialog(
          onSubmit: (reason) async {
            await ref
                .read(adminSubscriptionsControllerProvider.notifier)
                .waiveInvoice(invoiceId: invoiceId, reason: reason);
            return ref.read(adminSubscriptionsControllerProvider).error == null;
          },
        ),
      );
    } finally {
      _suppressTransientMessages = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminSubscriptionsControllerProvider);

    ref.listen<AdminSubscriptionsState>(adminSubscriptionsControllerProvider,
        (prev, next) {
      if (_suppressTransientMessages) return;
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
      if (next.successMessage != null &&
          next.successMessage != prev?.successMessage) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.successMessage!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(
          ar: 'اشتراكات المتاجر الشهرية',
          en: 'Merchant monthly subscriptions',
        )),
        actions: [
          IconButton(
            tooltip: context.lt(ar: 'إنشاء فواتير الشهر', en: 'Generate month'),
            onPressed: state.saving
                ? null
                : () => ref
                    .read(adminSubscriptionsControllerProvider.notifier)
                    .generateCurrentMonth(),
            icon: const Icon(Icons.playlist_add_outlined),
          ),
          IconButton(
            onPressed: () => ref
                .read(adminSubscriptionsControllerProvider.notifier)
                .bootstrap(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref
                  .read(adminSubscriptionsControllerProvider.notifier)
                  .bootstrap(),
              child: state.invoices.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Text(context.lt(
                            ar: 'لا توجد فواتير اشتراك.',
                            en: 'No subscription invoices.',
                          )),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: state.invoices.length,
                      itemBuilder: (context, index) {
                        final invoice = state.invoices[index];
                        return _InvoiceCard(
                          invoice: invoice,
                          saving: state.saving,
                          onPay: () => _showPaymentDialog(invoice),
                          onWaive: () => _showWaiveDialog(invoice),
                        );
                      },
                    ),
            ),
    );
  }
}

num _asNum(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.invoice, required this.onSubmit});

  final Map<String, dynamic> invoice;
  final Future<bool> Function(num amount, String? notes) onSubmit;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  late final num _subscriptionAmount;
  late final num _remaining;
  String? _amountError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _subscriptionAmount = _asNum(widget.invoice['subscriptionAmount']);
    _remaining = _asNum(widget.invoice['remainingAmount']);
    _amountCtrl = TextEditingController(text: _remaining.toStringAsFixed(0));
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final amount = num.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _amountError =
          context.lt(ar: 'أدخل مبلغاً صحيحاً.', en: 'Enter a valid amount.'));
      return;
    }
    setState(() {
      _submitting = true;
      _amountError = null;
    });
    final ok = await widget.onSubmit(
      amount,
      _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _submitting = false);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final entered = num.tryParse(_amountCtrl.text.trim()) ?? 0;
    final projectedRemaining =
        (_remaining - entered).clamp(0, _subscriptionAmount);
    return AlertDialog(
      title: Text(context.lt(
        ar: 'استلام دفعة اشتراك',
        en: 'Receive subscription payment',
      )),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.invoice['merchantName'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${context.lt(ar: "المتبقي", en: "Remaining")}: ${formatIqd(_remaining)}',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText:
                      context.lt(ar: 'المبلغ المستلم', en: 'Amount received'),
                  errorText: _amountError,
                ),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 8),
              Text(
                '${context.lt(ar: "المتبقي بعد الدفع", en: "Remaining after payment")}: ${formatIqd(projectedRemaining)}',
                key: const Key('projected_remaining'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                  labelText:
                      context.lt(ar: 'ملاحظة (اختياري)', en: 'Note (optional)'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(context.lt(ar: 'إلغاء', en: 'Cancel')),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: Text(context.lt(ar: 'تأكيد', en: 'Confirm')),
        ),
      ],
    );
  }
}

class _WaiveDialog extends StatefulWidget {
  const _WaiveDialog({required this.onSubmit});

  final Future<bool> Function(String reason) onSubmit;

  @override
  State<_WaiveDialog> createState() => _WaiveDialogState();
}

class _WaiveDialogState extends State<_WaiveDialog> {
  late final TextEditingController _reasonCtrl;
  String? _reasonError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _reasonCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _reasonError = context.lt(
            ar: 'سبب الإعفاء مطلوب.',
            en: 'A waive reason is required.',
          ));
      return;
    }
    setState(() {
      _submitting = true;
      _reasonError = null;
    });
    final ok = await widget.onSubmit(reason);
    if (!mounted) return;
    if (!ok) {
      setState(() => _submitting = false);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.lt(ar: 'إعفاء الفاتورة', en: 'Waive invoice')),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _reasonCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: context.lt(
              ar: 'سبب الإعفاء (مطلوب)',
              en: 'Waive reason (required)',
            ),
            errorText: _reasonError,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(context.lt(ar: 'إلغاء', en: 'Cancel')),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: Text(context.lt(ar: 'إعفاء', en: 'Waive')),
        ),
      ],
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.saving,
    required this.onPay,
    required this.onWaive,
  });

  final Map<String, dynamic> invoice;
  final bool saving;
  final VoidCallback onPay;
  final VoidCallback onWaive;

  @override
  Widget build(BuildContext context) {
    final status = invoice['status'] as String?;
    final closed = status == 'paid' || status == 'waived';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${invoice['merchantName'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(MonthlySubscriptionCard.statusLabel(context, status)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${context.lt(ar: 'الشهر', en: 'Month')}: ${invoice['billingMonth'] ?? '-'}'),
            Text('${context.lt(ar: 'قيمة الاشتراك', en: 'Amount')}: ${formatIqd(_asNum(invoice['subscriptionAmount']))}'),
            Text('${context.lt(ar: 'المدفوع', en: 'Paid')}: ${formatIqd(_asNum(invoice['paidAmount']))}'),
            Text('${context.lt(ar: 'المتبقي', en: 'Remaining')}: ${formatIqd(_asNum(invoice['remainingAmount']))}'),
            if (invoice['dueAt'] != null)
              Text('${context.lt(ar: 'الاستحقاق', en: 'Due')}: ${invoice['dueAt'].toString().split('T').first}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ElevatedButton.icon(
                  onPressed: (saving || closed) ? null : onPay,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: Text(context.lt(ar: 'استلام دفعة', en: 'Receive payment')),
                ),
                OutlinedButton.icon(
                  onPressed: (saving || closed) ? null : onWaive,
                  icon: const Icon(Icons.block_outlined, size: 18),
                  label: Text(context.lt(ar: 'إعفاء', en: 'Waive')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
