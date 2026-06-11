import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../models/managed_merchant_model.dart';
import '../state/admin_controller.dart';
import 'admin_merchant_billing_profile_screen.dart';

class AdminMerchantStateManagementScreen extends ConsumerStatefulWidget {
  const AdminMerchantStateManagementScreen({super.key});

  @override
  ConsumerState<AdminMerchantStateManagementScreen> createState() =>
      _AdminMerchantStateManagementScreenState();
}

class _AdminMerchantStateManagementScreenState
    extends ConsumerState<AdminMerchantStateManagementScreen> {
  String _filter = 'all';
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ManagedMerchantModel> _visible(List<ManagedMerchantModel> items) {
    Iterable<ManagedMerchantModel> out = items;
    switch (_filter) {
      case 'pending':
        out = out.where((item) => !item.isApproved);
        break;
      case 'disabled':
        out = out.where((item) => item.isDisabled);
        break;
      case 'active':
        out = out.where((item) => item.isApproved && !item.isDisabled);
        break;
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((item) {
        return item.name.toLowerCase().contains(q) ||
            item.type.toLowerCase().contains(q) ||
            (item.phone ?? '').toLowerCase().contains(q) ||
            (item.ownerFullName ?? '').toLowerCase().contains(q);
      });
    }
    return out.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final items = _visible(state.managedMerchants);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminMerchantStateManagementTitle),
        actions: [
          IconButton(
            onPressed: () => ref.read(adminControllerProvider.notifier).bootstrap(),
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
                labelText: l10n.adminMerchantStateSearch,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(
                  label: l10n.commonAll,
                  selected: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                _FilterChip(
                  label: l10n.commonPending,
                  selected: _filter == 'pending',
                  onTap: () => setState(() => _filter = 'pending'),
                ),
                _FilterChip(
                  label: l10n.adminMerchantStateActiveFilter,
                  selected: _filter == 'active',
                  onTap: () => setState(() => _filter = 'active'),
                ),
                _FilterChip(
                  label: l10n.adminMerchantStateDisabledFilter,
                  selected: _filter == 'disabled',
                  onTap: () => setState(() => _filter = 'disabled'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Center(
                  child: Text(l10n.adminMerchantStateNoMatches),
                ),
              )
            else
              ...items.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.adminMerchantStateTypeLine(item.type),
                                  ),
                                  if ((item.ownerFullName ?? '').trim().isNotEmpty)
                                    Text(
                                      l10n.adminMerchantStateOwnerLine(
                                        item.ownerFullName!,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: !item.isDisabled,
                              onChanged: state.saving
                                  ? null
                                  : (value) {
                                      ref
                                          .read(adminControllerProvider.notifier)
                                          .toggleMerchantDisabled(
                                            merchantId: item.id,
                                            isDisabled: !value,
                                          );
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatusPill(
                              label: item.isApproved
                                  ? l10n.adminMerchantStateApproved
                                  : l10n.adminMerchantStatePendingApproval,
                              active: item.isApproved,
                            ),
                            _StatusPill(
                              label: item.isDisabled
                                  ? l10n.adminMerchantStateDisabled
                                  : l10n.adminMerchantStateEnabled,
                              active: !item.isDisabled,
                            ),
                            _StatusPill(
                              label: item.isOpen
                                  ? l10n.adminMerchantStateOpen
                                  : l10n.adminMerchantStateClosed,
                              active: item.isOpen,
                            ),
                            _StatusPill(
                              label: l10n.adminMerchantStateTodayOrders(
                                item.todayOrdersCount,
                              ),
                              active: item.todayOrdersCount > 0,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AdminMerchantBillingProfileScreen(
                                    merchantId: item.id,
                                    merchantName: item.name,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.tune_rounded),
                            label: Text(l10n.adminMerchantStateBillingProfile),
                          ),
                        ),
                      ],
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool active;

  const _StatusPill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}
