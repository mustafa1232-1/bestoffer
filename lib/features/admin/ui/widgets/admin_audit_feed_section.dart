import 'package:flutter/material.dart';

import '../../models/admin_audit_event_model.dart';

class AdminAuditFeedSection extends StatelessWidget {
  final List<AdminAuditEventModel> items;
  final bool loadingMore;
  final bool hasMore;
  final Future<void> Function() onLoadMore;

  const AdminAuditFeedSection({
    super.key,
    required this.items,
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'سجل التدقيق الإداري',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'كل إجراء إداري مهم يتم تسجيله هنا مع وقت التنفيذ والهدف المتأثر.',
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'لا توجد أحداث تدقيق معروضة حتى الآن.',
                    textAlign: TextAlign.right,
                  ),
                )
              else ...[
                for (final item in items) _AuditEventCard(item: item),
                if (hasMore || loadingMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: loadingMore
                          ? const SizedBox(
                              height: 26,
                              width: 26,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : OutlinedButton.icon(
                              onPressed: onLoadMore,
                              icon: const Icon(Icons.more_horiz_rounded),
                              label: const Text('تحميل المزيد'),
                            ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditEventCard extends StatelessWidget {
  final AdminAuditEventModel item;

  const _AuditEventCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final accent = _actionColor(item.actionKey);
    final metadataEntries = item.metadata.entries
        .take(3)
        .toList(growable: false);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_actionIcon(item.actionKey), color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.summary,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _actorLine(item),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    if ((item.targetLabel ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'الهدف: ${item.targetLabel}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.74),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(item.createdAt),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (metadataEntries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in metadataEntries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${entry.key}: ${_metadataValue(entry.value)}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Color _actionColor(String actionKey) {
  if (actionKey.contains('approved')) return const Color(0xFF79E18B);
  if (actionKey.contains('rejected') || actionKey.contains('disabled')) {
    return const Color(0xFFFF8A80);
  }
  if (actionKey.contains('created')) return const Color(0xFF43D0FF);
  if (actionKey.contains('updated')) return const Color(0xFFFFD16A);
  if (actionKey.contains('deleted')) return const Color(0xFFFF9A65);
  return const Color(0xFFD0A3FF);
}

IconData _actionIcon(String actionKey) {
  if (actionKey.contains('approved')) return Icons.check_circle_outline;
  if (actionKey.contains('rejected')) return Icons.cancel_outlined;
  if (actionKey.contains('disabled')) return Icons.block_outlined;
  if (actionKey.contains('created')) return Icons.add_circle_outline;
  if (actionKey.contains('updated')) return Icons.edit_outlined;
  if (actionKey.contains('deleted')) return Icons.delete_outline;
  return Icons.history_rounded;
}

String _actorLine(AdminAuditEventModel item) {
  final parts = <String>[];
  final name = (item.actorFullName ?? '').trim();
  final role = (item.actorRole ?? '').trim();
  final phone = (item.actorPhone ?? '').trim();
  if (name.isNotEmpty) parts.add(name);
  if (role.isNotEmpty) parts.add(role);
  if (phone.isNotEmpty) parts.add(phone);
  if (parts.isEmpty) return 'منفذ الإجراء غير متاح';
  return parts.join(' • ');
}

String _metadataValue(dynamic value) {
  if (value == null) return '-';
  final text = '$value'.trim();
  if (text.isEmpty) return '-';
  if (text.length <= 32) return text;
  return '${text.substring(0, 29)}...';
}

String _formatDate(DateTime? value) {
  if (value == null) return 'بدون وقت';
  final local = value.toLocal();
  final hour = local.hour > 12
      ? local.hour - 12
      : (local.hour == 0 ? 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'م' : 'ص';
  return '${local.year}/${local.month}/${local.day} - $hour:$minute $suffix';
}
