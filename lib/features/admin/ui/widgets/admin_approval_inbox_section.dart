import 'package:flutter/material.dart';

import '../../models/admin_approval_inbox_item_model.dart';

class AdminApprovalInboxSection extends StatelessWidget {
  final bool saving;
  final bool canManage;
  final int total;
  final Map<String, int> counts;
  final List<AdminApprovalInboxItemModel> items;
  final Future<void> Function(AdminApprovalInboxItemModel item) onPrimaryAction;

  const AdminApprovalInboxSection({
    super.key,
    required this.saving,
    required this.canManage,
    required this.total,
    required this.counts,
    required this.items,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(10).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$total',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'صندوق الموافقات الموحد',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'كل العمليات المعلقة المهمة في مكان واحد مع تنفيذ سريع.',
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CountChip(
                    label: 'متاجر',
                    value: counts['merchants'] ?? 0,
                    color: const Color(0xFF43D0FF),
                  ),
                  _CountChip(
                    label: 'دلفري',
                    value: counts['deliveryAccounts'] ?? 0,
                    color: const Color(0xFF88F08E),
                  ),
                  _CountChip(
                    label: 'تسويات',
                    value: counts['settlements'] ?? 0,
                    color: const Color(0xFFFFD16A),
                  ),
                  _CountChip(
                    label: 'اشتراك تكسي',
                    value: counts['taxiCashPayments'] ?? 0,
                    color: const Color(0xFFFF9A65),
                  ),
                  _CountChip(
                    label: 'تعديل بيانات',
                    value: counts['taxiProfileEdits'] ?? 0,
                    color: const Color(0xFFD0A3FF),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'لا توجد أي موافقات معلقة حالياً.',
                    textAlign: TextAlign.right,
                  ),
                )
              else ...[
                for (final item in visibleItems)
                  _ApprovalInboxCard(
                    item: item,
                    saving: saving,
                    canManage: canManage,
                    onPrimaryAction: onPrimaryAction,
                  ),
                if (items.length > visibleItems.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'هناك ${items.length - visibleItems.length} عناصر أخرى في الأقسام التفصيلية أدناه.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.74),
                        fontSize: 12,
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

class _ApprovalInboxCard extends StatelessWidget {
  final AdminApprovalInboxItemModel item;
  final bool saving;
  final bool canManage;
  final Future<void> Function(AdminApprovalInboxItemModel item) onPrimaryAction;

  const _ApprovalInboxCard({
    required this.item,
    required this.saving,
    required this.canManage,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _kindColor(item.kind);
    final primaryLabel = _primaryActionLabel(item.kind);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.subject,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.title,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if ((item.subtitle ?? '').trim().isNotEmpty)
                  Text(
                    item.subtitle!,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.84),
                    ),
                  ),
                if ((item.meta ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.meta!,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
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
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: (!canManage || saving)
                ? null
                : () => onPrimaryAction(item),
            icon: Icon(_kindIcon(item.kind), size: 18),
            label: Text(primaryLabel),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _CountChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

Color _kindColor(String kind) {
  switch (kind) {
    case 'merchant':
      return const Color(0xFF43D0FF);
    case 'delivery':
      return const Color(0xFF88F08E);
    case 'settlement':
      return const Color(0xFFFFD16A);
    case 'taxi_cash':
      return const Color(0xFFFF9A65);
    case 'taxi_profile_edit':
      return const Color(0xFFD0A3FF);
    default:
      return Colors.white;
  }
}

IconData _kindIcon(String kind) {
  switch (kind) {
    case 'merchant':
      return Icons.storefront_outlined;
    case 'delivery':
      return Icons.two_wheeler_outlined;
    case 'settlement':
      return Icons.account_balance_wallet_outlined;
    case 'taxi_cash':
      return Icons.payments_outlined;
    case 'taxi_profile_edit':
      return Icons.edit_note_outlined;
    default:
      return Icons.pending_actions_outlined;
  }
}

String _primaryActionLabel(String kind) {
  switch (kind) {
    case 'merchant':
    case 'delivery':
      return 'موافقة';
    case 'settlement':
      return 'اعتماد';
    case 'taxi_cash':
      return 'فتح التسديد';
    case 'taxi_profile_edit':
      return 'فتح الطلب';
    default:
      return 'فتح';
  }
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
