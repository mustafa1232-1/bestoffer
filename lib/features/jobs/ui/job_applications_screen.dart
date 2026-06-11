import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/jobs_api.dart';
import '../models/job_models.dart';
import 'job_application_details_screen.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

final jobsApiClientProvider = Provider<JobsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return JobsApi(dio);
});

class JobApplicationsScreen extends ConsumerStatefulWidget {
  final int? initialJobId;
  final String? initialJobTitle;
  final String? initialActivityType;
  final String? initialDepartment;
  final String? initialSearch;

  const JobApplicationsScreen({
    super.key,
    this.initialJobId,
    this.initialJobTitle,
    this.initialActivityType,
    this.initialDepartment,
    this.initialSearch,
  });

  @override
  ConsumerState<JobApplicationsScreen> createState() =>
      _JobApplicationsScreenState();
}

class _JobApplicationsScreenState extends ConsumerState<JobApplicationsScreen>
    with SingleTickerProviderStateMixin {
  static const List<String?> _statusTabs = [
    null,
    'submitted',
    'shortlisted',
    'rejected',
    'hired',
    'withdrawn',
    'dismissed_after_hire',
    'archived',
  ];

  late final TabController _tabController = TabController(
    length: _statusTabs.length,
    vsync: this,
  )..addListener(_handleTabChanged);

  late final TextEditingController _searchCtrl = TextEditingController(
    text: widget.initialSearch ?? '',
  );

  bool _loadingJobs = true;
  bool _loadingApps = false;
  bool _busy = false;
  final Set<int> _acceptingRecommendationIds = <int>{};

  List<JobPostModel> _jobs = const [];
  List<JobApplicationModel> _applications = const [];
  List<JobRecommendationModel> _recommendations = const [];

  int? _selectedJobId;
  String? _selectedJobTitle;
  String? _activityType;
  String? _department;

  String? get _activeStatus => _statusTabs[_tabController.index];

  String _statusTabLabel(String? status) {
    switch (status) {
      case null:
        return context.l10n.jobApplicationsAll;
      case 'submitted':
        return context.l10n.jobsStatusReceivedGroup;
      case 'shortlisted':
        return context.l10n.jobsStatusShortlistedGroup;
      case 'rejected':
        return context.l10n.jobsStatusRejectedGroup;
      case 'hired':
        return context.l10n.jobApplicationsHired;
      case 'withdrawn':
        return context.l10n.jobsStatusWithdrawnGroup;
      case 'dismissed_after_hire':
        return context.l10n.jobsStatusDismissedGroup;
      case 'archived':
        return context.l10n.jobsStatusArchivedGroup;
      default:
        return status;
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedJobId = widget.initialJobId;
    _selectedJobTitle = widget.initialJobTitle;
    _activityType = widget.initialActivityType;
    _department = widget.initialDepartment;
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _canManageJobs {
    final auth = ref.read(authControllerProvider);
    return auth.isAdmin || auth.isOwner || auth.isHr || auth.isSuperAdmin;
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    _loadApplications();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _bootstrap() async {
    await _loadManagedJobs();
    await _loadApplications();
  }

  Future<void> _loadManagedJobs() async {
    if (!_canManageJobs) return;
    setState(() => _loadingJobs = true);
    try {
      final raw = await ref
          .read(jobsApiClientProvider)
          .listManagedJobs(onlyOpen: false, page: 1, limit: 120);
      final rawItems = raw['items'] is List ? raw['items'] as List : const [];
      final jobs = rawItems
          .whereType<Map>()
          .map((e) => JobPostModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);

      int? selectedJobId = _selectedJobId;
      String? selectedJobTitle = _selectedJobTitle;

      if (selectedJobId != null) {
        final hit = jobs.where((job) => job.id == selectedJobId).toList();
        if (hit.isNotEmpty) {
          selectedJobTitle = hit.first.title;
        }
      }

      if (selectedJobId == null && jobs.isNotEmpty) {
        final preferred = jobs
            .where((job) => job.applicationsCount > 0)
            .toList();
        final picked = preferred.isNotEmpty ? preferred.first : jobs.first;
        selectedJobId = picked.id;
        selectedJobTitle = picked.title;
      }

      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _selectedJobId = selectedJobId;
        _selectedJobTitle = selectedJobTitle;
        _loadingJobs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingJobs = false);
      _snack(
        mapAnyError(e, fallback: context.l10n.jobApplicationsLoadJobsFailed),
      );
    }
  }

  Future<void> _loadApplications() async {
    if (!_canManageJobs) return;
    setState(() => _loadingApps = true);
    try {
      final search = _searchCtrl.text.trim();
      final api = ref.read(jobsApiClientProvider);
      final results = await Future.wait<dynamic>([
        api.listManagerApplications(
          status: _activeStatus,
          search: search.isEmpty ? null : search,
          activityType: _activityType,
          department: _department,
          jobId: _selectedJobId,
          page: 1,
          limit: 250,
        ),
        _selectedJobId == null
            ? Future<Map<String, dynamic>>.value(const <String, dynamic>{})
            : api.listJobRecommendations(jobId: _selectedJobId!),
      ]);
      final raw = Map<String, dynamic>.from(results[0] as Map);
      final rawItems = raw['items'] is List ? raw['items'] as List : const [];
      final applications = rawItems
          .whereType<Map>()
          .map(
            (e) => JobApplicationModel.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false);
      final rawRecommendationsMap = Map<String, dynamic>.from(
        results[1] as Map,
      );
      final rawRecommendations = rawRecommendationsMap['items'] is List
          ? rawRecommendationsMap['items'] as List
          : const [];
      final recommendations = rawRecommendations
          .whereType<Map>()
          .map(
            (e) =>
                JobRecommendationModel.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _applications = applications;
        _recommendations = recommendations;
        _loadingApps = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingApps = false);
      _snack(
        mapAnyError(
          e,
          fallback: context.l10n.jobApplicationsLoadApplicationsFailed,
        ),
      );
    }
  }

  Future<JobApplicationModel?> _changeStatus({
    required JobApplicationModel item,
    required String status,
    String? reason,
  }) async {
    _OfferDraft? offerDraft;
    if (status == 'hired') {
      offerDraft = await _askOfferDraft(item);
      if (offerDraft == null) return null;
    }

    if (_busy) return null;
    setState(() => _busy = true);
    try {
      final raw = await ref
          .read(jobsApiClientProvider)
          .updateJobApplicationStatus(
            jobId: item.jobId,
            applicationId: item.id,
            status: status,
            reason: reason,
            offerSalary: offerDraft?.salary,
            offerWorkHours: offerDraft?.workHours,
            offerWorkDays: offerDraft?.workDays,
            offerMessage: offerDraft?.message,
            offerAttachmentFile: offerDraft?.attachmentFile,
          );
      final data = raw['application'];
      if (data is! Map) {
        return null;
      }
      final updated = JobApplicationModel.fromJson(
        Map<String, dynamic>.from(data),
      );
      if (!mounted) return updated;
      setState(() {
        if (_activeStatus != null && _activeStatus != updated.status) {
          _applications = _applications
              .where((entry) => entry.id != updated.id)
              .toList(growable: false);
        } else {
          _applications = _applications
              .map((entry) => entry.id == updated.id ? updated : entry)
              .toList(growable: false);
        }
      });
      return updated;
    } catch (e) {
      if (!mounted) return null;
      _snack(
        mapAnyError(
          e,
          fallback: context.l10n.jobApplicationsUpdateStatusFailed,
        ),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<_OfferDraft?> _askOfferDraft(JobApplicationModel item) async {
    final salaryCtrl = TextEditingController(
      text: item.offerSalary == null
          ? ''
          : item.offerSalary!.toStringAsFixed(0),
    );
    final hoursCtrl = TextEditingController(text: item.offerWorkHours ?? '');
    final daysCtrl = TextEditingController(text: item.offerWorkDays ?? '');
    final messageCtrl = TextEditingController(text: item.offerMessage ?? '');
    LocalMediaFile? attachment;

    final out = await showModalBottomSheet<_OfferDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Directionality(
            textDirection: context.appTextDirection,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                10,
                12,
                12 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n.jobApplicationsOfferDetailsBeforeHiring,
                      textAlign: context.isEnglishLocale
                          ? TextAlign.left
                          : TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${item.jobTitle ?? context.l10n.commonJob} - ${item.jobCompanyName ?? context.l10n.commonCompany}',
                      textAlign: context.isEnglishLocale
                          ? TextAlign.left
                          : TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: salaryCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textDirection: context.appTextDirection,
                      decoration: InputDecoration(
                        labelText: context.l10n.jobApplicationsOfferedSalaryIqd,
                        hintText: context.l10n.jobApplicationsOfferedSalaryHint,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: hoursCtrl,
                      textDirection: context.appTextDirection,
                      decoration: InputDecoration(
                        labelText: context.l10n.commonWorkHours,
                        hintText: context.l10n.jobApplicationsWorkHoursHint,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: daysCtrl,
                      textDirection: context.appTextDirection,
                      decoration: InputDecoration(
                        labelText: context.l10n.commonWorkDays,
                        hintText: context.l10n.jobApplicationsWorkDaysHint,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: messageCtrl,
                      minLines: 2,
                      maxLines: 5,
                      textDirection: context.appTextDirection,
                      decoration: InputDecoration(
                        labelText:
                            context.l10n.jobApplicationsOfferMessageDetails,
                        hintText: context.l10n.jobApplicationsOfferMessageHint,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked =
                                await pickJobApplicationAttachmentFromDevice();
                            if (!mounted) return;
                            setSheetState(() => attachment = picked);
                          },
                          icon: const Icon(Icons.attach_file_rounded),
                          label: Text(
                            attachment == null
                                ? context
                                      .l10n
                                      .jobApplicationsOfferAttachmentOptional
                                : context.l10n.jobApplicationsChangeAttachment,
                          ),
                        ),
                        if (attachment != null)
                          OutlinedButton.icon(
                            onPressed: () =>
                                setSheetState(() => attachment = null),
                            icon: const Icon(Icons.close_rounded),
                            label: Text(context.l10n.commonRemove),
                          ),
                      ],
                    ),
                    if (attachment != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          attachment!.name,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(context.l10n.commonCancel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              final salaryText = salaryCtrl.text.trim();
                              final salary = salaryText.isEmpty
                                  ? null
                                  : double.tryParse(salaryText);
                              if (salaryText.isNotEmpty && salary == null) {
                                _snack(
                                  context
                                      .l10n
                                      .jobApplicationsInvalidSalaryValue,
                                );
                                return;
                              }
                              Navigator.of(context).pop(
                                _OfferDraft(
                                  salary: salary,
                                  workHours: hoursCtrl.text.trim(),
                                  workDays: daysCtrl.text.trim(),
                                  message: messageCtrl.text.trim(),
                                  attachmentFile: attachment,
                                ),
                              );
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: Text(
                              context.l10n.jobApplicationsSaveAndContinue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    salaryCtrl.dispose();
    hoursCtrl.dispose();
    daysCtrl.dispose();
    messageCtrl.dispose();
    return out;
  }

  Future<void> _openDetails(JobApplicationModel item) async {
    final canChangeStatus = item.canChangeStatus;
    final updated = await Navigator.of(context).push<JobApplicationModel>(
      MaterialPageRoute(
        builder: (_) => JobApplicationDetailsScreen(
          application: item,
          onChangeStatus: canChangeStatus
              ? ({required status, reason}) =>
                    _changeStatus(item: item, status: status, reason: reason)
              : null,
        ),
      ),
    );
    if (updated == null) return;
    if (!mounted) return;
    setState(() {
      if (_activeStatus != null && _activeStatus != updated.status) {
        _applications = _applications
            .where((entry) => entry.id != updated.id)
            .toList(growable: false);
      } else {
        _applications = _applications
            .map((entry) => entry.id == updated.id ? updated : entry)
            .toList(growable: false);
      }
    });
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'submitted':
        return context.l10n.jobApplicationsReceived;
      case 'shortlisted':
        return context.l10n.jobApplicationsShortlisted;
      case 'rejected':
        return context.l10n.jobApplicationsRejected;
      case 'hired':
        return context.l10n.jobApplicationsHired;
      case 'withdrawn':
        return context.l10n.jobApplicationsWithdrawn;
      case 'dismissed_after_hire':
        return context.l10n.jobsStatusDismissed;
      case 'archived':
        return context.l10n.jobApplicationsArchived;
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'submitted':
        return const Color(0xFF79C6FF);
      case 'shortlisted':
        return const Color(0xFF4FD08A);
      case 'rejected':
        return const Color(0xFFFF7A7A);
      case 'hired':
        return const Color(0xFF36D6B7);
      case 'withdrawn':
        return const Color(0xFFFFB35C);
      case 'dismissed_after_hire':
        return const Color(0xFFFF986E);
      case 'archived':
        return const Color(0xFFB7C0D1);
      default:
        return Colors.white70;
    }
  }

  String _taxonomyLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return '-';
    final words = cleaned
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .toList(growable: false);
    return words.join(' ');
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      _snack(context.l10n.jobApplicationsInvalidLink);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) {
      _snack(context.l10n.jobApplicationsFailedToOpenLink);
    }
  }

  Future<void> _openRecommendationDetails(JobRecommendationModel item) async {
    final source = item.sourceApplication;
    final subtitle = [
      if ((item.candidateWorkTitle ?? '').trim().isNotEmpty)
        item.candidateWorkTitle!.trim(),
      if ((item.candidateWorkCompany ?? '').trim().isNotEmpty)
        item.candidateWorkCompany!.trim(),
    ].join(' - ');
    final createdAt = item.createdAt == null
        ? '-'
        : '${item.createdAt!.toLocal()}'.split('.').first;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Directionality(
          textDirection: context.appTextDirection,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.jobApplicationsRecommendationCandidateDetails,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                _infoLine(context.l10n.commonName, item.candidateFullName),
                _infoLine(context.l10n.commonPhone, item.candidatePhone ?? '-'),
                _infoLine(context.l10n.commonEmail, item.candidateEmail ?? '-'),
                if (subtitle.isNotEmpty)
                  _infoLine(
                    context.l10n.jobApplicationsCurrentExperience,
                    subtitle,
                  ),
                _infoLine(
                  context.l10n.jobApplicationsRecommendedBy,
                  (item.recommendedByName ?? '').trim().isEmpty
                      ? context.l10n.jobApplicationsAdminSource
                      : item.recommendedByName!,
                ),
                _infoLine(
                  context.l10n.jobApplicationsRecommendationTime,
                  createdAt,
                ),
                if ((item.note ?? '').trim().isNotEmpty)
                  _infoLine(
                    context.l10n.jobApplicationsRecommendationNote,
                    item.note!.trim(),
                  ),
                if (item.linkedApplication != null)
                  _infoLine(
                    context.l10n.jobApplicationsRecommendationStatus,
                    _statusLabel(item.linkedApplication!.status ?? 'submitted'),
                  ),
                if (item.sourceJobTitle?.trim().isNotEmpty == true ||
                    item.sourceCompanyName?.trim().isNotEmpty == true)
                  _infoLine(
                    context.l10n.jobApplicationsExperienceSource,
                    '${item.sourceJobTitle ?? '-'} - ${item.sourceCompanyName ?? '-'}',
                  ),
                if (source != null) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.jobApplicationsOriginalApplicationData,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  if ((source.candidateFullName ?? '').trim().isNotEmpty)
                    _infoLine(
                      context.l10n.jobApplicationsApplicationName,
                      source.candidateFullName!,
                    ),
                  if ((source.candidatePhone ?? '').trim().isNotEmpty)
                    _infoLine(
                      context.l10n.jobApplicationsApplicationPhone,
                      source.candidatePhone!,
                    ),
                  if ((source.candidateEmail ?? '').trim().isNotEmpty)
                    _infoLine(
                      context.l10n.jobApplicationsApplicationEmail,
                      source.candidateEmail!,
                    ),
                  if (source.expectedSalary != null)
                    _infoLine(
                      context.l10n.jobApplicationsExpectedSalary,
                      source.expectedSalary!.toStringAsFixed(0),
                    ),
                  if ((source.message ?? '').trim().isNotEmpty)
                    _infoLine(
                      context.l10n.jobApplicationsCoverMessage,
                      source.message!.trim(),
                    ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if ((item.attachmentUrl ?? '').trim().isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _openExternal(item.attachmentUrl!),
                        icon: const Icon(Icons.download_rounded),
                        label: Text(
                          (item.attachmentName ?? '').trim().isNotEmpty
                              ? context.l10n
                                    .jobApplicationsRecommendationAttachmentWithName(
                                      item.attachmentName!,
                                    )
                              : context
                                    .l10n
                                    .jobApplicationsOpenRecommendationAttachment,
                        ),
                      ),
                    if (source != null &&
                        (source.attachmentUrl ?? '').trim().isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _openExternal(source.attachmentUrl!),
                        icon: const Icon(Icons.attach_file_rounded),
                        label: Text(
                          (source.attachmentName ?? '').trim().isNotEmpty
                              ? context.l10n
                                    .jobApplicationsApplicantAttachmentWithName(
                                      source.attachmentName!,
                                    )
                              : context
                                    .l10n
                                    .jobApplicationsOpenApplicantAttachment,
                        ),
                      ),
                    if (source != null &&
                        (source.resumeUrl ?? '').trim().isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _openExternal(source.resumeUrl!),
                        icon: const Icon(Icons.description_outlined),
                        label: Text(context.l10n.jobApplicationsOpenResumeLink),
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

  Future<void> _acceptRecommendation(JobRecommendationModel item) async {
    if (_selectedJobId == null ||
        _acceptingRecommendationIds.contains(item.id)) {
      return;
    }
    if (!item.canAcceptToShortlist) return;

    final reason = await _askRecommendationReason();
    if (reason == null) return;

    setState(() => _acceptingRecommendationIds.add(item.id));
    try {
      final out = await ref
          .read(jobsApiClientProvider)
          .acceptJobRecommendation(
            jobId: _selectedJobId!,
            recommendationId: item.id,
            reason: reason,
          );
      final recommendationRaw = out['recommendation'];
      if (mounted && recommendationRaw is Map) {
        final nextRecommendation = JobRecommendationModel.fromJson(
          Map<String, dynamic>.from(recommendationRaw),
        );
        setState(() {
          _recommendations = _recommendations
              .map((entry) => entry.id == item.id ? nextRecommendation : entry)
              .toList(growable: false);
        });
      }

      if (!mounted) return;
      _snack(context.l10n.jobApplicationsRecommendationAccepted);
      await _loadApplications();
    } catch (e) {
      if (!mounted) return;
      _snack(
        mapAnyError(
          e,
          fallback: context.l10n.jobApplicationsRecommendationAcceptFailed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _acceptingRecommendationIds.remove(item.id));
      }
    }
  }

  Future<String?> _askRecommendationReason() async {
    final ctrl = TextEditingController();
    final out = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.jobApplicationsRecommendationAcceptanceReasonTitle,
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          textDirection: context.appTextDirection,
          decoration: InputDecoration(
            hintText:
                context.l10n.jobApplicationsRecommendationAcceptanceReasonHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: Text(context.l10n.commonConfirm),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return out;
  }

  Widget _infoLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        textAlign: TextAlign.right,
        text: TextSpan(
          style: const TextStyle(color: Colors.white, height: 1.35),
          children: [
            TextSpan(
              text: '$title: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF204D6E).withValues(alpha: 0.34),
        border: Border.all(
          color: const Color(0xFF6BC7FF).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.jobApplicationsAdminRecommendations,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ..._recommendations.map((item) {
            final subtitle = [
              if ((item.candidateWorkTitle ?? '').trim().isNotEmpty)
                item.candidateWorkTitle!.trim(),
              if ((item.candidateWorkCompany ?? '').trim().isNotEmpty)
                item.candidateWorkCompany!.trim(),
            ].join(' - ');
            final createdAt = item.createdAt == null
                ? '-'
                : '${item.createdAt!.toLocal()}'.split('.').first;
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openRecommendationDetails(item),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: const Color(
                              0xFF6BC7FF,
                            ).withValues(alpha: 0.18),
                            border: Border.all(
                              color: const Color(
                                0xFF6BC7FF,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            context
                                .l10n
                                .jobApplicationsAdministrativeRecommendation,
                            style: const TextStyle(
                              color: Color(0xFF9EDDFF),
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if ((item.recommendedByName ?? '').trim().isNotEmpty)
                          Text(
                            context.l10n.jobApplicationsByName(
                              item.recommendedByName!,
                            ),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.candidateFullName,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.84),
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      item.candidatePhone ?? '-',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                    if ((item.note ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.note!.trim(),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.jobApplicationsRecommendationTimeLine(
                        createdAt,
                      ),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (item.sourceApplicationId != null)
                      Text(
                        context.l10n.jobApplicationsRecommendationSourceLine(
                          item.sourceApplicationId!,
                        ),
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (item.linkedApplication?.status != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.l10n.jobApplicationsCurrentStatusLine(
                          _statusLabel(item.linkedApplication!.status!),
                        ),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Color(0xFF9DECCB),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    if (item.canAcceptToShortlist &&
                        _selectedJobId != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed:
                              _acceptingRecommendationIds.contains(item.id)
                              ? null
                              : () => _acceptRecommendation(item),
                          icon: _acceptingRecommendationIds.contains(item.id)
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.how_to_reg_rounded),
                          label: Text(
                            _acceptingRecommendationIds.contains(item.id)
                                ? context.l10n.jobApplicationsAccepting
                                : context
                                      .l10n
                                      .jobApplicationsAcceptRecommendation,
                          ),
                        ),
                      ),
                    ] else if ((item.candidateUserId ?? 0) <= 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.l10n.jobApplicationsManualRecommendationNoUser,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canManageJobs) {
      return Scaffold(
        body: Center(child: Text(context.l10n.jobApplicationsManagementOnly)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.jobApplicationsApplicationsManagement),
        actions: [
          IconButton(
            tooltip: context.l10n.commonRefresh,
            onPressed: _loadingApps || _loadingJobs ? null : _bootstrap,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _statusTabs
              .map((entry) => Tab(text: _statusTabLabel(entry)))
              .toList(growable: false),
        ),
      ),
      body: Directionality(
        textDirection: context.appTextDirection,
        child: _loadingJobs
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeaderCard(),
                        const SizedBox(height: 8),
                        _buildSearchRow(),
                        if (_jobs.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildJobsSelector(),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _loadingApps
                        ? const Center(child: CircularProgressIndicator())
                        : _applications.isEmpty && _recommendations.isEmpty
                        ? Center(
                            child: Text(
                              context
                                  .l10n
                                  .jobApplicationsNoApplicationsForCurrentFilters,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount:
                                _applications.length +
                                (_recommendations.isNotEmpty ? 1 : 0),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final hasRecommendationSection =
                                  _recommendations.isNotEmpty;
                              if (hasRecommendationSection && index == 0) {
                                return _buildRecommendationSection();
                              }
                              final applicationIndex =
                                  index - (hasRecommendationSection ? 1 : 0);
                              final item = _applications[applicationIndex];
                              final statusColor = _statusColor(item.status);
                              return Card(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _openDetails(item),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
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
                                                item.profileFullName ??
                                                    item.fullName ??
                                                    context
                                                        .l10n
                                                        .jobApplicationsApplicant,
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                item.profilePhone ??
                                                    item.submittedPhone ??
                                                    '-',
                                                textAlign: TextAlign.right,
                                              ),
                                              if (item.jobTitle
                                                          ?.trim()
                                                          .isNotEmpty ==
                                                      true ||
                                                  item.jobCompanyName
                                                          ?.trim()
                                                          .isNotEmpty ==
                                                      true)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Text(
                                                    '${item.jobTitle ?? '-'} - ${item.jobCompanyName ?? '-'}',
                                                    textAlign: TextAlign.right,
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.78,
                                                          ),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 9,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                      border: Border.all(
                                                        color: statusColor
                                                            .withValues(
                                                              alpha: 0.55,
                                                            ),
                                                      ),
                                                      color: statusColor
                                                          .withValues(
                                                            alpha: 0.16,
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
                                                  Text(
                                                    item.createdAt == null
                                                        ? '-'
                                                        : '${item.createdAt!.toLocal()}'
                                                              .split('.')
                                                              .first,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
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
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final scopeParts = <String>[];
    if (_selectedJobTitle?.trim().isNotEmpty == true) {
      scopeParts.add(context.l10n.jobApplicationsJob(_selectedJobTitle!));
    }
    if (_activityType?.trim().isNotEmpty == true) {
      scopeParts.add(
        context.l10n.jobApplicationsScopeActivity(
          _taxonomyLabel(_activityType!),
        ),
      );
    }
    if (_department?.trim().isNotEmpty == true) {
      scopeParts.add(
        context.l10n.jobApplicationsScopeDepartment(
          _taxonomyLabel(_department!),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF234B83), Color(0xFF142E56)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              context.l10n.jobApplicationsHiringBoard,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              textAlign: context.isEnglishLocale
                  ? TextAlign.left
                  : TextAlign.right,
            ),
            const SizedBox(height: 6),
            Text(
              scopeParts.isEmpty
                  ? context.l10n.jobApplicationsViewingAllCurrentApplications
                  : scopeParts.join(' • '),
              textAlign: context.isEnglishLocale
                  ? TextAlign.left
                  : TextAlign.right,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.jobApplicationsVisibleNow(_applications.length),
              textAlign: context.isEnglishLocale
                  ? TextAlign.left
                  : TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF9DECCB),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.l10n.jobApplicationsSearchByApplicantPhoneJob,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onSubmitted: (_) => _loadApplications(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _loadingApps ? null : _loadApplications,
          child: Text(context.l10n.commonSearch),
        ),
      ],
    );
  }

  Widget _buildJobsSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          selected: _selectedJobId == null,
          label: Text(context.l10n.jobApplicationsAllJobs),
          onSelected: (_) {
            setState(() {
              _selectedJobId = null;
              _selectedJobTitle = null;
            });
            _loadApplications();
          },
        ),
        ..._jobs.map(
          (job) => ChoiceChip(
            selected: _selectedJobId == job.id,
            label: Text('${job.title} (${job.applicationsCount})'),
            onSelected: (_) {
              setState(() {
                _selectedJobId = job.id;
                _selectedJobTitle = job.title;
              });
              _loadApplications();
            },
          ),
        ),
      ],
    );
  }
}

class _OfferDraft {
  final double? salary;
  final String? workHours;
  final String? workDays;
  final String? message;
  final LocalMediaFile? attachmentFile;

  const _OfferDraft({
    required this.salary,
    required this.workHours,
    required this.workDays,
    required this.message,
    required this.attachmentFile,
  });
}
