import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../models/admin_financial_reports_model.dart';
import '../state/admin_controller.dart';
import 'widgets/admin_financial_filter_bar.dart';
import 'widgets/admin_financial_print_actions.dart';

enum AdminFinancialMerchantReportType { sales, collections, receivables }

class AdminFinancialMerchantDetailsScreen extends ConsumerStatefulWidget {
  final AdminFinancialMerchantReportType reportType;
  final int merchantId;
  final String merchantName;
  final AdminFinancialPeriod initialPeriod;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  const AdminFinancialMerchantDetailsScreen({
    super.key,
    required this.reportType,
    required this.merchantId,
    required this.merchantName,
    this.initialPeriod = AdminFinancialPeriod.day,
    this.initialFrom,
    this.initialTo,
  });

  @override
  ConsumerState<AdminFinancialMerchantDetailsScreen> createState() =>
      _AdminFinancialMerchantDetailsScreenState();
}

class _AdminFinancialMerchantDetailsScreenState
    extends ConsumerState<AdminFinancialMerchantDetailsScreen> {
  AdminFinancialPeriod _period = AdminFinancialPeriod.day;
  DateTime? _from;
  DateTime? _to;
  bool _loading = false;
  String? _error;
  AdminFinancialMerchantDetailModel? _detail;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _from = widget.initialFrom;
    _to = widget.initialTo;
    Future.microtask(_load);
  }

  String? _iso(DateTime? date, {bool endOfDay = false}) {
    if (date == null) return null;
    final normalized = endOfDay
        ? DateTime(date.year, date.month, date.day, 23, 59, 59)
        : DateTime(date.year, date.month, date.day);
    return normalized.toUtc().toIso8601String();
  }

  String _periodLabel(BuildContext context) {
    final l10n = context.l10n;
    switch (_period) {
      case AdminFinancialPeriod.day:
        return l10n.adminFinancialMerchantPeriodToday;
      case AdminFinancialPeriod.week:
        return l10n.adminFinancialMerchantPeriodThisWeek;
      case AdminFinancialPeriod.month:
        return l10n.adminFinancialMerchantPeriodThisMonth;
      case AdminFinancialPeriod.year:
        return l10n.adminFinancialMerchantPeriodThisYear;
      case AdminFinancialPeriod.custom:
        if (_from == null || _to == null) {
          return l10n.adminFinancialMerchantPeriodCustomRange;
        }
        final from = DateFormat('yyyy-MM-dd').format(_from!);
        final to = DateFormat('yyyy-MM-dd').format(_to!);
        return '$from -> $to';
    }
  }

  String _title(BuildContext context) {
    final l10n = context.l10n;
    switch (widget.reportType) {
      case AdminFinancialMerchantReportType.sales:
        return l10n.adminFinancialMerchantSalesDetailsTitle;
      case AdminFinancialMerchantReportType.collections:
        return l10n.adminFinancialMerchantCollectionsDetailsTitle;
      case AdminFinancialMerchantReportType.receivables:
        return l10n.adminFinancialMerchantReceivablesDetailsTitle;
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initialStart = _from ?? now.subtract(const Duration(days: 7));
    final initialEnd = _to ?? now;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      locale: Localizations.localeOf(context),
    );
    if (range == null) return;
    setState(() {
      _from = range.start;
      _to = range.end;
      _period = AdminFinancialPeriod.custom;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(adminApiProvider);
      final period = adminFinancialPeriodCode(_period);
      final from = _iso(_from);
      final to = _iso(_to, endOfDay: true);

      final raw = switch (widget.reportType) {
        AdminFinancialMerchantReportType.sales => await api
            .adminSalesMerchantDetails(
              merchantId: widget.merchantId,
              period: period,
              from: from,
              to: to,
              limit: 300,
              offset: 0,
            ),
        AdminFinancialMerchantReportType.collections => await api
            .adminCollectionsMerchantDetails(
              merchantId: widget.merchantId,
              period: period,
              from: from,
              to: to,
              limit: 300,
              offset: 0,
            ),
        AdminFinancialMerchantReportType.receivables => await api
            .adminReceivablesMerchantStatement(
              merchantId: widget.merchantId,
              period: period,
              from: from,
              to: to,
              limit: 400,
              offset: 0,
            ),
      };

      final detail = switch (widget.reportType) {
        AdminFinancialMerchantReportType.sales =>
          AdminFinancialMerchantDetailModel.fromSalesJson(raw),
        AdminFinancialMerchantReportType.collections =>
          AdminFinancialMerchantDetailModel.fromCollectionsJson(raw),
        AdminFinancialMerchantReportType.receivables =>
          AdminFinancialMerchantDetailModel.fromStatementJson(raw),
      };

      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = context.l10n.adminFinancialMerchantLoadFailed;
      });
    }
  }

  String _fmtDate(dynamic value) {
    if (value == null) return '-';
    final raw = '$value'.trim();
    if (raw.isEmpty) return '-';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return DateFormat('yyyy-MM-dd HH:mm').format(date.toLocal());
  }

  Future<void> _print() async {
    final detail = _detail;
    if (detail == null) return;
    final l10n = context.l10n;

    final summary = <String>[
      '${l10n.adminFinancialMerchantLabelMerchant}: ${detail.merchant.name}',
      '${l10n.adminFinancialMerchantLabelPeriod}: ${_periodLabel(context)}',
    ];

    late final List<String> headers;
    late final List<List<String>> rows;

    if (widget.reportType == AdminFinancialMerchantReportType.sales) {
      headers = [
        l10n.adminFinancialMerchantHeaderOrder,
        l10n.adminFinancialMerchantHeaderDate,
        l10n.commonStatus,
        l10n.adminFinancialMerchantHeaderCustomer,
        l10n.adminFinancialMerchantHeaderAmount,
      ];
      rows = detail.salesItems
          .map(
            (item) => [
              '#${item.orderId}',
              _fmtDate(item.createdAt),
              item.status,
              item.customerName,
              formatIqd(item.totalAmount),
            ],
          )
          .toList(growable: false);
      summary.add(
        '${l10n.adminFinancialMerchantTotalSales}: ${formatIqd(detail.summary.totalSales)}',
      );
      summary.add(
        '${l10n.adminFinancialMerchantOrdersCount}: ${detail.summary.totalOrders}',
      );
    } else if (widget.reportType == AdminFinancialMerchantReportType.collections) {
      headers = [
        l10n.adminFinancialMerchantHeaderOperation,
        l10n.adminFinancialMerchantHeaderDate,
        l10n.adminFinancialMerchantHeaderScope,
        l10n.commonStatus,
        l10n.adminFinancialMerchantHeaderAmount,
      ];
      rows = detail.collectionItems
          .map(
            (item) => [
              '#${item.paymentRequestId}',
              _fmtDate(item.eventAt),
              item.paymentScope,
              item.status,
              formatIqd(
                item.paidAmount > 0 ? item.paidAmount : item.requestedAmount,
              ),
            ],
          )
          .toList(growable: false);
      summary.add(
        '${l10n.adminFinancialMerchantTotalCollected}: ${formatIqd(detail.summary.totalCollected)}',
      );
      summary.add(
        '${l10n.adminFinancialMerchantOperationsCount}: ${detail.summary.totalOperations}',
      );
    } else {
      headers = [
        l10n.adminFinancialMerchantHeaderDate,
        l10n.adminFinancialMerchantHeaderDescription,
        l10n.adminFinancialMerchantHeaderDebit,
        l10n.adminFinancialMerchantHeaderCredit,
        l10n.adminFinancialMerchantHeaderBalance,
      ];
      rows = detail.statementItems
          .map(
            (item) => [
              _fmtDate(item.eventAt),
              item.description,
              formatIqd(item.debit),
              formatIqd(item.credit),
              formatIqd(item.balanceAfter),
            ],
          )
          .toList(growable: false);
      summary.add(
        '${l10n.adminFinancialMerchantOpeningBalance}: ${formatIqd(detail.summary.openingBalance)}',
      );
      summary.add(
        '${l10n.adminFinancialMerchantNetReceivables}: ${formatIqd(detail.summary.netReceivables)}',
      );
    }

    await printAdminFinancialTableReport(
      title: _title(context),
      periodLabel: _periodLabel(context),
      summaryLines: summary,
      headers: headers,
      rows: rows,
      merchantName: detail.merchant.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final detail = _detail;
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
            AdminFinancialFilterBar(
              period: _period,
              customRangeLabel: _periodLabel(context),
              onPeriodChanged: (value) async {
                setState(() => _period = value);
                if (value == AdminFinancialPeriod.custom &&
                    (_from == null || _to == null)) {
                  await _pickRange();
                  return;
                }
                await _load();
              },
              onPickCustomRange: _pickRange,
            ),
            if (detail != null) ...[
              Card(
                child: ListTile(
                  title: Text(detail.merchant.name),
                  subtitle: Text(
                    '${l10n.adminFinancialMerchantLabelPeriod}: ${_periodLabel(context)}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AdminFinancialPrintActions(onPrint: _print),
              const SizedBox(height: 8),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
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
            else if (detail == null)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Center(
                  child: Text(l10n.adminFinancialMerchantNoDetailData),
                ),
              )
            else
              ..._buildDetailRows(context, detail),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDetailRows(
    BuildContext context,
    AdminFinancialMerchantDetailModel detail,
  ) {
    final l10n = context.l10n;
    if (widget.reportType == AdminFinancialMerchantReportType.sales) {
      if (detail.salesItems.isEmpty) {
        return [
          Center(
            child: Text(l10n.adminFinancialMerchantNoSalesInRange),
          ),
        ];
      }
      return detail.salesItems.map((item) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('#${item.orderId} - ${formatIqd(item.totalAmount)}'),
            subtitle: Text(
              '${_fmtDate(item.createdAt)} - ${item.status}\n'
              '${item.customerName} - ${item.customerPhone}',
            ),
          ),
        );
      }).toList(growable: false);
    }

    if (widget.reportType == AdminFinancialMerchantReportType.collections) {
      if (detail.collectionItems.isEmpty) {
        return [
          Center(
            child: Text(l10n.adminFinancialMerchantNoCollectionsInRange),
          ),
        ];
      }
      return detail.collectionItems.map((item) {
        final amount = item.paidAmount > 0 ? item.paidAmount : item.requestedAmount;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('#${item.paymentRequestId} - ${formatIqd(amount)}'),
            subtitle: Text(
              '${_fmtDate(item.eventAt)} - ${item.status}\n'
              '${item.paymentMethod ?? '-'} - ${item.referenceCode ?? '-'}',
            ),
          ),
        );
      }).toList(growable: false);
    }

    if (detail.statementItems.isEmpty) {
      return [
        Center(
          child: Text(l10n.adminFinancialMerchantNoStatementEntriesInRange),
        ),
      ];
    }

    return detail.statementItems.map((item) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text(_fmtDate(item.eventAt)),
          subtitle: Text(
            '${item.description}\n'
            '${l10n.adminFinancialMerchantHeaderDebit}: ${formatIqd(item.debit)} - '
            '${l10n.adminFinancialMerchantHeaderCredit}: ${formatIqd(item.credit)} - '
            '${l10n.adminFinancialMerchantHeaderBalance}: ${formatIqd(item.balanceAfter)}',
          ),
        ),
      );
    }).toList(growable: false);
  }
}
