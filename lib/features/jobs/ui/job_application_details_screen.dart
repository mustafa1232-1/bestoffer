import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../../social/ui/social_profile_screen.dart';
import '../job_portal_text.dart';
import '../models/job_models.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

typedef JobApplicationStatusUpdater =
    Future<JobApplicationModel?> Function({
      required String status,
      String? reason,
    });

typedef JobApplicationWithdrawer =
    Future<JobApplicationModel?> Function({required String reason});

class JobApplicationDetailsScreen extends StatefulWidget {
  final JobApplicationModel application;
  final JobApplicationStatusUpdater? onChangeStatus;
  final JobApplicationWithdrawer? onWithdraw;

  const JobApplicationDetailsScreen({
    super.key,
    required this.application,
    required this.onChangeStatus,
    this.onWithdraw,
  });

  @override
  State<JobApplicationDetailsScreen> createState() =>
      _JobApplicationDetailsScreenState();
}

class _JobApplicationDetailsScreenState
    extends State<JobApplicationDetailsScreen> {
  late JobApplicationModel _application = widget.application;
  bool _busy = false;

  bool get _canChangeStatus =>
      widget.onChangeStatus != null && _application.canChangeStatus;

  bool get _canWithdraw =>
      widget.onWithdraw != null &&
      <String>{
        'submitted',
        'shortlisted',
        'hired',
      }.contains(_application.status) &&
      _application.offerAcceptedAt == null;

  String _statusLabel(String status) =>
      jobApplicationStatusLabel(context, status);

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
    return cleaned
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _dateTimeText(DateTime? value) {
    if (value == null) return '-';
    return '${value.toLocal()}'.split('.').first;
  }

  Future<void> _setStatus(String status) async {
    if (_busy || _application.status == status || !_canChangeStatus) return;

    String? reason;
    final needsReason = <String>{
      'shortlisted',
      'rejected',
      'hired',
      'dismissed_after_hire',
      'archived',
    }.contains(status);

    if (needsReason) {
      reason = await _askReason(status);
      if (reason == null) return;
    }

    setState(() => _busy = true);
    try {
      final updated = await widget.onChangeStatus!(
        status: status,
        reason: reason,
      );
      if (updated == null || !mounted) return;
      setState(() => _application = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.jobApplicationDetailsStatusUpdated),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(_application);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _withdrawApplication() async {
    if (_busy || !_canWithdraw) return;
    final reason = await _askReason('withdrawn');
    if (reason == null) return;

    setState(() => _busy = true);
    try {
      final updated = await widget.onWithdraw!(reason: reason);
      if (updated == null || !mounted) return;
      setState(() => _application = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.jobApplicationDetailsWithdrawn)),
      );
      if (mounted) {
        Navigator.of(context).pop(_application);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String?> _askReason(String status) async {
    final ctrl = TextEditingController();
    final statusLabel = _statusLabel(status);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          status == 'withdrawn'
              ? context.l10n.jobApplicationDetailsWithdrawReasonTitle
              : context.l10n.jobApplicationDetailsChangeStatusReasonTitle(
                  statusLabel,
                ),
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          textDirection: Directionality.of(context),
          decoration: InputDecoration(
            hintText: context.l10n.jobApplicationDetailsReasonHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final reason = ctrl.text.trim();
              if (reason.length < 2) return;
              Navigator.of(context).pop(reason);
            },
            child: Text(context.l10n.commonSave),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.jobApplicationDetailsInvalidLink)),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.commonOpenLinkFailed)),
      );
    }
  }

  Future<void> _openLinkedProfile() async {
    final applicantUserId = _application.applicantUserId;
    if (applicantUserId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.jobApplicationDetailsNoLinkedAccount),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfileScreen(
          userId: applicantUserId,
          initialName: _application.profileFullName ?? _application.fullName,
        ),
      ),
    );
  }

  String _changedByText(JobApplicationStatusHistoryModel item) {
    final actorName = (item.changedByName ?? '').trim();
    if (actorName.isNotEmpty) return actorName;
    final actorRole = (item.changedByRole ?? '').trim();
    if (actorRole.isNotEmpty) return _taxonomyLabel(actorRole);
    return context.l10n.commonSystem;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final statusColor = _statusColor(_application.status);
    final fullName =
        _application.profileFullName ??
        _application.fullName ??
        context.l10n.jobApplicationDetailsApplicantFallback;
    final hasOfferBlock =
        _application.offerSentAt != null ||
        _application.offerSalary != null ||
        (_application.offerWorkHours ?? '').trim().isNotEmpty ||
        (_application.offerWorkDays ?? '').trim().isNotEmpty ||
        (_application.offerMessage ?? '').trim().isNotEmpty ||
        (_application.offerAttachmentUrl ?? '').trim().isNotEmpty ||
        _application.offerAcceptedAt != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.jobApplicationDetailsTitle),
        actions: [
          if (_canWithdraw)
            IconButton(
              tooltip: l10n.jobApplicationDetailsWithdrawAction,
              onPressed: _busy ? null : _withdrawApplication,
              icon: const Icon(Icons.undo_rounded),
            ),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _busy
                ? null
                : () => Navigator.of(context).pop(_application),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: Directionality.of(context),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage:
                          _application.applicantImageUrl?.isNotEmpty == true
                          ? AppCachedImageProvider(
                              _application.applicantImageUrl!,
                            )
                          : null,
                      child: _application.applicantImageUrl?.isNotEmpty == true
                          ? null
                          : const Icon(Icons.person_outline, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            fullName,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${l10n.commonSubmitted}: ${_dateTimeText(_application.createdAt)}',
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${l10n.commonAccountId}: ${_application.applicantUserId > 0 ? _application.applicantUserId : '-'}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.55),
                              ),
                              color: statusColor.withValues(alpha: 0.16),
                            ),
                            child: Text(
                              _statusLabel(_application.status),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_application.applicantUserId > 0) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _openLinkedProfile,
                  icon: const Icon(Icons.person_search_rounded),
                  label: Text(l10n.jobApplicationDetailsOpenLinkedAccount),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (hasOfferBlock) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.jobApplicationDetailsOfferSection,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 8),
                      _line(
                        title: l10n.jobApplicationDetailsOfferSentAt,
                        value: _dateTimeText(_application.offerSentAt),
                      ),
                      _line(
                        title: l10n.commonSalary,
                        value: _application.offerSalary == null
                            ? '-'
                            : '${formatIqd(_application.offerSalary!, withCode: false)} IQD',
                      ),
                      _line(
                        title: l10n.commonWorkHours,
                        value:
                            (_application.offerWorkHours ?? '')
                                .trim()
                                .isNotEmpty
                            ? _application.offerWorkHours!.trim()
                            : '-',
                      ),
                      _line(
                        title: l10n.commonWorkDays,
                        value:
                            (_application.offerWorkDays ?? '').trim().isNotEmpty
                            ? _application.offerWorkDays!.trim()
                            : '-',
                      ),
                      _line(
                        title: l10n.jobApplicationDetailsOfferDetails,
                        value:
                            (_application.offerMessage ?? '').trim().isNotEmpty
                            ? _application.offerMessage!.trim()
                            : '-',
                      ),
                      _line(
                        title: l10n.jobApplicationDetailsOfferAcceptedAt,
                        value: _dateTimeText(_application.offerAcceptedAt),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_application.offerAttachmentUrl
                                  ?.trim()
                                  .isNotEmpty ==
                              true)
                            OutlinedButton.icon(
                              onPressed: () => _openExternal(
                                _application.offerAttachmentUrl!,
                              ),
                              icon: const Icon(Icons.description_outlined),
                              label: Text(
                                _application.offerAttachmentName
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? l10n.jobApplicationDetailsOfferAttachmentNamed(
                                        _application.offerAttachmentName!,
                                      )
                                    : l10n.jobApplicationDetailsOpenOfferAttachment,
                              ),
                            ),
                          if (_application.offerAcceptanceAttachmentUrl
                                  ?.trim()
                                  .isNotEmpty ==
                              true)
                            OutlinedButton.icon(
                              onPressed: () => _openExternal(
                                _application.offerAcceptanceAttachmentUrl!,
                              ),
                              icon: const Icon(Icons.verified_rounded),
                              label: Text(
                                _application.offerAcceptanceAttachmentName
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? l10n.jobApplicationDetailsAcceptanceAttachmentNamed(
                                        _application
                                            .offerAcceptanceAttachmentName!,
                                      )
                                    : l10n.jobApplicationDetailsOpenAcceptanceAttachment,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.jobApplicationDetailsJobInfo,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 8),
                    _line(
                      title: l10n.commonTitle,
                      value: _application.jobTitle ?? '-',
                    ),
                    _line(
                      title: l10n.commonCompany,
                      value: _application.jobCompanyName ?? '-',
                    ),
                    _line(
                      title: l10n.commonActivity,
                      value: _application.jobActivityType == null
                          ? '-'
                          : _taxonomyLabel(_application.jobActivityType!),
                    ),
                    _line(
                      title: l10n.commonDepartment,
                      value: _application.jobDepartment == null
                          ? '-'
                          : _taxonomyLabel(_application.jobDepartment!),
                    ),
                    _line(
                      title: l10n.commonCategory,
                      value: _application.jobCategory ?? '-',
                    ),
                    _line(
                      title: l10n.commonMerchant,
                      value: _application.jobMerchantName ?? '-',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.jobApplicationDetailsApplicantInfo,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 8),
                    _line(
                      title: l10n.jobApplicationDetailsProfileName,
                      value:
                          _application.profileFullName ??
                          _application.fullName ??
                          '-',
                    ),
                    _line(
                      title: l10n.jobApplicationDetailsProfilePhone,
                      value: _application.profilePhone ?? '-',
                    ),
                    _line(
                      title: l10n.jobApplicationDetailsSubmittedPhone,
                      value:
                          _application.submittedPhone ??
                          _application.phone ??
                          '-',
                    ),
                    _line(
                      title: l10n.commonEmail,
                      value: _application.applicantEmail ?? '-',
                    ),
                    _line(
                      title: l10n.commonAddress,
                      value:
                          '${_application.applicantBlock ?? '-'} / ${_application.applicantBuildingNumber ?? '-'} / ${_application.applicantApartment ?? '-'}',
                    ),
                    _line(
                      title: l10n.jobApplicationDetailsExpectedSalary,
                      value: _application.expectedSalary == null
                          ? '-'
                          : '${formatIqd(_application.expectedSalary!, withCode: false)} IQD',
                    ),
                    if ((_application.message ?? '').trim().isNotEmpty)
                      _line(
                        title: l10n.jobApplicationDetailsIntroductionMessage,
                        value: _application.message!.trim(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.jobApplicationDetailsResumeSection,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_application.attachmentUrl?.trim().isNotEmpty ==
                            true)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _openExternal(_application.attachmentUrl!),
                            icon: const Icon(Icons.download_rounded),
                            label: Text(
                              _application.attachmentName?.trim().isNotEmpty ==
                                      true
                                  ? l10n.jobApplicationDetailsDownloadAttachmentNamed(
                                      _application.attachmentName!,
                                    )
                                  : l10n.jobApplicationDetailsDownloadAttachment,
                            ),
                          ),
                        if (_application.resumeUrl?.trim().isNotEmpty == true)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _openExternal(_application.resumeUrl!),
                            icon: const Icon(Icons.link_rounded),
                            label: Text(
                              l10n.jobApplicationDetailsOpenResumeLink,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.jobApplicationDetailsDecisionSection,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 8),
                    _line(
                      title: l10n.jobApplicationDetailsCurrentStatus,
                      value: _statusLabel(_application.status),
                    ),
                    _line(
                      title: l10n.commonReason,
                      value: (_application.statusReason ?? '').trim().isNotEmpty
                          ? _application.statusReason!.trim()
                          : '-',
                    ),
                    _line(
                      title: l10n.jobApplicationDetailsLastStatusUpdate,
                      value: _dateTimeText(_application.statusChangedAt),
                    ),
                    const SizedBox(height: 10),
                    if (_canChangeStatus)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _statusBtn(
                            'submitted',
                            jobApplicationStatusLabel(context, 'submitted'),
                          ),
                          _statusBtn(
                            'shortlisted',
                            jobApplicationStatusLabel(context, 'shortlisted'),
                          ),
                          _statusBtn(
                            'rejected',
                            jobApplicationStatusLabel(context, 'rejected'),
                          ),
                          _statusBtn(
                            'hired',
                            jobApplicationStatusLabel(context, 'hired'),
                          ),
                          _statusBtn(
                            'dismissed_after_hire',
                            l10n.jobsStatusDismissed,
                          ),
                          _statusBtn('archived', l10n.commonArchive),
                        ],
                      )
                    else
                      Text(
                        l10n.jobApplicationDetailsStatusLocked,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.jobApplicationDetailsHistorySection,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 8),
                    if (_application.statusHistory.isEmpty)
                      Text(
                        l10n.jobApplicationDetailsHistoryEmpty,
                        textAlign: TextAlign.right,
                      )
                    else
                      ..._application.statusHistory.map(
                        (item) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white.withValues(alpha: 0.05),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${_statusLabel(item.previousStatus ?? 'submitted')} → ${_statusLabel(item.nextStatus)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${l10n.commonBy}: ${_changedByText(item)}',
                                textAlign: TextAlign.right,
                              ),
                              Text(
                                '${l10n.commonTime}: ${_dateTimeText(item.changedAt)}',
                                textAlign: TextAlign.right,
                              ),
                              if ((item.reason ?? '').trim().isNotEmpty)
                                Text(
                                  '${l10n.commonReason}: ${item.reason!.trim()}',
                                  textAlign: TextAlign.right,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _statusBtn(String value, String label) {
    return OutlinedButton(
      onPressed: _busy || _application.status == value
          ? null
          : () => _setStatus(value),
      child: _busy && _application.status != value
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }

  Widget _line({required String title, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        textAlign: TextAlign.right,
        text: TextSpan(
          style: const TextStyle(color: Colors.white, height: 1.4),
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
}
