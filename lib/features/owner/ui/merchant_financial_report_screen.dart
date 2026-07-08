import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../models/merchant_financial_request_model.dart';
import '../models/merchant_receivable_invoice_model.dart';
import '../state/owner_controller.dart';

enum MerchantFinancialReportType {
  sales,
  commission,
  serviceFee,
  appDelivery,
  storeDelivery,
  netSales,
  appDue,
  paidAmount,
  remaining,
}

class MerchantFinancialReportScreen extends ConsumerStatefulWidget {
  final MerchantFinancialReportType reportType;

  const MerchantFinancialReportScreen({
    super.key,
    required this.reportType,
  });

  @override
  ConsumerState<MerchantFinancialReportScreen> createState() =>
      _MerchantFinancialReportScreenState();
}

class _MerchantFinancialReportScreenState
    extends ConsumerState<MerchantFinancialReportScreen> {
  String _period = 'all';
  DateTime? _from;
  DateTime? _to;
  bool _loading = false;
  String? _error;
  List<MerchantReceivableInvoiceModel> _invoices = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim())?.toLocal();
  }

  String? _iso(DateTime? value, {bool endOfDay = false}) {
    if (value == null) return null;
    final normalized = endOfDay
        ? DateTime(value.year, value.month, value.day, 23, 59, 59)
        : DateTime(value.year, value.month, value.day);
    return normalized.toUtc().toIso8601String();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: _from ?? now.subtract(const Duration(days: 30)),
        end: _to ?? now,
      ),
      locale: Localizations.localeOf(context),
    );
    if (range == null) return;
    setState(() {
      _from = range.start;
      _to = range.end;
      _period = 'custom';
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final controller = ref.read(ownerControllerProvider.notifier);
    try {
      final invoicesRaw = await controller.fetchMerchantReceivableInvoicesV2(
        limit: 2000,
        period: _period,
        from: _iso(_from),
        to: _iso(_to, endOfDay: true),
        onlyOpen: false,
      );
      await controller.loadMerchantReceivablesV2(silent: true);
      if (!mounted) return;
      setState(() {
        _invoices = invoicesRaw
            .map(MerchantReceivableInvoiceModel.fromJson)
            .toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.ownerFinancialReportLoadFailed;
      });
    }
  }

  List<MerchantFinancialRequestModel> get _confirmedPayments {
    final requests = ref.watch(ownerControllerProvider).merchantPaymentRequestsV2;
    final start = _period == 'custom' ? _from : null;
    final end = _period == 'custom' ? _to : null;

    bool within(DateTime? value) {
      if (value == null) return false;
      if (_period == 'all') return true;
      final now = DateTime.now();
      final target = DateTime(value.year, value.month, value.day);
      if (_period == 'day') {
        final today = DateTime(now.year, now.month, now.day);
        return target == today;
      }
      if (_period == 'yesterday') {
        final yesterday = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 1));
        return target == yesterday;
      }
      if (_period == 'week') {
        final today = DateTime(now.year, now.month, now.day);
        final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return !target.isBefore(startOfWeek) && !target.isAfter(endOfWeek);
      }
      if (_period == 'month') {
        return value.year == now.year && value.month == now.month;
      }
      if (_period == 'year') {
        return value.year == now.year;
      }
      if (_period == 'custom' && start != null && end != null) {
        final begin = DateTime(start.year, start.month, start.day);
        final finish = DateTime(end.year, end.month, end.day, 23, 59, 59);
        return !value.isBefore(begin) && !value.isAfter(finish);
      }
      return true;
    }

    return requests
        .map(MerchantFinancialRequestModel.fromJson)
        .where(
          (request) =>
              request.requestType == 'store_pays_app' &&
              request.status == 'confirmed_by_admin' &&
              within(
                _parseDate(request.paymentDate) ??
                    _parseDate(request.updatedAt) ??
                    _parseDate(request.createdAt),
              ),
        )
        .toList(growable: false);
  }

  double get _confirmedPaidAmount {
    return _confirmedPayments.fold<double>(
      0,
      (sum, request) =>
          sum +
          (request.paidAmount > 0
              ? request.paidAmount
              : request.requestedAmount > 0
                  ? request.requestedAmount
                  : request.amount),
    );
  }

  String _title(BuildContext context) {
    final l10n = context.l10n;
    return switch (widget.reportType) {
      MerchantFinancialReportType.sales => l10n.ownerFinancialReportTitleSales,
      MerchantFinancialReportType.commission =>
        l10n.ownerFinancialReportTitleCommission,
      MerchantFinancialReportType.serviceFee =>
        l10n.ownerFinancialReportTitleServiceFee,
      MerchantFinancialReportType.appDelivery =>
        l10n.ownerFinancialReportTitleAppDelivery,
      MerchantFinancialReportType.storeDelivery =>
        l10n.ownerFinancialReportTitleStoreDelivery,
      MerchantFinancialReportType.netSales =>
        l10n.ownerFinancialReportTitleNetSales,
      MerchantFinancialReportType.appDue => l10n.ownerFinancialReportTitleAppDue,
      MerchantFinancialReportType.paidAmount =>
        l10n.ownerFinancialReportTitlePaidAmount,
      MerchantFinancialReportType.remaining =>
        l10n.ownerFinancialReportTitleRemaining,
    };
  }

  String _periodLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (_period) {
      'day' => l10n.commonToday,
      'yesterday' => l10n.commonYesterday,
      'week' => l10n.commonThisWeek,
      'month' => l10n.commonThisMonth,
      'year' => l10n.commonThisYear,
      'custom' =>
        _from == null || _to == null
            ? l10n.commonCustomRange
            : '${DateFormat('yyyy-MM-dd').format(_from!)} - ${DateFormat('yyyy-MM-dd').format(_to!)}',
      _ => l10n.commonAllTime,
    };
  }

  List<MerchantReceivableInvoiceModel> get _invoiceRows {
    switch (widget.reportType) {
      case MerchantFinancialReportType.sales:
        return _invoices.where((invoice) => invoice.subtotal > 0).toList();
      case MerchantFinancialReportType.commission:
        return _invoices
            .where((invoice) => invoice.commissionAmount > 0)
            .toList();
      case MerchantFinancialReportType.serviceFee:
        return _invoices
            .where((invoice) => invoice.serviceFeeAmount > 0)
            .toList();
      case MerchantFinancialReportType.appDelivery:
        return _invoices
            .where((invoice) => invoice.appDeliveryFeeAmount > 0)
            .toList();
      case MerchantFinancialReportType.storeDelivery:
        return _invoices
            .where((invoice) => invoice.storeDeliveryFeeAmount > 0)
            .toList();
      case MerchantFinancialReportType.netSales:
      case MerchantFinancialReportType.appDue:
        return _invoices;
      case MerchantFinancialReportType.remaining:
        return _invoices
            .where((invoice) => invoice.outstandingAmount > 0)
            .toList();
      case MerchantFinancialReportType.paidAmount:
        return const [];
    }
  }

  double _metricValue(MerchantReceivableInvoiceModel invoice) {
    switch (widget.reportType) {
      case MerchantFinancialReportType.sales:
        return invoice.subtotal;
      case MerchantFinancialReportType.commission:
        return invoice.commissionAmount;
      case MerchantFinancialReportType.serviceFee:
        return invoice.serviceFeeAmount;
      case MerchantFinancialReportType.appDelivery:
        return invoice.appDeliveryFeeAmount;
      case MerchantFinancialReportType.storeDelivery:
        return invoice.storeDeliveryFeeAmount;
      case MerchantFinancialReportType.netSales:
        return invoice.effectiveStoreNetReceivedAmount;
      case MerchantFinancialReportType.appDue:
        return invoice.effectiveAppDueFromDelivery;
      case MerchantFinancialReportType.remaining:
        return invoice.outstandingAmount;
      case MerchantFinancialReportType.paidAmount:
        return 0;
    }
  }

  double get _totalValue {
    if (widget.reportType == MerchantFinancialReportType.paidAmount) {
      return _confirmedPaidAmount;
    }
    if (widget.reportType == MerchantFinancialReportType.appDue) {
      return _invoiceRows.fold<double>(
        0,
        (sum, invoice) => sum + invoice.appReceivableAmount,
      );
    }
    return _invoiceRows.fold<double>(
      0,
      (sum, invoice) => sum + _metricValue(invoice),
    );
  }

  Widget _buildPeriodChips(BuildContext context) {
    final l10n = context.l10n;

    Widget chip(String code, String label) {
      return ChoiceChip(
        selected: _period == code,
        label: Text(label),
        onSelected: (_) async {
          if (code == 'custom') {
            await _pickCustomRange();
            return;
          }
          setState(() => _period = code);
          await _load();
        },
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('all', l10n.commonAll),
        chip('day', l10n.commonToday),
        chip('yesterday', l10n.commonYesterday),
        chip('week', l10n.commonWeek),
        chip('month', l10n.commonMonth),
        chip('year', l10n.commonYear),
        chip('custom', l10n.commonCustom),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final payments = _confirmedPayments;
    final totalDue = _invoiceRows.fold<double>(
      0,
      (sum, invoice) => sum + invoice.appReceivableAmount,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(context)),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            _buildPeriodChips(context),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: Text(_title(context)),
                subtitle: Text('${l10n.commonPeriod}: ${_periodLabel(context)}'),
                trailing: Text(
                  formatIqd(_totalValue),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            if (widget.reportType == MerchantFinancialReportType.appDue)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.ownerFinancialReportDueAndPaidSummary,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text('${l10n.commonTotalDue}: ${formatIqd(totalDue)}'),
                      Text(
                        '${l10n.commonConfirmedPaid}: ${formatIqd(_confirmedPaidAmount)}',
                      ),
                      Text(
                        '${l10n.commonRemaining}: ${formatIqd(totalDue - _confirmedPaidAmount)}',
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.reportType == MerchantFinancialReportType.paidAmount &&
                payments.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Center(
                  child: Text(l10n.ownerFinancialReportNoConfirmedPayments),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _load,
                        child: Text(l10n.commonRetry),
                      ),
                    ],
                  ),
                ),
              )
            else if (widget.reportType == MerchantFinancialReportType.paidAmount)
              ...payments.map(
                (request) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      '#${request.id} - ${formatIqd(request.paidAmount > 0 ? request.paidAmount : request.requestedAmount)}',
                    ),
                    subtitle: Text(
                      '${l10n.commonMethod}: ${request.paymentMethod ?? '-'}\n'
                      '${l10n.commonLinkedInvoices}: ${request.linkedInvoiceCount}',
                    ),
                  ),
                ),
              )
            else if (_invoiceRows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Center(
                  child: Text(l10n.ownerFinancialReportNoDataForPeriod),
                ),
              )
            else
              ..._invoiceRows.map((invoice) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${invoice.invoiceNumber} - #${invoice.orderId}'),
                    subtitle: Text(
                      '${l10n.commonMetric}: ${formatIqd(_metricValue(invoice))}\n'
                      'Service fee: ${formatIqd(invoice.serviceFeeAmount)}\n'
                      'Commission: ${formatIqd(invoice.commissionAmount)}\n'
                      'Delivery fee: ${formatIqd(invoice.appDeliveryFeeAmount + invoice.storeDeliveryFeeAmount)}\n'
                      'Store net received: ${formatIqd(invoice.effectiveStoreNetReceivedAmount)}\n'
                      'App due from delivery: ${formatIqd(invoice.effectiveAppDueFromDelivery)}\n'
                      'Difference: ${formatIqd(invoice.differenceAmount)}\n'
                      '${l10n.commonRemaining}: ${formatIqd(invoice.outstandingAmount)}',
                    ),
                    trailing: Text(
                      invoice.issuedAt == null
                          ? '-'
                          : DateFormat('yyyy-MM-dd').format(
                              DateTime.tryParse(invoice.issuedAt!)?.toLocal() ??
                                  DateTime.now(),
                            ),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}
