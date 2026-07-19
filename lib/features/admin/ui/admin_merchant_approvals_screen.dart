import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../models/pending_merchant_model.dart';
import '../state/admin_controller.dart';
import 'admin_approvals_hub_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_services_hub_screen.dart';
import 'admin_service_provider_subscription_requests_screen.dart';
import 'admin_merchant_billing_profile_screen.dart';

class AdminMerchantApprovalsScreen extends ConsumerStatefulWidget {
  const AdminMerchantApprovalsScreen({super.key});

  @override
  ConsumerState<AdminMerchantApprovalsScreen> createState() =>
      _AdminMerchantApprovalsScreenState();
}

class _AdminMerchantApprovalsScreenState
    extends ConsumerState<AdminMerchantApprovalsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<PendingMerchantModel> _filter(List<PendingMerchantModel> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where((item) {
          return item.name.toLowerCase().contains(q) ||
              item.type.toLowerCase().contains(q) ||
              (item.phone ?? '').toLowerCase().contains(q) ||
              (item.ownerName ?? '').toLowerCase().contains(q) ||
              (item.ownerPhone ?? '').toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  Widget _buildAdminDrawer() {
    final auth = ref.watch(authControllerProvider);
    return AppUserDrawer(
      title: 'لوحة الإدارة',
      subtitle: auth.user?.fullName,
      showCommunitySection: false,
      showSettings: false,
      enableItemSearch: false,
      items: [
        AppUserDrawerItem(
          icon: Icons.space_dashboard_rounded,
          label: 'لوحة التحكم',
          subtitle: 'الصفحة الرئيسية للأدمن',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(
                builder: (_) => const AdminDashboardScreen(),
              ),
              (route) => false,
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.verified_user_outlined,
          label: 'حوض الموافقات',
          subtitle: 'مراجعة الطلبات المعلقة',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminApprovalsHubScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.home_repair_service_outlined,
          label: 'إدارة الخدمات',
          subtitle: 'ملخص الخدمات والطلبات',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminServicesHubScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.description_outlined,
          label: 'طلبات الاشتراك',
          subtitle: 'عرض طلبات أصحاب الخدمة',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const AdminServiceProviderSubscriptionRequestsScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.refresh_rounded,
          label: 'تحديث الصفحة',
          subtitle: 'إعادة تحميل طلبات الموافقات',
          group: 'الإجراءات',
          onTap: (_) async {
            await ref.read(adminControllerProvider.notifier).bootstrap();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final items = _filter(state.pendingMerchants);

    return Scaffold(
      drawer: Drawer(child: _buildAdminDrawer()),
      appBar: AppBar(
        title: Text(l10n.adminMerchantApprovalsTitle),
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
            TextField(
              controller: _searchCtrl,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                labelText: l10n.adminMerchantApprovalsSearch,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            if (state.error != null)
              _MessageBanner(text: state.error!, isError: true),
            if (state.success != null)
              _MessageBanner(text: state.success!, isError: false),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Center(child: Text(l10n.adminMerchantApprovalsEmpty)),
              )
            else
              ...items.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const CircleAvatar(
                      child: Icon(Icons.storefront_outlined),
                    ),
                    title: Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.adminMerchantApprovalsType(item.type)),
                          if ((item.ownerName ?? '').trim().isNotEmpty)
                            Text(
                              l10n.adminMerchantApprovalsOwner(item.ownerName!),
                            ),
                          if ((item.ownerPhone ?? '').trim().isNotEmpty)
                            Text(item.ownerPhone!),
                          if ((item.description ?? '').trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(item.description!),
                            ),
                        ],
                      ),
                    ),
                    trailing: FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AdminMerchantBillingProfileScreen(
                              merchantId: item.id,
                              merchantName: item.name,
                              approvalMode: true,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.rule_folder_outlined),
                      label: Text(l10n.adminMerchantApprovalsReview),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  final String text;
  final bool isError;

  const _MessageBanner({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : Colors.greenAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(text),
    );
  }
}
