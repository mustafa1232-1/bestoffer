import 'package:flutter/material.dart';

import '../models/ops_action.dart';
import 'severity_badge.dart';

class ApprovalActionCard extends StatelessWidget {
  final OpsAction action;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const ApprovalActionCard({
    super.key,
    required this.action,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final needsCriticalConfirm =
        action.riskLevel.toLowerCase() == 'high' ||
        action.riskLevel.toLowerCase() == 'critical';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${action.actionType} • #${action.id}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SeverityBadge(severity: action.riskLevel.toUpperCase()),
              ],
            ),
            const SizedBox(height: 8),
            Text('Incident: ${action.incidentId} • Status: ${action.status}'),
            if (needsCriticalConfirm)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Critical/High action requires typed confirmation (APPROVE/CONFIRM).',
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
