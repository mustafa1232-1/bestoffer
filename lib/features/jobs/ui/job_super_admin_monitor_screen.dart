import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/parsers.dart';
import '../../auth/state/auth_controller.dart';
import '../job_portal_text.dart';
import '../models/job_models.dart';
import 'job_application_details_screen.dart';
import 'job_applications_screen.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class JobSuperAdminMonitorScreen extends ConsumerStatefulWidget {
  const JobSuperAdminMonitorScreen({super.key});

  @override
  ConsumerState<JobSuperAdminMonitorScreen> createState() =>
      _JobSuperAdminMonitorScreenState();
}

class _JobSuperAdminMonitorScreenState
    extends ConsumerState<JobSuperAdminMonitorScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _loadingMeta = true;

  int _totalApplications = 0;
  List<JobApplicationModel> _applications = const [];
  List<JobTalentPoolGroupModel> _groups = const [];

  String? _status;
  String? _category;
  String? _activityType;
  String? _department;
  int? _jobId;

  JobFilterMetaModel _meta = const JobFilterMetaModel(
    categories: [],
    cities: [],
    areas: [],
    activityTypes: [],
    departmentsByActivity: {},
    employmentTypes: [],
    workplaceTypes: [],
    experienceLevels: [],
    salaryPeriods: [],
    sortOptions: ['recent', 'salary_high', 'salary_low', 'expires_soon'],
  );

  bool get _canOpen => ref.read(authControllerProvider).isSuperAdmin;

  List<(String?, String)> get _statusOptions => [
    (null, jobApplicationStatusGroupLabel(context, null)),
    ('submitted', jobApplicationStatusGroupLabel(context, 'submitted')),
    ('shortlisted', jobApplicationStatusGroupLabel(context, 'shortlisted')),
    ('rejected', jobApplicationStatusGroupLabel(context, 'rejected')),
    ('hired', jobApplicationStatusGroupLabel(context, 'hired')),
    ('withdrawn', jobApplicationStatusGroupLabel(context, 'withdrawn')),
    (
      'dismissed_after_hire',
      jobApplicationStatusGroupLabel(context, 'dismissed_after_hire'),
    ),
    ('archived', jobApplicationStatusGroupLabel(context, 'archived')),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadMeta(), _loadData()]);
  }

  Future<void> _loadMeta() async {
    if (!_canOpen) return;
    setState(() => _loadingMeta = true);
    try {
      final raw = await ref.read(jobsApiClientProvider).filterMeta();
      if (!mounted) return;
      setState(() {
        _meta = JobFilterMetaModel.fromJson(raw);
        _loadingMeta = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMeta = false);
    }
  }

  Future<void> _loadData() async {
    if (!_canOpen) return;
    setState(() => _loading = true);
    try {
      final raw = await ref
          .read(jobsApiClientProvider)
          .listSuperAdminApplicationsMonitor(
            search: _searchCtrl.text.trim().isEmpty
                ? null
                : _searchCtrl.text.trim(),
            status: _status,
            category: _category,
            activityType: _activityType,
            department: _department,
            jobId: _jobId,
            page: 1,
            limit: 150,
          );

      final rawGroups = raw['groups'] is List
          ? raw['groups'] as List
          : const [];
      final groups = rawGroups
          .whereType<Map>()
          .map(
            (entry) => JobTalentPoolGroupModel.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(growable: false);

      final rawAppsRoot = raw['applications'];
      final rawAppsMap = rawAppsRoot is Map
          ? Map<String, dynamic>.from(rawAppsRoot)
          : const <String, dynamic>{};
      final rawItems = rawAppsMap['items'] is List
          ? rawAppsMap['items'] as List
          : const [];
      final applications = rawItems
          .whereType<Map>()
          .map(
            (entry) =>
                JobApplicationModel.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _applications = applications;
        _totalApplications = parseInt(
          rawAppsMap['total'],
          fallback: applications.length,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(
        mapAnyError(e, fallback: context.l10n.jobSuperAdminMonitorLoadFailed),
      );
    }
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

  String _statusLabel(String status) {
    return jobApplicationStatusLabel(context, status);
  }

  Color _statusColor(String status) {
    return switch (status) {
      'submitted' => const Color(0xFF7DC9FF),
      'shortlisted' => const Color(0xFF53D593),
      'rejected' => const Color(0xFFFF8A8A),
      'hired' => const Color(0xFF31D7B3),
      'withdrawn' => const Color(0xFFFFB35C),
      'dismissed_after_hire' => const Color(0xFFFF986E),
      'archived' => const Color(0xFFB7C0D1),
      _ => Colors.white70,
    };
  }

  Future<void> _openApplication(JobApplicationModel item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobApplicationDetailsScreen(
          application: item,
          onChangeStatus: null,
        ),
      ),
    );
  }

  Future<void> _openFilters() async {
    String? tmpStatus = _status;
    String? tmpCategory = _category;
    String? tmpActivity = _activityType;
    String? tmpDepartment = _department;
    final jobIdCtrl = TextEditingController(text: _jobId?.toString() ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final departments = tmpActivity == null
                ? const <String>[]
                : (_meta.departmentsByActivity[tmpActivity!] ??
                      const <String>[]);
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 14,
                  right: 14,
                  top: 14,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 14,
                ),
                child: Directionality(
                  textDirection: Directionality.of(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.l10n.jobSuperAdminMonitorFiltersTitle,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        initialValue: tmpStatus,
                        decoration: InputDecoration(
                          labelText: context.l10n.commonStatus,
                        ),
                        items: _statusOptions
                            .map(
                              (entry) => DropdownMenuItem<String?>(
                                value: entry.$1,
                                child: Text(entry.$2),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setModalState(() => tmpStatus = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        initialValue: tmpActivity,
                        decoration: InputDecoration(
                          labelText: context.l10n.commonActivity,
                        ),
                        items: <DropdownMenuItem<String?>>[
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(context.l10n.commonAll),
                          ),
                          ..._meta.activityTypes.map(
                            (value) => DropdownMenuItem<String?>(
                              value: value,
                              child: Text(_taxonomyLabel(value)),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setModalState(() {
                            tmpActivity = value;
                            if (value == null ||
                                !(_meta.departmentsByActivity[value] ??
                                        const [])
                                    .contains(tmpDepartment)) {
                              tmpDepartment = null;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        initialValue: tmpDepartment,
                        decoration: InputDecoration(
                          labelText: context.l10n.commonDepartment,
                        ),
                        items: <DropdownMenuItem<String?>>[
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(context.l10n.commonAll),
                          ),
                          ...departments.map(
                            (value) => DropdownMenuItem<String?>(
                              value: value,
                              child: Text(_taxonomyLabel(value)),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setModalState(() => tmpDepartment = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        initialValue: tmpCategory,
                        decoration: InputDecoration(
                          labelText: context.l10n.commonCategory,
                        ),
                        items: <DropdownMenuItem<String?>>[
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(context.l10n.commonAll),
                          ),
                          ..._meta.categories.map(
                            (value) => DropdownMenuItem<String?>(
                              value: value,
                              child: Text(value),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setModalState(() => tmpCategory = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: jobIdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText:
                              context.l10n.jobSuperAdminMonitorJobIdLabel,
                          hintText: context.l10n.jobSuperAdminMonitorJobIdHint,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                setState(() {
                                  _status = null;
                                  _category = null;
                                  _activityType = null;
                                  _department = null;
                                  _jobId = null;
                                });
                                _loadData();
                              },
                              child: Text(context.l10n.commonReset),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                setState(() {
                                  _status = tmpStatus;
                                  _category = tmpCategory;
                                  _activityType = tmpActivity;
                                  _department = tmpDepartment;
                                  final rawJobId = jobIdCtrl.text.trim();
                                  _jobId = rawJobId.isEmpty
                                      ? null
                                      : int.tryParse(rawJobId);
                                });
                                _loadData();
                              },
                              child: Text(context.l10n.commonApply),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    jobIdCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!_canOpen) {
      return Scaffold(
        body: Center(child: Text(l10n.jobSuperAdminMonitorSuperAdminOnly)),
      );
    }

    final submitted = _groups.fold<int>(
      0,
      (sum, item) => sum + item.submittedCount,
    );
    final shortlisted = _groups.fold<int>(
      0,
      (sum, item) => sum + item.shortlistedCount,
    );
    final rejected = _groups.fold<int>(
      0,
      (sum, item) => sum + item.rejectedCount,
    );
    final hired = _groups.fold<int>(0, (sum, item) => sum + item.hiredCount);
    final withdrawn = _groups.fold<int>(
      0,
      (sum, item) => sum + item.withdrawnCount,
    );
    final dismissedAfterHire = _groups.fold<int>(
      0,
      (sum, item) => sum + item.dismissedAfterHireCount,
    );
    final archived = _groups.fold<int>(
      0,
      (sum, item) => sum + item.archivedCount,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.jobSuperAdminMonitorTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonFilters,
            onPressed: _loadingMeta ? null : _openFilters,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: Directionality.of(context),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0xFF1C4D87), Color(0xFF10345F)],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.jobSuperAdminMonitorHeroTitle,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.jobSuperAdminMonitorHeroSubtitle,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.84),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _statBadge(
                                l10n.jobSuperAdminMonitorTotalApplications,
                                _totalApplications,
                              ),
                              _statBadge(
                                jobApplicationStatusGroupLabel(
                                  context,
                                  'submitted',
                                ),
                                submitted,
                              ),
                              _statBadge(
                                jobApplicationStatusGroupLabel(
                                  context,
                                  'shortlisted',
                                ),
                                shortlisted,
                              ),
                              _statBadge(
                                jobApplicationStatusGroupLabel(
                                  context,
                                  'rejected',
                                ),
                                rejected,
                              ),
                              _statBadge(
                                jobApplicationStatusGroupLabel(
                                  context,
                                  'hired',
                                ),
                                hired,
                              ),
                              _statBadge(
                                jobApplicationStatusGroupLabel(
                                  context,
                                  'withdrawn',
                                ),
                                withdrawn,
                              ),
                              _statBadge(
                                jobApplicationStatusGroupLabel(
                                  context,
                                  'dismissed_after_hire',
                                ),
                                dismissedAfterHire,
                              ),
                              _statBadge(
                                jobApplicationStatusGroupLabel(
                                  context,
                                  'archived',
                                ),
                                archived,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: l10n.jobSuperAdminMonitorSearchHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                          ),
                          onSubmitted: (_) => _loadData(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _loading ? null : _loadData,
                        child: Text(l10n.commonSearch),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                        children: [
                          if (_groups.isNotEmpty) ...[
                            Text(
                              l10n.jobSuperAdminMonitorDistributionTitle,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _groups
                                  .map(
                                    (group) => _groupChip(
                                      '${_taxonomyLabel(group.activityType)} / ${_taxonomyLabel(group.department)}',
                                      group.totalApplications,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_applications.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text(l10n.jobSuperAdminMonitorEmpty),
                              ),
                            )
                          else
                            ..._applications.map((item) {
                              final statusColor = _statusColor(item.status);
                              final applicantName =
                                  item.profileFullName ??
                                  item.fullName ??
                                  l10n.jobApplicationDetailsApplicantFallback;
                              final subtitleParts = <String>[
                                item.jobTitle ?? '-',
                                item.jobCompanyName ?? '-',
                              ];
                              if (item.jobCategory?.trim().isNotEmpty == true) {
                                subtitleParts.add(item.jobCategory!);
                              }

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _openApplication(item),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          backgroundImage:
                                              item
                                                      .applicantImageUrl
                                                      ?.isNotEmpty ==
                                                  true
                                              ? AppCachedImageProvider(
                                                  item.applicantImageUrl!,
                                                )
                                              : null,
                                          child:
                                              item
                                                      .applicantImageUrl
                                                      ?.isNotEmpty ==
                                                  true
                                              ? null
                                              : const Icon(
                                                  Icons.person_outline,
                                                ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                applicantName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                subtitleParts.join(' - '),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.right,
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                item.profilePhone ??
                                                    item.submittedPhone ??
                                                    '-',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.78),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                      color: statusColor
                                                          .withValues(
                                                            alpha: 0.16,
                                                          ),
                                                      border: Border.all(
                                                        color: statusColor
                                                            .withValues(
                                                              alpha: 0.45,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      _statusLabel(item.status),
                                                      style: TextStyle(
                                                        color: statusColor,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 11.5,
                                                      ),
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  IconButton(
                                                    tooltip: l10n.commonDetails,
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    onPressed: () =>
                                                        _openApplication(item),
                                                    icon: const Icon(
                                                      Icons.open_in_new_rounded,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBadge(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  Widget _groupChip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        color: Colors.white.withValues(alpha: 0.05),
      ),
      child: Text(
        '$label ($count)',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
