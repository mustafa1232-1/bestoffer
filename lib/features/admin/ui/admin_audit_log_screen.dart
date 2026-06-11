import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../models/admin_audit_event_model.dart';
import '../state/admin_controller.dart';

class AdminAuditLogScreen extends ConsumerStatefulWidget {
  const AdminAuditLogScreen({super.key});

  @override
  ConsumerState<AdminAuditLogScreen> createState() =>
      _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends ConsumerState<AdminAuditLogScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AdminAuditEventModel> _filtered(List<AdminAuditEventModel> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where((item) {
          return item.summary.toLowerCase().contains(q) ||
              item.actionKey.toLowerCase().contains(q) ||
              (item.actorFullName ?? '').toLowerCase().contains(q) ||
              (item.actorPhone ?? '').toLowerCase().contains(q) ||
              (item.targetLabel ?? '').toLowerCase().contains(q) ||
              (item.targetType ?? '').toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return context.l10n.adminAuditLogNoTimestamp;
    }
    final local = value.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final items = _filtered(state.auditFeed);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminAuditLogTitle),
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
                labelText: l10n.adminAuditLogSearch,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Center(child: Text(l10n.adminAuditLogEmpty)),
              )
            else
              ...items.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    title: Text(
                      item.summary,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.adminAuditLogAction(item.actionKey)),
                          Text(
                            l10n.adminAuditLogActor(item.actorFullName ?? '-'),
                          ),
                          Text(_formatDate(item.createdAt)),
                        ],
                      ),
                    ),
                    children: [
                      if ((item.targetType ?? '').trim().isNotEmpty)
                        _AuditRow(
                          label: l10n.adminAuditLogTarget,
                          value: '${item.targetType} ${item.targetLabel ?? ''}'
                              .trim(),
                        ),
                      if ((item.actorPhone ?? '').trim().isNotEmpty)
                        _AuditRow(
                          label: l10n.adminAuditLogActorPhone,
                          value: item.actorPhone!,
                        ),
                      if (item.metadata.isNotEmpty)
                        _AuditRow(
                          label: l10n.adminAuditLogMetadata,
                          value: item.metadata.entries
                              .map((entry) => '${entry.key}: ${entry.value}')
                              .join('\n'),
                        ),
                    ],
                  ),
                ),
              ),
            if (state.auditFeedNextCursor != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: state.auditFeedLoadingMore
                      ? null
                      : () => ref
                            .read(adminControllerProvider.notifier)
                            .loadMoreAuditFeed(),
                  icon: state.auditFeedLoadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(l10n.adminAuditLogLoadMore),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  final String label;
  final String value;

  const _AuditRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}
