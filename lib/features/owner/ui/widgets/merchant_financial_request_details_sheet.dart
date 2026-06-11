import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/utils/currency.dart';
import '../../models/merchant_financial_request_model.dart';

class MerchantFinancialRequestDetailsSheet extends StatelessWidget {
  final MerchantFinancialRequestModel request;
  final List<Map<String, dynamic>> invoices;
  final Future<void> Function()? onConfirmReceived;
  final Future<void> Function(String issueNote)? onReportIssue;
  final Future<void> Function()? onEdit;

  const MerchantFinancialRequestDetailsSheet({
    super.key,
    required this.request,
    this.invoices = const [],
    this.onConfirmReceived,
    this.onReportIssue,
    this.onEdit,
  });

  double _n(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  String _paymentMethodLabel(BuildContext context, String? method) {
    final l10n = context.l10n;
    switch (method) {
      case 'cash':
        return l10n.ownerFinancialRequestPaymentMethodCash;
      case 'bank_transfer':
        return l10n.ownerFinancialRequestPaymentMethodBankTransfer;
      case 'zain_cash':
        return l10n.ownerFinancialRequestPaymentMethodZainCash;
      case 'asiacell_cash':
        return l10n.ownerFinancialRequestPaymentMethodAsiacellCash;
      case 'manual_handover':
        return l10n.ownerFinancialRequestPaymentMethodManualHandover;
      case 'other':
        return l10n.ownerFinancialRequestPaymentMethodOther;
      default:
        return l10n.ownerFinancialRequestPaymentMethodNotSet;
    }
  }

  String _requestTypeLabel(BuildContext context, String requestType) {
    return requestType == 'app_pays_store'
        ? context.l10n.ownerFinancialRequestTypeAppPaysStore
        : context.l10n.ownerFinancialRequestTypeStorePaysApp;
  }

  Future<void> _askIssue(BuildContext context) async {
    if (onReportIssue == null) return;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.ownerFinancialRequestReportIssueTitle),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: context.l10n.ownerFinancialRequestReportIssueHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.ownerFinancialRequestSend),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final note = controller.text.trim();
    if (note.isEmpty) return;
    await onReportIssue!(note);
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 5, child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '#${request.id} - ${_requestTypeLabel(context, request.requestType)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _detailRow(context, l10n.commonStatus, request.status),
              _detailRow(
                context,
                l10n.ownerFinancialRequestRequestedAmount,
                formatIqd(request.requestedAmount),
              ),
              _detailRow(
                context,
                l10n.ownerFinancialRequestPaidAmount,
                formatIqd(request.paidAmount),
              ),
              _detailRow(
                context,
                l10n.ownerFinancialRequestPaymentMethod,
                request.paymentMethod == 'other' &&
                        (request.paymentMethodOther ?? '').isNotEmpty
                    ? '${_paymentMethodLabel(context, request.paymentMethod)} - ${request.paymentMethodOther}'
                    : _paymentMethodLabel(context, request.paymentMethod),
              ),
              if ((request.paymentDate ?? '').isNotEmpty)
                _detailRow(
                  context,
                  l10n.ownerFinancialRequestPaymentDate,
                  request.paymentDate!,
                ),
              if ((request.referenceCode ?? '').isNotEmpty)
                _detailRow(
                  context,
                  l10n.ownerFinancialRequestReference,
                  request.referenceCode!,
                ),
              if ((request.receiverName ?? '').isNotEmpty)
                _detailRow(
                  context,
                  l10n.ownerFinancialRequestReceiverName,
                  request.receiverName!,
                ),
              if ((request.note ?? '').isNotEmpty)
                _detailRow(context, l10n.ownerFinancialRequestNotes, request.note!),
              if ((request.reviewNote ?? '').isNotEmpty)
                _detailRow(
                  context,
                  l10n.ownerFinancialRequestReviewNote,
                  request.reviewNote!,
                ),
              if ((request.internalAdminNote ?? '').isNotEmpty)
                _detailRow(
                  context,
                  l10n.ownerFinancialRequestInternalAdminNote,
                  request.internalAdminNote!,
                ),
              const SizedBox(height: 12),
              Text(
                l10n.ownerFinancialRequestLinkedInvoices,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (invoices.isEmpty)
                Text(l10n.ownerFinancialRequestNoLinkedInvoices)
              else
                ...invoices.map((invoice) {
                  final invoiceNumber = '${invoice['invoice_number'] ?? '-'}';
                  final orderId = '${invoice['order_id'] ?? '-'}';
                  final allocatedAmount = _n(invoice['allocated_amount']);
                  final outstandingAmount = _n(invoice['outstanding_amount']);
                  final invoiceStatus = '${invoice['invoice_status'] ?? '-'}';
                  final issuedAt = '${invoice['issued_at'] ?? ''}'.trim();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text('$invoiceNumber - #$orderId'),
                      subtitle: Text(
                        '${l10n.ownerFinancialRequestAllocatedAmount}: ${formatIqd(allocatedAmount)}\n'
                        '${l10n.ownerFinancialRequestOutstanding}: ${formatIqd(outstandingAmount)}\n'
                        '${l10n.commonStatus}: $invoiceStatus'
                        '${issuedAt.isEmpty ? '' : '\n${l10n.ownerFinancialRequestDate}: $issuedAt'}',
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (request.canEditByMerchant && onEdit != null)
                    OutlinedButton(
                      onPressed: onEdit,
                      child: Text(l10n.commonEdit),
                    ),
                  if (request.canConfirmByMerchant && onConfirmReceived != null)
                    ElevatedButton.icon(
                      onPressed: onConfirmReceived,
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(l10n.ownerFinancialRequestConfirmReceipt),
                    ),
                  if (request.canConfirmByMerchant && onReportIssue != null)
                    OutlinedButton.icon(
                      onPressed: () => _askIssue(context),
                      icon: const Icon(Icons.report_gmailerrorred_outlined),
                      label: Text(l10n.ownerFinancialRequestReportIssueAction),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
