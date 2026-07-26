import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/utils/currency.dart';
import '../../models/order_revision_model.dart';

typedef OrderRevisionLoader = Future<List<OrderRevisionModel>> Function();
typedef OrderRevisionAction =
    Future<void> Function(OrderRevisionModel revision);
typedef OrderRevisionPredicate = bool Function(OrderRevisionModel revision);

class OrderRevisionPanel extends StatefulWidget {
  final String title;
  final String emptyText;
  final OrderRevisionLoader loadRevisions;
  final OrderRevisionPredicate canApprove;
  final OrderRevisionPredicate canReject;
  final OrderRevisionPredicate canSubmit;
  final OrderRevisionPredicate canApply;
  final OrderRevisionAction? onApprove;
  final OrderRevisionAction? onReject;
  final OrderRevisionAction? onSubmit;
  final OrderRevisionAction? onApply;
  final bool initiallyExpanded;

  const OrderRevisionPanel({
    super.key,
    required this.title,
    required this.emptyText,
    required this.loadRevisions,
    this.canApprove = _never,
    this.canReject = _never,
    this.canSubmit = _never,
    this.canApply = _never,
    this.onApprove,
    this.onReject,
    this.onSubmit,
    this.onApply,
    this.initiallyExpanded = true,
  });

  static bool _never(OrderRevisionModel revision) => false;

  @override
  State<OrderRevisionPanel> createState() => _OrderRevisionPanelState();
}

class _OrderRevisionPanelState extends State<OrderRevisionPanel> {
  late Future<List<OrderRevisionModel>> _future;
  int? _busyRevisionId;

  @override
  void initState() {
    super.initState();
    _future = widget.loadRevisions();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.loadRevisions());
    await _future;
  }

  Future<void> _run(
    OrderRevisionModel revision,
    OrderRevisionAction? action,
  ) async {
    if (action == null || _busyRevisionId != null) return;
    setState(() => _busyRevisionId = revision.id);
    try {
      await action(revision);
      if (!mounted) return;
      await _refresh();
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapDioError(error, fallback: 'تعذر تنفيذ إجراء تعديل الطلب.'),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تنفيذ إجراء تعديل الطلب.')),
      );
    } finally {
      if (mounted) setState(() => _busyRevisionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OrderRevisionModel>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        if (snapshot.hasError) {
          return _RevisionShell(
            title: widget.title,
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded),
                const SizedBox(width: 8),
                const Expanded(child: Text('تعذر تحميل تعديلات الطلب.')),
                IconButton(
                  tooltip: 'إعادة المحاولة',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          );
        }
        final revisions = snapshot.data ?? const <OrderRevisionModel>[];
        if (revisions.isEmpty) {
          return _RevisionShell(
            title: widget.title,
            child: Text(widget.emptyText),
          );
        }
        return _RevisionShell(
          title: widget.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final revision in revisions.take(3)) ...[
                _RevisionCard(
                  revision: revision,
                  busy: _busyRevisionId == revision.id,
                  canApprove: widget.canApprove(revision),
                  canReject: widget.canReject(revision),
                  canSubmit: widget.canSubmit(revision),
                  canApply: widget.canApply(revision),
                  onApprove: () => _run(revision, widget.onApprove),
                  onReject: () => _run(revision, widget.onReject),
                  onSubmit: () => _run(revision, widget.onSubmit),
                  onApply: () => _run(revision, widget.onApply),
                ),
                if (revision != revisions.take(3).last)
                  const Divider(height: 20),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RevisionShell extends StatelessWidget {
  final String title;
  final Widget child;

  const _RevisionShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_history_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _RevisionCard extends StatelessWidget {
  final OrderRevisionModel revision;
  final bool busy;
  final bool canApprove;
  final bool canReject;
  final bool canSubmit;
  final bool canApply;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onSubmit;
  final VoidCallback onApply;

  const _RevisionCard({
    required this.revision,
    required this.busy,
    required this.canApprove,
    required this.canReject,
    required this.canSubmit,
    required this.canApply,
    required this.onApprove,
    required this.onReject,
    required this.onSubmit,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final totalBefore = revision.originalTotals.totalAmount;
    final totalAfter = revision.proposedTotals.totalAmount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(label: Text(_statusLabel(revision.status))),
            Text('نسخة ${revision.versionNumber}'),
            Text('فرق الإجمالي: ${formatIqd(revision.priceDifference)}'),
          ],
        ),
        const SizedBox(height: 8),
        if (revision.reason.trim().isNotEmpty)
          Text('سبب التعديل: ${revision.reason}'),
        const SizedBox(height: 8),
        _TotalsDiffRow(before: totalBefore, after: totalAfter),
        const SizedBox(height: 8),
        _ItemsDiff(
          before: revision.originalItems,
          after: revision.proposedItems,
        ),
        if (revision.priceDifference > 0) ...[
          const SizedBox(height: 8),
          Text(
            'توجد زيادة مالية قدرها ${formatIqd(revision.priceDifference)} وسيتم تحصيل الفرق حسب طريقة دفع الطلب.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text('الموافقات المطلوبة: ${revision.approvalsRequired.join('، ')}'),
        if (revision.expiresAt != null)
          Text('تنتهي الموافقة: ${revision.expiresAt!.toLocal()}'),
        if (canApprove || canReject || canSubmit || canApply) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canApprove)
                FilledButton.icon(
                  onPressed: busy ? null : onApprove,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('موافقة'),
                ),
              if (canReject)
                OutlinedButton.icon(
                  onPressed: busy ? null : onReject,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('رفض'),
                ),
              if (canSubmit)
                FilledButton.icon(
                  onPressed: busy ? null : onSubmit,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('إرسال للموافقة'),
                ),
              if (canApply)
                FilledButton.icon(
                  onPressed: busy ? null : onApply,
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('تطبيق التعديل'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TotalsDiffRow extends StatelessWidget {
  final double before;
  final double after;

  const _TotalsDiffRow({required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('قبل: ${formatIqd(before)}')),
        const Icon(Icons.arrow_forward_rounded, size: 18),
        Expanded(
          child: Text(
            'بعد: ${formatIqd(after)}',
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _ItemsDiff extends StatelessWidget {
  final List<OrderRevisionLineSnapshot> before;
  final List<OrderRevisionLineSnapshot> after;

  const _ItemsDiff({required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final beforeByProduct = {for (final item in before) _lineKey(item): item};
    final afterByProduct = {for (final item in after) _lineKey(item): item};
    final keys = {...beforeByProduct.keys, ...afterByProduct.keys}.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (afterByProduct[key] ?? beforeByProduct[key])
                            ?.productName ??
                        'مادة',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${beforeByProduct[key]?.quantity ?? 0} → ${afterByProduct[key]?.quantity ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _lineKey(OrderRevisionLineSnapshot item) =>
      '${item.productId}:${item.variantId ?? 0}';
}

String _statusLabel(String status) {
  switch (status) {
    case 'DRAFT':
      return 'مسودة';
    case 'AWAITING_CUSTOMER':
      return 'بانتظار المستخدم';
    case 'AWAITING_MERCHANT':
      return 'بانتظار المتجر';
    case 'AWAITING_BOTH':
      return 'بانتظار المستخدم والمتجر';
    case 'APPROVED':
      return 'جاهز للتطبيق';
    case 'APPLIED':
      return 'مطبق';
    case 'REJECTED':
      return 'مرفوض';
    case 'FAILED':
      return 'فشل';
    case 'EXPIRED':
      return 'منتهي';
    default:
      return status;
  }
}
