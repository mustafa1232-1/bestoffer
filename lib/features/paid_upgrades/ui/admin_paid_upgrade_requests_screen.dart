import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/backend_field_error_parser.dart';
import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart'
    hide parseBackendFieldErrors;
import '../../../core/utils/currency.dart';
import '../data/paid_upgrades_api.dart';
import '../models/paid_upgrade_models.dart';

class AdminPaidUpgradeRequestsScreen extends ConsumerStatefulWidget {
  const AdminPaidUpgradeRequestsScreen({super.key});

  @override
  ConsumerState<AdminPaidUpgradeRequestsScreen> createState() =>
      _AdminPaidUpgradeRequestsScreenState();
}

class _AdminPaidUpgradeRequestsScreenState
    extends ConsumerState<AdminPaidUpgradeRequestsScreen> {
  bool _loading = true;
  bool _busy = false;
  String _status = 'pending_admin_review';
  String? _error;
  List<PaidUpgradeRequestModel> _items = const [];

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
      final raw = await ref
          .read(paidUpgradesApiProvider)
          .listAdminRequests(status: _status, limit: 120);
      if (!mounted) return;
      setState(() {
        _items = raw
            .map(PaidUpgradeRequestModel.fromJson)
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.adminPaidUpgradeRequestsLoadFailed,
        );
      });
    }
  }

  Future<bool> _runReviewAction({
    required int requestId,
    required String title,
    required String failureFallback,
    required Future<void> Function(String? reviewNote) submit,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ReviewNoteDialog(
        title: title,
        confirmLabel: context.l10n.commonConfirm,
        fieldLabel: context.l10n.adminPaidUpgradeRequestsOptionalNote,
        failureFallback: failureFallback,
        onSubmit: submit,
      ),
    );
    return ok == true;
  }

  Future<void> _approve(int requestId) async {
    if (_busy) return;
    final ok = await _runReviewAction(
      requestId: requestId,
      title: context.l10n.adminPaidUpgradeRequestsApproveTitle,
      failureFallback: context.l10n.adminPaidUpgradeRequestsApproveFailed,
      submit: (note) => ref
          .read(paidUpgradesApiProvider)
          .approveRequest(requestId, reviewNote: note),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(int requestId) async {
    if (_busy) return;
    final ok = await _runReviewAction(
      requestId: requestId,
      title: context.l10n.adminPaidUpgradeRequestsRejectTitle,
      failureFallback: context.l10n.adminPaidUpgradeRequestsRejectFailed,
      submit: (note) => ref
          .read(paidUpgradesApiProvider)
          .rejectRequest(requestId, reviewNote: note),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate(int requestId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(paidUpgradesApiProvider).activateRequest(requestId);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.adminPaidUpgradeRequestsActivateFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'activated':
        return const Color(0xFF16A34A);
      case 'approved':
        return const Color(0xFF2563EB);
      case 'rejected':
        return const Color(0xFFDC2626);
      case 'cancelled':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String _statusLabel(String status) {
    final l10n = context.l10n;
    switch (status) {
      case 'approved':
        return l10n.adminPaidUpgradeRequestsStatusApproved;
      case 'activated':
        return l10n.adminPaidUpgradeRequestsStatusActivated;
      case 'rejected':
        return l10n.adminPaidUpgradeRequestsStatusRejected;
      case 'cancelled':
        return l10n.adminPaidUpgradeRequestsStatusCancelled;
      default:
        return l10n.adminPaidUpgradeRequestsStatusPendingReview;
    }
  }

  String _filterLabel(String status) {
    final l10n = context.l10n;
    switch (status) {
      case 'pending_admin_review':
        return l10n.adminPaidUpgradeRequestsFilterPending;
      case 'approved':
        return l10n.adminPaidUpgradeRequestsFilterApproved;
      case 'activated':
        return l10n.adminPaidUpgradeRequestsFilterActivated;
      case 'rejected':
        return l10n.adminPaidUpgradeRequestsFilterRejected;
      case 'cancelled':
        return l10n.adminPaidUpgradeRequestsFilterCancelled;
      default:
        return l10n.commonAll;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminPaidUpgradeRequestsTitle)),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                for (final status in const [
                  'pending_admin_review',
                  'approved',
                  'activated',
                  'rejected',
                  'cancelled',
                  'all',
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(_filterLabel(status)),
                      selected: _status == status,
                      onSelected: (_) async {
                        setState(() => _status = status);
                        await _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ListView(
                      children: [
                        const SizedBox(height: 140),
                        Center(
                          child: Text(
                            _error!,
                            textDirection: context.appTextDirection,
                          ),
                        ),
                      ],
                    )
                  : _items.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 140),
                        Center(
                          child: Text(
                            l10n.adminPaidUpgradeRequestsEmpty,
                            textDirection: context.appTextDirection,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    textDirection: context.appTextDirection,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.planTitle ??
                                              item.planCode ??
                                              '-',
                                          textDirection:
                                              context.appTextDirection,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _statusLabel(item.status),
                                        style: TextStyle(
                                          color: _statusColor(item.status),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n.adminPaidUpgradeRequestsUserLine(
                                      item.userFullName ?? '-',
                                      item.userId,
                                    ),
                                    textDirection: context.appTextDirection,
                                  ),
                                  if ((item.userPhone ?? '').trim().isNotEmpty)
                                    Text(
                                      l10n.adminPaidUpgradeRequestsPhoneLine(
                                        item.userPhone!,
                                      ),
                                      textDirection: context.appTextDirection,
                                    ),
                                  if ((item.activityName ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      l10n.adminPaidUpgradeRequestsActivityLine(
                                        item.activityName!,
                                      ),
                                      textDirection: context.appTextDirection,
                                    ),
                                  if ((item.activityDescription ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      l10n.adminPaidUpgradeRequestsDescriptionLine(
                                        item.activityDescription!,
                                      ),
                                      textDirection: context.appTextDirection,
                                    ),
                                  Text(
                                    l10n.adminPaidUpgradeRequestsFeeLine(
                                      formatIqd(item.monthlyFeeIqd),
                                    ),
                                    textDirection: context.appTextDirection,
                                  ),
                                  if ((item.notes ?? '').trim().isNotEmpty)
                                    Text(
                                      l10n.adminPaidUpgradeRequestsNotesLine(
                                        item.notes!,
                                      ),
                                      textDirection: context.appTextDirection,
                                    ),
                                  if ((item.reviewNote ?? '').trim().isNotEmpty)
                                    Text(
                                      l10n.adminPaidUpgradeRequestsReviewNoteLine(
                                        item.reviewNote!,
                                      ),
                                      textDirection: context.appTextDirection,
                                    ),
                                  if (item.status == 'pending_admin_review')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Wrap(
                                        alignment: WrapAlignment.end,
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : () => _reject(item.id),
                                            icon: const Icon(
                                              Icons.close_rounded,
                                            ),
                                            label: Text(
                                              l10n.adminPaidUpgradeRequestsRejectAction,
                                            ),
                                          ),
                                          FilledButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : () => _approve(item.id),
                                            icon: const Icon(
                                              Icons.check_rounded,
                                            ),
                                            label: Text(
                                              l10n.adminPaidUpgradeRequestsApproveAction,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (item.status == 'approved')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _activate(item.id),
                                          icon: const Icon(Icons.bolt_rounded),
                                          label: Text(
                                            l10n.adminPaidUpgradeRequestsActivateThirtyDays,
                                          ),
                                        ),
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
          ),
        ],
      ),
    );
  }
}

class _ReviewNoteDialog extends StatefulWidget {
  const _ReviewNoteDialog({
    required this.title,
    required this.confirmLabel,
    required this.fieldLabel,
    required this.failureFallback,
    required this.onSubmit,
  });

  final String title;
  final String confirmLabel;
  final String fieldLabel;
  final String failureFallback;
  final Future<void> Function(String? reviewNote) onSubmit;

  @override
  State<_ReviewNoteDialog> createState() => _ReviewNoteDialogState();
}

class _ReviewNoteDialogState extends State<_ReviewNoteDialog> {
  final TextEditingController _controller = TextEditingController();
  final FormScrollCoordinator _scrollCoordinator = FormScrollCoordinator();
  final Map<String, String> _fieldErrors = <String, String>{};

  bool _submitting = false;
  String? _formError;

  @override
  void dispose() {
    _controller.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field) && _formError == null) return;
    setState(() {
      _fieldErrors.remove(field);
      if (_fieldErrors.isEmpty) {
        _formError = null;
      }
    });
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final note = _controller.text.trim();
    final nextErrors = <String, String>{};
    if (note.length > 2000) {
      nextErrors['reviewNote'] = resolveFormFieldError(
        l10n: l10n,
        field: 'reviewNote',
        code: 'TOO_LONG',
        fieldLabel: widget.fieldLabel,
      );
    }
    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(nextErrors);
        _formError = l10n.validationReviewRequiredFields;
      });
      await _scrollCoordinator.focusFirstError(const ['reviewNote']);
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
      _fieldErrors.clear();
    });

    try {
      await widget.onSubmit(note.isEmpty ? null : note);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final parsed = parseBackendFieldErrors(error);
      final backendErrors = <String, String>{};
      for (final entry in parsed.fieldCodes.entries) {
        if (entry.key == '_form') continue;
        backendErrors[entry.key] = resolveFormFieldError(
          l10n: l10n,
          field: entry.key,
          code: entry.value,
          fieldLabel: widget.fieldLabel,
        );
      }
      setState(() {
        _submitting = false;
        _fieldErrors
          ..clear()
          ..addAll(backendErrors);
        _formError = resolveFormLevelError(
          l10n,
          code: parsed.formCode,
          fallback: mapAnyError(error, fallback: widget.failureFallback),
        );
      });
      if (backendErrors.isNotEmpty) {
        await _scrollCoordinator.focusFirstError(backendErrors.keys);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, textDirection: context.appTextDirection),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormErrorBanner(message: _formError),
            TextField(
              controller: _controller,
              focusNode: _scrollCoordinator.focusNodeFor('reviewNote'),
              minLines: 2,
              maxLines: 4,
              maxLength: 2000,
              onChanged: (_) => _clearFieldError('reviewNote'),
              textDirection: context.appTextDirection,
              decoration: InputDecoration(
                labelText: widget.fieldLabel,
                hintText: context.l10n.adminPaidUpgradeRequestsOptionalNote,
                errorText: _fieldErrors['reviewNote'],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
