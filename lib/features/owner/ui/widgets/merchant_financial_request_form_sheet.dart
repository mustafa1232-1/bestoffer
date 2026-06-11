import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/utils/currency.dart';
import '../../models/merchant_payment_selection_preview_model.dart';
import '../../models/merchant_receivable_invoice_model.dart';
import '../../state/owner_controller.dart';
import 'merchant_auto_match_suggestion_sheet.dart';
import 'merchant_receivable_invoice_picker_sheet.dart';

class MerchantFinancialRequestDraft {
  final String requestType;
  final String paymentScope;
  final double? amount;
  final String? note;
  final String? paymentMethod;
  final String? paymentMethodOther;
  final String? paymentAt;
  final String? referenceCode;
  final String? receiverName;
  final String? selectionMode;
  final List<int> selectedInvoiceIds;
  final double? targetAmount;
  final double? confirmedAdjustedAmount;
  final Map<String, dynamic>? selectionMeta;

  const MerchantFinancialRequestDraft({
    required this.requestType,
    required this.paymentScope,
    this.amount,
    this.note,
    this.paymentMethod,
    this.paymentMethodOther,
    this.paymentAt,
    this.referenceCode,
    this.receiverName,
    this.selectionMode,
    this.selectedInvoiceIds = const [],
    this.targetAmount,
    this.confirmedAdjustedAmount,
    this.selectionMeta,
  });
}

class MerchantFinancialRequestFormSheet extends ConsumerStatefulWidget {
  final MerchantFinancialRequestDraft? initialValue;

  const MerchantFinancialRequestFormSheet({super.key, this.initialValue});

  @override
  ConsumerState<MerchantFinancialRequestFormSheet> createState() =>
      _MerchantFinancialRequestFormSheetState();
}

