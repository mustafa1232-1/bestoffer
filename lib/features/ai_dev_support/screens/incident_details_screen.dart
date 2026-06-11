import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ai_dev_support_api.dart';
import '../widgets/incident_timeline.dart';
import '../widgets/ops_feedback_state.dart';
import '../widgets/severity_badge.dart';

class IncidentDetailsScreen extends ConsumerStatefulWidget {
  final int incidentId;

  const IncidentDetailsScreen({super.key, required this.incidentId});

  @override
  ConsumerState<IncidentDetailsScreen> createState() =>
      _IncidentDetailsScreenState();
}

class _IncidentDetailsScreenState extends ConsumerState<IncidentDetailsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _item;
  List<Map<String, dynamic>> _auditLogs = const <Map<String, dynamic>>[];

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
      final api = ref.read(aiDevSupportApiProvider);
      final detail = await api.incidentDetails(widget.incidentId);
      final logs = await api.auditLogs(incidentId: widget.incidentId);
      if (!mounted) return;
      setState(() {
        _item = detail['item'] is Map<String, dynamic>
            ? detail['item'] as Map<String, dynamic>
            : null;
        _auditLogs = logs;
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

  Future<void> _createIssue() async {
    try {
      await ref
          .read(aiDevSupportApiProvider)
          .createGithubIssue(incidentId: widget.incidentId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('GitHub issue created')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _requestCodeFix() async {
    try {
      await ref
          .read(aiDevSupportApiProvider)
          .requestCodeFix(incidentId: widget.incidentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code fix request submitted')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _markResolved() async {
    try {
      await ref
          .read(aiDevSupportApiProvider)
          .markResolved(incidentId: widget.incidentId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Incident marked resolved')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _approveAction() async {
    final riskLevel = '${_item?['risk_level'] ?? ''}'.toLowerCase();
    String confirmationText = '';

    if (riskLevel == 'high' || riskLevel == 'critical') {
      confirmationText = await _showCriticalConfirmDialog() ?? '';
      if (confirmationText.isEmpty) return;
    }

    try {
      await ref.read(aiDevSupportApiProvider).approveAction(
        incidentId: widget.incidentId,
        confirmationText: confirmationText,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Action approved')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _rejectAction() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject action'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if ((reason ?? '').isEmpty) return;

    try {
      await ref
          .read(aiDevSupportApiProvider)
          .rejectAction(incidentId: widget.incidentId, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Action rejected')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<String?> _showCriticalConfirmDialog() {
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
            const Text('Type APPROVE or CONFIRM to continue.'),
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

  Future<void> _copyReport() async {
    final item = _item;
    if (item == null) return;
    final buffer = StringBuffer()
      ..writeln('Incident #${item['id']}')
      ..writeln('Title: ${item['title']}')
      ..writeln('Severity: ${item['severity']}')
      ..writeln('Status: ${item['status']}')
      ..writeln('Risk: ${item['risk_level']}')
      ..writeln('Module: ${item['affected_module']}')
      ..writeln('Summary: ${item['summary']}')
      ..writeln('Root cause: ${item['probable_root_cause']}')
      ..writeln('Mitigation: ${item['suggested_mitigation']}')
      ..writeln('Long fix: ${item['long_term_fix']}');
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Incident report copied')));
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;

    return Scaffold(
      appBar: AppBar(
        title: Text('Incident #${widget.incidentId}'),
        actions: [
          IconButton(
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy report',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? OpsFeedbackState(
              icon: Icons.find_in_page_outlined,
              title: 'Incident details unavailable',
              message: _error!,
              actionLabel: 'Retry',
              onAction: _load,
            )
          : item == null
          ? const OpsFeedbackState(
              icon: Icons.search_off_rounded,
              title: 'Incident not found',
              message:
                  'The requested incident could not be found or may no longer be accessible.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item['title'] ?? 'Incident'}',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      SeverityBadge(severity: '${item['severity'] ?? 'SEV3'}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Status: ${item['status']} • Risk: ${item['risk_level']} • Source: ${item['source']}',
                  ),
                  const SizedBox(height: 12),
                  if ((item['summary'] ?? '').toString().isNotEmpty)
                    Text('${item['summary']}'),
                  const SizedBox(height: 12),
                  Text(
                    'Probable root cause:\n${item['probable_root_cause'] ?? 'n/a'}',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Immediate mitigation:\n${item['suggested_mitigation'] ?? 'n/a'}',
                  ),
                  const SizedBox(height: 10),
                  Text('Long-term fix:\n${item['long_term_fix'] ?? 'n/a'}'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _createIssue,
                        icon: const Icon(Icons.bug_report_outlined),
                        label: const Text('Create GitHub Issue'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _requestCodeFix,
                        icon: const Icon(Icons.code_off_outlined),
                        label: const Text('Request code fix'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _approveAction,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Approve action'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _rejectAction,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Reject action'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _markResolved,
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Mark resolved'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Audit timeline',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  IncidentTimeline(logs: _auditLogs),
                ],
              ),
            ),
    );
  }
}
