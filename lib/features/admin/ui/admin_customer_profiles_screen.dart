import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../../auth/state/auth_controller.dart';
import '../state/admin_controller.dart';
import 'customer_insight_profile_screen.dart';

class AdminCustomerProfilesScreen extends ConsumerStatefulWidget {
  const AdminCustomerProfilesScreen({super.key});

  @override
  ConsumerState<AdminCustomerProfilesScreen> createState() =>
      _AdminCustomerProfilesScreenState();
}

class _AdminCustomerProfilesScreenState
    extends ConsumerState<AdminCustomerProfilesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openDetails(Map<String, dynamic> item) async {
    final id = int.tryParse('${item['id'] ?? item['customerId'] ?? ''}');
    if (id == null || id <= 0) return;
    final details = await ref
        .read(adminControllerProvider.notifier)
        .fetchCustomerInsightDetails(id);
    if (!mounted || details == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerInsightProfileScreen(details: details),
      ),
    );
  }

  String _fullName(Map<String, dynamic> item) =>
      '${item['full_name'] ?? item['fullName'] ?? '-'}';

  String _phone(Map<String, dynamic> item) => '${item['phone'] ?? '-'}';

  String _block(Map<String, dynamic> item) =>
      '${item['block'] ?? ''} ${item['building_number'] ?? item['buildingNumber'] ?? ''}'
          .trim();

  int _orders(Map<String, dynamic> item) =>
      int.tryParse('${item['orders_count'] ?? item['ordersCount'] ?? 0}') ?? 0;

  double _spent(Map<String, dynamic> item) =>
      double.tryParse('${item['total_spent'] ?? item['totalSpent'] ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final auth = ref.watch(authControllerProvider);

    if (!auth.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.adminCustomerProfilesTitle)),
        body: Center(
          child: Text(
            l10n.adminCustomerProfilesSuperAdminOnly,
            textDirection: Directionality.of(context),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminCustomerProfilesTitle),
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
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => ref
                  .read(adminControllerProvider.notifier)
                  .searchCustomerInsights(value),
              decoration: InputDecoration(
                labelText: l10n.adminCustomerProfilesSearch,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: () => ref
                      .read(adminControllerProvider.notifier)
                      .searchCustomerInsights(_searchCtrl.text),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (state.customerInsights.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Center(child: Text(l10n.adminCustomerProfilesEmpty)),
              )
            else
              ...state.customerInsights.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline_rounded),
                    ),
                    title: Text(
                      _fullName(item),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_phone(item)),
                          if (_block(item).isNotEmpty) Text(_block(item)),
                          const SizedBox(height: 4),
                          Text(
                            l10n.adminCustomerProfilesOrdersSpend(
                              _orders(item),
                              formatIqd(_spent(item)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () => _openDetails(item),
                      child: Text(l10n.commonOpen),
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
