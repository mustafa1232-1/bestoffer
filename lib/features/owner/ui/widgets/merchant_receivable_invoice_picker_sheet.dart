import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/utils/currency.dart';
import '../../models/merchant_receivable_invoice_model.dart';

class MerchantReceivableInvoicePickerSheet extends StatefulWidget {
  final List<MerchantReceivableInvoiceModel> invoices;
  final Set<int> initialSelection;

  const MerchantReceivableInvoicePickerSheet({
    super.key,
    required this.invoices,
    required this.initialSelection,
  });

  @override
  State<MerchantReceivableInvoicePickerSheet> createState() =>
      _MerchantReceivableInvoicePickerSheetState();
}

class _MerchantReceivableInvoicePickerSheetState
    extends State<MerchantReceivableInvoicePickerSheet> {
  late final Set<int> _selected = {...widget.initialSelection};

  double get _selectedOutstanding {
    return widget.invoices
        .where((invoice) => _selected.contains(invoice.id))
        .fold<double>(0, (sum, invoice) => sum + invoice.outstandingAmount);
  }

  void _selectAll(bool enabled) {
    setState(() {
      if (enabled) {
        _selected
          ..clear()
          ..addAll(widget.invoices.map((invoice) => invoice.id));
      } else {
        _selected.clear();
      }
    });
  }

  String _statusLabel(BuildContext context, String status) {
    final l10n = context.l10n;
    switch (status) {
      case 'paid':
        return l10n.ownerInvoicePickerStatusPaid;
      case 'partially_paid':
        return l10n.ownerInvoicePickerStatusPartiallyPaid;
      default:
        return l10n.ownerInvoicePickerStatusUnpaid;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final allSelected =
        widget.invoices.isNotEmpty &&
        _selected.length == widget.invoices.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.ownerInvoicePickerTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (widget.invoices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    l10n.ownerInvoicePickerEmpty,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _selectAll(true),
                    icon: const Icon(Icons.done_all_rounded),
                    label: Text(l10n.ownerInvoicePickerSelectAll),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _selectAll(false),
                    icon: const Icon(Icons.remove_done_rounded),
                    label: Text(l10n.ownerInvoicePickerClearSelection),
                  ),
                  FilterChip(
                    selected: allSelected,
                    onSelected: _selectAll,
                    label: Text(l10n.ownerInvoicePickerAllSelected),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.invoices.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final invoice = widget.invoices[index];
                    final selected = _selected.contains(invoice.id);
                    return CheckboxListTile(
                      value: selected,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selected.add(invoice.id);
                          } else {
                            _selected.remove(invoice.id);
                          }
                        });
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      tileColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      title: Text(
                        '${invoice.invoiceNumber} • #${invoice.orderId}',
                      ),
                      subtitle: Text(
                        '${l10n.commonOutstanding}: ${formatIqd(invoice.outstandingAmount)}\n'
                        '${l10n.commonStatus}: ${_statusLabel(context, invoice.invoiceStatus)}',
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.ownerInvoicePickerSelectedCount(_selected.length),
                      ),
                    ),
                    Text(
                      formatIqd(_selectedOutstanding),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.invoices.isEmpty
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(_selected.toList(growable: false)),
                    child: Text(l10n.commonApply),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
