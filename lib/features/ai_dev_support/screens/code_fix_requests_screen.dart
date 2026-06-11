import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:maslaki/features/ai_dev_support/models/ops_incident.dart';
import 'package:maslaki/features/ai_dev_support/services/ai_dev_support_api.dart';
import 'package:maslaki/features/ai_dev_support/widgets/ops_feedback_state.dart';
import 'package:maslaki/features/ai_dev_support/widgets/severity_badge.dart';

class CodeFixRequestsScreen extends ConsumerStatefulWidget {
  const CodeFixRequestsScreen({super.key});

  @override
  ConsumerState<CodeFixRequestsScreen> createState() =>
      _CodeFixRequestsScreenState();
}

class _CodeFixRequestsScreenState extends ConsumerState<CodeFixRequestsScreen> {
  bool _loading = true;
  String? _error;
  List<OpsIncident> _items = const <OpsIncident>[];

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
      final incidents = await ref.read(aiDevSupportApiProvider).incidents(status: 'all');
      if (!mounted) return;
      setState(() {
        _items = incidents;
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

  Future<void> _createIssue(int incidentId) async {
    try {
      await ref.read(aiDevSupportApiProvider).createGithubIssue(incidentId: incidentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Issue created')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _requestFix(int incidentId) async {
    try {
      await ref.read(aiDevSupportApiProvider).requestCodeFix(incidentId: incidentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code fix requested')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return OpsFeedbackState(
        icon: Icons.code_off_outlined,
        title: 'Code fix requests unavailable',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: _items.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(
                  height: 260,
                  child: OpsFeedbackState(
                    icon: Icons.integration_instructions_outlined,
                    title: 'No code fix requests',
                    message:
                        'There are no incidents requiring issue creation or code-fix requests right now.',
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final incident = _items[index];
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
                                '${incident.title} (#${incident.id})',
                                style: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                            SeverityBadge(severity: incident.severity),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Risk: ${incident.riskLevel} | Status: ${incident.status}',
                        ),
                        if ((incident.summary ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(incident.summary!),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _createIssue(incident.id),
                              icon: const Icon(Icons.bug_report_outlined),
                              label: const Text('Create issue'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _requestFix(incident.id),
                              icon: const Icon(Icons.code_outlined),
                              label: const Text('Request code fix'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
