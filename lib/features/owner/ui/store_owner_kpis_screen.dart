import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../models/merchant_financial_request_model.dart';
import '../models/merchant_receivable_invoice_model.dart';
import '../state/owner_controller.dart';
import 'merchant_financial_report_screen.dart';

class StoreOwnerKpisScreen extends ConsumerStatefulWidget {
  const StoreOwnerKpisScreen({super.key});

  @override
  ConsumerState<StoreOwnerKpisScreen> createState() =>
      _StoreOwnerKpisScreenState();
}

class _StoreOwnerKpisScreenState extends ConsumerState<StoreOwnerKpisScreen> {
  bool _loading = false;
  String? _error;
  List<MerchantReceivableInvoiceModel> _invoices = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = ref.read(ownerControllerProvider.notifier);
      final invoicesRaw = await controller.fetchMerchantReceivableInvoicesV2(
        limit: 2000,
        period: 'all',
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
        _error = context.l10n.ownerStoreKpisLoadFailed;
      });
    }
  }

  List<MerchantFinancialRequestModel> get _confirmedStorePayments {
    return ref
        .watch(ownerControllerProvider)
        .merchantPaymentRequestsV2
        .map(MerchantFinancialRequestModel.fromJson)
        .where(
          (request) =>
              request.requestType == 'store_pays_app' &&
              request.status == 'confirmed_by_admin',
        )
        .toList(growable: false);
  }

  double get _totalSales =>
      _invoices.fold<double>(0, (sum, invoice) => sum + invoice.subtotal);

  double get _totalCommission => _invoices.fold<double>(
    0,
    (sum, invoice) => sum + invoice.commissionAmount,
  );

  double get _totalServiceFees => _invoices.fold<double>(
    0,
    (sum, invoice) => sum + invoice.serviceFeeAmount,
  );

  double get _totalAppDeliveryFees => _invoices.fold<double>(
    0,
    (sum, invoice) => sum + invoice.appDeliveryFeeAmount,
  );

  double get _totalStoreDeliveryFees => _invoices.fold<double>(
    0,
    (sum, invoice) => sum + invoice.storeDeliveryFeeAmount,
  );

  double get _netSalesForStore =>
      _invoices.fold<double>(
        0,
        (sum, invoice) => sum + invoice.effectiveStoreNetReceivedAmount,
      );

  double get _netDueToApp => _invoices.fold<double>(
    0,
    (sum, invoice) => sum + invoice.effectiveAppDueFromDelivery,
  );

  double get _totalDifference =>
      _invoices.fold<double>(0, (sum, invoice) => sum + invoice.differenceAmount);

  double get _confirmedPaidAmount => _confirmedStorePayments.fold<double>(
    0,
    (sum, request) =>
        sum +
        (request.paidAmount > 0
            ? request.paidAmount
            : request.requestedAmount > 0
            ? request.requestedAmount
            : request.amount),
  );

  double get _remainingDueToApp => _netDueToApp - _confirmedPaidAmount;

  void _openReport(MerchantFinancialReportType type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantFinancialReportScreen(reportType: type),
      ),
    );
  }

  String _reportTitle(MerchantFinancialReportType type) {
    final l10n = context.l10n;
    switch (type) {
      case MerchantFinancialReportType.sales:
        return l10n.ownerFinancialReportTitleSales;
      case MerchantFinancialReportType.commission:
        return l10n.ownerFinancialReportTitleCommission;
      case MerchantFinancialReportType.serviceFee:
        return l10n.ownerFinancialReportTitleServiceFee;
      case MerchantFinancialReportType.appDelivery:
        return l10n.ownerFinancialReportTitleAppDelivery;
      case MerchantFinancialReportType.storeDelivery:
        return l10n.ownerFinancialReportTitleStoreDelivery;
      case MerchantFinancialReportType.netSales:
        return l10n.ownerFinancialReportTitleNetSales;
      case MerchantFinancialReportType.appDue:
        return l10n.ownerFinancialReportTitleAppDue;
      case MerchantFinancialReportType.paidAmount:
        return l10n.ownerFinancialReportTitlePaidAmount;
      case MerchantFinancialReportType.remaining:
        return l10n.ownerFinancialReportTitleRemaining;
    }
  }

  Widget _card({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required MerchantFinancialReportType reportType,
  }) {
    return InkWell(
      onTap: () => _openReport(reportType),
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.28),
              color.withValues(alpha: 0.12),
            ],
          ),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cards = [
      (
        title: _reportTitle(MerchantFinancialReportType.sales),
        value: formatIqd(_totalSales),
        icon: Icons.point_of_sale_outlined,
        color: const Color(0xFF2AA876),
        type: MerchantFinancialReportType.sales,
      ),
      (
        title: _reportTitle(MerchantFinancialReportType.commission),
        value: formatIqd(_totalCommission),
        icon: Icons.percent_rounded,
        color: const Color(0xFF3E7BFA),
        type: MerchantFinancialReportType.commission,
      ),
      (
        title: _reportTitle(MerchantFinancialReportType.serviceFee),
        value: formatIqd(_totalServiceFees),
        icon: Icons.design_services_outlined,
        color: const Color(0xFFE97A2E),
        type: MerchantFinancialReportType.serviceFee,
      ),
      (
        title: _reportTitle(MerchantFinancialReportType.appDelivery),
        value: formatIqd(_totalAppDeliveryFees),
        icon: Icons.local_shipping_outlined,
        color: const Color(0xFF9C4DCC),
        type: MerchantFinancialReportType.appDelivery,
      ),
      (
        title: _reportTitle(MerchantFinancialReportType.storeDelivery),
        value: formatIqd(_totalStoreDeliveryFees),
        icon: Icons.store_mall_directory_outlined,
        color: const Color(0xFFCC6B8E),
        type: MerchantFinancialReportType.storeDelivery,
      ),
      (
        title: _reportTitle(MerchantFinancialReportType.netSales),
        value: formatIqd(_netSalesForStore),
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF2F8F83),
        type: MerchantFinancialReportType.netSales,
      ),
      (
        title: _reportTitle(MerchantFinancialReportType.appDue),
        value: formatIqd(_netDueToApp),
        icon: Icons.receipt_long_outlined,
        color: const Color(0xFFD05A5A),
        type: MerchantFinancialReportType.appDue,
      ),
      (
        title: _reportTitle(MerchantFinancialReportType.paidAmount),
        value: formatIqd(_confirmedPaidAmount),
        icon: Icons.verified_outlined,
        color: const Color(0xFF4C78DD),
        type: MerchantFinancialReportType.paidAmount,
      ),
      (
        title: _reportTitle(MerchantFinancialReportType.remaining),
        value: formatIqd(_remainingDueToApp),
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFC76B12),
        type: MerchantFinancialReportType.remaining,
      ),
      (
        title: context.lt(ar: 'إجمالي الفروقات', en: 'Total differences'),
        value: formatIqd(_totalDifference),
        icon: Icons.balance_outlined,
        color: const Color(0xFF7C4DFF),
        type: MerchantFinancialReportType.remaining,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ownerStoreKpisTitle),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                title: Text(l10n.ownerStoreKpisSummaryTitle),
                subtitle: Text(l10n.ownerStoreKpisSummarySubtitle),
              ),
            ),
            const SizedBox(height: 12),
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
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cards.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.15,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final card = cards[index];
                  return _card(
                    title: card.title,
                    value: card.value,
                    icon: card.icon,
                    color: card.color,
                    reportType: card.type,
                  );
                },
              ),
            if (!_loading) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  title: Text(l10n.ownerStoreKpisInvoiceCount),
                  trailing: Text(
                    '${_invoices.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
