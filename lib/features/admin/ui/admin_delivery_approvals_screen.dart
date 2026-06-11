import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../models/pending_delivery_account_model.dart';
import '../state/admin_controller.dart';

class AdminDeliveryApprovalsScreen extends ConsumerWidget {
  const AdminDeliveryApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminDeliveryApprovalsTitle),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(adminControllerProvider.notifier).bootstrap(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(adminControllerProvider.notifier).bootstrap(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: state.pendingDeliveryAccounts.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Center(
                      child: Text(l10n.adminDeliveryApprovalsEmpty),
                    ),
                  ),
                ]
              : state.pendingDeliveryAccounts
                    .map(
                      (item) => _DeliveryApprovalCard(
                        item: item,
                        saving: state.saving,
                        onApprove: () => ref
                            .read(adminControllerProvider.notifier)
                            .approveDeliveryAccount(item.id),
                      ),
                    )
                    .toList(growable: false),
        ),
      ),
    );
  }
}

class _DeliveryApprovalCard extends StatelessWidget {
  const _DeliveryApprovalCard({
    required this.item,
    required this.saving,
    required this.onApprove,
  });

  final PendingDeliveryAccountModel item;
  final bool saving;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.fullName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(item.phone),
            const SizedBox(height: 4),
            Text('${item.block} / ${item.buildingNumber} / ${item.apartment}'),
            if (item.createdAt != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.adminDeliveryApprovalsCreatedAt(
                  item.createdAt!.toLocal().toString(),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: saving ? null : onApprove,
                icon: const Icon(Icons.check_rounded),
                label: Text(l10n.adminDeliveryApprovalsApproveCourier),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
