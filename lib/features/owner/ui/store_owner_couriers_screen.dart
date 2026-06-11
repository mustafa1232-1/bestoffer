import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../state/owner_controller.dart';

class StoreOwnerCouriersScreen extends ConsumerStatefulWidget {
  const StoreOwnerCouriersScreen({super.key});

  @override
  ConsumerState<StoreOwnerCouriersScreen> createState() =>
      _StoreOwnerCouriersScreenState();
}

class _StoreOwnerCouriersScreenState
    extends ConsumerState<StoreOwnerCouriersScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      await ref
          .read(ownerControllerProvider.notifier)
          .loadMerchantOpsOverviewV2();
    });
  }

  Future<void> _reload() {
    return ref
        .read(ownerControllerProvider.notifier)
        .loadMerchantOpsOverviewV2();
  }

  Future<void> _openAddCourierDialog() async {
    final l10n = context.l10n;
    final state = ref.read(ownerControllerProvider);
    final existing = state.deliveryAgents;
    if (existing.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.ownerCouriersNoAppCouriersFound)),
      );
      return;
    }

    int? selected;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(l10n.ownerCouriersAddMerchantCourier),
          content: DropdownButtonFormField<int>(
            initialValue: selected,
            items: existing
                .map(
                  (e) => DropdownMenuItem(
                    value: e.id,
                    child: Text('${e.fullName} • ${e.phone}'),
                  ),
                )
                .toList(),
            onChanged: (value) => setStateDialog(() => selected = value),
            decoration: InputDecoration(
              labelText: l10n.ownerCouriersSelectCourier,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );

    if (ok != true || selected == null) return;
    final success = await ref
        .read(ownerControllerProvider.notifier)
        .createMerchantCourierV2(deliveryUserId: selected!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? l10n.ownerCouriersAddedSuccess
              : l10n.ownerCouriersAddFailed,
        ),
      ),
    );
  }

  String _availabilityLabel(BuildContext context, String raw) {
    final l10n = context.l10n;
    switch (raw.trim().toLowerCase()) {
      case 'available':
        return l10n.ownerCouriersAvailabilityAvailable;
      case 'busy':
        return l10n.ownerCouriersAvailabilityBusy;
      case 'on_delivery':
      case 'delivering':
        return l10n.ownerCouriersAvailabilityOnDelivery;
      case 'offline':
        return l10n.ownerCouriersAvailabilityOffline;
      default:
        return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(ownerControllerProvider);
    final rows = state.merchantCouriersV2;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ownerCouriersTitle),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _openAddCourierDialog,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(l10n.ownerCouriersAddCourierButton),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Center(
                  child: Text(l10n.ownerCouriersEmptyState),
                ),
              )
            else
              ...rows.map((row) {
                final userId = int.tryParse('${row['user_id'] ?? ''}') ?? 0;
                final fullName = '${row['full_name'] ?? ''}';
                final phone = '${row['phone'] ?? ''}';
                final isActive = row['is_active'] == true;
                final availability =
                    '${row['availability_status'] ?? 'offline'}';
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          fullName.isEmpty
                              ? l10n.ownerCouriersFallbackName(userId)
                              : fullName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(phone),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Chip(
                              label: Text(
                                isActive
                                    ? l10n.ownerCouriersActive
                                    : l10n.ownerCouriersDisabled,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Chip(
                              label: Text(
                                _availabilityLabel(context, availability),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => ref
                                  .read(ownerControllerProvider.notifier)
                                  .patchMerchantCourierV2(
                                    courierUserId: userId,
                                    isActive: !isActive,
                                  ),
                              icon: const Icon(
                                Icons.power_settings_new_rounded,
                              ),
                              label: Text(
                                isActive
                                    ? l10n.ownerCouriersDisable
                                    : l10n.ownerCouriersEnable,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => ref
                                  .read(ownerControllerProvider.notifier)
                                  .patchMerchantCourierV2(
                                    courierUserId: userId,
                                    availabilityStatus: 'available',
                                  ),
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                              ),
                              label: Text(l10n.ownerCouriersAvailable),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
