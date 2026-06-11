import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../../auth/state/auth_controller.dart';
import '../data/jobs_api.dart';
import '../models/job_models.dart';
import 'job_application_details_screen.dart';

final myJobsApiProvider = Provider<JobsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return JobsApi(dio);
});

class JobMyApplicationsScreen extends ConsumerStatefulWidget {
  const JobMyApplicationsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<JobMyApplicationsScreen> createState() =>
      _JobMyApplicationsScreenState();
}

class _JobMyApplicationsScreenState
    extends ConsumerState<JobMyApplicationsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const List<String?> _tabs = [
    null,
    'submitted',
    'shortlisted',
    'hired',
    'rejected',
    'withdrawn',
    'dismissed_after_hire',
    'archived',
  ];

  late final TabController _tabController = TabController(
    length: _tabs.length,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, _tabs.length - 1),
  )..addListener(_onTabChanged);

  Timer? _autoRefreshTimer;
  bool _loading = true;
  bool _refreshing = false;
  List<JobApplicationModel> _items = const [];
  final Set<int> _acceptingIds = <int>{};

  String? get _activeStatus => _tabs[_tabController.index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_load);
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _load();
  }

  String _tabLabel(String? status) {
    final l10n = context.l10n;
    switch (status) {
      case null:
        return l10n.commonAll;
      case 'submitted':
        return l10n.jobsMyApplicationsTabReceived;
      case 'shortlisted':
        return l10n.jobsMyApplicationsTabShortlisted;
      case 'hired':
        return l10n.jobsMyApplicationsTabHired;
      case 'rejected':
        return l10n.jobsMyApplicationsTabRejected;
      case 'withdrawn':
        return l10n.jobsMyApplicationsTabWithdrawn;
      case 'dismissed_after_hire':
        return l10n.jobsMyApplicationsTabDismissed;
      case 'archived':
        return l10n.jobsMyApplicationsTabArchived;
      default:
        return status;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) {
      setState(() => _loading = true);
    }
    try {
      final raw = await ref
          .read(myJobsApiProvider)
          .listMyApplications(status: _activeStatus, page: 1, limit: 200);
      final list = raw['items'] is List ? raw['items'] as List : const [];
      final items = list
          .whereType<Map>()
          .map(
            (e) => JobApplicationModel.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) {
        final l10n = context.l10n;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mapAnyError(e, fallback: l10n.jobsMyApplicationsLoadFailed),
            ),
          ),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  String _statusLabel(String status) {
    final l10n = context.l10n;
    return switch (status) {
      'submitted' => l10n.jobsMyApplicationsStatusReceived,
      'shortlisted' => l10n.jobsMyApplicationsStatusShortlisted,
      'rejected' => l10n.jobsMyApplicationsStatusRejected,
      'hired' => l10n.jobsMyApplicationsStatusHired,
      'withdrawn' => l10n.jobsMyApplicationsStatusWithdrawn,
      'dismissed_after_hire' => l10n.jobsMyApplicationsStatusDismissed,
      'archived' => l10n.jobsMyApplicationsStatusArchived,
      _ => status,
    };
  }

  Color _statusColor(String status) {
    return switch (status) {
      'submitted' => const Color(0xFF7EB8FF),
      'shortlisted' => const Color(0xFF54D38C),
      'rejected' => const Color(0xFFFF9A9A),
      'hired' => const Color(0xFF31D7B3),
      'withdrawn' => const Color(0xFFFFB35C),
      'dismissed_after_hire' => const Color(0xFFFF986E),
      'archived' => const Color(0xFFB7C0D1),
      _ => Colors.white70,
    };
  }

  String _dateText(DateTime? value) {
    if (value == null) return '-';
    final locale = Localizations.localeOf(context).toLanguageTag();
    return intl.DateFormat.yMd(locale).format(value.toLocal());
  }

  String _dateTimeText(DateTime? value) {
    if (value == null) return '-';
    final locale = Localizations.localeOf(context).toLanguageTag();
    return intl.DateFormat.yMd(locale).add_jm().format(value.toLocal());
  }

  bool _canWithdraw(JobApplicationModel item) =>
      <String>{'submitted', 'shortlisted', 'hired'}.contains(item.status) &&
      item.offerAcceptedAt == null;

  Future<String?> _askWithdrawReason() async {
    final ctrl = TextEditingController();
    final scrollCoordinator = FormScrollCoordinator();
    String? fieldError;
    String? formError;
    var saving = false;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              if (saving) return;
              final reason = ctrl.text.trim();
              if (reason.length < 2) {
                setModalState(() {
                  fieldError = resolveFormFieldError(
                    l10n: l10n,
                    field: 'reason',
                    fieldLabel: l10n.commonReason,
                  );
                  formError = l10n.validationReviewRequiredFields;
                });
                await scrollCoordinator.focusFirstError(const ['reason']);
                return;
              }
              saving = true;
              Navigator.of(dialogContext).pop(reason);
            }

            return AlertDialog(
              title: Text(l10n.jobsMyApplicationsWithdrawReasonTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FormErrorBanner(message: formError),
                  scrollCoordinator.anchor(
                    'reason',
                    TextField(
                      controller: ctrl,
                      focusNode: scrollCoordinator.focusNodeFor('reason'),
                      maxLines: 4,
                      onChanged: (_) {
                        if ((fieldError != null || formError != null)) {
                          setModalState(() {
                            fieldError = null;
                            formError = null;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        hintText: l10n.jobsMyApplicationsWithdrawReasonHint,
                        errorText: fieldError,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(onPressed: submit, child: Text(l10n.commonSave)),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
    scrollCoordinator.dispose();
    return result;
  }

  Future<JobApplicationModel?> _submitWithdraw(
    JobApplicationModel item, {
    required String reason,
  }) async {
    final raw = await ref
        .read(myJobsApiProvider)
        .withdrawMyApplication(applicationId: item.id, reason: reason);
    final data = raw['application'];
    if (data is! Map) return null;
    final updated = JobApplicationModel.fromJson(
      Map<String, dynamic>.from(data),
    );
    if (!mounted) return updated;
    setState(() {
      if (_activeStatus != null && _activeStatus != updated.status) {
        _items = _items
            .where((entry) => entry.id != updated.id)
            .toList(growable: false);
      } else {
        _items = _items
            .map((entry) => entry.id == updated.id ? updated : entry)
            .toList(growable: false);
      }
    });
    return updated;
  }

  Future<void> _withdrawApplication(JobApplicationModel item) async {
    if (!_canWithdraw(item)) return;
    final reason = await _askWithdrawReason();
    if (reason == null) return;
    try {
      final updated = await _submitWithdraw(item, reason: reason);
      if (!mounted || updated == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.jobsMyApplicationsWithdrawSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.jobsMyApplicationsWithdrawFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openDetails(JobApplicationModel item) async {
    final updated = await Navigator.of(context).push<JobApplicationModel>(
      MaterialPageRoute(
        builder: (_) => JobApplicationDetailsScreen(
          application: item,
          onChangeStatus: null,
          onWithdraw: _canWithdraw(item)
              ? ({required reason}) => _submitWithdraw(item, reason: reason)
              : null,
        ),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      if (_activeStatus != null && _activeStatus != updated.status) {
        _items = _items
            .where((entry) => entry.id != updated.id)
            .toList(growable: false);
      } else {
        _items = _items
            .map((entry) => entry.id == updated.id ? updated : entry)
            .toList(growable: false);
      }
    });
  }

  Widget _offerLine(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.start,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAcceptOfferSheet(JobApplicationModel item) async {
    LocalMediaFile? attachment;
    var busy = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final l10n = sheetContext.l10n;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                12,
                14,
                12 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.jobsMyApplicationsAcceptOfferTitle,
                      textAlign: TextAlign.start,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _offerLine(
                      sheetContext,
                      label: l10n.commonJob,
                      value:
                          item.jobTitle ?? l10n.jobsMyApplicationsJobFallback,
                    ),
                    _offerLine(
                      sheetContext,
                      label: l10n.commonCompany,
                      value:
                          item.jobCompanyName ??
                          l10n.jobsMyApplicationsCompanyFallback,
                    ),
                    if (item.offerSalary != null)
                      _offerLine(
                        sheetContext,
                        label: l10n.commonSalary,
                        value:
                            '${formatIqd(item.offerSalary!, withCode: false)} IQD',
                      ),
                    if ((item.offerWorkHours ?? '').trim().isNotEmpty)
                      _offerLine(
                        sheetContext,
                        label: l10n.commonWorkHours,
                        value: item.offerWorkHours!.trim(),
                      ),
                    if ((item.offerWorkDays ?? '').trim().isNotEmpty)
                      _offerLine(
                        sheetContext,
                        label: l10n.commonWorkDays,
                        value: item.offerWorkDays!.trim(),
                      ),
                    if ((item.offerMessage ?? '').trim().isNotEmpty)
                      _offerLine(
                        sheetContext,
                        label: l10n.jobsMyApplicationsOfferDetails,
                        value: item.offerMessage!.trim(),
                      ),
                    if ((item.offerAttachmentUrl ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l10n.jobsMyApplicationsOfferAttachmentAvailable,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    const Divider(height: 20),
                    Text(
                      '${l10n.jobsMyApplicationsUploadSignedOffer} (${l10n.commonOptional})',
                      textAlign: TextAlign.start,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  final picked =
                                      await pickJobApplicationAttachmentFromDevice();
                                  if (!mounted) return;
                                  setSheetState(() => attachment = picked);
                                },
                          icon: const Icon(Icons.attach_file_rounded),
                          label: Text(
                            attachment == null
                                ? l10n.jobsMyApplicationsChooseAttachment
                                : l10n.jobsMyApplicationsChangeAttachment,
                          ),
                        ),
                        if (attachment != null)
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => setSheetState(() => attachment = null),
                            icon: const Icon(Icons.close_rounded),
                            label: Text(l10n.commonRemove),
                          ),
                      ],
                    ),
                    if (attachment != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        attachment!.name,
                        textAlign: TextAlign.start,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: busy
                                ? null
                                : () => Navigator.of(sheetContext).pop(false),
                            child: Text(l10n.commonCancel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () async {
                                    setSheetState(() => busy = true);
                                    final done = await _acceptOffer(
                                      item,
                                      attachment: attachment,
                                    );
                                    if (!sheetContext.mounted) return;
                                    Navigator.of(sheetContext).pop(done);
                                  },
                            icon: busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(
                              busy
                                  ? l10n.jobsMyApplicationsSubmitting
                                  : l10n.jobsMyApplicationsAcceptOfferAction,
                            ),
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
      ),
    );
    if (ok == true) {
      _load(silent: true);
    }
  }

  Future<bool> _acceptOffer(
    JobApplicationModel item, {
    LocalMediaFile? attachment,
  }) async {
    if (_acceptingIds.contains(item.id)) return false;
    setState(() => _acceptingIds.add(item.id));
    try {
      final raw = await ref
          .read(myJobsApiProvider)
          .acceptMyJobOffer(applicationId: item.id, attachmentFile: attachment);
      final updatedMap = raw['application'];
      final workProfileMap = raw['workProfile'];
      final updated = updatedMap is Map
          ? JobApplicationModel.fromJson(Map<String, dynamic>.from(updatedMap))
          : item;
      if (!mounted) return true;

      setState(() {
        _items = _items
            .map((entry) => entry.id == item.id ? updated : entry)
            .toList(growable: false);
      });

      if (workProfileMap is Map) {
        final workProfile = Map<String, dynamic>.from(workProfileMap);
        ref
            .read(authControllerProvider.notifier)
            .updateLocalWorkProfile(
              workTitle: workProfile['workTitle']?.toString(),
              workCompany: workProfile['workCompany']?.toString(),
            );
      } else {
        ref
            .read(authControllerProvider.notifier)
            .updateLocalWorkProfile(
              workTitle: updated.jobTitle,
              workCompany: updated.jobCompanyName,
            );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.jobsMyApplicationsOfferAcceptedSuccess),
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.jobsMyApplicationsOfferAcceptFailed,
            ),
          ),
        ),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _acceptingIds.remove(item.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.jobsMyApplicationsTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs
              .map((item) => Tab(text: _tabLabel(item)))
              .toList(growable: false),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.jobsMyApplicationsNoApplications,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final item = _items[index];
                  final statusColor = _statusColor(item.status);
                  final title =
                      item.jobTitle ?? l10n.jobsMyApplicationsJobFallback;
                  final company =
                      item.jobCompanyName ??
                      l10n.jobsMyApplicationsCompanyFallback;
                  final location =
                      [
                            item.applicantBlock,
                            item.applicantBuildingNumber,
                            item.applicantApartment,
                          ]
                          .where((entry) => (entry ?? '').trim().isNotEmpty)
                          .join(' - ');
                  final isAccepting = _acceptingIds.contains(item.id);

                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openDetails(item),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: const Color(0xFF173A62),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
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
                                  color: statusColor.withValues(alpha: 0.16),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  _statusLabel(item.status),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _dateText(item.createdAt),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            title,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            company,
                            textAlign: TextAlign.end,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          if (location.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              location,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          if ((item.statusReason ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              l10n.jobsMyApplicationsStatusReason(
                                item.statusReason!.trim(),
                              ),
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          if (_canWithdraw(item)) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: OutlinedButton.icon(
                                onPressed: () => _withdrawApplication(item),
                                icon: const Icon(Icons.undo_rounded),
                                label: Text(
                                  l10n.jobsMyApplicationsWithdrawAction,
                                ),
                              ),
                            ),
                          ],
                          if (item.canAcceptOffer ||
                              item.offerAcceptedAt != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: const Color(
                                  0xFF36D6B7,
                                ).withValues(alpha: 0.12),
                                border: Border.all(
                                  color: const Color(
                                    0xFF36D6B7,
                                  ).withValues(alpha: 0.45),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    l10n.jobsMyApplicationsOfferSectionTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (item.offerSalary != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        l10n.jobsMyApplicationsOfferSalaryLine(
                                          '${formatIqd(item.offerSalary!, withCode: false)} IQD',
                                        ),
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                  if ((item.offerWorkHours ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        l10n.jobsMyApplicationsOfferWorkHoursLine(
                                          item.offerWorkHours!.trim(),
                                        ),
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                  if ((item.offerWorkDays ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        l10n.jobsMyApplicationsOfferWorkDaysLine(
                                          item.offerWorkDays!.trim(),
                                        ),
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                  if (item.offerAcceptedAt != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        l10n.jobsMyApplicationsOfferAcceptedAtLine(
                                          _dateTimeText(item.offerAcceptedAt),
                                        ),
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.82,
                                          ),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (item.canAcceptOffer) ...[
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: isAccepting
                                            ? null
                                            : () => _openAcceptOfferSheet(item),
                                        icon: isAccepting
                                            ? const SizedBox(
                                                width: 15,
                                                height: 15,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.check_circle),
                                        label: Text(
                                          isAccepting
                                              ? l10n.jobsMyApplicationsSubmittingAcceptance
                                              : l10n.jobsMyApplicationsAcceptOfferButton,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
