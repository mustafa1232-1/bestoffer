import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:maslaki/features/auth/state/auth_controller.dart';

import '../models/ops_incident.dart';
import '../models/ops_status.dart';
import '../services/ai_dev_support_api.dart';
import '../widgets/incident_card.dart';
import '../widgets/ops_feedback_state.dart';
import '../widgets/ops_status_card.dart';
import 'ai_dev_support_settings_screen.dart';
import 'code_fix_requests_screen.dart';
import 'incident_details_screen.dart';
import 'pending_approvals_screen.dart';

class AiDevSupportDashboardScreen extends ConsumerWidget {
  const AiDevSupportDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI DEV SUPPORT')),
        body: const OpsFeedbackState(
          icon: Icons.lock_outline_rounded,
          title: 'Access denied',
          message: 'This workspace is available to the super admin only.',
        ),
      );
    }

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI DEV SUPPORT'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Incidents'),
              Tab(text: 'Pending Approvals'),
              Tab(text: 'Code Fix Requests'),
              Tab(text: 'Notifications'),
              Tab(text: 'Settings'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OverviewTab(),
            _IncidentsTab(),
            PendingApprovalsScreen(),
            CodeFixRequestsScreen(),
            _NotificationsTab(),
            AiDevSupportSettingsScreen(),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends ConsumerStatefulWidget {
  const _OverviewTab();

  @override
  ConsumerState<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<_OverviewTab> {
  OpsStatus? _status;
  String? _error;
  bool _loading = true;

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
      final status = await ref.read(aiDevSupportApiProvider).status();
      if (!mounted) return;
      setState(() {
        _status = status;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return OpsFeedbackState(
        icon: Icons.cloud_off_rounded,
        title: 'Overview unavailable',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    final status = _status;
    if (status == null) {
      return OpsFeedbackState(
        icon: Icons.monitor_heart_outlined,
        title: 'No status data',
        message: 'The operations overview did not return any data yet.',
        actionLabel: 'Reload',
        onAction: _load,
      );
    }

    final overview = status.overview;
    final integrations = status.integrations;

    String integrationState(String key) {
      final raw = integrations[key];
      if (raw is Map) {
        final enabled = raw['enabled'];
        if (enabled == true) return 'Connected';
        if (enabled == false) return 'Disabled';
      }
      return 'Unknown';
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 320,
                child: OpsStatusCard(
                  title: 'Open Incidents',
                  value: '${overview.openIncidents}',
                  icon: Icons.error_outline,
                ),
              ),
              SizedBox(
                width: 320,
                child: OpsStatusCard(
                  title: 'SEV1 Alerts',
                  value: '${overview.sev1Open}',
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFC62828),
                ),
              ),
              SizedBox(
                width: 320,
                child: OpsStatusCard(
                  title: 'SEV2 Alerts',
                  value: '${overview.sev2Open}',
                  icon: Icons.report_problem_outlined,
                  color: const Color(0xFFEF6C00),
                ),
              ),
              SizedBox(
                width: 320,
                child: OpsStatusCard(
                  title: 'Pending Approvals',
                  value: '${overview.pendingApprovals}',
                  icon: Icons.pending_actions_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Integrations',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text('Sentry: ${integrationState('sentry')}'),
                  Text('Datadog: ${integrationState('datadog')}'),
                  Text('Railway: ${integrationState('railway')}'),
                  Text('GitHub: ${integrationState('github')}'),
                  Text('OpenAI: ${integrationState('openai')}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncidentsTab extends ConsumerStatefulWidget {
  const _IncidentsTab();

  @override
  ConsumerState<_IncidentsTab> createState() => _IncidentsTabState();
}

class _IncidentsTabState extends ConsumerState<_IncidentsTab> {
  bool _loading = true;
  String? _error;
  String _severity = 'all';
  String _status = 'all';
  String _source = 'all';
  String _search = '';
  final TextEditingController _searchController = TextEditingController();
  List<OpsIncident> _items = const <OpsIncident>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final incidents = await ref.read(aiDevSupportApiProvider).incidents(
            severity: _severity,
            status: _status,
            source: _source,
            search: _search,
          );
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return OpsFeedbackState(
        icon: Icons.error_outline_rounded,
        title: 'Unable to load incidents',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _severity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All severities')),
                    DropdownMenuItem(value: 'SEV1', child: Text('SEV1')),
                    DropdownMenuItem(value: 'SEV2', child: Text('SEV2')),
                    DropdownMenuItem(value: 'SEV3', child: Text('SEV3')),
                    DropdownMenuItem(value: 'SEV4', child: Text('SEV4')),
                  ],
                  onChanged: (value) {
                    setState(() => _severity = value ?? 'all');
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All statuses')),
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(value: 'investigating', child: Text('Investigating')),
                    DropdownMenuItem(value: 'waiting_approval', child: Text('Waiting approval')),
                    DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
                    DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                  ],
                  onChanged: (value) {
                    setState(() => _status = value ?? 'all');
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _source,
                  decoration: const InputDecoration(labelText: 'Source'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All sources')),
                    DropdownMenuItem(value: 'sentry', child: Text('Sentry')),
                    DropdownMenuItem(value: 'datadog', child: Text('Datadog')),
                    DropdownMenuItem(value: 'railway', child: Text('Railway')),
                    DropdownMenuItem(value: 'github_actions', child: Text('GitHub Actions')),
                    DropdownMenuItem(value: 'manual', child: Text('Manual')),
                  ],
                  onChanged: (value) {
                    setState(() => _source = value ?? 'all');
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search',
                    suffixIcon: IconButton(
                      onPressed: () {
                        _searchController.clear();
                        _search = '';
                        _load();
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  ),
                  onSubmitted: (value) {
                    _search = value.trim();
                    _load();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            const SizedBox(
              height: 260,
              child: OpsFeedbackState(
                icon: Icons.rule_folder_outlined,
                title: 'No incidents found',
                message: 'There are no incidents matching the current filters.',
              ),
            ),
          for (final incident in _items)
            IncidentCard(
              incident: incident,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => IncidentDetailsScreen(incidentId: incident.id),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _NotificationsTab extends ConsumerStatefulWidget {
  const _NotificationsTab();

  @override
  ConsumerState<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends ConsumerState<_NotificationsTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

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
      final logs = await ref.read(aiDevSupportApiProvider).auditLogs();
      if (!mounted) return;
      setState(() {
        _items = logs;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return OpsFeedbackState(
        icon: Icons.notifications_off_outlined,
        title: 'Notifications unavailable',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent ops notifications and audit events',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await ref.read(aiDevSupportApiProvider).incidents();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notification test completed')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$e')),
                    );
                  }
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Test notification'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_items.isEmpty)
            const SizedBox(
              height: 220,
              child: OpsFeedbackState(
                icon: Icons.notifications_paused_outlined,
                title: 'No notification events yet',
                message:
                    'Ops audit and notification events will appear here once they start flowing.',
              ),
            ),
          for (final row in _items.take(80))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${row['action'] ?? 'event'}'),
                subtitle: Text(
                  '${row['target_type'] ?? ''} #${row['target_id'] ?? '-'}\n${row['created_at'] ?? ''}',
                ),
                isThreeLine: true,
              ),
            ),
        ],
      ),
    );
  }
}
