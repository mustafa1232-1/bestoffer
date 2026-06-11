import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/backend_field_error_parser.dart';
import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/forms/inline_field_error_text.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart'
    hide parseBackendFieldErrors;
import '../../../core/utils/currency.dart';
import '../data/paid_upgrades_api.dart';
import '../models/paid_upgrade_models.dart';

class PaidUpgradesHomeScreen extends ConsumerStatefulWidget {
  const PaidUpgradesHomeScreen({super.key});

  @override
  ConsumerState<PaidUpgradesHomeScreen> createState() =>
      _PaidUpgradesHomeScreenState();
}

class _PaidUpgradeRequestSheet extends ConsumerStatefulWidget {
  final List<PaidUpgradePlanModel> plans;

  const _PaidUpgradeRequestSheet({required this.plans});

  @override
  ConsumerState<_PaidUpgradeRequestSheet> createState() =>
      _PaidUpgradeRequestSheetState();
}

class _PaidUpgradeRequestSheetState
    extends ConsumerState<_PaidUpgradeRequestSheet> {
  final _activityNameCtrl = TextEditingController();
  final _activityDescriptionCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final Set<String> _selectedCodes = <String>{};
  final FormScrollCoordinator _scrollCoordinator = FormScrollCoordinator();
  final Map<String, String> _fieldErrors = <String, String>{};

  bool _saving = false;
  String? _formError;

  @override
  void dispose() {
    _activityNameCtrl.dispose();
    _activityDescriptionCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  String? _fieldLabel(String field) {
    final l10n = context.l10n;
    switch (field) {
      case 'planCodes':
        return l10n.paidUpgradesPlansLabel;
      case 'activityName':
        return l10n.paidUpgradesActivityName;
      case 'contactPhone':
        return l10n.paidUpgradesContactPhone;
      default:
        return null;
    }
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

  String _planDescription(PaidUpgradePlanModel plan) {
    final l10n = context.l10n;
    switch (plan.code) {
      case 'car_seller_monthly':
        return l10n.paidUpgradesPlanCarsDescription;
      case 'property_seller_monthly':
        return l10n.paidUpgradesPlanPropertyDescription;
      case 'premium_monthly':
        return l10n.paidUpgradesPlanPremiumDescription;
      default:
        return plan.description?.trim() ?? '';
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    final l10n = context.l10n;
    final nextErrors = <String, String>{};

    if (_selectedCodes.isEmpty) {
      nextErrors['planCodes'] = resolveFormFieldError(
        l10n: l10n,
        field: 'planCodes',
        code: 'SELECT_OPTION',
        fieldLabel: _fieldLabel('planCodes'),
      );
    }
    if (_activityNameCtrl.text.trim().isEmpty) {
      nextErrors['activityName'] = resolveFormFieldError(
        l10n: l10n,
        field: 'activityName',
        fieldLabel: _fieldLabel('activityName'),
      );
    }

    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(nextErrors);
        _formError = l10n.validationReviewRequiredFields;
      });
      await _scrollCoordinator.focusFirstError(
        const [
          'planCodes',
          'activityName',
          'contactPhone',
        ].where(nextErrors.containsKey),
      );
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _fieldErrors.clear();
    });

    try {
      await ref.read(paidUpgradesApiProvider).createRequests({
        'planCodes': _selectedCodes.toList(growable: false),
        'activityName': _activityNameCtrl.text.trim(),
        'activityDescription': _activityDescriptionCtrl.text.trim(),
        'contactPhone': _contactPhoneCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final parsed = parseBackendFieldErrors(e);
      final backendErrors = <String, String>{};
      if (parsed.hasAnyErrors) {
        for (final entry in parsed.fieldCodes.entries) {
          backendErrors[entry.key] = resolveFormFieldError(
            l10n: l10n,
            field: entry.key,
            code: entry.value,
            fieldLabel: _fieldLabel(entry.key),
          );
        }
      }

      setState(() {
        _saving = false;
        if (backendErrors.isNotEmpty) {
          _fieldErrors
            ..clear()
            ..addAll(backendErrors);
          _formError = resolveFormLevelError(
            l10n,
            code: parsed.formCode,
            fallback: l10n.validationReviewRequiredFields,
          );
        } else {
          _formError = mapAnyError(
            e,
            fallback: l10n.paidUpgradesRequestSubmitFailed,
          );
        }
      });
      if (backendErrors.isNotEmpty) {
        await _scrollCoordinator.focusFirstError(
          const [
            'planCodes',
            'activityName',
            'contactPhone',
          ].where(backendErrors.containsKey),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 18, 16, bottom + 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FormErrorBanner(message: _formError),
            Text(
              l10n.paidUpgradesRequestSheetTitle,
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 12),
            _scrollCoordinator.anchor(
              'planCodes',
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _fieldErrors.containsKey('planCodes')
                        ? Theme.of(context).colorScheme.error
                        : Colors.transparent,
                  ),
                ),
                child: Column(
                  children: [
                    ...widget.plans.map(
                      (plan) => CheckboxListTile(
                        value: _selectedCodes.contains(plan.code),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedCodes.add(plan.code);
                            } else {
                              _selectedCodes.remove(plan.code);
                            }
                          });
                          _clearFieldError('planCodes');
                        },
                        title: Text(plan.title, textAlign: TextAlign.right),
                        subtitle: Text(
                          '${_planDescription(plan)}\n${formatIqd(plan.monthlyFeeIqd)}',
                          textAlign: TextAlign.right,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            InlineFieldErrorText(text: _fieldErrors['planCodes']),
            _scrollCoordinator.anchor(
              'activityName',
              TextField(
                controller: _activityNameCtrl,
                focusNode: _scrollCoordinator.focusNodeFor('activityName'),
                textDirection: context.appTextDirection,
                onChanged: (_) => _clearFieldError('activityName'),
                decoration: InputDecoration(
                  labelText: l10n.paidUpgradesActivityName,
                  errorText: _fieldErrors['activityName'],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _activityDescriptionCtrl,
              minLines: 2,
              maxLines: 4,
              textDirection: context.appTextDirection,
              decoration: InputDecoration(
                labelText: l10n.paidUpgradesActivityDescription,
              ),
            ),
            const SizedBox(height: 10),
            _scrollCoordinator.anchor(
              'contactPhone',
              TextField(
                controller: _contactPhoneCtrl,
                focusNode: _scrollCoordinator.focusNodeFor('contactPhone'),
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                onChanged: (_) => _clearFieldError('contactPhone'),
                decoration: InputDecoration(
                  labelText: l10n.paidUpgradesContactPhone,
                  errorText: _fieldErrors['contactPhone'],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 4,
              textDirection: context.appTextDirection,
              decoration: InputDecoration(labelText: l10n.paidUpgradesNotes),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(l10n.commonCancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: Text(l10n.paidUpgradesSubmitRequest),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaidUpgradesHomeScreenState
    extends ConsumerState<PaidUpgradesHomeScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  PaidUpgradesSummaryModel? _summary;

  PaidUpgradesApi get _api => ref.read(paidUpgradesApiProvider);

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
      final out = await _api.me();
      if (!mounted) return;
      setState(() {
        _summary = PaidUpgradesSummaryModel.fromJson(out);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(e, fallback: context.l10n.paidUpgradesLoadFailed);
      });
    }
  }

  Future<void> _openRequestSheet() async {
    final summary = _summary;
    if (summary == null || _busy) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaidUpgradeRequestSheet(plans: summary.plans),
    );
    if (created == true) {
      await _load();
    }
  }

  Future<void> _cancelRequest(int requestId) async {
    if (_busy) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await _api.cancelRequest(requestId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.paidUpgradesRequestCancelled)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: l10n.paidUpgradesCancelRequestFailed),
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
      case 'active':
        return const Color(0xFF16A34A);
      case 'approved':
        return const Color(0xFF2563EB);
      case 'rejected':
        return const Color(0xFFDC2626);
      case 'cancelled':
      case 'expired':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String _statusLabel(String status) {
    final l10n = context.l10n;
    switch (status) {
      case 'pending_admin_review':
        return l10n.paidUpgradesStatusPendingAdminReview;
      case 'approved':
        return l10n.commonApproved;
      case 'activated':
      case 'active':
        return l10n.commonActive;
      case 'rejected':
        return l10n.commonRejected;
      case 'expired':
        return l10n.paidUpgradesExpired;
      default:
        return l10n.commonCancelled;
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return value.toLocal().toIso8601String().split('T').first;
  }

  String _remainingLabel(DateTime? expiresAt) {
    final l10n = context.l10n;
    if (expiresAt == null) return l10n.paidUpgradesNoExpirySet;
    final diff = expiresAt.toLocal().difference(DateTime.now());
    if (diff.isNegative || diff.inSeconds <= 0) {
      return l10n.paidUpgradesExpired;
    }
    if (diff.inDays >= 1) {
      return l10n.paidUpgradesDaysLeft(diff.inDays);
    }
    final hours = diff.inHours > 0 ? diff.inHours : 1;
    return l10n.paidUpgradesHoursLeft(hours);
  }

  bool _planIncludedWithPremium(
    PaidUpgradePlanModel plan,
    PaidUpgradesSummaryModel summary,
  ) {
    if (!summary.premiumMonthly) return false;
    return plan.code == 'car_seller_monthly' ||
        plan.code == 'property_seller_monthly';
  }

  bool _isPlanEffectivelyActive(
    PaidUpgradePlanModel plan,
    PaidUpgradesSummaryModel summary,
  ) {
    return summary.activePlanCodes.contains(plan.code) ||
        _planIncludedWithPremium(plan, summary);
  }

  DateTime? _effectiveExpiryForPlan(
    PaidUpgradePlanModel plan,
    PaidUpgradesSummaryModel summary,
  ) {
    for (final sub in summary.activeSubscriptions) {
      if (sub.planCode == plan.code) return sub.expiresAt;
    }
    if (_planIncludedWithPremium(plan, summary)) {
      return summary.premiumBadgeExpiresAt;
    }
    return null;
  }

  String _planDescription(PaidUpgradePlanModel plan) {
    final l10n = context.l10n;
    switch (plan.code) {
      case 'car_seller_monthly':
        return l10n.paidUpgradesPlanCarsExtendedDescription;
      case 'property_seller_monthly':
        return l10n.paidUpgradesPlanPropertyExtendedDescription;
      case 'premium_monthly':
        return l10n.paidUpgradesPlanPremiumExtendedDescription;
      default:
        return plan.description?.trim() ?? '';
    }
  }

  Widget _buildActiveSubscriptions(PaidUpgradesSummaryModel summary) {
    final l10n = context.l10n;
    final activeSubscriptions = summary.activeSubscriptions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              l10n.paidUpgradesCurrentSubscription,
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 12),
            if (activeSubscriptions.isEmpty)
              Text(
                l10n.paidUpgradesNoActiveSubscription,
                textDirection: context.appTextDirection,
              )
            else
              ...activeSubscriptions.map(
                (sub) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      border: Border.all(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          textDirection: context.appTextDirection,
                          children: [
                            Expanded(
                              child: Text(
                                sub.planTitle ?? sub.planCode ?? '-',
                                textDirection: context.appTextDirection,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: const Color(
                                  0xFF16A34A,
                                ).withValues(alpha: 0.14),
                              ),
                              child: Text(
                                l10n.paidUpgradesActiveNow,
                                style: const TextStyle(
                                  color: Color(0xFF16A34A),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.paidUpgradesActiveDescription,
                          textDirection: context.appTextDirection,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.paidUpgradesSubscriptionEndsOn(
                            _formatDate(sub.expiresAt),
                          ),
                          textDirection: context.appTextDirection,
                        ),
                        Text(
                          _remainingLabel(sub.expiresAt),
                          textDirection: context.appTextDirection,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (sub.planCode == 'premium_monthly') ...[
                          const SizedBox(height: 8),
                          Text(
                            l10n.paidUpgradesPremiumIncludesEntitlements,
                            textDirection: context.appTextDirection,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(
    PaidUpgradePlanModel plan,
    PaidUpgradesSummaryModel summary,
  ) {
    final l10n = context.l10n;
    final active = _isPlanEffectivelyActive(plan, summary);
    final includedWithPremium =
        _planIncludedWithPremium(plan, summary) &&
        !summary.activePlanCodes.contains(plan.code);
    final expiry = _effectiveExpiryForPlan(plan, summary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          border: Border.all(
            color: active
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              textDirection: context.appTextDirection,
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    textDirection: context.appTextDirection,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color:
                        (active
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF64748B))
                            .withValues(alpha: 0.14),
                  ),
                  child: Text(
                    active
                        ? includedWithPremium
                              ? l10n.paidUpgradesIncludedWithPremium
                              : l10n.paidUpgradesCurrentlyActive
                        : l10n.paidUpgradesAvailableStatus,
                    style: TextStyle(
                      color: active
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _planDescription(plan),
              textDirection: context.appTextDirection,
            ),
            if (active && expiry != null) ...[
              const SizedBox(height: 10),
              Text(
                l10n.paidUpgradesCurrentAccessEnds(
                  _formatDate(expiry),
                  _remainingLabel(expiry),
                ),
                textDirection: context.appTextDirection,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (includedWithPremium)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.paidUpgradesPlanEnabledByPremium,
                  textDirection: context.appTextDirection,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              formatIqd(plan.monthlyFeeIqd),
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.paidUpgradesHomeTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
          ),
        ],
      ),
      floatingActionButton: summary == null
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              onPressed: _busy ? null : _openRequestSheet,
              icon: const Icon(Icons.upgrade_rounded),
              label: Text(l10n.paidUpgradesRequestUpgrade),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [
                  const SizedBox(height: 140),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _error!,
                        textDirection: context.appTextDirection,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  if (summary != null && summary.premiumBadgeActive)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.workspace_premium_rounded),
                        title: Text(l10n.paidUpgradesPremiumBadgeActive),
                        subtitle: Text(
                          l10n.paidUpgradesPremiumBadgeSubtitle(
                            _formatDate(summary.premiumBadgeExpiresAt),
                            _remainingLabel(summary.premiumBadgeExpiresAt),
                          ),
                          textDirection: context.appTextDirection,
                        ),
                      ),
                    ),
                  if (summary != null) _buildActiveSubscriptions(summary),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            l10n.paidUpgradesAvailablePlans,
                            textDirection: context.appTextDirection,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...?summary?.plans.map(
                            (plan) => _buildPlanCard(plan, summary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            l10n.paidUpgradesYourRequests,
                            textDirection: context.appTextDirection,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (summary == null || summary.requests.isEmpty)
                            Text(
                              l10n.paidUpgradesNoRequests,
                              textDirection: context.appTextDirection,
                            )
                          else
                            ...summary.requests.map((request) {
                              final pending =
                                  request.status == 'pending_admin_review';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.3),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        textDirection: context.appTextDirection,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              request.planTitle ??
                                                  request.planCode ??
                                                  '-',
                                              textDirection:
                                                  context.appTextDirection,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            _statusLabel(request.status),
                                            style: TextStyle(
                                              color: _statusColor(
                                                request.status,
                                              ),
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      if ((request.activityName ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Text(
                                          l10n.paidUpgradesActivityLine(
                                            request.activityName!,
                                          ),
                                          textDirection:
                                              context.appTextDirection,
                                        ),
                                      if ((request.contactPhone ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Text(
                                          l10n.paidUpgradesPhoneLine(
                                            request.contactPhone!,
                                          ),
                                          textDirection:
                                              context.appTextDirection,
                                        ),
                                      Text(
                                        l10n.paidUpgradesMonthlyFeeLine(
                                          formatIqd(request.monthlyFeeIqd),
                                        ),
                                        textDirection: context.appTextDirection,
                                      ),
                                      if ((request.reviewNote ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Text(
                                          l10n.paidUpgradesReviewNoteLine(
                                            request.reviewNote!,
                                          ),
                                          textDirection:
                                              context.appTextDirection,
                                        ),
                                      if (request.activatedAt != null)
                                        Text(
                                          l10n.paidUpgradesActivatedOn(
                                            _formatDate(request.activatedAt),
                                          ),
                                          textDirection:
                                              context.appTextDirection,
                                        ),
                                      if (pending)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 10,
                                          ),
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: OutlinedButton.icon(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _cancelRequest(
                                                      request.id,
                                                    ),
                                              icon: const Icon(
                                                Icons.close_rounded,
                                              ),
                                              label: Text(
                                                l10n.paidUpgradesCancelRequest,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
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
}
