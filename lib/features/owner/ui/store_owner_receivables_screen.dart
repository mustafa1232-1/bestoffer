import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../models/merchant_financial_request_model.dart';
import '../state/owner_controller.dart';
import 'widgets/merchant_financial_request_details_sheet.dart';
import 'widgets/merchant_financial_request_form_sheet.dart';

class StoreOwnerReceivablesScreen extends ConsumerStatefulWidget {
  const StoreOwnerReceivablesScreen({super.key});

  @override
  ConsumerState<StoreOwnerReceivablesScreen> createState() =>
      _StoreOwnerReceivablesScreenState();
}

class _StoreOwnerReceivablesScreenState
    extends ConsumerState<StoreOwnerReceivablesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    Future.microtask(_reload);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _reload() {
    return ref.read(ownerControllerProvider.notifier).loadMerchantReceivablesV2();
  }

  double _n(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  List<int> _selectedInvoiceIds(Map<String, dynamic> meta) {
    final raw = meta['selectedInvoiceIds'];
    if (raw is! List) return const [];
    return raw
        .map((value) => int.tryParse('$value') ?? 0)
        .where((value) => value > 0)
        .toList(growable: false);
  }

  Future<void> _showFeedback({
    required bool ok,
    required String successMessage,
    required String fallbackMessage,
  }) async {
    if (!mounted) return;
    final latestState = ref.read(ownerControllerProvider);
    final message = ok
        ? successMessage
        : (latestState.error?.trim().isNotEmpty ?? false)
            ? latestState.error!
            : fallbackMessage;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCreateRequest() async {
    final l10n = context.l10n;
    final draft = await showModalBottomSheet<MerchantFinancialRequestDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const MerchantFinancialRequestFormSheet(),
    );
    if (draft == null) return;

    final ok = await ref
        .read(ownerControllerProvider.notifier)
        .createMerchantPaymentRequestV2(
          requestType: draft.requestType,
          paymentScope: draft.paymentScope,
          amount: draft.amount,
          note: draft.note,
          paymentMethod: draft.paymentMethod,
          paymentMethodOther: draft.paymentMethodOther,
          paymentAt: draft.paymentAt,
          referenceCode: draft.referenceCode,
          receiverName: draft.receiverName,
          selectionMode: draft.selectionMode,
          selectedInvoiceIds: draft.selectedInvoiceIds,
          targetAmount: draft.targetAmount,
          confirmedAdjustedAmount: draft.confirmedAdjustedAmount,
          selectionMeta: draft.selectionMeta,
        );

    await _showFeedback(
      ok: ok,
      successMessage: l10n.ownerReceivablesSubmitSuccess,
      fallbackMessage: l10n.ownerReceivablesSubmitFailed,
    );
  }

  Future<void> _showDetails(MerchantFinancialRequestModel request) async {
    final l10n = context.l10n;
    final raw = await ref
        .read(ownerControllerProvider.notifier)
        .fetchMerchantPaymentRequestInvoicesV2(request.id);
    final invoices = List<dynamic>.from(raw?['invoices'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MerchantFinancialRequestDetailsSheet(
        request: request,
        invoices: invoices,
        onEdit: request.canEditByMerchant
            ? () async {
                Navigator.of(context).pop();
                final draft =
                    await showModalBottomSheet<MerchantFinancialRequestDraft>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => MerchantFinancialRequestFormSheet(
                    initialValue: MerchantFinancialRequestDraft(
                      requestType: request.requestType,
                      paymentScope: request.paymentScope,
                      amount: request.requestedAmount > 0
                          ? request.requestedAmount
                          : request.amount,
                      note: request.note,
                      paymentMethod: request.paymentMethod,
                      paymentMethodOther: request.paymentMethodOther,
                      paymentAt: request.paymentDate,
                      referenceCode: request.referenceCode,
                      receiverName: request.receiverName,
                      selectionMode: request.selectionMode,
                      selectedInvoiceIds: _selectedInvoiceIds(
                        request.selectionMeta,
                      ),
                      targetAmount: request.selectionMode == 'auto_match_amount'
                          ? _n(request.selectionMeta['requestedAmount'])
                          : null,
                      confirmedAdjustedAmount: _n(
                        request.selectionMeta['confirmedAdjustedAmount'],
                      ),
                      selectionMeta: request.selectionMeta,
                    ),
                  ),
                );
                if (draft == null) return;
                final ok = await ref
                    .read(ownerControllerProvider.notifier)
                    .patchMerchantPaymentRequestV2(
                      paymentRequestId: request.id,
                      paymentScope: draft.paymentScope,
                      amount: draft.amount,
                      note: draft.note,
                      paymentMethod: draft.paymentMethod,
                      paymentMethodOther: draft.paymentMethodOther,
                      paymentAt: draft.paymentAt,
                      referenceCode: draft.referenceCode,
                      receiverName: draft.receiverName,
                      selectionMode: draft.selectionMode,
                      selectedInvoiceIds: draft.selectedInvoiceIds,
                      targetAmount: draft.targetAmount,
                      confirmedAdjustedAmount: draft.confirmedAdjustedAmount,
                      selectionMeta: draft.selectionMeta,
                      resubmit: true,
                    );
                await _showFeedback(
                  ok: ok,
                  successMessage: l10n.ownerReceivablesUpdateSuccess,
                  fallbackMessage: l10n.ownerReceivablesUpdateFailed,
                );
              }
            : null,
        onConfirmReceived: request.canConfirmByMerchant
            ? () async {
                final ok = await ref
                    .read(ownerControllerProvider.notifier)
                    .confirmMerchantPaymentRequestReceivedV2(
                      paymentRequestId: request.id,
                    );
                await _showFeedback(
                  ok: ok,
                  successMessage: l10n.ownerReceivablesConfirmReceiptSuccess,
                  fallbackMessage: l10n.ownerReceivablesConfirmReceiptFailed,
                );
                if (ok && mounted) {
                  Navigator.of(context).pop();
                }
              }
            : null,
        onReportIssue: request.canConfirmByMerchant
            ? (issueNote) async {
                final ok = await ref
                    .read(ownerControllerProvider.notifier)
                    .reportMerchantPaymentRequestIssueV2(
                      paymentRequestId: request.id,
                      issueNote: issueNote,
                    );
                await _showFeedback(
                  ok: ok,
                  successMessage: l10n.ownerReceivablesIssueReportSuccess,
                  fallbackMessage: l10n.ownerReceivablesIssueReportFailed,
                );
                if (ok && mounted) {
                  Navigator.of(context).pop();
                }
              }
            : null,
      ),
    );
  }

  List<MerchantFinancialRequestModel> _requestsByType(
    List<Map<String, dynamic>> source,
    String requestType,
  ) {
    return source
        .where((row) => '${row['request_type'] ?? ''}' == requestType)
        .map(MerchantFinancialRequestModel.fromJson)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(ownerControllerProvider);
    final summary = state.merchantReceivablesV2;
    final requests = state.merchantPaymentRequestsV2;

    final storePaysApp = _requestsByType(requests, 'store_pays_app');
    final appPaysStore = _requestsByType(requests, 'app_pays_store');

    final storeBreakdown = Map<String, dynamic>.from(
      (Map<String, dynamic>.from(
        (summary['storePaysApp'] as Map?) ?? const {},
      )['breakdown'] as Map?) ??
          const {},
    );
    final appBreakdown = Map<String, dynamic>.from(
      (Map<String, dynamic>.from(
        (summary['appPaysStore'] as Map?) ?? const {},
      )['breakdown'] as Map?) ??
          const {},
    );
    final storeTotals = Map<String, dynamic>.from(
      (storeBreakdown['totals'] as Map?) ?? const {},
    );
    final appTotals = Map<String, dynamic>.from(
      (appBreakdown['totals'] as Map?) ?? const {},
    );
    final invoiceSummary = Map<String, dynamic>.from(
      (Map<String, dynamic>.from(
        (summary['receivableInvoices'] as Map?) ?? const {},
      )['summary'] as Map?) ??
          const {},
    );
    final openInvoiceCount =
        int.tryParse(
          '${Map<String, dynamic>.from(summary['receivableInvoices'] as Map? ?? const {})['openCount'] ?? 0}',
        ) ??
        0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ownerReceivablesTitle),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: l10n.ownerReceivablesTabStorePays),
            Tab(text: l10n.ownerReceivablesTabAppPays),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: state.savingOrder ? null : _openCreateRequest,
        icon: const Icon(Icons.add_card_outlined),
        label: Text(l10n.ownerReceivablesNewRequest),
      ),
      body: Column(
        children: [
          if (state.savingOrder) const LinearProgressIndicator(minHeight: 2),
          if ((state.error ?? '').trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Text(
                state.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: TabBarView(
                controller: _tab,
                children: [
                  _RequestListView(
                    title: l10n.ownerReceivablesSectionStoreDebtTitle,
                    outstanding: _n(storeTotals['outstanding']),
                    debit: _n(storeTotals['debit']),
                    credit: _n(storeTotals['credit']),
                    auxiliaryLabel: l10n.ownerReceivablesOpenInvoices,
                    auxiliaryValue:
                        '$openInvoiceCount - ${formatIqd(_n(invoiceSummary['appReceivableAmount']))}',
                    requests: storePaysApp,
                    onTapRequest: _showDetails,
                  ),
                  _RequestListView(
                    title: l10n.ownerReceivablesSectionAppDebtTitle,
                    outstanding: _n(appTotals['outstanding']),
                    debit: _n(appTotals['debit']),
                    credit: _n(appTotals['credit']),
                    auxiliaryLabel: l10n.ownerReceivablesAwaitingConfirmation,
                    auxiliaryValue:
                        '${appPaysStore.where((request) => request.canConfirmByMerchant).length}',
                    requests: appPaysStore,
                    onTapRequest: _showDetails,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestListView extends StatelessWidget {
  final String title;
  final double outstanding;
  final double debit;
  final double credit;
  final String auxiliaryLabel;
  final String auxiliaryValue;
  final List<MerchantFinancialRequestModel> requests;
  final Future<void> Function(MerchantFinancialRequestModel request) onTapRequest;

  const _RequestListView({
    required this.title,
    required this.outstanding,
    required this.debit,
    required this.credit,
    required this.auxiliaryLabel,
    required this.auxiliaryValue,
    required this.requests,
    required this.onTapRequest,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed_by_admin':
      case 'confirmed_received_by_store':
        return Colors.green;
      case 'rejected_by_admin':
      case 'cancelled':
        return Colors.red;
      case 'awaiting_store_confirmation':
      case 'pending_admin_confirmation':
      case 'pending_admin_review':
      case 'returned_for_revision':
      case 'issue_reported_by_store':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _statusLabel(BuildContext context, String status) {
    final l10n = context.l10n;
    return switch (status) {
      'pending_admin_confirmation' =>
        l10n.ownerReceivablesStatusAwaitingAdminApproval,
      'pending_admin_review' => l10n.ownerReceivablesStatusAwaitingReview,
      'returned_for_revision' =>
        l10n.ownerReceivablesStatusReturnedForRevision,
      'approved_by_admin' => l10n.ownerReceivablesStatusApproved,
      'assigned_for_payment' => l10n.ownerReceivablesStatusAssignedForPayment,
      'awaiting_store_confirmation' =>
        l10n.ownerReceivablesStatusAwaitingStoreConfirmation,
      'confirmed_by_admin' => l10n.ownerReceivablesStatusConfirmedByAdmin,
      'confirmed_received_by_store' =>
        l10n.ownerReceivablesStatusReceiptConfirmed,
      'rejected_by_admin' => l10n.commonRejected,
      'issue_reported_by_store' => l10n.ownerReceivablesStatusIssueReported,
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SummaryChip(
              label: l10n.commonOutstanding,
              value: formatIqd(outstanding),
            ),
            _SummaryChip(
              label: l10n.ownerReceivablesTotalDebit,
              value: formatIqd(debit),
            ),
            _SummaryChip(
              label: l10n.ownerReceivablesTotalCredit,
              value: formatIqd(credit),
            ),
            _SummaryChip(label: auxiliaryLabel, value: auxiliaryValue),
          ],
        ),
        const SizedBox(height: 12),
        if (requests.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(
              child: Text(l10n.ownerReceivablesNoRequestsInSection),
            ),
          )
        else
          ...requests.map((request) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => onTapRequest(request),
                title: Text('#${request.id} - ${formatIqd(request.requestedAmount)}'),
                subtitle: Text(
                  '${l10n.commonStatus}: ${_statusLabel(context, request.status)}\n'
                  '${l10n.commonLinkedInvoices}: ${request.linkedInvoiceCount}',
                ),
                trailing: Chip(
                  label: Text(_statusLabel(context, request.status)),
                  backgroundColor: _statusColor(request.status).withValues(alpha: 0.12),
                  side: BorderSide(color: _statusColor(request.status)),
                  labelStyle: TextStyle(
                    color: _statusColor(request.status),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 90),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
