import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/parsers.dart';
import '../../../core/utils/currency.dart';
import '../../auth/state/auth_controller.dart';
import '../../taxi/data/taxi_api.dart';

TaxiApi _taxiApi(WidgetRef ref) => TaxiApi(ref.read(dioClientProvider).dio);

class AdminTaxiCaptainDetailsScreen extends ConsumerStatefulWidget {
  final int captainUserId;

  const AdminTaxiCaptainDetailsScreen({super.key, required this.captainUserId});

  @override
  ConsumerState<AdminTaxiCaptainDetailsScreen> createState() =>
      _AdminTaxiCaptainDetailsScreenState();
}

class _AdminTaxiCaptainDetailsScreenState
    extends ConsumerState<AdminTaxiCaptainDetailsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _details = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry<String, dynamic>(key.toString(), val),
      );
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => _asMap(item))
        .toList(growable: false);
  }

  int _asInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return tryParseLocalizedInt(value) ?? fallback;
  }

  double _asDouble(dynamic value, [double fallback = 0]) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return tryParseLocalizedDouble(value) ?? fallback;
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = !silent;
      _error = null;
    });
    try {
      final details = await _taxiApi(ref).adminTaxiCaptainDetails(
        widget.captainUserId,
      );
      if (!mounted) return;
      setState(() {
        _details = details;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (l10n) => l10n.adminTaxiCaptainDetailsLoadFailed,
        );
      });
    }
  }

  String _governanceStatusLabel(String value) {
    final l10n = context.l10n;
    switch (value.trim().toLowerCase()) {
      case 'active':
        return l10n.adminTaxiCaptainStatusActive;
      case 'warned':
        return l10n.adminTaxiCaptainStatusWarned;
      case 'temporarily_suspended':
        return l10n.adminTaxiCaptainStatusTemporarilySuspended;
      case 'under_review':
        return l10n.adminTaxiCaptainStatusUnderReview;
      case 'banned':
        return l10n.adminTaxiCaptainStatusBanned;
      default:
        return value;
    }
  }

  String _rewardTypeLabel(String value) {
    final l10n = context.l10n;
    switch (value.trim().toLowerCase()) {
      case 'credit':
        return l10n.adminTaxiCaptainRewardTypeCredit;
      case 'cash_equivalent':
        return l10n.adminTaxiCaptainRewardTypeCashEquivalent;
      case 'subscription_discount':
        return l10n.adminTaxiCaptainRewardTypeSubscriptionDiscount;
      case 'gift':
        return l10n.adminTaxiCaptainRewardTypeGift;
      default:
        return value;
    }
  }

  String _warningSeverityLabel(String value) {
    final l10n = context.l10n;
    switch (value.trim().toLowerCase()) {
      case 'low':
        return l10n.adminTaxiCaptainWarningSeverityLow;
      case 'medium':
        return l10n.adminTaxiCaptainWarningSeverityMedium;
      case 'high':
        return l10n.adminTaxiCaptainWarningSeverityHigh;
      case 'critical':
        return l10n.adminTaxiCaptainWarningSeverityCritical;
      default:
        return value;
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  Future<void> _openGiftDialog() async {
    final l10n = context.l10n;
    final rewardValueCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final fieldErrors = <String, String?>{};
    String? formError;
    var submitting = false;
    var rewardType = 'credit';

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              String? fieldError(String field, String label) {
                final code = fieldErrors[field];
                if (code == null) return null;
                return resolveFormFieldError(
                  l10n: l10n,
                  field: field,
                  code: code,
                  fieldLabel: label,
                );
              }

              void clearFieldError(String field) {
                if (!fieldErrors.containsKey(field)) return;
                setSheetState(() => fieldErrors.remove(field));
              }

              Future<void> submit() async {
                final rewardValue = tryParseLocalizedDouble(
                  rewardValueCtrl.text.trim(),
                );
                final validationErrors = <String, String?>{};
                if (rewardValue == null || rewardValue <= 0) {
                  validationErrors['rewardValue'] = 'INVALID_NUMBER';
                }
                if (validationErrors.isNotEmpty) {
                  setSheetState(() {
                    fieldErrors
                      ..clear()
                      ..addAll(validationErrors);
                    formError = l10n.validationReviewRequiredFields;
                  });
                  return;
                }

                setSheetState(() {
                  submitting = true;
                  formError = null;
                  fieldErrors.clear();
                });

                try {
                  await _taxiApi(ref).adminIssueCaptainGift(
                    captainUserId: widget.captainUserId,
                    payload: {
                      'rewardValue': rewardValue,
                      'rewardType': rewardType,
                      if (reasonCtrl.text.trim().isNotEmpty)
                        'reason': reasonCtrl.text.trim(),
                      if (noteCtrl.text.trim().isNotEmpty)
                        'adminNote': noteCtrl.text.trim(),
                    },
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop(true);
                } catch (error) {
                  final parsed = parseBackendFieldErrors(error);
                  setSheetState(() {
                    submitting = false;
                    fieldErrors
                      ..clear()
                      ..addAll(parsed.fieldCodes);
                    formError = resolveFormLevelError(
                      l10n,
                      code: parsed.formCode ?? parsed.messageCode,
                      fallback: mapAnyErrorL10n(
                        error,
                        fallbackBuilder: (l10n) => l10n.errorsUnknown,
                      ),
                    );
                  });
                }
              }

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.adminTaxiCaptainDetailsIssueGift,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormErrorBanner(message: formError),
                    TextField(
                      controller: rewardValueCtrl,
                      textInputAction: TextInputAction.next,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (_) => clearFieldError('rewardValue'),
                      decoration: InputDecoration(
                        labelText: l10n.commonAmount,
                        errorText: fieldError('rewardValue', l10n.commonAmount),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: rewardType,
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCaptainDetailsRewardType,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'credit',
                          child: Text(
                            l10n.adminTaxiCaptainRewardTypeCredit,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'cash_equivalent',
                          child: Text(
                            l10n.adminTaxiCaptainRewardTypeCashEquivalent,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'subscription_discount',
                          child: Text(
                            l10n.adminTaxiCaptainRewardTypeSubscriptionDiscount,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'gift',
                          child: Text(l10n.adminTaxiCaptainRewardTypeGift),
                        ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) => setSheetState(
                              () => rewardType = value ?? 'credit',
                            ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reasonCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.commonReason,
                        errorText: fieldError('reason', l10n.commonReason),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCaptainDetailsAdminNote,
                        errorText: fieldError(
                          'adminNote',
                          l10n.adminTaxiCaptainDetailsAdminNote,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(sheetContext).pop(false),
                            child: Text(l10n.commonCancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: submitting ? null : submit,
                            child: Text(l10n.commonSave),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    rewardValueCtrl.dispose();
    reasonCtrl.dispose();
    noteCtrl.dispose();

    if (submitted == true) {
      await _load(silent: true);
      _showSnack(l10n.commonDone);
    }
  }

  Future<void> _openWarningDialog() async {
    final l10n = context.l10n;
    final reasonCodeCtrl = TextEditingController();
    final reasonTextCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final fieldErrors = <String, String?>{};
    String? formError;
    var submitting = false;
    var severity = 'medium';
    var affectsStatus = true;
    String? statusEffect;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              String? fieldError(String field, String label) {
                final code = fieldErrors[field];
                if (code == null) return null;
                return resolveFormFieldError(
                  l10n: l10n,
                  field: field,
                  code: code,
                  fieldLabel: label,
                );
              }

              void clearFieldError(String field) {
                if (!fieldErrors.containsKey(field)) return;
                setSheetState(() => fieldErrors.remove(field));
              }

              Future<void> submit() async {
                setSheetState(() {
                  submitting = true;
                  formError = null;
                  fieldErrors.clear();
                });

                try {
                  await _taxiApi(ref).adminIssueCaptainWarning(
                    captainUserId: widget.captainUserId,
                    payload: {
                      'severity': severity,
                      'affectsStatus': affectsStatus,
                      if (statusEffect != null && statusEffect!.isNotEmpty)
                        'statusEffect': statusEffect,
                      if (reasonCodeCtrl.text.trim().isNotEmpty)
                        'reasonCode': reasonCodeCtrl.text.trim(),
                      if (reasonTextCtrl.text.trim().isNotEmpty)
                        'reasonText': reasonTextCtrl.text.trim(),
                      if (noteCtrl.text.trim().isNotEmpty)
                        'adminNote': noteCtrl.text.trim(),
                    },
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop(true);
                } catch (error) {
                  final parsed = parseBackendFieldErrors(error);
                  setSheetState(() {
                    submitting = false;
                    fieldErrors
                      ..clear()
                      ..addAll(parsed.fieldCodes);
                    formError = resolveFormLevelError(
                      l10n,
                      code: parsed.formCode ?? parsed.messageCode,
                      fallback: mapAnyErrorL10n(
                        error,
                        fallbackBuilder: (l10n) => l10n.errorsUnknown,
                      ),
                    );
                  });
                }
              }

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.adminTaxiCaptainDetailsIssueWarning,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormErrorBanner(message: formError),
                    DropdownButtonFormField<String>(
                      initialValue: severity,
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCaptainDetailsSeverity,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'low',
                          child: Text(
                            l10n.adminTaxiCaptainWarningSeverityLow,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text(
                            l10n.adminTaxiCaptainWarningSeverityMedium,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'high',
                          child: Text(
                            l10n.adminTaxiCaptainWarningSeverityHigh,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'critical',
                          child: Text(
                            l10n.adminTaxiCaptainWarningSeverityCritical,
                          ),
                        ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) => setSheetState(
                              () => severity = value ?? 'medium',
                            ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.adminTaxiCaptainDetailsStatusEffect),
                      value: affectsStatus,
                      onChanged: submitting
                          ? null
                          : (value) => setSheetState(() {
                              affectsStatus = value;
                              if (!value) statusEffect = null;
                            }),
                    ),
                    DropdownButtonFormField<String?>(
                      initialValue: statusEffect,
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCaptainDetailsStatusEffect,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l10n.adminTaxiCaptainDetailsNoStatusEffect),
                        ),
                        DropdownMenuItem(
                          value: 'warned',
                          child: Text(l10n.adminTaxiCaptainStatusWarned),
                        ),
                        DropdownMenuItem(
                          value: 'temporarily_suspended',
                          child: Text(
                            l10n.adminTaxiCaptainStatusTemporarilySuspended,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'under_review',
                          child: Text(l10n.adminTaxiCaptainStatusUnderReview),
                        ),
                        DropdownMenuItem(
                          value: 'banned',
                          child: Text(l10n.adminTaxiCaptainStatusBanned),
                        ),
                      ],
                      onChanged: (!affectsStatus || submitting)
                          ? null
                          : (value) => setSheetState(() => statusEffect = value),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reasonCodeCtrl,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => clearFieldError('reasonCode'),
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCaptainDetailsReasonCode,
                        errorText: fieldError(
                          'reasonCode',
                          l10n.adminTaxiCaptainDetailsReasonCode,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reasonTextCtrl,
                      minLines: 2,
                      maxLines: 3,
                      onChanged: (_) => clearFieldError('reasonText'),
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCaptainDetailsReasonText,
                        errorText: fieldError(
                          'reasonText',
                          l10n.adminTaxiCaptainDetailsReasonText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (_) => clearFieldError('adminNote'),
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCaptainDetailsAdminNote,
                        errorText: fieldError(
                          'adminNote',
                          l10n.adminTaxiCaptainDetailsAdminNote,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(sheetContext).pop(false),
                            child: Text(l10n.commonCancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: submitting ? null : submit,
                            child: Text(l10n.commonSave),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    reasonCodeCtrl.dispose();
    reasonTextCtrl.dispose();
    noteCtrl.dispose();

    if (submitted == true) {
      await _load(silent: true);
      _showSnack(l10n.commonDone);
    }
  }

  Future<void> _openStatusDialog() async {
    final l10n = context.l10n;
    final reasonCodeCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final fieldErrors = <String, String?>{};
    String? formError;
    var submitting = false;
    var newStatus = 'active';
    DateTime? suspendedUntil;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              String? fieldError(String field, String label) {
                final code = fieldErrors[field];
                if (code == null) return null;
                return resolveFormFieldError(
                  l10n: l10n,
                  field: field,
                  code: code,
                  fieldLabel: label,
                );
              }

              void clearFieldError(String field) {
                if (!fieldErrors.containsKey(field)) return;
                setSheetState(() => fieldErrors.remove(field));
              }

              Future<void> pickSuspendedUntil() async {
                final initial = suspendedUntil ?? DateTime.now();
                final date = await showDatePicker(
                  context: sheetContext,
                  initialDate: initial,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (date == null || !sheetContext.mounted) return;
                final time = await showTimePicker(
                  context: sheetContext,
                  initialTime: TimeOfDay.fromDateTime(initial),
                );
                if (time == null) return;
                setSheetState(() {
                  suspendedUntil = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  );
                });
              }

              Future<void> submit() async {
                setSheetState(() {
                  submitting = true;
                  formError = null;
                  fieldErrors.clear();
                });

                try {
                  await _taxiApi(ref).adminSetCaptainStatus(
                    captainUserId: widget.captainUserId,
                    payload: {
                      'newStatus': newStatus,
                      if (reasonCodeCtrl.text.trim().isNotEmpty)
                        'reasonCode': reasonCodeCtrl.text.trim(),
                      if (noteCtrl.text.trim().isNotEmpty)
                        'note': noteCtrl.text.trim(),
                      if (suspendedUntil != null)
                        'suspendedUntil': suspendedUntil!
                            .toUtc()
                            .toIso8601String(),
                    },
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop(true);
                } catch (error) {
                  final parsed = parseBackendFieldErrors(error);
                  setSheetState(() {
                    submitting = false;
                    fieldErrors
                      ..clear()
                      ..addAll(parsed.fieldCodes);
                    formError = resolveFormLevelError(
                      l10n,
                      code: parsed.formCode ?? parsed.messageCode,
                      fallback: mapAnyErrorL10n(
                        error,
                        fallbackBuilder: (l10n) => l10n.errorsUnknown,
                      ),
                    );
                  });
                }
              }

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.adminTaxiCaptainDetailsUpdateStatus,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormErrorBanner(message: formError),
                    DropdownButtonFormField<String>(
                      initialValue: newStatus,
                      decoration: InputDecoration(labelText: l10n.commonStatus),
                      items: [
                        DropdownMenuItem(
                          value: 'active',
                          child: Text(l10n.adminTaxiCaptainStatusActive),
                        ),
                        DropdownMenuItem(
                          value: 'warned',
                          child: Text(l10n.adminTaxiCaptainStatusWarned),
                        ),
                        DropdownMenuItem(
                          value: 'temporarily_suspended',
                          child: Text(
                            l10n.adminTaxiCaptainStatusTemporarilySuspended,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'under_review',
                          child: Text(l10n.adminTaxiCaptainStatusUnderReview),
                        ),
                        DropdownMenuItem(
                          value: 'banned',
                          child: Text(l10n.adminTaxiCaptainStatusBanned),
                        ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) => setSheetState(
                              () => newStatus = value ?? 'active',
                            ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reasonCodeCtrl,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => clearFieldError('reasonCode'),
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCaptainDetailsReasonCode,
                        errorText: fieldError(
                          'reasonCode',
                          l10n.adminTaxiCaptainDetailsReasonCode,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (_) => clearFieldError('note'),
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCaptainDetailsAdminNote,
                        errorText: fieldError(
                          'note',
                          l10n.adminTaxiCaptainDetailsAdminNote,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (newStatus == 'temporarily_suspended')
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.adminTaxiCaptainDetailsSuspendedUntil),
                        subtitle: Text(
                          suspendedUntil == null
                              ? l10n.adminTaxiCaptainDetailsNoExpiry
                              : suspendedUntil!.toLocal().toString(),
                        ),
                        trailing: TextButton(
                          onPressed: submitting ? null : pickSuspendedUntil,
                          child: Text(
                            l10n.adminTaxiCaptainDetailsPickDateTime,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(sheetContext).pop(false),
                            child: Text(l10n.commonCancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: submitting ? null : submit,
                            child: Text(l10n.commonSave),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    reasonCodeCtrl.dispose();
    noteCtrl.dispose();

    if (submitted == true) {
      await _load(silent: true);
      _showSnack(l10n.commonDone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.adminTaxiCaptainDetailsTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.commonRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final profile = _asMap(_details['profile']);
    final subscription = _asMap(_details['subscription']);
    final governance = _asMap(_details['governance']);
    final ledger = _asMapList(_details['ledger']);
    final complaints = _asMapList(_details['complaints']);
    final warnings = _asMapList(_details['warnings']);
    final statusHistory = _asMapList(_details['statusHistory']);
    final rides = _asMapList(_details['rides']);
    final rewards = _asMapList(_details['rewards']);
    final contests = _asMapList(_details['contests']);

    final name = '${profile['full_name'] ?? profile['fullName'] ?? '-'}';
    final phone = '${profile['phone'] ?? '-'}';
    final statusRaw =
        '${governance['governanceStatus'] ?? profile['governance_status'] ?? 'active'}';
    final rating = _asDouble(profile['rating_avg'] ?? profile['ratingAvg']);
    final ridesCount = _asInt(profile['rides_count'] ?? profile['ridesCount']);
    final warningCount = _asInt(
      governance['warningCount'] ??
          profile['warning_count'] ??
          warnings.length,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminTaxiCaptainDetailsTitle),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.tertiaryContainer,
                  ],
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        child: Icon(Icons.local_taxi_rounded),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              phone,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        label: l10n.commonStatus,
                        value: _governanceStatusLabel(statusRaw),
                      ),
                      _InfoChip(
                        label: l10n.commonRating,
                        value: rating.toStringAsFixed(2),
                      ),
                      _InfoChip(
                        label: l10n.adminTaxiKpiTotalRides,
                        value: ridesCount.toString(),
                      ),
                      _InfoChip(
                        label: l10n.taxiCaptainWarningsCount,
                        value: warningCount.toString(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.adminTaxiCaptainDetailsActionsSection,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _openGiftDialog,
                    icon: const Icon(Icons.card_giftcard_rounded),
                    label: Text(l10n.adminTaxiCaptainDetailsIssueGift),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _openWarningDialog,
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: Text(l10n.adminTaxiCaptainDetailsIssueWarning),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _openStatusDialog,
                    icon: const Icon(Icons.shield_rounded),
                    label: Text(l10n.adminTaxiCaptainDetailsUpdateStatus),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.adminTaxiCaptainDetailsSubscriptionSection,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    label: l10n.taxiCaptainMonthlySubscription,
                    value: formatIqd(
                      _asInt(subscription['monthlySubscriptionAmountIqd']),
                    ),
                  ),
                  _InfoChip(
                    label: l10n.taxiCaptainApprovedCredits,
                    value: formatIqd(_asInt(subscription['approvedCreditsIqd'])),
                  ),
                  _InfoChip(
                    label: l10n.adminTaxiCashPaymentsDiscount,
                    value: formatIqd(
                      _asInt(subscription['approvedDiscountsIqd']),
                    ),
                  ),
                  _InfoChip(
                    label: l10n.taxiCaptainPayableAmount,
                    value: formatIqd(_asInt(subscription['payableAmountIqd'])),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.adminTaxiCaptainDetailsLedgerSection,
              child: ledger.isEmpty
                  ? Text(l10n.commonNoData)
                  : Column(
                      children: ledger.take(12).map((item) {
                        final amount = _asInt(item['amountIqd']);
                        final status = '${item['status'] ?? '-'}';
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${item['entryType'] ?? '-'}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text('${item['createdAt'] ?? '-'}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(formatIqd(amount)),
                              Text(
                                status,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        );
                      }).toList(growable: false),
                    ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.taxiCaptainContestsTitle,
              child: contests.isEmpty
                  ? Text(l10n.commonNoData)
                  : Column(
                      children: contests.take(8).map((item) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${item['title'] ?? '-'}'),
                          subtitle: Text(
                            '${item['progressValue'] ?? 0} / ${item['targetValue'] ?? 0}',
                          ),
                        );
                      }).toList(growable: false),
                    ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.taxiCaptainRewardsTitle,
              child: rewards.isEmpty
                  ? Text(l10n.commonNoData)
                  : Column(
                      children: rewards.take(8).map((item) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _rewardTypeLabel('${item['rewardType'] ?? '-'}'),
                          ),
                          subtitle: Text('${item['createdAt'] ?? '-'}'),
                          trailing: Text(
                            formatIqd(_asInt(item['rewardValue'])),
                          ),
                        );
                      }).toList(growable: false),
                    ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.adminTaxiCaptainDetailsWarningsSection,
              child: warnings.isEmpty
                  ? Text(l10n.commonNoData)
                  : Column(
                      children: warnings.take(8).map((item) {
                        final severity = _warningSeverityLabel(
                          '${item['severity'] ?? ''}',
                        );
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            severity,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${item['reason_text'] ?? item['reasonText'] ?? item['reason_code'] ?? '-'}\n${item['created_at'] ?? item['createdAt'] ?? '-'}',
                          ),
                          isThreeLine: true,
                        );
                      }).toList(growable: false),
                    ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.adminTaxiCaptainDetailsComplaintsSection,
              child: complaints.isEmpty
                  ? Text(l10n.commonNoData)
                  : Column(
                      children: complaints.take(8).map((item) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${item['category'] ?? '-'}'),
                          subtitle: Text(
                            '${item['reason'] ?? '-'}\n${item['status'] ?? '-'}',
                          ),
                          isThreeLine: true,
                        );
                      }).toList(growable: false),
                    ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.adminTaxiCaptainDetailsStatusHistorySection,
              child: statusHistory.isEmpty
                  ? Text(l10n.commonNoData)
                  : Column(
                      children: statusHistory.take(8).map((item) {
                        final oldStatus = _governanceStatusLabel(
                          '${item['oldStatus'] ?? item['old_status'] ?? '-'}',
                        );
                        final newStatus = _governanceStatusLabel(
                          '${item['newStatus'] ?? item['new_status'] ?? '-'}',
                        );
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('$oldStatus -> $newStatus'),
                          subtitle: Text(
                            '${item['createdAt'] ?? item['created_at'] ?? '-'}',
                          ),
                        );
                      }).toList(growable: false),
                    ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: l10n.adminTaxiCaptainDetailsRidesSection,
              child: rides.isEmpty
                  ? Text(l10n.commonNoData)
                  : Column(
                      children: rides.take(10).map((item) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '#${item['id'] ?? '-'} - ${item['status'] ?? '-'}',
                          ),
                          subtitle: Text('${item['created_at'] ?? '-'}'),
                          trailing: Text(
                            formatIqd(
                              _asInt(
                                item['agreed_fare_iqd'] ??
                                    item['proposed_fare_iqd'],
                              ),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
      ),
      child: Text('$label: $value'),
    );
  }
}
