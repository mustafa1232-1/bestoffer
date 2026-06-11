import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ops_action.dart';
import '../services/ai_dev_support_api.dart';
import '../widgets/approval_action_card.dart';
import '../widgets/ops_feedback_state.dart';

class PendingApprovalsScreen extends ConsumerStatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  ConsumerState<PendingApprovalsScreen> createState() =>
      _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends ConsumerState<PendingApprovalsScreen> {
  bool _loading = true;
  String? _error;
  List<OpsAction> _items = const <OpsAction>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref.read(aiDevSupportApiProvider).pendingActions();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _approve(OpsAction action) async {
    String confirmation = '';
    final risk = action.riskLevel.toLowerCase();
    if (risk == 'high' || risk == 'critical') {
      confirmation = await _askForTypedConfirmation() ?? '';
      if (confirmation.isEmpty) return;
    }

    try {
      await ref.read(aiDevSupportApiProvider).approveAction(
            incidentId: action.incidentId,
            actionId: action.id,
            confirmationText: confirmation,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action approved')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reject(OpsAction action) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject action'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: 'Rejection reason'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reasonController.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if ((reason ?? '').trim().isEmpty) return;

    try {
      await ref
          .read(aiDevSupportApiProvider)
          .rejectAction(incidentId: action.incidentId, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action rejected')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<String?> _askForTypedConfirmation() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm critical action'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Type APPROVE or CONFIRM.'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'APPROVE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return OpsFeedbackState(
        icon: Icons.pending_actions_outlined,
        title: 'Pending approvals unavailable',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(
              height: 280,
              child: OpsFeedbackState(
                icon: Icons.verified_outlined,
                title: 'No pending approvals',
                message:
                    'Approval-required actions will appear here when the ops engine pauses a critical step.',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final action = _items[index];
          return ApprovalActionCard(
            action: action,
            onApprove: () => _approve(action),
            onReject: () => _reject(action),
          );
        },
      ),
    );
  }
}