class _MerchantFinancialRequestFormSheetState
    extends ConsumerState<MerchantFinancialRequestFormSheet> {
  static const _paymentMethods = <String, String>{
    'cash': 'cash',
    'bank_transfer': 'bank_transfer',
    'zain_cash': 'zain_cash',
    'asiacell_cash': 'asiacell_cash',
    'manual_handover': 'manual_handover',
    'other': 'other',
  };

  late String _requestType;
  late String _selectionMode;
  String? _paymentMethod;
  DateTime? _paymentAt;
  final _amountCtrl = TextEditingController();
  final _targetAmountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _receiverCtrl = TextEditingController();
  final _paymentMethodOtherCtrl = TextEditingController();
  bool _loadingInvoices = false;
  bool _buildingPreview = false;
  List<int> _selectedInvoiceIds = const [];
  MerchantPaymentSelectionPreviewModel? _preview;
  double? _confirmedAdjustedAmount;

  bool get _isStorePaysApp => _requestType == 'store_pays_app';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _requestType = initial?.requestType ?? 'store_pays_app';
    _selectionMode = initial?.selectionMode ?? 'all_invoices';
    _paymentMethod = initial?.paymentMethod;
    _paymentAt = initial?.paymentAt == null
        ? null
        : DateTime.tryParse(initial!.paymentAt!);
    _amountCtrl.text = initial?.amount == null
        ? ''
        : initial!.amount!.toStringAsFixed(0);
    _targetAmountCtrl.text = initial?.targetAmount == null
        ? ''
        : initial!.targetAmount!.toStringAsFixed(0);
    _noteCtrl.text = initial?.note ?? '';
    _referenceCtrl.text = initial?.referenceCode ?? '';
    _receiverCtrl.text = initial?.receiverName ?? '';
    _paymentMethodOtherCtrl.text = initial?.paymentMethodOther ?? '';
    _selectedInvoiceIds = List<int>.from(initial?.selectedInvoiceIds ?? const []);
    _confirmedAdjustedAmount = initial?.confirmedAdjustedAmount;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _targetAmountCtrl.dispose();
    _noteCtrl.dispose();
    _referenceCtrl.dispose();
    _receiverCtrl.dispose();
    _paymentMethodOtherCtrl.dispose();
    super.dispose();
  }

  String _paymentMethodLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    switch (value) {
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
        return value;
    }
  }

  String _selectionModeLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    switch (value) {
      case 'all_invoices':
        return l10n.ownerFinancialRequestSelectionAllInvoices;
      case 'manual_selection':
        return l10n.ownerFinancialRequestSelectionPickInvoices;
      case 'auto_match_amount':
        return l10n.ownerFinancialRequestSelectionMatchAmount;
      default:
        return value;
    }
  }

  String? _formatDateTime(DateTime? value) {
    if (value == null) return null;
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  Future<void> _pickPaymentDateTime() async {
    final now = DateTime.now();
    final initialDate = _paymentAt ?? now;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 3),
      initialDate: initialDate,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_paymentAt ?? now),
    );
    if (time == null) return;
    setState(() {
      _paymentAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickInvoices() async {
    setState(() => _loadingInvoices = true);
    final invoicesRaw = await ref
        .read(ownerControllerProvider.notifier)
        .fetchMerchantReceivableInvoicesV2();
    if (!mounted) return;
    setState(() => _loadingInvoices = false);
    final invoices = invoicesRaw
        .map(MerchantReceivableInvoiceModel.fromJson)
        .toList(growable: false);
    final selected = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MerchantReceivableInvoicePickerSheet(
        invoices: invoices,
        initialSelection: _selectedInvoiceIds.toSet(),
      ),
    );
    if (selected == null) return;
    setState(() {
      _selectedInvoiceIds = selected;
      _preview = null;
      _confirmedAdjustedAmount = null;
    });
  }

  double? _readDouble(TextEditingController controller) {
    final value = controller.text.trim().replaceAll(',', '');
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  Future<MerchantPaymentSelectionPreviewModel?> _buildPreview({
    double? confirmedAdjustedAmount,
  }) async {
    setState(() => _buildingPreview = true);
    final raw = await ref
        .read(ownerControllerProvider.notifier)
        .previewMerchantPaymentSelectionV2(
          selectionMode: _selectionMode,
          selectedInvoiceIds: _selectedInvoiceIds,
          amount: _selectionMode == 'auto_match_amount'
              ? null
              : _readDouble(_amountCtrl),
          targetAmount: _selectionMode == 'auto_match_amount'
              ? _readDouble(_targetAmountCtrl)
              : null,
          confirmedAdjustedAmount:
              confirmedAdjustedAmount ?? _confirmedAdjustedAmount,
        );
    if (!mounted) return null;
    setState(() => _buildingPreview = false);
    if (raw == null) return null;
    final preview = MerchantPaymentSelectionPreviewModel.fromJson(
      Map<String, dynamic>.from((raw['preview'] as Map?) ?? const {}),
    );
    if (preview.requiresAmountConfirmation) {
      final approvedAmount = await showModalBottomSheet<double>(
        context: context,
        builder: (_) => MerchantAutoMatchSuggestionSheet(preview: preview),
      );
      if (approvedAmount == null) return null;
      setState(() => _confirmedAdjustedAmount = approvedAmount);
      return _buildPreview(confirmedAdjustedAmount: approvedAmount);
    }
    setState(() {
      _preview = preview;
      _selectedInvoiceIds = preview.selectedInvoiceIds;
      _amountCtrl.text = preview.finalizedAmount.toStringAsFixed(0);
    });
    return preview;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (_paymentMethod == null || _paymentMethod!.isEmpty) {
      _showMessage(l10n.ownerFinancialRequestChoosePaymentMethod);
      return;
    }
    if (_paymentMethod == 'other' && _paymentMethodOtherCtrl.text.trim().isEmpty) {
      _showMessage(l10n.ownerFinancialRequestDescribeOtherPaymentMethodError);
      return;
    }
    if (_paymentAt == null) {
      _showMessage(l10n.ownerFinancialRequestChoosePaymentDateTime);
      return;
    }

    MerchantPaymentSelectionPreviewModel? preview = _preview;
    if (_isStorePaysApp) {
      if (_selectionMode == 'manual_selection' && _selectedInvoiceIds.isEmpty) {
        _showMessage(l10n.ownerFinancialRequestSelectInvoice);
        return;
      }
      preview = await _buildPreview();
      if (preview == null) return;
    } else {
      final amount = _readDouble(_amountCtrl);
      if (amount == null || amount <= 0) {
        _showMessage(l10n.ownerFinancialRequestEnterValidAmount);
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      MerchantFinancialRequestDraft(
        requestType: _requestType,
        paymentScope: 'all',
        amount: _isStorePaysApp ? preview?.finalizedAmount : _readDouble(_amountCtrl),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        paymentMethod: _paymentMethod,
        paymentMethodOther: _paymentMethod == 'other'
            ? _paymentMethodOtherCtrl.text.trim()
            : null,
        paymentAt: _paymentAt?.toUtc().toIso8601String(),
        referenceCode: _referenceCtrl.text.trim().isEmpty
            ? null
            : _referenceCtrl.text.trim(),
        receiverName: _receiverCtrl.text.trim().isEmpty
            ? null
            : _receiverCtrl.text.trim(),
        selectionMode: _isStorePaysApp ? _selectionMode : null,
        selectedInvoiceIds: _isStorePaysApp ? _selectedInvoiceIds : const [],
        targetAmount: _selectionMode == 'auto_match_amount'
            ? _readDouble(_targetAmountCtrl)
            : null,
        confirmedAdjustedAmount: _confirmedAdjustedAmount,
        selectionMeta: _isStorePaysApp && preview != null
            ? {
                'requestedAmount': preview.requestedAmount,
                'finalizedAmount': preview.finalizedAmount,
                'exactMatch': preview.exactMatch,
                'adjustmentDirection': preview.adjustmentDirection,
                'nearestLowerAmount': preview.nearestLowerAmount,
                'nearestHigherAmount': preview.nearestHigherAmount,
                'confirmedAdjustedAmount': preview.confirmedAdjustedAmount,
                'selectedInvoiceIds': preview.selectedInvoiceIds,
                'invoiceCount': preview.summary.invoicesCount,
                'oldestIssuedAt': preview.summary.oldestIssuedAt,
                'latestIssuedAt': preview.summary.latestIssuedAt,
                'summary': {
                  'invoicesCount': preview.summary.invoicesCount,
                  'subtotal': preview.summary.subtotal,
                  'commissionAmount': preview.summary.commissionAmount,
                  'serviceFeeAmount': preview.summary.serviceFeeAmount,
                  'appDeliveryFeeAmount': preview.summary.appDeliveryFeeAmount,
                  'storeDeliveryFeeAmount': preview.summary.storeDeliveryFeeAmount,
                  'appReceivableAmount': preview.summary.appReceivableAmount,
                  'storeNetAmount': preview.summary.storeNetAmount,
                  'oldestIssuedAt': preview.summary.oldestIssuedAt,
                  'latestIssuedAt': preview.summary.latestIssuedAt,
                },
              }
            : null,
      ),
    );
  }

  Widget _buildSelectionSection() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('selection-mode-$_selectionMode'),
          initialValue: _selectionMode,
          decoration: InputDecoration(
            labelText: l10n.ownerFinancialRequestInvoiceSelectionMode,
          ),
          items: [
            DropdownMenuItem(
              value: 'all_invoices',
              child: Text(l10n.ownerFinancialRequestSelectionAllInvoices),
            ),
            DropdownMenuItem(
              value: 'manual_selection',
              child: Text(l10n.ownerFinancialRequestSelectionPickInvoices),
            ),
            DropdownMenuItem(
              value: 'auto_match_amount',
              child: Text(l10n.ownerFinancialRequestSelectionMatchAmount),
            ),
          ],
          selectedItemBuilder: (context) => [
            'all_invoices',
            'manual_selection',
            'auto_match_amount',
          ]
              .map(
                (value) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(_selectionModeLabel(context, value)),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            setState(() {
              _selectionMode = value ?? 'all_invoices';
              _preview = null;
              _confirmedAdjustedAmount = null;
              if (_selectionMode != 'manual_selection') {
                _selectedInvoiceIds = const [];
              }
            });
          },
        ),
        const SizedBox(height: 10),
        if (_selectionMode == 'manual_selection') ...[
          OutlinedButton.icon(
            onPressed: _loadingInvoices ? null : _pickInvoices,
            icon: _loadingInvoices
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
            label: Text(l10n.ownerFinancialRequestChooseInvoices),
          ),
          if (_selectedInvoiceIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.ownerFinancialRequestInvoicesSelected(
                  '${_selectedInvoiceIds.length}',
                ),
              ),
            ),
        ] else if (_selectionMode == 'auto_match_amount') ...[
          TextField(
            controller: _targetAmountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.ownerFinancialRequestTargetAmountToMatch,
            ),
          ),
        ] else ...[
          Text(l10n.ownerFinancialRequestLinkAllOpenInvoices),
        ],
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _buildingPreview ? null : _buildPreview,
          icon: _buildingPreview
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.preview_outlined),
          label: Text(l10n.ownerFinancialRequestPreviewMatching),
        ),
        if (_preview != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _preview!.message,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '${l10n.ownerFinancialRequestInvoicesCount}: ${_preview!.summary.invoicesCount}',
                ),
                Text(
                  '${l10n.ownerFinancialRequestFinalTotal}: ${formatIqd(_preview!.finalizedAmount)}',
                ),
                if (_preview!.summary.oldestIssuedAt != null)
                  Text(
                    '${l10n.ownerFinancialRequestOldestInvoice}: ${_preview!.summary.oldestIssuedAt}',
                  ),
                if (_preview!.summary.latestIssuedAt != null)
                  Text(
                    '${l10n.ownerFinancialRequestLatestInvoice}: ${_preview!.summary.latestIssuedAt}',
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.ownerFinancialRequestTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('request-type-$_requestType'),
                initialValue: _requestType,
                decoration: InputDecoration(
                  labelText: l10n.ownerFinancialRequestType,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'store_pays_app',
                    child: Text(l10n.ownerFinancialRequestTypeStorePaysApp),
                  ),
                  DropdownMenuItem(
                    value: 'app_pays_store',
                    child: Text(l10n.ownerFinancialRequestTypeAppPaysStore),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _requestType = value ?? 'store_pays_app';
                    _preview = null;
                  });
                },
              ),
              const SizedBox(height: 10),
              if (_isStorePaysApp) _buildSelectionSection() else ...[
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: l10n.ownerFinancialRequestRequestedAmount,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('payment-method-${_paymentMethod ?? 'none'}'),
                initialValue: _paymentMethod,
                decoration: InputDecoration(
                  labelText: l10n.ownerFinancialRequestPaymentMethod,
                ),
                items: _paymentMethods.keys
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_paymentMethodLabel(context, value)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _paymentMethod = value),
              ),
              if (_paymentMethod == 'other') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _paymentMethodOtherCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.ownerFinancialRequestDescribeOtherMethod,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickPaymentDateTime,
                icon: const Icon(Icons.event_rounded),
                label: Text(
                  _formatDateTime(_paymentAt) ??
                      l10n.ownerFinancialRequestPickDateTime,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _referenceCtrl,
                decoration: InputDecoration(
                  labelText: l10n.ownerFinancialRequestReferenceCode,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _receiverCtrl,
                decoration: InputDecoration(
                  labelText: l10n.ownerFinancialRequestReceiverName,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.ownerFinancialRequestNotes,
                ),
              ),
              const SizedBox(height: 16),
              if (_isStorePaysApp && _preview != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${l10n.ownerFinancialRequestFinalAmount}: ${formatIqd(_preview!.finalizedAmount)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
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
                      onPressed: _submit,
                      child: Text(l10n.commonContinue),
                    ),
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
