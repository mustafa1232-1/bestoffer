import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/jobs_api.dart';
import '../models/job_models.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

final jobAdminReaderApiProvider = Provider<JobsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return JobsApi(dio);
});

class JobAdminJobsReaderScreen extends ConsumerStatefulWidget {
  const JobAdminJobsReaderScreen({super.key});

  @override
  ConsumerState<JobAdminJobsReaderScreen> createState() =>
      _JobAdminJobsReaderScreenState();
}

class _JobAdminJobsReaderScreenState
    extends ConsumerState<JobAdminJobsReaderScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  List<JobPostModel> _jobs = const [];

  bool get _canOpen {
    final auth = ref.read(authControllerProvider);
    return auth.isAdmin || auth.isSuperAdmin;
  }

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

  String _taxonomyLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return '-';
    return cleaned
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    if (!_canOpen) return;
    setState(() => _loading = true);
    try {
      final raw = await ref
          .read(jobAdminReaderApiProvider)
          .listAdminReadableJobs(
            search: _searchCtrl.text.trim().isEmpty
                ? null
                : _searchCtrl.text.trim(),
            page: 1,
            limit: 180,
            onlyOpen: false,
            sort: 'recent',
          );
      final rawItems = raw['items'] is List ? raw['items'] as List : const [];
      final items = rawItems
          .whereType<Map>()
          .map(
            (entry) => JobPostModel.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _jobs = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(
        mapAnyError(
          e,
          fallback: context.l10n.jobAdminJobsReaderLoadPublishedJobsFailed,
        ),
      );
    }
  }

  Future<void> _openRecommendationComposer(JobPostModel job) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _JobRecommendationComposerSheet(
        api: ref.read(jobAdminReaderApiProvider),
        job: job,
      ),
    );
    if (created == true && mounted) {
      _snack(
        context.l10n.jobAdminJobsReaderRecommendationSubmittedSuccessfully,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canOpen) {
      return Scaffold(
        body: Center(
          child: Text(context.l10n.jobAdminJobsReaderThisPageIsForAdminsOnly),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.jobAdminJobsReaderTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.drawerRefresh,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: context.appTextDirection,
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
                        hintText: context
                            .l10n
                            .jobAdminJobsReaderSearchByJobTitleOrCompany,
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _loading ? null : _load,
                    child: Text(context.l10n.commonSearch),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _jobs.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.jobAdminJobsReaderNoJobsMatchCurrentSearch,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: _jobs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final job = _jobs[index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    job.title,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${job.companyName} - ${job.city}${job.area == null ? '' : ' - ${job.area}'}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      _chip(
                                        '${_taxonomyLabel(job.activityType)} / ${_taxonomyLabel(job.department)}',
                                      ),
                                      _chip(
                                        '${context.l10n.jobsHubCategory}: ${job.category}',
                                      ),
                                      _chip(
                                        '${context.l10n.jobsHubApplications}: ${job.applicationsCount}',
                                      ),
                                      _chip(
                                        '${context.l10n.companyPromotionsCampaignStatus}: ${job.status}',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.icon(
                                      onPressed: () =>
                                          _openRecommendationComposer(job),
                                      icon: const Icon(
                                        Icons.person_search_rounded,
                                      ),
                                      label: Text(
                                        context
                                            .l10n
                                            .jobAdminJobsReaderRecommendCandidate,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _JobRecommendationComposerSheet extends StatefulWidget {
  final JobsApi api;
  final JobPostModel job;

  const _JobRecommendationComposerSheet({required this.api, required this.job});

  @override
  State<_JobRecommendationComposerSheet> createState() =>
      _JobRecommendationComposerSheetState();
}

class _JobRecommendationComposerSheetState
    extends State<_JobRecommendationComposerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _manualNameCtrl = TextEditingController();
  final TextEditingController _manualPhoneCtrl = TextEditingController();
  final TextEditingController _manualEmailCtrl = TextEditingController();
  final TextEditingController _manualTitleCtrl = TextEditingController();
  final TextEditingController _manualCompanyCtrl = TextEditingController();

  bool _loadingCandidates = true;
  bool _saving = false;
  bool _manualMode = false;
  List<JobRecommendationCandidateModel> _candidates = const [];
  LocalMediaFile? _manualAttachment;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadCandidates);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    _manualNameCtrl.dispose();
    _manualPhoneCtrl.dispose();
    _manualEmailCtrl.dispose();
    _manualTitleCtrl.dispose();
    _manualCompanyCtrl.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadCandidates() async {
    setState(() => _loadingCandidates = true);
    try {
      final raw = await widget.api.listRecommendationCandidatesForJob(
        jobId: widget.job.id,
        search: _searchCtrl.text.trim().isEmpty
            ? null
            : _searchCtrl.text.trim(),
        limit: 70,
      );
      final rawItems = raw['items'] is List ? raw['items'] as List : const [];
      final items = rawItems
          .whereType<Map>()
          .map(
            (entry) => JobRecommendationCandidateModel.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _candidates = items;
        _loadingCandidates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCandidates = false);
      _snack(
        mapAnyError(
          e,
          fallback:
              context.l10n.jobAdminJobsReaderLoadRecommendationCandidatesFailed,
        ),
      );
    }
  }

  Future<void> _recommendFromPool(
    JobRecommendationCandidateModel candidate,
  ) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.api.createJobRecommendation(
        jobId: widget.job.id,
        sourceApplicationId: candidate.sourceApplicationId,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack(
        mapAnyError(
          e,
          fallback: context.l10n.jobAdminJobsReaderSubmitRecommendationFailed,
        ),
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _pickManualAttachment() async {
    final picked = await pickJobApplicationAttachmentFromDevice();
    if (!mounted || picked == null) return;
    setState(() => _manualAttachment = picked);
  }

  Future<void> _submitManualRecommendation() async {
    if (_saving) return;
    final candidateName = _manualNameCtrl.text.trim();
    if (candidateName.isEmpty) {
      _snack(context.l10n.jobAdminJobsReaderPleaseEnterCandidateName);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.api.createJobRecommendation(
        jobId: widget.job.id,
        candidateFullName: candidateName,
        candidatePhone: _manualPhoneCtrl.text.trim().isEmpty
            ? null
            : _manualPhoneCtrl.text.trim(),
        candidateEmail: _manualEmailCtrl.text.trim().isEmpty
            ? null
            : _manualEmailCtrl.text.trim(),
        candidateWorkTitle: _manualTitleCtrl.text.trim().isEmpty
            ? null
            : _manualTitleCtrl.text.trim(),
        candidateWorkCompany: _manualCompanyCtrl.text.trim().isEmpty
            ? null
            : _manualCompanyCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        attachmentFile: _manualAttachment,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack(
        mapAnyError(
          e,
          fallback:
              context.l10n.jobAdminJobsReaderSubmitManualRecommendationFailed,
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        child: Directionality(
          textDirection: context.appTextDirection,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${context.l10n.jobAdminJobsReaderRecommendationFor}: ${widget.job.title}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.job.companyName,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.82)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      selected: !_manualMode,
                      label: Text(
                        context.l10n.jobAdminJobsReaderFromTalentPool,
                      ),
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _manualMode = false),
                    ),
                    ChoiceChip(
                      selected: _manualMode,
                      label: Text(
                        context.l10n.jobAdminJobsReaderManualRecommendation,
                      ),
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _manualMode = true),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteCtrl,
                  minLines: 2,
                  maxLines: 4,
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(
                    labelText: context
                        .l10n
                        .jobAdminJobsReaderRecommendationNoteOptional,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                if (_manualMode) ...[
                  TextField(
                    controller: _manualNameCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      labelText: context.l10n.jobAdminJobsReaderCandidateName,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      labelText: context.l10n.jobAdminJobsReaderPhone,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      labelText: context.l10n.companyDashboardEmail,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualTitleCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      labelText: context.l10n.jobAdminJobsReaderCurrentJobTitle,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualCompanyCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      labelText: context.l10n.jobAdminJobsReaderCurrentCompany,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _pickManualAttachment,
                        icon: const Icon(Icons.attach_file_rounded),
                        label: Text(
                          context.l10n.jobAdminJobsReaderAttachFileImage,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _manualAttachment == null
                              ? context
                                    .l10n
                                    .jobAdminJobsReaderNoAttachmentSelected
                              : _manualAttachment!.name,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _submitManualRecommendation,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      context.l10n.jobAdminJobsReaderSubmitManualRecommendation,
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: context
                                .l10n
                                .jobAdminJobsReaderSearchByNameOrPhone,
                            prefixIcon: const Icon(Icons.search_rounded),
                          ),
                          onSubmitted: (_) => _loadCandidates(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saving || _loadingCandidates
                            ? null
                            : _loadCandidates,
                        child: Text(context.l10n.commonSearch),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_loadingCandidates)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_candidates.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        context
                            .l10n
                            .jobAdminJobsReaderNoMatchingCandidatesRightNow,
                        textAlign: TextAlign.right,
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _candidates.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _candidates[index];
                        final subtitle = [
                          if ((item.candidateWorkTitle ?? '').trim().isNotEmpty)
                            item.candidateWorkTitle!.trim(),
                          if ((item.candidateWorkCompany ?? '')
                              .trim()
                              .isNotEmpty)
                            item.candidateWorkCompany!.trim(),
                        ].join(' - ');
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            color: Colors.white.withValues(alpha: 0.04),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundImage:
                                        (item.candidateImageUrl ?? '')
                                            .trim()
                                            .isNotEmpty
                                        ? AppCachedImageProvider(
                                            item.candidateImageUrl!.trim(),
                                          )
                                        : null,
                                    child:
                                        (item.candidateImageUrl ?? '')
                                            .trim()
                                            .isNotEmpty
                                        ? null
                                        : const Icon(Icons.person_outline),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          item.candidateFullName,
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        if (subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            subtitle,
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.82,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 2),
                                        Text(
                                          item.candidatePhone ?? '-',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.78,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${context.l10n.jobAdminJobsReaderLatestAppliedJob}: ${item.sourceJobTitle ?? '-'} (${item.sourceCompanyName ?? '-'})',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${context.l10n.jobAdminJobsReaderPreviousApplications}: ${item.applicationsCount}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.tonalIcon(
                                  onPressed: _saving
                                      ? null
                                      : () => _recommendFromPool(item),
                                  icon: const Icon(
                                    Icons.person_add_alt_1_rounded,
                                  ),
                                  label: Text(
                                    context
                                        .l10n
                                        .jobAdminJobsReaderRecommendThisCandidate,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
