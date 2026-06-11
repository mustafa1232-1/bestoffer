import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/parsers.dart';
import '../../auth/state/auth_controller.dart';
import '../data/jobs_api.dart';
import '../models/job_models.dart';
import 'job_apply_screen.dart';
import 'job_admin_jobs_reader_screen.dart';
import 'job_applications_screen.dart';
import 'job_my_applications_screen.dart';
import 'job_super_admin_monitor_screen.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

final jobsApiProvider = Provider<JobsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return JobsApi(dio);
});

class JobsHubScreen extends ConsumerStatefulWidget {
  final bool startInManageMode;

  const JobsHubScreen({super.key, this.startInManageMode = false});

  @override
  ConsumerState<JobsHubScreen> createState() => _JobsHubScreenState();
}

class _JobsHubScreenState extends ConsumerState<JobsHubScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _loadingMeta = true;
  bool _loadingMore = false;
  bool _busyAction = false;

  bool _manageMode = false;
  bool _onlyOpen = true;

  int _page = 1;
  final int _limit = 20;
  int _total = 0;
  bool _hasMore = true;

  String _sort = 'recent';
  String? _search;
  String? _category;
  String? _activityType;
  String? _department;
  String? _city;
  String? _area;
  String? _employmentType;
  String? _workplaceType;
  String? _experienceLevel;
  String? _statusFilter;
  double? _minSalary;
  double? _maxSalary;

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
  List<JobPostModel> _jobs = const [];

  bool get _canManageJobs {
    final auth = ref.read(authControllerProvider);
    return auth.isAdmin || auth.isOwner || auth.isHr || auth.isSuperAdmin;
  }

  bool get _isSuperAdmin => ref.read(authControllerProvider).isSuperAdmin;

  bool get _canApplyJobs {
    final role =
        ref.read(authControllerProvider).user?.role.toLowerCase() ?? '';
    return role == 'user';
  }

  bool get _canOpenTalentPool {
    final auth = ref.read(authControllerProvider);
    return auth.isSuperAdmin;
  }

  @override
  void initState() {
    super.initState();
    _manageMode = widget.startInManageMode && _canManageJobs;
    _onlyOpen = !_manageMode;
    _scrollController.addListener(_onScroll);
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait(<Future<void>>[_loadMeta(), _loadJobs(reset: true)]);
  }

  Future<void> _loadMeta() async {
    setState(() => _loadingMeta = true);
    try {
      final raw = await ref.read(jobsApiProvider).filterMeta();
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

  Future<void> _loadJobs({required bool reset}) async {
    if (_loadingMore || _busyAction) return;
    if (reset) {
      setState(() {
        _loading = true;
        _page = 1;
        _hasMore = true;
      });
    } else {
      if (!_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final api = ref.read(jobsApiProvider);
      final queryPage = reset ? 1 : _page + 1;
      Map<String, dynamic> raw;
      if (_manageMode) {
        try {
          raw = await api.listManagedJobs(
            search: _search,
            category: _category,
            activityType: _activityType,
            department: _department,
            city: _city,
            area: _area,
            employmentType: _employmentType,
            workplaceType: _workplaceType,
            experienceLevel: _experienceLevel,
            status: _statusFilter,
            sort: _sort,
            minSalary: _minSalary,
            maxSalary: _maxSalary,
            onlyOpen: _onlyOpen,
            page: queryPage,
            limit: _limit,
          );
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) {
            raw = await api.listJobs(
              search: _search,
              category: _category,
              activityType: _activityType,
              department: _department,
              city: _city,
              area: _area,
              employmentType: _employmentType,
              workplaceType: _workplaceType,
              experienceLevel: _experienceLevel,
              sort: _sort,
              minSalary: _minSalary,
              maxSalary: _maxSalary,
              onlyOpen: _onlyOpen,
              page: queryPage,
              limit: _limit,
            );
          } else {
            rethrow;
          }
        }
      } else {
        raw = await api.listJobs(
          search: _search,
          category: _category,
          activityType: _activityType,
          department: _department,
          city: _city,
          area: _area,
          employmentType: _employmentType,
          workplaceType: _workplaceType,
          experienceLevel: _experienceLevel,
          sort: _sort,
          minSalary: _minSalary,
          maxSalary: _maxSalary,
          onlyOpen: _onlyOpen,
          page: queryPage,
          limit: _limit,
        );
      }
      final rawItems = raw['items'] is List ? raw['items'] as List : const [];
      final items = rawItems
          .whereType<Map>()
          .map((e) => JobPostModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      final total = parseInt(raw['total']);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _page = queryPage;
        _total = total;
        _jobs = reset ? items : [..._jobs, ...items];
        _hasMore = _jobs.length < total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      _snack(mapAnyError(e, fallback: context.l10n.jobsHubLoadFailed));
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 220) {
      _loadJobs(reset: false);
    }
  }

  Future<void> _refresh() async {
    await _loadJobs(reset: true);
  }

  int _countByStatus(String status) {
    return _jobs.where((job) => job.status == status).length;
  }

  Future<void> _applyOpenOnlyFilter(bool openOnly) async {
    if (_onlyOpen == openOnly && _statusFilter == null) return;
    setState(() {
      _onlyOpen = openOnly;
      _statusFilter = null;
    });
    await _loadJobs(reset: true);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _applySearch() async {
    _search = _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim();
    await _loadJobs(reset: true);
  }

  Future<void> _toggleMode(bool manageMode) async {
    if (!_canManageJobs) return;
    if (_manageMode == manageMode) return;
    setState(() {
      _manageMode = manageMode;
      _onlyOpen = !_manageMode;
      _statusFilter = null;
    });
    await _loadJobs(reset: true);
  }

  Future<void> _openFiltersSheet() async {
    final result = await showModalBottomSheet<_JobFilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _JobsFilterSheet(
          meta: _meta,
          initial: _JobFilterResult(
            category: _category,
            activityType: _activityType,
            department: _department,
            city: _city,
            area: _area,
            employmentType: _employmentType,
            workplaceType: _workplaceType,
            experienceLevel: _experienceLevel,
            status: _statusFilter,
            minSalary: _minSalary,
            maxSalary: _maxSalary,
            sort: _sort,
            onlyOpen: _onlyOpen,
            manageMode: _manageMode,
          ),
        );
      },
    );
    if (result == null) return;
    setState(() {
      _category = result.category;
      _activityType = result.activityType;
      _department = result.department;
      _city = result.city;
      _area = result.area;
      _employmentType = result.employmentType;
      _workplaceType = result.workplaceType;
      _experienceLevel = result.experienceLevel;
      _statusFilter = result.status;
      _minSalary = result.minSalary;
      _maxSalary = result.maxSalary;
      _sort = result.sort;
      _onlyOpen = result.onlyOpen;
    });
    await _loadJobs(reset: true);
  }

  Future<void> _clearFilters() async {
    setState(() {
      _searchCtrl.clear();
      _search = null;
      _category = null;
      _activityType = null;
      _department = null;
      _city = null;
      _area = null;
      _employmentType = null;
      _workplaceType = null;
      _experienceLevel = null;
      _statusFilter = null;
      _minSalary = null;
      _maxSalary = null;
      _sort = 'recent';
      _onlyOpen = !_manageMode;
    });
    await _loadJobs(reset: true);
  }

  Future<void> _openCreateJobSheet() async {
    if (!_canManageJobs) return;
    final l10n = context.l10n;
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateJobSheet(meta: _meta),
    );
    if (payload == null) return;

    setState(() => _busyAction = true);
    try {
      await ref.read(jobsApiProvider).createJob(payload);
      if (!mounted) return;
      _snack(l10n.jobsHubPostedSuccess);
      await _loadJobs(reset: true);
    } catch (e) {
      _snack(mapAnyError(e, fallback: l10n.jobsHubPublishFailed));
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<JobPostModel?> _fetchJobDetails(int jobId) async {
    final l10n = context.l10n;
    try {
      final raw = await ref.read(jobsApiProvider).getJobById(jobId);
      final data = raw['job'];
      if (data is Map) {
        return JobPostModel.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      _snack(mapAnyError(e, fallback: l10n.jobsHubLoadDetailsFailed));
    }
    return null;
  }

  Future<void> _openJobDetails(JobPostModel job) async {
    final details = await _fetchJobDetails(job.id);
    if (!mounted || details == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _JobDetailsSheet(
        job: details,
        canApply: _canApplyJobs,
        canManage: _canManageJobs && details.canManage,
        onApply: () => _openApplySheet(details),
        onViewApplications: () => _openApplicationsForJob(details),
        onSetStatus: (status) => _changeJobStatus(details, status),
        onDelete: () => _deleteJob(details),
      ),
    );
  }

  Future<void> _changeJobStatus(JobPostModel job, String status) async {
    setState(() => _busyAction = true);
    try {
      final raw = await ref
          .read(jobsApiProvider)
          .updateJobStatus(jobId: job.id, status: status);
      final data = raw['job'];
      if (data is Map) {
        final updated = JobPostModel.fromJson(Map<String, dynamic>.from(data));
        _replaceJob(updated);
      } else {
        _replaceJob(job.copyWith(status: status));
      }
      if (!mounted) return;
      _snack(context.l10n.jobsHubJobStatusUpdated);
      Navigator.of(context).pop();
    } catch (e) {
      _snack(mapAnyError(e, fallback: context.l10n.jobsHubUpdateStatusFailed));
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _deleteJob(JobPostModel job) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.jobsHubDeleteJob),
        content: Text(l10n.jobsHubDeleteConfirm(job.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyAction = true);
    try {
      await ref.read(jobsApiProvider).deleteJob(job.id);
      if (!mounted) return;
      setState(() {
        _jobs = _jobs
            .where((item) => item.id != job.id)
            .toList(growable: false);
        _total = _total > 0 ? _total - 1 : 0;
      });
      _snack(l10n.jobsHubJobDeleted);
      Navigator.of(context).pop();
    } catch (e) {
      _snack(mapAnyError(e, fallback: l10n.jobsHubDeleteFailed));
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _openApplySheet(JobPostModel job) async {
    if (!_canApplyJobs) return;
    final phoneDefault = ref.read(authControllerProvider).user?.phone ?? '';
    final l10n = context.l10n;
    final payload = await Navigator.of(context).push<JobApplyDraft>(
      MaterialPageRoute(
        builder: (_) => JobApplyScreen(job: job, defaultPhone: phoneDefault),
      ),
    );
    if (payload == null) return;

    setState(() => _busyAction = true);
    try {
      await ref
          .read(jobsApiProvider)
          .applyToJob(
            jobId: job.id,
            message: payload.message,
            phone: payload.phone,
            email: payload.email,
            expectedSalary: payload.expectedSalary,
            attachmentFile: payload.attachmentFile,
          );
      if (!mounted) return;
      _replaceJob(
        job.copyWith(
          hasApplied: true,
          applicationsCount: job.applicationsCount + 1,
        ),
      );
      _snack(l10n.jobsHubApplicationSubmitted);
      Navigator.of(context).pop();
    } catch (e) {
      _snack(mapAnyError(e, fallback: l10n.jobsHubApplicationFailed));
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _openApplicationsInbox() async {
    if (!_canManageJobs) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const JobApplicationsScreen()));
  }

  Future<void> _openMyApplications() async {
    if (!_canApplyJobs) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const JobMyApplicationsScreen()));
  }

  Future<void> _openTalentPool() async {
    if (!_canOpenTalentPool) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const JobSuperAdminMonitorScreen()),
    );
  }

  Future<void> _openAdminJobReader() async {
    if (!_canManageJobs) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const JobAdminJobsReaderScreen()));
  }

  Future<void> _openApplicationsForJob(JobPostModel job) async {
    if (!_canManageJobs) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobApplicationsScreen(
          initialJobId: job.id,
          initialJobTitle: job.title,
        ),
      ),
    );
  }

  void _replaceJob(JobPostModel job) {
    setState(() {
      _jobs = _jobs
          .map((item) => item.id == job.id ? job : item)
          .toList(growable: false);
    });
  }

  String _typeLabel(String value) {
    switch (value) {
      case 'full_time':
        return context.l10n.jobsHubFullTime;
      case 'part_time':
        return context.l10n.jobsHubPartTime;
      case 'contract':
        return context.l10n.jobsHubContract;
      case 'internship':
        return context.l10n.jobsHubInternship;
      case 'freelance':
        return context.l10n.jobsHubFreelance;
      default:
        return value;
    }
  }

  String _workplaceLabel(String value) {
    switch (value) {
      case 'on_site':
        return context.l10n.jobsHubOnSite;
      case 'hybrid':
        return context.l10n.jobsHubHybrid;
      case 'remote':
        return context.l10n.jobsHubRemote;
      default:
        return value;
    }
  }

  String _experienceLabel(String value) {
    switch (value) {
      case 'entry':
        return context.l10n.jobsHubEntry;
      case 'junior':
        return context.l10n.jobsHubJunior;
      case 'mid':
        return context.l10n.jobsHubMid;
      case 'senior':
        return context.l10n.jobsHubSenior;
      case 'lead':
        return context.l10n.jobsHubLead;
      case 'manager':
        return context.l10n.jobsHubManager;
      default:
        return value;
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'active':
        return context.l10n.adminMerchantStateActiveFilter;
      case 'paused':
        return context.l10n.jobsHubPaused;
      case 'closed':
        return context.l10n.jobsHubClosed;
      case 'draft':
        return context.l10n.companyPromotionsStatusDraft;
      default:
        return value;
    }
  }

  String _salaryText(JobPostModel job) {
    final min = job.salaryMin;
    final max = job.salaryMax;
    if (min == null && max == null) {
      return job.salaryIsNegotiable
          ? context.l10n.jobsHubSalaryIsNegotiable
          : context.l10n.jobsHubSalaryNotSpecified;
    }

    final period = switch (job.salaryPeriod) {
      'hourly' => context.l10n.jobsHubPerHour,
      'monthly' => context.l10n.jobsHubMonthly,
      'yearly' => context.l10n.jobsHubYearly,
      'project' => context.l10n.jobsHubPerProject,
      _ => '',
    };

    if (min != null && max != null) {
      return '${formatIqd(min, withCode: false)} - ${formatIqd(max, withCode: false)} ${job.salaryCurrency} $period';
    }
    final value = min ?? max ?? 0;
    return '${formatIqd(value, withCode: false)} ${job.salaryCurrency} $period';
  }

  @override
  Widget build(BuildContext context) {
    final jobsSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.jobs, displayName: 'الوظائف');
    if (jobsSection.isBlocked) {
      return SectionUnavailableScreen(entry: jobsSection);
    }
    return Scaffold(
      drawer: _canApplyJobs ? _buildCustomerDrawer() : null,
      appBar: AppBar(
        title: Text(context.l10n.onboardingJobsTitle),
        actions: [
          if (_canManageJobs)
            IconButton(
              tooltip: context.l10n.jobsHubRecommendCandidates,
              onPressed: _openAdminJobReader,
              icon: const Icon(Icons.person_search_rounded),
            ),
          if (_canManageJobs && !_isSuperAdmin)
            IconButton(
              tooltip: context.l10n.jobsHubApplications,
              onPressed: _openApplicationsInbox,
              icon: const Icon(Icons.assignment_ind_rounded),
            ),
          if (_canOpenTalentPool)
            IconButton(
              tooltip: context.l10n.jobsHubTalentPool,
              onPressed: _openTalentPool,
              icon: const Icon(Icons.hub_rounded),
            ),
          IconButton(
            tooltip: context.l10n.jobsHubFilter,
            onPressed: _openFiltersSheet,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: context.l10n.drawerRefresh,
            onPressed: _loading ? null : () => _loadJobs(reset: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _canManageJobs
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _busyAction ? null : _openCreateJobSheet,
              icon: const Icon(Icons.work_outline_rounded),
              label: Text(context.l10n.jobsHubPostJob),
            )
          : null,
      body: Directionality(
        textDirection: context.appTextDirection,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            children: [
              _buildHeaderCard(context),
              const SizedBox(height: 10),
              _buildQuickActions(context),
              const SizedBox(height: 10),
              _buildSnapshotCards(),
              const SizedBox(height: 10),
              if (_canManageJobs && !_isSuperAdmin) _buildModeSwitch(),
              if (_canManageJobs && !_isSuperAdmin) const SizedBox(height: 10),
              _buildSearchBar(),
              const SizedBox(height: 10),
              _buildFilterSummary(),
              const SizedBox(height: 8),
              if (_loadingMeta)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 42),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_jobs.isEmpty)
                _buildEmptyState()
              else ...[
                Text(
                  '${context.l10n.jobsHubShowing}: ${_jobs.length} ${context.l10n.jobsHubOf} $_total',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 8),
                ..._jobs.map(
                  (job) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _JobCard(
                      job: job,
                      salaryText: _salaryText(job),
                      typeLabel: _typeLabel(job.employmentType),
                      workplaceLabel: _workplaceLabel(job.workplaceType),
                      experienceLabel: _experienceLabel(job.experienceLevel),
                      statusLabel: _statusLabel(job.status),
                      onTap: () => _openJobDetails(job),
                    ),
                  ),
                ),
                if (_loadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_loadingMore && _hasMore)
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () => _loadJobs(reset: false),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(context.l10n.settingsActivityLoadMore),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerDrawer() {
    return Drawer(
      child: SafeArea(
        child: Directionality(
          textDirection: context.appTextDirection,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              ListTile(
                title: Text(
                  context.l10n.jobsHubJobsSection,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  context.l10n.jobsHubDrawerSubtitle,
                  textAlign: TextAlign.right,
                ),
              ),
              const Divider(height: 18),
              ListTile(
                leading: const Icon(Icons.work_outline_rounded),
                title: Text(
                  context.l10n.notificationsJobs,
                  textAlign: TextAlign.right,
                ),
                selected: true,
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.assignment_turned_in_outlined),
                title: Text(
                  context.l10n.jobsHubMyApplications,
                  textAlign: TextAlign.right,
                ),
                subtitle: Text(
                  context.l10n.jobsHubDrawerStatusesSubtitle,
                  textAlign: TextAlign.right,
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openMyApplications();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final text = _manageMode
        ? context.l10n.jobsHubManageHeaderSubtitle
        : context.l10n.jobsHubBrowseHeaderSubtitle;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF5B2A6D), Color(0xFF121C61), Color(0xFF040D2B)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE9A3C0), Color(0xFF53B8FF)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    size: 26,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.jobsHubPlatformTitle,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniTag(
                  text: _manageMode
                      ? context.l10n.jobsHubManageMode
                      : context.l10n.jobsHubBrowseMode,
                  color: const Color(0xFF53B8FF),
                ),
                _MiniTag(
                  text: context.l10n.jobsHubSmartFilters,
                  color: const Color(0xFFE9A3C0),
                ),
                _MiniTag(
                  text: context.l10n.jobsHubDirectApply,
                  color: const Color(0xFF5B69FF),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSwitch() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          selected: !_manageMode,
          label: Text(context.l10n.jobsHubAllJobs),
          onSelected: (_) => _toggleMode(false),
        ),
        ChoiceChip(
          selected: _manageMode,
          label: Text(context.l10n.jobsHubManageMyListings),
          onSelected: (_) => _toggleMode(true),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: context.l10n.jobsHubSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _applySearch(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _applySearch,
          child: Text(context.l10n.commonSearch),
        ),
      ],
    );
  }

  Widget _buildFilterSummary() {
    final chips = <String>[
      if (_category != null) '${context.l10n.jobsHubCategory}: $_category',
      if (_activityType != null)
        '${context.l10n.socialShellActivity}: ${_prettyTaxonomyLabel(_activityType!)}',
      if (_department != null)
        '${context.l10n.jobsHubDepartment}: ${_prettyTaxonomyLabel(_department!)}',
      if (_city != null) '${context.l10n.jobsHubCity}: $_city',
      if (_area != null) '${context.l10n.jobsHubArea}: $_area',
      if (_employmentType != null)
        '${context.l10n.jobsHubEmployment}: ${_typeLabel(_employmentType!)}',
      if (_workplaceType != null)
        '${context.l10n.jobsHubWorkplace}: ${_workplaceLabel(_workplaceType!)}',
      if (_experienceLevel != null)
        '${context.l10n.jobsHubExperience}: ${_experienceLabel(_experienceLevel!)}',
      if (_statusFilter != null)
        '${context.l10n.companyPromotionsCampaignStatus}: ${_statusLabel(_statusFilter!)}',
      if (_minSalary != null || _maxSalary != null)
        '${context.l10n.commonSalary}: ${_minSalary?.toStringAsFixed(0) ?? '...'} - ${_maxSalary?.toStringAsFixed(0) ?? '...'}',
      if (_sort != 'recent')
        '${context.l10n.jobsHubSort}: ${_sortLabel(_sort)}',
      if (_onlyOpen) context.l10n.jobsHubOpenOnly,
    ];

    if (chips.isEmpty) {
      return Row(
        children: [
          const Icon(Icons.filter_alt_off_rounded, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              context.l10n.jobsHubNoActiveFilters,
              textAlign: TextAlign.right,
            ),
          ),
          TextButton(
            onPressed: _openFiltersSheet,
            child: Text(context.l10n.jobsHubFilter),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips
              .map(
                (chip) => Chip(
                  label: Text(chip),
                  visualDensity: VisualDensity.compact,
                ),
              )
              .toList(growable: false),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.close_rounded),
            label: Text(context.l10n.jobsHubClearFilters),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = <Widget>[
      _JobsQuickActionCard(
        icon: Icons.tune_rounded,
        label: context.l10n.commonFilters,
        subtitle: context.l10n.jobsHubAdvancedFiltering,
        onTap: _openFiltersSheet,
      ),
      _JobsQuickActionCard(
        icon: Icons.refresh_rounded,
        label: context.l10n.drawerRefresh,
        subtitle: context.l10n.jobsHubReload,
        onTap: () => _loadJobs(reset: true),
      ),
      if (_canApplyJobs)
        _JobsQuickActionCard(
          icon: Icons.assignment_turned_in_outlined,
          label: context.l10n.jobsHubMyApplications,
          subtitle: context.l10n.jobsHubApplicationStatuses,
          onTap: _openMyApplications,
        ),
      if (_canManageJobs && !_isSuperAdmin)
        _JobsQuickActionCard(
          icon: Icons.assignment_ind_rounded,
          label: context.l10n.jobsHubApplications,
          subtitle: context.l10n.jobsHubManageApplicants,
          onTap: _openApplicationsInbox,
        ),
      if (_canOpenTalentPool)
        _JobsQuickActionCard(
          icon: Icons.hub_rounded,
          label: context.l10n.jobsHubTalentPool2,
          subtitle: context.l10n.jobsHubApplicantsCenter,
          onTap: _openTalentPool,
        ),
      if (_canManageJobs)
        _JobsQuickActionCard(
          icon: Icons.work_outline_rounded,
          label: context.l10n.jobsHubPostJob2,
          subtitle: context.l10n.jobsHubNewListing,
          onTap: _openCreateJobSheet,
        ),
    ];

    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => actions[index],
      ),
    );
  }

  Widget _buildSnapshotCards() {
    final active = _countByStatus('active');
    final paused = _countByStatus('paused');
    final closed = _countByStatus('closed');

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        _JobsStatCard(
          label: context.l10n.jobsHubVisibleNow,
          value: '${_jobs.length}',
          selected: false,
          onTap: () => _loadJobs(reset: true),
        ),
        _JobsStatCard(
          label: context.l10n.jobsHubOpen,
          value: '$active',
          selected: _onlyOpen && _statusFilter == null,
          onTap: () => _applyOpenOnlyFilter(true),
        ),
        _JobsStatCard(
          label: context.l10n.jobsHubAllStatuses,
          value: '$_total',
          selected: !_onlyOpen && _statusFilter == null,
          onTap: () => _applyOpenOnlyFilter(false),
        ),
        if (_canManageJobs && !_isSuperAdmin)
          _JobsStatCard(
            label: context.l10n.jobsHubPaused,
            value: '$paused',
            selected: _statusFilter == 'paused',
            onTap: () async {
              setState(() {
                _onlyOpen = false;
                _statusFilter = 'paused';
              });
              await _loadJobs(reset: true);
            },
          ),
        if (_canManageJobs && !_isSuperAdmin)
          _JobsStatCard(
            label: context.l10n.jobsHubClosed,
            value: '$closed',
            selected: _statusFilter == 'closed',
            onTap: () async {
              setState(() {
                _onlyOpen = false;
                _statusFilter = 'closed';
              });
              await _loadJobs(reset: true);
            },
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.work_off_rounded, size: 44),
            const SizedBox(height: 10),
            Text(
              _manageMode
                  ? context.l10n.jobsHubEmptyManage
                  : context.l10n.jobsHubEmptyBrowse,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(context.l10n.jobsHubResetFilters),
                ),
                if (_canManageJobs && !_isSuperAdmin)
                  FilledButton.icon(
                    onPressed: _openCreateJobSheet,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(context.l10n.jobsHubPostJob),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(String value) {
    switch (value) {
      case 'salary_high':
        return context.l10n.jobsHubHighestSalary;
      case 'salary_low':
        return context.l10n.jobsHubLowestSalary;
      case 'expires_soon':
        return context.l10n.jobsHubExpiresSoon;
      default:
        return context.l10n.jobsHubMostRecent;
    }
  }

  String _prettyTaxonomyLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return '-';
    final pieces = cleaned.split('_').where((part) => part.isNotEmpty);
    final words = pieces
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .toList(growable: false);
    return words.join(' ');
  }
}

class _JobCard extends StatelessWidget {
  final JobPostModel job;
  final String salaryText;
  final String typeLabel;
  final String workplaceLabel;
  final String experienceLabel;
  final String statusLabel;
  final VoidCallback onTap;

  const _JobCard({
    required this.job,
    required this.salaryText,
    required this.typeLabel,
    required this.workplaceLabel,
    required this.experienceLabel,
    required this.statusLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = switch (job.status) {
      'active' => Colors.green,
      'paused' => Colors.orange,
      'closed' => Colors.redAccent,
      'draft' => Colors.blueGrey,
      _ => Colors.grey,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF2E2451), Color(0xFF121C61), Color(0xFF040D2B)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (job.companyLogoUrl != null &&
                        job.companyLogoUrl!.isNotEmpty)
                      CircleAvatar(
                        radius: 20,
                        backgroundImage: AppCachedImageProvider(
                          job.companyLogoUrl!,
                        ),
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                        child: const Icon(Icons.storefront_rounded),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            job.title,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            job.companyName,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12.8,
                              color: Colors.white.withValues(alpha: 0.84),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${job.city}${job.area == null ? '' : ' - ${job.area}'}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF53B8FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(
                            0xFF53B8FF,
                          ).withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        salaryText,
                        style: const TextStyle(
                          color: Color(0xFFE9E9FF),
                          fontWeight: FontWeight.w700,
                          fontSize: 11.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MiniTag(text: typeLabel),
                    _MiniTag(text: workplaceLabel),
                    _MiniTag(text: experienceLabel),
                    _MiniTag(text: job.category),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (job.hasApplied)
                      _MiniTag(
                        text: context.l10n.jobsHubApplied,
                        color: const Color(0xFF5B69FF),
                      ),
                    const Spacer(),
                    if (job.canManage)
                      Text(
                        '${context.l10n.jobsHubApplications}: ${job.applicationsCount}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JobsQuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Future<void> Function() onTap;

  const _JobsQuickActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          width: 166,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                scheme.primary.withValues(alpha: 0.2),
                scheme.surfaceContainerHighest.withValues(alpha: 0.34),
              ],
            ),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primary.withValues(alpha: 0.18),
                child: Icon(icon, size: 17, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobsStatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final Future<void> Function() onTap;

  const _JobsStatCard({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? scheme.primary.withValues(alpha: 0.2)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String text;
  final Color? color;

  const _MiniTag({required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final base = color ?? const Color(0xFF53B8FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withValues(alpha: 0.34)),
        color: base.withValues(alpha: 0.16),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11.4, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _JobsFilterSheet extends StatefulWidget {
  final JobFilterMetaModel meta;
  final _JobFilterResult initial;

  const _JobsFilterSheet({required this.meta, required this.initial});

  @override
  State<_JobsFilterSheet> createState() => _JobsFilterSheetState();
}

class _JobsFilterSheetState extends State<_JobsFilterSheet> {
  late String? category = widget.initial.category;
  late String? activityType = widget.initial.activityType;
  late String? department = widget.initial.department;
  late String? city = widget.initial.city;
  late String? area = widget.initial.area;
  late String? employmentType = widget.initial.employmentType;
  late String? workplaceType = widget.initial.workplaceType;
  late String? experienceLevel = widget.initial.experienceLevel;
  late String? status = widget.initial.status;
  late String sort = widget.initial.sort;
  late bool onlyOpen = widget.initial.onlyOpen;
  late final TextEditingController minSalaryCtrl = TextEditingController(
    text: widget.initial.minSalary?.toStringAsFixed(0) ?? '',
  );
  late final TextEditingController maxSalaryCtrl = TextEditingController(
    text: widget.initial.maxSalary?.toStringAsFixed(0) ?? '',
  );

  @override
  void dispose() {
    minSalaryCtrl.dispose();
    maxSalaryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 12,
          bottom: bottomInset + 12,
        ),
        child: Directionality(
          textDirection: context.appTextDirection,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.jobsHubJobsFilters,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                _dd<String>(
                  value: category,
                  hint: context.l10n.jobsHubCategory,
                  values: widget.meta.categories,
                  onChanged: (v) => setState(() => category = v),
                ),
                const SizedBox(height: 8),
                _dd<String>(
                  value: activityType,
                  hint: context.l10n.jobsHubActivityType,
                  values: widget.meta.activityTypes,
                  label: _prettyTaxonomyLabel,
                  onChanged: (v) {
                    setState(() {
                      activityType = v;
                      final departments = v == null
                          ? const <String>[]
                          : (widget.meta.departmentsByActivity[v] ??
                                const <String>[]);
                      if (department != null &&
                          !departments.contains(department)) {
                        department = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                _dd<String>(
                  value: department,
                  hint: context.l10n.jobsHubDepartment,
                  values: activityType == null
                      ? const <String>[]
                      : (widget.meta.departmentsByActivity[activityType!] ??
                            const <String>[]),
                  label: _prettyTaxonomyLabel,
                  onChanged: (v) => setState(() => department = v),
                ),
                const SizedBox(height: 8),
                _dd<String>(
                  value: city,
                  hint: context.l10n.carsCity,
                  values: widget.meta.cities,
                  onChanged: (v) => setState(() => city = v),
                ),
                const SizedBox(height: 8),
                _dd<String>(
                  value: area,
                  hint: context.l10n.jobsHubArea,
                  values: widget.meta.areas,
                  onChanged: (v) => setState(() => area = v),
                ),
                const SizedBox(height: 8),
                _dd<String>(
                  value: employmentType,
                  hint: context.l10n.jobsHubEmploymentType,
                  values: widget.meta.employmentTypes,
                  label: _typeLabel,
                  onChanged: (v) => setState(() => employmentType = v),
                ),
                const SizedBox(height: 8),
                _dd<String>(
                  value: workplaceType,
                  hint: context.l10n.jobsHubWorkplaceType,
                  values: widget.meta.workplaceTypes,
                  label: _workplaceLabel,
                  onChanged: (v) => setState(() => workplaceType = v),
                ),
                const SizedBox(height: 8),
                _dd<String>(
                  value: experienceLevel,
                  hint: context.l10n.jobsHubExperienceLevel,
                  values: widget.meta.experienceLevels,
                  label: _experienceLabel,
                  onChanged: (v) => setState(() => experienceLevel = v),
                ),
                const SizedBox(height: 8),
                _dd<String>(
                  value: sort,
                  hint: context.l10n.jobsHubSort,
                  values: const [
                    'recent',
                    'salary_high',
                    'salary_low',
                    'expires_soon',
                  ],
                  label: _sortLabel,
                  onChanged: (v) => setState(() => sort = v ?? 'recent'),
                  allowNull: false,
                ),
                if (widget.initial.manageMode) ...[
                  const SizedBox(height: 8),
                  _dd<String>(
                    value: status,
                    hint: context.l10n.jobsHubListingStatus,
                    values: const ['active', 'paused', 'closed', 'draft'],
                    label: _statusLabel,
                    onChanged: (v) => setState(() => status = v),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minSalaryCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: context.l10n.jobsHubMinimumSalary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: maxSalaryCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: context.l10n.jobsHubMaximumSalary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  value: onlyOpen,
                  title: Text(context.l10n.jobsHubOpenOnly),
                  onChanged: (v) => setState(() => onlyOpen = v),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    final minSalary = double.tryParse(
                      minSalaryCtrl.text.trim(),
                    );
                    final maxSalary = double.tryParse(
                      maxSalaryCtrl.text.trim(),
                    );
                    Navigator.of(context).pop(
                      _JobFilterResult(
                        category: category,
                        activityType: activityType,
                        department: department,
                        city: city,
                        area: area,
                        employmentType: employmentType,
                        workplaceType: workplaceType,
                        experienceLevel: experienceLevel,
                        status: status,
                        minSalary: minSalary,
                        maxSalary: maxSalary,
                        sort: sort,
                        onlyOpen: onlyOpen,
                        manageMode: widget.initial.manageMode,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(context.l10n.jobsHubApplyFilters),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dd<T>({
    required T? value,
    required String hint,
    required List<T> values,
    required ValueChanged<T?> onChanged,
    String Function(T value)? label,
    bool allowNull = true,
  }) {
    final items = <DropdownMenuItem<T?>>[];
    if (allowNull) {
      items.add(
        DropdownMenuItem(
          value: null,
          child: Text(context.l10n.notificationsAll),
        ),
      );
    }
    items.addAll(
      values.map(
        (value) => DropdownMenuItem<T?>(
          value: value,
          child: Text(label == null ? '$value' : label(value)),
        ),
      ),
    );

    return DropdownButtonFormField<T?>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: hint),
      isExpanded: true,
    );
  }

  String _typeLabel(String value) {
    switch (value) {
      case 'full_time':
        return context.l10n.jobsHubFullTime;
      case 'part_time':
        return context.l10n.jobsHubPartTime;
      case 'contract':
        return context.l10n.jobsHubContract;
      case 'internship':
        return context.l10n.jobsHubInternship;
      case 'freelance':
        return context.l10n.jobsHubFreelance;
      default:
        return value;
    }
  }

  String _workplaceLabel(String value) {
    switch (value) {
      case 'on_site':
        return context.l10n.jobsHubOnSite;
      case 'hybrid':
        return context.l10n.jobsHubHybrid;
      case 'remote':
        return context.l10n.jobsHubRemote;
      default:
        return value;
    }
  }

  String _experienceLabel(String value) {
    switch (value) {
      case 'entry':
        return context.l10n.jobsHubEntry;
      case 'junior':
        return context.l10n.jobsHubJunior;
      case 'mid':
        return context.l10n.jobsHubMid;
      case 'senior':
        return context.l10n.jobsHubSenior;
      case 'lead':
        return context.l10n.jobsHubLead;
      case 'manager':
        return context.l10n.jobsHubManager;
      default:
        return value;
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'active':
        return context.l10n.adminMerchantStateActiveFilter;
      case 'paused':
        return context.l10n.jobsHubPaused;
      case 'closed':
        return context.l10n.jobsHubClosed;
      case 'draft':
        return context.l10n.companyPromotionsStatusDraft;
      default:
        return value;
    }
  }

  String _sortLabel(String value) {
    switch (value) {
      case 'salary_high':
        return context.l10n.jobsHubHighestSalary;
      case 'salary_low':
        return context.l10n.jobsHubLowestSalary;
      case 'expires_soon':
        return context.l10n.jobsHubExpiresSoon;
      default:
        return context.l10n.jobsHubMostRecent;
    }
  }

  String _prettyTaxonomyLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return '-';
    final words = cleaned
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .toList(growable: false);
    return words.join(' ');
  }
}

class _JobFilterResult {
  final String? category;
  final String? activityType;
  final String? department;
  final String? city;
  final String? area;
  final String? employmentType;
  final String? workplaceType;
  final String? experienceLevel;
  final String? status;
  final double? minSalary;
  final double? maxSalary;
  final String sort;
  final bool onlyOpen;
  final bool manageMode;

  const _JobFilterResult({
    required this.category,
    required this.activityType,
    required this.department,
    required this.city,
    required this.area,
    required this.employmentType,
    required this.workplaceType,
    required this.experienceLevel,
    required this.status,
    required this.minSalary,
    required this.maxSalary,
    required this.sort,
    required this.onlyOpen,
    required this.manageMode,
  });
}

class _CreateJobSheet extends StatefulWidget {
  final JobFilterMetaModel meta;

  const _CreateJobSheet({required this.meta});

  @override
  State<_CreateJobSheet> createState() => _CreateJobSheetState();
}

class _CreateJobSheetState extends State<_CreateJobSheet> {
  final FormScrollCoordinator _scrollCoordinator = FormScrollCoordinator();
  final titleCtrl = TextEditingController();
  final companyCtrl = TextEditingController();
  final categoryCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final areaCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();
  final requirementsCtrl = TextEditingController();
  final responsibilitiesCtrl = TextEditingController();
  final benefitsCtrl = TextEditingController();
  final skillsCtrl = TextEditingController();
  final salaryMinCtrl = TextEditingController();
  final salaryMaxCtrl = TextEditingController();
  final vacanciesCtrl = TextEditingController(text: '1');
  final contactPhoneCtrl = TextEditingController();
  final contactEmailCtrl = TextEditingController();
  final applyUrlCtrl = TextEditingController();

  String activityType = 'general_business';
  String department = 'operations';
  String employmentType = 'full_time';
  String workplaceType = 'on_site';
  String experienceLevel = 'mid';
  String salaryPeriod = 'monthly';
  String status = 'active';
  bool negotiable = true;
  DateTime? expiresAt;
  Map<String, String> _fieldErrors = const <String, String>{};
  String? _formError;

  List<String> get _activityOptions {
    if (widget.meta.activityTypes.isNotEmpty) {
      return widget.meta.activityTypes;
    }
    return const <String>['general_business'];
  }

  List<String> get _departmentOptions {
    return widget.meta.departmentsByActivity[activityType] ??
        const <String>['operations'];
  }

  @override
  void initState() {
    super.initState();
    if (!_activityOptions.contains(activityType)) {
      activityType = _activityOptions.first;
    }
    final departments = _departmentOptions;
    if (departments.isNotEmpty && !departments.contains(department)) {
      department = departments.first;
    }
  }

  @override
  void dispose() {
    _scrollCoordinator.dispose();
    titleCtrl.dispose();
    companyCtrl.dispose();
    categoryCtrl.dispose();
    cityCtrl.dispose();
    areaCtrl.dispose();
    descriptionCtrl.dispose();
    requirementsCtrl.dispose();
    responsibilitiesCtrl.dispose();
    benefitsCtrl.dispose();
    skillsCtrl.dispose();
    salaryMinCtrl.dispose();
    salaryMaxCtrl.dispose();
    vacanciesCtrl.dispose();
    contactPhoneCtrl.dispose();
    contactEmailCtrl.dispose();
    applyUrlCtrl.dispose();
    super.dispose();
  }

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field) &&
        (_formError == null || _formError!.isEmpty)) {
      return;
    }
    setState(() {
      _fieldErrors = Map<String, String>.from(_fieldErrors)..remove(field);
      if (_formError != null && _formError!.isNotEmpty) {
        _formError = null;
      }
    });
  }

  String _fieldLabel(BuildContext context, String field) {
    final l10n = context.l10n;
    switch (field) {
      case 'title':
        return l10n.jobsHubJobTitleLabel;
      case 'category':
        return l10n.jobsHubCategory2;
      case 'activityType':
        return l10n.jobsHubActivityType2;
      case 'department':
        return l10n.jobsHubDepartment2;
      case 'city':
        return l10n.jobsHubCity2;
      case 'description':
        return l10n.jobsHubJobDescription;
      case 'salaryMin':
        return l10n.jobsHubMinimumSalary;
      case 'salaryMax':
        return l10n.jobsHubMaximumSalary;
      default:
        return field;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 12,
          bottom: inset + 12,
        ),
        child: Directionality(
          textDirection: context.appTextDirection,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.jobsHubPostNewJob,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                FormErrorBanner(message: _formError),
                _scrollCoordinator.anchor(
                  'title',
                  TextField(
                    controller: titleCtrl,
                    focusNode: _scrollCoordinator.focusNodeFor('title'),
                    decoration: InputDecoration(
                      labelText: context.l10n.jobsHubJobTitleLabel,
                      errorText: _fieldErrors['title'],
                    ),
                    onChanged: (_) => _clearFieldError('title'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: companyCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.jobsHubCompanyNameOptional,
                  ),
                ),
                const SizedBox(height: 8),
                _scrollCoordinator.anchor(
                  'category',
                  TextField(
                    controller: categoryCtrl,
                    focusNode: _scrollCoordinator.focusNodeFor('category'),
                    decoration: InputDecoration(
                      labelText: context.l10n.jobsHubCategory2,
                      errorText: _fieldErrors['category'],
                    ),
                    onChanged: (_) => _clearFieldError('category'),
                  ),
                ),
                const SizedBox(height: 8),
                // activity-department selectors
                _scrollCoordinator.anchor(
                  'activityType',
                  DropdownButtonFormField<String>(
                    initialValue: _activityOptions.contains(activityType)
                        ? activityType
                        : _activityOptions.first,
                    isExpanded: true,
                    items: _activityOptions
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item,
                            child: Text(_prettyTaxonomyLabel(item)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        activityType = value;
                        _fieldErrors = Map<String, String>.from(_fieldErrors)
                          ..remove('activityType');
                        _formError = null;
                        if (!_departmentOptions.contains(department)) {
                          department = _departmentOptions.first;
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: context.l10n.jobsHubActivityType2,
                      errorText: _fieldErrors['activityType'],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _scrollCoordinator.anchor(
                  'department',
                  DropdownButtonFormField<String>(
                    initialValue: _departmentOptions.contains(department)
                        ? department
                        : _departmentOptions.first,
                    isExpanded: true,
                    items: _departmentOptions
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item,
                            child: Text(_prettyTaxonomyLabel(item)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        department = value;
                        _fieldErrors = Map<String, String>.from(_fieldErrors)
                          ..remove('department');
                        _formError = null;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: context.l10n.jobsHubDepartment2,
                      errorText: _fieldErrors['department'],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _scrollCoordinator.anchor(
                        'city',
                        TextField(
                          controller: cityCtrl,
                          focusNode: _scrollCoordinator.focusNodeFor('city'),
                          decoration: InputDecoration(
                            labelText: context.l10n.jobsHubCity2,
                            errorText: _fieldErrors['city'],
                          ),
                          onChanged: (_) => _clearFieldError('city'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: areaCtrl,
                        decoration: InputDecoration(
                          labelText: context.l10n.jobsHubArea,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _enumField(
                  value: employmentType,
                  label: context.l10n.jobsHubEmploymentType,
                  items: [
                    _EnumItem('full_time', context.l10n.jobsHubFullTime),
                    _EnumItem('part_time', context.l10n.jobsHubPartTime),
                    _EnumItem('contract', context.l10n.jobsHubContract),
                    _EnumItem('internship', context.l10n.jobsHubInternship),
                    _EnumItem('freelance', context.l10n.jobsHubFreelance),
                  ],
                  onChanged: (v) => setState(() => employmentType = v),
                ),
                const SizedBox(height: 8),
                _enumField(
                  value: workplaceType,
                  label: context.l10n.jobsHubWorkplaceType,
                  items: [
                    _EnumItem('on_site', context.l10n.jobsHubOnSite),
                    _EnumItem('hybrid', context.l10n.jobsHubHybrid),
                    _EnumItem('remote', context.l10n.jobsHubRemote),
                  ],
                  onChanged: (v) => setState(() => workplaceType = v),
                ),
                const SizedBox(height: 8),
                _enumField(
                  value: experienceLevel,
                  label: context.l10n.jobsHubExperienceLevel,
                  items: [
                    _EnumItem('entry', context.l10n.jobsHubEntry),
                    _EnumItem('junior', context.l10n.jobsHubJunior),
                    _EnumItem('mid', context.l10n.jobsHubMid),
                    _EnumItem('senior', context.l10n.jobsHubSenior),
                    _EnumItem('lead', context.l10n.jobsHubLead),
                    _EnumItem('manager', context.l10n.jobsHubManager),
                  ],
                  onChanged: (v) => setState(() => experienceLevel = v),
                ),
                const SizedBox(height: 8),
                _enumField(
                  value: salaryPeriod,
                  label: context.l10n.jobsHubSalaryPeriod,
                  items: [
                    _EnumItem('hourly', context.l10n.jobsHubHourly),
                    _EnumItem('monthly', context.l10n.jobsHubMonthly2),
                    _EnumItem('yearly', context.l10n.jobsHubYearly2),
                    _EnumItem('project', context.l10n.jobsHubPerProject2),
                  ],
                  onChanged: (v) => setState(() => salaryPeriod = v),
                ),
                const SizedBox(height: 8),
                _enumField(
                  value: status,
                  label: context.l10n.jobsHubListingStatus,
                  items: [
                    _EnumItem(
                      'active',
                      context.l10n.adminMerchantStateActiveFilter,
                    ),
                    _EnumItem(
                      'draft',
                      context.l10n.companyPromotionsStatusDraft,
                    ),
                  ],
                  onChanged: (v) => setState(() => status = v),
                ),
                const SizedBox(height: 8),
                _scrollCoordinator.anchor(
                  'description',
                  TextField(
                    controller: descriptionCtrl,
                    focusNode: _scrollCoordinator.focusNodeFor('description'),
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: '${context.l10n.jobsHubJobDescription} *',
                      errorText: _fieldErrors['description'],
                    ),
                    onChanged: (_) => _clearFieldError('description'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: requirementsCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: context.l10n.jobsHubRequirements,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: responsibilitiesCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: context.l10n.jobsHubResponsibilities,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: benefitsCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: context.l10n.jobsHubBenefits,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: skillsCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.jobsHubSkillsCommaSeparated,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _scrollCoordinator.anchor(
                        'salaryMin',
                        TextField(
                          controller: salaryMinCtrl,
                          focusNode: _scrollCoordinator.focusNodeFor(
                            'salaryMin',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: context.l10n.jobsHubMinimumSalary,
                            errorText: _fieldErrors['salaryMin'],
                          ),
                          onChanged: (_) => _clearFieldError('salaryMin'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _scrollCoordinator.anchor(
                        'salaryMax',
                        TextField(
                          controller: salaryMaxCtrl,
                          focusNode: _scrollCoordinator.focusNodeFor(
                            'salaryMax',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: context.l10n.jobsHubMaximumSalary,
                            errorText: _fieldErrors['salaryMax'],
                          ),
                          onChanged: (_) => _clearFieldError('salaryMax'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: vacanciesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.l10n.jobsHubVacancies,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickExpiryDate,
                        icon: const Icon(Icons.event_rounded),
                        label: Text(
                          expiresAt == null
                              ? context.l10n.jobsHubExpirationDate
                              : '${context.l10n.jobsHubExpires}: ${expiresAt!.toLocal().toString().split(' ').first}',
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  value: negotiable,
                  title: Text(context.l10n.jobsHubSalaryIsNegotiable),
                  onChanged: (v) => setState(() => negotiable = v),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: contactPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: context.l10n.jobsHubContactPhone,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: contactEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: context.l10n.jobsHubContactEmail,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: applyUrlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: context.l10n.jobsHubExternalApplyUrl,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.publish_rounded),
                  label: Text(context.l10n.jobsHubPublishJob),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _enumField({
    required String value,
    required String label,
    required List<_EnumItem> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item.value,
              child: Text(item.label),
            ),
          )
          .toList(growable: false),
      onChanged: (v) => onChanged(v ?? value),
      decoration: InputDecoration(labelText: label),
    );
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      initialDate: expiresAt ?? now,
      locale: Localizations.localeOf(context),
    );
    if (picked == null) return;
    setState(() {
      expiresAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    });
  }

  String _prettyTaxonomyLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return '-';
    final words = cleaned
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .toList(growable: false);
    return words.join(' ');
  }

  void _submit() {
    final title = titleCtrl.text.trim();
    final category = categoryCtrl.text.trim();
    final city = cityCtrl.text.trim();
    final description = descriptionCtrl.text.trim();
    final vacancies = int.tryParse(vacanciesCtrl.text.trim()) ?? 1;
    final salaryMin = double.tryParse(salaryMinCtrl.text.trim());
    final salaryMax = double.tryParse(salaryMaxCtrl.text.trim());
    final nextErrors = <String, String>{};
    if (title.isEmpty) {
      nextErrors['title'] = context.l10n.validationRequiredField(
        _fieldLabel(context, 'title'),
      );
    }
    if (category.isEmpty) {
      nextErrors['category'] = context.l10n.validationRequiredField(
        _fieldLabel(context, 'category'),
      );
    }
    if (city.isEmpty) {
      nextErrors['city'] = context.l10n.validationRequiredField(
        _fieldLabel(context, 'city'),
      );
    }
    if (description.isEmpty) {
      nextErrors['description'] = context.l10n.validationRequiredField(
        _fieldLabel(context, 'description'),
      );
    }
    if (activityType.trim().isEmpty) {
      nextErrors['activityType'] = context.l10n.validationSelectOption;
    }
    if (department.trim().isEmpty) {
      nextErrors['department'] = context.l10n.validationSelectOption;
    }
    if (salaryMin != null && salaryMax != null && salaryMax < salaryMin) {
      nextErrors['salaryMin'] = context.l10n.jobsHubSalaryRangeInvalid;
      nextErrors['salaryMax'] = context.l10n.jobsHubSalaryRangeInvalid;
    }
    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors = nextErrors;
        _formError = context.l10n.validationReviewRequiredFields;
      });
      _scrollCoordinator.focusFirstError(
        const [
          'title',
          'category',
          'activityType',
          'department',
          'city',
          'description',
          'salaryMin',
          'salaryMax',
        ].where(nextErrors.containsKey),
      );
      return;
    }

    setState(() {
      _fieldErrors = const <String, String>{};
      _formError = null;
    });

    final companyName = companyCtrl.text.trim();
    final area = areaCtrl.text.trim();
    final requirements = requirementsCtrl.text.trim();
    final responsibilities = responsibilitiesCtrl.text.trim();
    final benefits = benefitsCtrl.text.trim();
    final skills = skillsCtrl.text.trim();
    final contactPhone = contactPhoneCtrl.text.trim();
    final contactEmail = contactEmailCtrl.text.trim();
    final applyUrl = applyUrlCtrl.text.trim();

    Navigator.of(context).pop({
      'title': title,
      ...?(companyName.isEmpty ? null : {'companyName': companyName}),
      'category': category,
      'activityType': activityType,
      'department': department,
      'city': city,
      ...?(area.isEmpty ? null : {'area': area}),
      'employmentType': employmentType,
      'workplaceType': workplaceType,
      'experienceLevel': experienceLevel,
      'salaryPeriod': salaryPeriod,
      'status': status,
      'salaryIsNegotiable': negotiable,
      ...?(salaryMin == null ? null : {'salaryMin': salaryMin}),
      ...?(salaryMax == null ? null : {'salaryMax': salaryMax}),
      'vacancies': vacancies,
      'description': description,
      ...?(requirements.isEmpty ? null : {'requirements': requirements}),
      ...?(responsibilities.isEmpty
          ? null
          : {'responsibilities': responsibilities}),
      ...?(benefits.isEmpty ? null : {'benefits': benefits}),
      ...?(skills.isEmpty ? null : {'skills': skills}),
      ...?(contactPhone.isEmpty ? null : {'contactPhone': contactPhone}),
      ...?(contactEmail.isEmpty ? null : {'contactEmail': contactEmail}),
      ...?(applyUrl.isEmpty ? null : {'applyUrl': applyUrl}),
      ...?(expiresAt == null
          ? null
          : {'expiresAt': expiresAt!.toUtc().toIso8601String()}),
    });
  }
}

class _EnumItem {
  final String value;
  final String label;

  const _EnumItem(this.value, this.label);
}

class _JobDetailsSheet extends StatelessWidget {
  final JobPostModel job;
  final bool canApply;
  final bool canManage;
  final VoidCallback onApply;
  final VoidCallback onViewApplications;
  final ValueChanged<String> onSetStatus;
  final VoidCallback onDelete;

  const _JobDetailsSheet({
    required this.job,
    required this.canApply,
    required this.canManage,
    required this.onApply,
    required this.onViewApplications,
    required this.onSetStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final location = '${job.city}${job.area == null ? '' : ' - ${job.area}'}';
    final salary = () {
      if (job.salaryMin == null && job.salaryMax == null) {
        return job.salaryIsNegotiable
            ? context.l10n.realEstateNegotiable
            : context.l10n.companyBranchRequestNoOwner;
      }
      if (job.salaryMin != null && job.salaryMax != null) {
        return '${formatIqd(job.salaryMin!, withCode: false)} - ${formatIqd(job.salaryMax!, withCode: false)} ${job.salaryCurrency}';
      }
      final value = job.salaryMin ?? job.salaryMax ?? 0;
      return '${formatIqd(value, withCode: false)} ${job.salaryCurrency}';
    }();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 12,
          bottom: insets + 12,
        ),
        child: Directionality(
          textDirection: context.appTextDirection,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  job.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 6),
                Text(
                  '${job.companyName} • $location',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${context.l10n.commonSalary}: $salary',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _detailsSection(
                  context.l10n.jobsHubJobDescription,
                  job.description,
                ),
                if (job.requirements?.trim().isNotEmpty == true)
                  _detailsSection(
                    context.l10n.jobsHubRequirements,
                    job.requirements!,
                  ),
                if (job.responsibilities?.trim().isNotEmpty == true)
                  _detailsSection(
                    context.l10n.jobsHubResponsibilities,
                    job.responsibilities!,
                  ),
                if (job.benefits?.trim().isNotEmpty == true)
                  _detailsSection(context.l10n.jobsHubBenefits, job.benefits!),
                if (job.skills.isNotEmpty)
                  _detailsSection(
                    context.l10n.jobsHubSkills,
                    job.skills.join(' • '),
                  ),
                if (job.contactPhone?.trim().isNotEmpty == true ||
                    job.contactEmail?.trim().isNotEmpty == true)
                  _detailsSection(
                    context.l10n.realEstateContact,
                    [
                      if (job.contactPhone?.trim().isNotEmpty == true)
                        '${context.l10n.jobsHubPhone}: ${job.contactPhone}',
                      if (job.contactEmail?.trim().isNotEmpty == true)
                        '${context.l10n.jobsHubEmail}: ${job.contactEmail}',
                    ].join('\n'),
                  ),
                const SizedBox(height: 12),
                if (canManage) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (job.status == 'active')
                        OutlinedButton.icon(
                          onPressed: () => onSetStatus('paused'),
                          icon: const Icon(Icons.pause_circle_outline),
                          label: Text(context.l10n.jobsHubPauseListing),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () => onSetStatus('active'),
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(context.l10n.jobsHubActivateListing),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => onSetStatus('closed'),
                        icon: const Icon(Icons.lock_outline_rounded),
                        label: Text(context.l10n.jobsHubCloseListing),
                      ),
                      OutlinedButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(context.l10n.jobsHubDeleteListing),
                      ),
                      OutlinedButton.icon(
                        onPressed: onViewApplications,
                        icon: const Icon(Icons.assignment_ind_rounded),
                        label: Text(context.l10n.jobsHubApplications),
                      ),
                    ],
                  ),
                ] else if (canApply && job.isOpen && !job.hasApplied)
                  FilledButton.icon(
                    onPressed: onApply,
                    icon: const Icon(Icons.send_rounded),
                    label: Text(context.l10n.jobsHubApplyNow),
                  )
                else if (job.hasApplied)
                  _MiniTag(
                    text: context.l10n.jobsHubAlreadyAppliedToThisJob,
                    color: const Color(0xFF5B69FF),
                  )
                else
                  Text(
                    context.l10n.jobsHubUnavailableForApplication,
                    textAlign: TextAlign.right,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailsSection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.right,
            style: const TextStyle(height: 1.45),
          ),
        ],
      ),
    );
  }
}
