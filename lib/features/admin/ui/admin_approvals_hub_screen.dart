import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../state/admin_controller.dart';
import 'admin_delivery_approvals_screen.dart';
import 'admin_merchant_approvals_screen.dart';
import 'admin_receivables_screen.dart';
import 'admin_service_provider_subscription_requests_screen.dart';
import 'admin_taxi_captain_requests_screen.dart';
import 'admin_taxi_cash_payments_screen.dart';

/// Purpose: شاشة التجميع التي توزّع مسارات الموافقات الإدارية إلى صفحات مستقلة لكل نوع طلب.
/// Used by: لوحة الأدمن عند الدخول إلى approvals hub.
/// Depends on: `adminControllerProvider` لتغذية العدادات، وشاشات approvals المتخصصة لكل module.
/// Critical notes: هذه الشاشة لا تنفذ الموافقات بنفسها؛ هي طبقة routing/summary فقط.
/// Maintenance notes: إذا ظهرت العدادات صفرية أو قديمة افحص `admin_controller.dart` ومسار bootstrap قبل الشاشات الفرعية.
/// مدخل مركزي لفريق الإدارة يوضّح أين يوجد كل workflow موافقة بعد فصلها عن الصفحة الرئيسية.
class AdminApprovalsHubScreen extends ConsumerWidget {
  const AdminApprovalsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminControllerProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminApprovalsHubTitle),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(adminControllerProvider.notifier).bootstrap(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(adminControllerProvider.notifier).bootstrap(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.adminApprovalsHubSubtitle,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 16),
            _ApprovalHubTile(
              icon: Icons.storefront_outlined,
              title: l10n.adminApprovalsHubMerchantTitle,
              subtitle: l10n.adminApprovalsHubMerchantSubtitle,
              count: state.pendingMerchants.length,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminMerchantApprovalsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _ApprovalHubTile(
              icon: Icons.delivery_dining_outlined,
              title: l10n.adminApprovalsHubDeliveryTitle,
              subtitle: l10n.adminApprovalsHubDeliverySubtitle,
              count: state.pendingDeliveryAccounts.length,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminDeliveryApprovalsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _ApprovalHubTile(
              icon: Icons.local_taxi_outlined,
              title: l10n.adminApprovalsHubTaxiTitle,
              subtitle: l10n.adminApprovalsHubTaxiSubtitle,
              count:
                  state.pendingTaxiCaptainAccounts.length +
                  state.pendingTaxiProfileEditRequests.length,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminTaxiCaptainRequestsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _ApprovalHubTile(
              icon: Icons.payments_outlined,
              title: l10n.adminApprovalsHubTaxiPaymentsTitle,
              subtitle: l10n.adminApprovalsHubTaxiPaymentsSubtitle,
              count: state.pendingTaxiCashPayments.length,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminTaxiCashPaymentsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _ApprovalHubTile(
              icon: Icons.home_repair_service_outlined,
              title: 'اشتراكات أصحاب الخدمة',
              subtitle: 'تسعير الاشتراك، الموافقة، وتأكيد الاستلام النقدي',
              count: state.pendingServiceProviderSubscriptionRequests.length,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const AdminServiceProviderSubscriptionRequestsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _ApprovalHubTile(
              icon: Icons.account_balance_wallet_outlined,
              title: l10n.adminApprovalsHubFinancialTitle,
              subtitle: l10n.adminApprovalsHubFinancialSubtitle,
              count: state.pendingSettlements.length,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminReceivablesScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة ملخص قابلة للنقر تعرض نوع الموافقة والعداد وتحوّل المستخدم إلى الصفحة المتخصصة.
class _ApprovalHubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback onTap;

  const _ApprovalHubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primary.withValues(alpha: 0.14),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: count > 0
                      ? scheme.error.withValues(alpha: 0.14)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: count > 0 ? scheme.error : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
