import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../subscriptions/ui/admin_merchant_subscriptions_screen.dart';
import '../models/admin_financial_kpi_model.dart';
import '../state/admin_controller.dart';
import 'admin_collections_report_screen.dart';
import 'admin_receivables_report_screen.dart';
import 'admin_sales_report_screen.dart';
import 'widgets/admin_financial_kpi_cards.dart';

class AdminFinancialReportsHubScreen extends ConsumerStatefulWidget {
  const AdminFinancialReportsHubScreen({super.key});

  @override
  ConsumerState<AdminFinancialReportsHubScreen> createState() =>
      _AdminFinancialReportsHubScreenState();
}

class _AdminFinancialReportsHubScreenState
    extends ConsumerState<AdminFinancialReportsHubScreen> {
  Future<void> _reload() {
    return ref
        .read(adminControllerProvider.notifier)
        .refreshAdminFinancialKpisV3(period: 'all');
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  void _openSales() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AdminSalesReportScreen()));
  }

  void _openCollections() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminCollectionsReportScreen()),
    );
  }

  void _openReceivables() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminReceivablesReportScreen()),
    );
  }

  void _openMerchantSubscriptions() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AdminMerchantSubscriptionsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final kpiRaw = state.adminFinancialKpisV3;
    final kpi = AdminFinancialKpiModel.fromJson(kpiRaw);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminFinancialReportsHubTitle),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            AdminFinancialKpiCards(
              kpi: kpi,
              onOpenSales: _openSales,
              onOpenCollections: _openCollections,
              onOpenReceivables: _openReceivables,
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.point_of_sale_outlined),
                    title: Text(l10n.adminSalesReportTitle),
                    subtitle: Text(l10n.adminFinancialReportsHubSalesSubtitle),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openSales,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(l10n.adminCollectionsReportTitle),
                    subtitle: Text(
                      l10n.adminFinancialReportsHubCollectionsSubtitle,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openCollections,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(l10n.adminReceivablesReportTitle),
                    subtitle: Text(
                      l10n.adminFinancialReportsHubReceivablesSubtitle,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openReceivables,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text(context.lt(
                      ar: 'اشتراكات المتاجر الشهرية',
                      en: 'Merchant monthly subscriptions',
                    )),
                    subtitle: Text(context.lt(
                      ar: 'إصدار الفواتير واستلام مدفوعات الاشتراك الشهري.',
                      en: 'Generate invoices and collect monthly subscription payments.',
                    )),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openMerchantSubscriptions,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
