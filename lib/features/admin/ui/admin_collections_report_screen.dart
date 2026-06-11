import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../models/admin_financial_reports_model.dart';
import '../state/admin_controller.dart';
import 'admin_financial_merchant_details_screen.dart';
import 'widgets/admin_financial_filter_bar.dart';
import 'widgets/admin_financial_print_actions.dart';

class AdminCollectionsReportScreen extends ConsumerStatefulWidget {
  final AdminFinancialPeriod initialPeriod;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  const AdminCollectionsReportScreen({
    super.key,
    this.initialPeriod = AdminFinancialPeriod.day,
    this.initialFrom,
    this.initialTo,
  });

  @override
  ConsumerState<AdminCollectionsReportScreen> createState() =>
      _AdminCollectionsReportScreenState();
}

class _AdminCollectionsReportScreenState
    extends ConsumerState<AdminCollectionsReportScreen> {
  final _searchCtrl = TextEditingController();
  AdminFinancialPeriod _period = AdminFinancialPeriod.day;
  DateTime? _from;
  DateTime? _to;
  bool _loading = false;
  String? _error;
  AdminFinancialMerchantsReportModel? _report;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _from = widget.initialFrom;
    _to = widget.initialTo;
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
        return l10n.commonToday;
      case AdminFinancialPeriod.week:
        return l10n.commonThisWeek;
      case AdminFinancialPeriod.month:
        return l10n.commonThisMonth;
      case AdminFinancialPeriod.year:
        return l10n.commonThisYear;
      case AdminFinancialPeriod.custom:
        if (_from == null || _to == null) {
          return l10n.commonCustomRange;
        }
        final from = DateFormat('yyyy-MM-dd').format(_from!);
        final to = DateFormat('yyyy-MM-dd').format(_to!);
        return '$from -> $to';
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
    final l10n = context.l10n;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref.read(adminApiProvider).adminCollectionsReport(
            period: adminFinancialPeriodCode(_period),
            from: _iso(_from),
            to: _iso(_to, endOfDay: true),
            search: _searchCtrl.text.trim().isEmpty
                ? null
                : _searchCtrl.text.trim(),
            limit: 200,
            offset: 0,
          );
      setState(() {
        _report = AdminFinancialMerchantsReportModel.fromJson(raw);
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = l10n.adminCollectionsReportLoadFailed;
      });
    }
  }

  Future<void> _print() async {
    final report = _report;
    if (report == null) return;

    final l10n = context.l10n;
    final headers = <String>[
      l10n.commonMerchant,
      l10n.commonOperations,
      l10n.adminCollectionsReportTotalCollected,
      l10n.adminCollectionsReportFirstCollection,
      l10n.adminCollectionsReportLastCollection,
    ];
    final rows = report.merchants
        .map(
          (row) => [
            row.merchantName,
            '${row.operationsCount}',
            formatIqd(row.totalCollected),
            row.firstEventAt ?? '-',
            row.lastEventAt ?? '-',
          ],
        )
        .toList(growable: false);
    final summary = [
      '${l10n.commonPeriod}: ${_periodLabel(context)}',
      '${l10n.adminCollectionsReportTotalCollected}: ${formatIqd(report.summary.totalCollected)}',
      '${l10n.commonOperations}: ${report.summary.totalOperations}',
      '${l10n.commonMerchantsCount}: ${report.summary.merchantsCount}',
    ];

    await printAdminFinancialTableReport(
      title: l10n.adminCollectionsReportTitle,
      periodLabel: _periodLabel(context),
      summaryLines: summary,
      headers: headers,
      rows: rows,
    );
  }

  void _openMerchant(AdminFinancialMerchantSummaryRow row) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminFinancialMerchantDetailsScreen(
          reportType: AdminFinancialMerchantReportType.collections,
          merchantId: row.merchantId,
          merchantName: row.merchantName,
          initialPeriod: _period,
          initialFrom: _from,
          initialTo: _to,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final report = _report;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminCollectionsReportTitle),
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
              searchController: _searchCtrl,
              onSearch: _load,
              onPickCustomRange: _pickRange,
            ),
            if (report != null) ...[
              Card(
                child: ListTile(
                  title: Text(l10n.adminCollectionsReportTotalCollected),
                  subtitle: Text(
                    '${formatIqd(report.summary.totalCollected)} - '
                    '${l10n.commonOperations}: ${report.summary.totalOperations}',
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
            else if (report == null || report.merchants.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Center(
                  child: Text(l10n.adminCollectionsReportNoData),
                ),
              )
            else
              ...report.merchants.map((row) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _openMerchant(row),
                    title: Text(row.merchantName),
                    subtitle: Text(
                      '${l10n.commonOperations}: ${row.operationsCount} - '
                      '${l10n.commonCollected}: ${formatIqd(row.totalCollected)}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                );
              }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
