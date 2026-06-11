import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../models/job_models.dart';
import '../job_portal_text.dart';
import 'job_applications_screen.dart';

class JobTalentPoolScreen extends ConsumerStatefulWidget {
  const JobTalentPoolScreen({super.key});

  @override
  ConsumerState<JobTalentPoolScreen> createState() =>
      _JobTalentPoolScreenState();
}

class _JobTalentPoolScreenState extends ConsumerState<JobTalentPoolScreen> {
  bool _loading = true;
  List<JobTalentPoolGroupModel> _groups = const [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _canOpen {
    final auth = ref.read(authControllerProvider);
    return auth.isSuperAdmin || auth.isAdmin || auth.isOwner || auth.isHr;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _taxonomyLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return '-';
    return cleaned
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Future<void> _load() async {
    if (!_canOpen) return;
    setState(() => _loading = true);
    try {
      final search = _searchCtrl.text.trim();
      final raw = await ref
          .read(jobsApiClientProvider)
          .listTalentPoolGroups(search: search.isEmpty ? null : search);
      final rawGroups = raw['groups'] is List
          ? raw['groups'] as List
          : const [];
      final groups = rawGroups
          .whereType<Map>()
          .map(
            (e) =>
                JobTalentPoolGroupModel.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(
        mapAnyError(
          e,
          fallback: context.l10n.jobTalentPoolLoadFailed,
        ),
      );
    }
  }

  Future<void> _openGroup(JobTalentPoolGroupModel group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobApplicationsScreen(
          initialActivityType: group.activityType,
          initialDepartment: group.department,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!_canOpen) {
      return Scaffold(
        body: Center(
          child: Text(
            l10n.jobTalentPoolManagementOnly,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.jobTalentPoolTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: Directionality.of(context),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: l10n.jobTalentPoolSearchHint,
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _load,
                    child: Text(l10n.commonSearch),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _groups.isEmpty
                  ? Center(
                      child: Text(
                        l10n.jobTalentPoolEmpty,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _groups.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final group = _groups[index];
                        return Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _openGroup(group),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${_taxonomyLabel(group.activityType)} / ${_taxonomyLabel(group.department)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _chip(
                                        '${l10n.jobTalentPoolApplications}: ${group.totalApplications}',
                                      ),
                                      _chip(
                                        '${l10n.jobTalentPoolApplicants}: ${group.uniqueApplicants}',
                                      ),
                                      _chip(
                                        '${jobApplicationStatusGroupLabel(context, 'shortlisted')}: ${group.shortlistedCount}',
                                      ),
                                      _chip(
                                        '${jobApplicationStatusGroupLabel(context, 'rejected')}: ${group.rejectedCount}',
                                      ),
                                      _chip(
                                        '${jobApplicationStatusGroupLabel(context, 'hired')}: ${group.hiredCount}',
                                      ),
                                      _chip(
                                        '${jobApplicationStatusGroupLabel(context, 'withdrawn')}: ${group.withdrawnCount}',
                                      ),
                                      _chip(
                                        '${jobApplicationStatusGroupLabel(context, 'dismissed_after_hire')}: ${group.dismissedAfterHireCount}',
                                      ),
                                      _chip(
                                        '${jobApplicationStatusGroupLabel(context, 'archived')}: ${group.archivedCount}',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    group.lastApplicationAt == null
                                        ? '${l10n.jobTalentPoolLastApplication}: -'
                                        : '${l10n.jobTalentPoolLastApplication}: ${'${group.lastApplicationAt!.toLocal()}'.split('.').first}',
                                    textAlign: TextAlign.right,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
