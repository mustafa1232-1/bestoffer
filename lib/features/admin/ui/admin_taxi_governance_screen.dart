import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/parsers.dart';
import '../../auth/state/auth_controller.dart';
import '../../taxi/data/taxi_api.dart';

TaxiApi _taxiApi(WidgetRef ref) => TaxiApi(ref.read(dioClientProvider).dio);

class AdminTaxiGovernanceScreen extends ConsumerStatefulWidget {
  const AdminTaxiGovernanceScreen({super.key});

  @override
  ConsumerState<AdminTaxiGovernanceScreen> createState() =>
      _AdminTaxiGovernanceScreenState();
}

class _AdminTaxiGovernanceScreenState
    extends ConsumerState<AdminTaxiGovernanceScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _kpi = const <String, dynamic>{};
  List<Map<String, dynamic>> _coupons = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _contests = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _complaints = const <Map<String, dynamic>>[];

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

  String _generateCouponCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    final random = Random.secure();
    final first = chars[random.nextInt(chars.length)];
    final second = chars[random.nextInt(chars.length)];
    final digits = random.nextInt(1000).toString().padLeft(3, '0');
    return '$first$second$digits';
  }

  String _money(num value) {
    if (value is int) return value.toString();
    final rounded = value.roundToDouble();
    if (rounded == value) return rounded.toInt().toString();
    return value.toStringAsFixed(2);
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait<dynamic>([
        _taxiApi(ref).adminTaxiKpiOverview(),
        _taxiApi(ref).listAdminTaxiCoupons(includeInactive: true),
        _taxiApi(ref).listAdminTaxiContests(includeInactive: true),
        _taxiApi(ref).listAdminTaxiComplaints(status: 'new', limit: 80),
      ]);
      if (!mounted) return;
      setState(() {
        _kpi = _asMap(responses[0]);
        _coupons = List<Map<String, dynamic>>.from(
          (responses[1] as List<dynamic>).map(_asMap),
        );
        _contests = List<Map<String, dynamic>>.from(
          (responses[2] as List<dynamic>).map(_asMap),
        );
        _complaints = List<Map<String, dynamic>>.from(
          (responses[3] as List<dynamic>).map(_asMap),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyErrorL10n(
          error,
          fallbackBuilder: (l10n) => l10n.adminTaxiGovernanceLoadFailed,
        );
      });
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _createContest() async {
    final l10n = context.l10n;
    final titleCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final targetValueCtrl = TextEditingController();
    final firstRewardCtrl = TextEditingController();
    var startAt = DateTime.now().add(const Duration(minutes: 10));
    var endAt = startAt.add(const Duration(days: 7));
    String? formError;
    var submitting = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final firstReward = _asDouble(firstRewardCtrl.text, 0);
          final secondReward = firstReward * 0.5;
          final thirdReward = firstReward * 0.25;

          Future<void> submit() async {
            final title = titleCtrl.text.trim();
            final targetValue = tryParseLocalizedDouble(
              targetValueCtrl.text.trim(),
            );
            if (title.isEmpty ||
                targetValue == null ||
                targetValue <= 0 ||
                firstReward <= 0 ||
                !endAt.isAfter(startAt)) {
              setDialogState(
                () => formError = l10n.validationReviewRequiredFields,
              );
              return;
            }
            setDialogState(() {
              submitting = true;
              formError = null;
            });
            try {
              await _taxiApi(ref).upsertAdminTaxiContest(
                payload: {
                  'title': title,
                  'description': descriptionCtrl.text.trim().isEmpty
                      ? null
                      : descriptionCtrl.text.trim(),
                  'startAt': startAt.toUtc().toIso8601String(),
                  'endAt': endAt.toUtc().toIso8601String(),
                  'targetType': 'completed_rides',
                  'targetValue': targetValue,
                  'rewardType': 'credit',
                  'rewardValue': firstReward,
                  'eligibilityRules': {
                    'rewardCenters': [
                      {'rank': 1, 'percent': 100, 'rewardValue': firstReward},
                      {'rank': 2, 'percent': 50, 'rewardValue': secondReward},
                      {'rank': 3, 'percent': 25, 'rewardValue': thirdReward},
                    ],
                  },
                  'isActive': true,
                }..removeWhere((key, value) => value == null),
              );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(true);
            } catch (error) {
              setDialogState(() {
                submitting = false;
                formError = mapAnyErrorL10n(
                  error,
                  fallbackBuilder: (l10n) => l10n.adminCompetitionsCreateFailed,
                );
              });
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.emoji_events_rounded),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.commonCreate)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (formError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        formError!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ),
                  TextField(
                    controller: titleCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: l10n.commonTitle),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.adminCompetitionsDescription,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: targetValueCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.adminCompetitionsRequiredOrders,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: firstRewardCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: l10n.adminCompetitionsRewardIqd,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CenterRewardLine(
                          title: l10n.adminCompetitionsFirstPlace,
                          percent: '100%',
                          value: _money(firstReward),
                        ),
                        _CenterRewardLine(
                          title: l10n.adminCompetitionsSecondPlace,
                          percent: '50%',
                          value: _money(secondReward),
                        ),
                        _CenterRewardLine(
                          title: l10n.adminCompetitionsThirdPlace,
                          percent: '25%',
                          value: _money(thirdReward),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.adminCompetitionsStartDateTime),
                    subtitle: Text(startAt.toLocal().toString()),
                    onTap: () async {
                      final picked = await _pickDateTime(startAt);
                      if (picked != null) {
                        setDialogState(() => startAt = picked);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.adminCompetitionsEndDateTime),
                    subtitle: Text(endAt.toLocal().toString()),
                    onTap: () async {
                      final picked = await _pickDateTime(endAt);
                      if (picked != null) {
                        setDialogState(() => endAt = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: Text(l10n.commonSave),
              ),
            ],
          );
        },
      ),
    );

    titleCtrl.dispose();
    descriptionCtrl.dispose();
    targetValueCtrl.dispose();
    firstRewardCtrl.dispose();

    if (created == true) {
      await _load();
      _showSnack(l10n.adminCompetitionsCreateSuccess);
    }
  }

  Future<void> _createCoupon() async {
    final l10n = context.l10n;
    final codeCtrl = TextEditingController(text: _generateCouponCode());
    final titleCtrl = TextEditingController();
    final firstDiscountCtrl = TextEditingController();
    final secondDiscountCtrl = TextEditingController();
    final thirdDiscountCtrl = TextEditingController();
    var maxUses = 1;
    final fieldErrors = <String, String?>{};
    String? formError;
    var submitting = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          String? resolveFieldError(String field, String label) {
            final code = fieldErrors[field];
            if (code == null) return null;
            if (field == 'code' && code == 'INVALID_COUPON_CODE') {
              return l10n.validationInvalidCouponCode;
            }
            return resolveFormFieldError(
              l10n: l10n,
              field: field,
              code: code,
              fieldLabel: label,
            );
          }

          void clearFieldError(String field) {
            if (!fieldErrors.containsKey(field)) return;
            setDialogState(() => fieldErrors.remove(field));
          }

          InputDecoration discountDecoration(String label) =>
              InputDecoration(labelText: label, suffixText: '%');

          Future<void> submit() async {
            final code = codeCtrl.text.trim().toUpperCase();
            final title = titleCtrl.text.trim();
            final first = tryParseLocalizedDouble(firstDiscountCtrl.text.trim());
            final second = tryParseLocalizedDouble(
              secondDiscountCtrl.text.trim(),
            );
            final third = tryParseLocalizedDouble(thirdDiscountCtrl.text.trim());

            bool invalidPercent(double? value) =>
                value == null || value <= 0 || value > 100;

            final validationErrors = <String, String?>{};
            if (!RegExp(r'^[A-Z]{2}\d{3}$').hasMatch(code)) {
              validationErrors['code'] = 'INVALID_COUPON_CODE';
            }
            if (title.isEmpty) {
              validationErrors['title'] = 'REQUIRED';
            }
            if (invalidPercent(first)) {
              validationErrors['firstDiscount'] = 'INVALID_NUMBER';
            }
            if (maxUses >= 2 && invalidPercent(second)) {
              validationErrors['secondDiscount'] = 'INVALID_NUMBER';
            }
            if (maxUses == 3 && invalidPercent(third)) {
              validationErrors['thirdDiscount'] = 'INVALID_NUMBER';
            }

            if (validationErrors.isNotEmpty) {
              setDialogState(() {
                formError = l10n.validationReviewRequiredFields;
                fieldErrors
                  ..clear()
                  ..addAll(validationErrors);
              });
              return;
            }

            final tiers = <Map<String, dynamic>>[
              {
                'useIndex': 1,
                'discountType': 'percent',
                'discountValue': first,
              },
              if (maxUses >= 2)
                {
                  'useIndex': 2,
                  'discountType': 'percent',
                  'discountValue': second,
                },
              if (maxUses == 3)
                {
                  'useIndex': 3,
                  'discountType': 'percent',
                  'discountValue': third,
                },
            ];

            setDialogState(() {
              submitting = true;
              formError = null;
              fieldErrors.clear();
            });
            try {
              await _taxiApi(ref).upsertAdminTaxiCoupon(
                payload: {
                  'code': code,
                  'title': title,
                  'isActive': true,
                  'applyWholeApp': true,
                  'maxUsesPerUser': maxUses,
                  'tiers': tiers,
                },
              );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(true);
            } catch (error) {
              final parsed = parseBackendFieldErrors(error);
              setDialogState(() {
                submitting = false;
                fieldErrors
                  ..clear()
                  ..addAll(parsed.fieldCodes);
                formError = resolveFormLevelError(
                  l10n,
                  code: parsed.formCode ?? parsed.messageCode,
                  fallback: mapAnyErrorL10n(
                    error,
                    fallbackBuilder: (l10n) => l10n.couponManagementCreateFailed,
                  ),
                );
              });
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.local_offer_rounded),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.commonCreate)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FormErrorBanner(message: formError),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(l10n.couponManagementCreateGlobalDescription),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: codeCtrl,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 5,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        final text = newValue.text.toUpperCase();
                        return newValue.copyWith(
                          text: text,
                          selection: TextSelection.collapsed(offset: text.length),
                        );
                      }),
                    ],
                    onChanged: (_) => clearFieldError('code'),
                    decoration: InputDecoration(
                      labelText: l10n.couponManagementCodeLabel,
                      hintText: l10n.couponManagementCodeHintShort,
                      errorText: resolveFieldError(
                        'code',
                        l10n.couponManagementCodeLabel,
                      ),
                      suffixIcon: IconButton(
                        onPressed: submitting
                            ? null
                            : () => setDialogState(
                                () => codeCtrl.text = _generateCouponCode(),
                              ),
                        icon: const Icon(Icons.autorenew_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleCtrl,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => clearFieldError('title'),
                    decoration: InputDecoration(
                      labelText: l10n.commonTitle,
                      errorText: resolveFieldError('title', l10n.commonTitle),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: maxUses,
                    decoration: InputDecoration(
                      labelText: l10n.couponManagementMaxUsesLabel,
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1')),
                      DropdownMenuItem(value: 2, child: Text('2')),
                      DropdownMenuItem(value: 3, child: Text('3')),
                    ],
                    onChanged: submitting
                        ? null
                        : (value) => setDialogState(() => maxUses = value ?? 1),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: firstDiscountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => clearFieldError('firstDiscount'),
                    decoration: discountDecoration(
                      l10n.couponManagementDiscountValueLabel,
                    ).copyWith(
                      errorText: resolveFieldError(
                        'firstDiscount',
                        l10n.couponManagementDiscountValueLabel,
                      ),
                    ),
                  ),
                  if (maxUses >= 2) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: secondDiscountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (_) => clearFieldError('secondDiscount'),
                      decoration: discountDecoration(
                        l10n.couponManagementDiscountValueLabel,
                      ).copyWith(
                        errorText: resolveFieldError(
                          'secondDiscount',
                          l10n.couponManagementDiscountValueLabel,
                        ),
                      ),
                    ),
                  ],
                  if (maxUses == 3) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: thirdDiscountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (_) => clearFieldError('thirdDiscount'),
                      decoration: discountDecoration(
                        l10n.couponManagementDiscountValueLabel,
                      ).copyWith(
                        errorText: resolveFieldError(
                          'thirdDiscount',
                          l10n.couponManagementDiscountValueLabel,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: Text(l10n.commonSave),
              ),
            ],
          );
        },
      ),
    );
    codeCtrl.dispose();
    titleCtrl.dispose();
    firstDiscountCtrl.dispose();
    secondDiscountCtrl.dispose();
    thirdDiscountCtrl.dispose();
    if (created == true) {
      await _load();
      _showSnack(l10n.couponManagementCreatedSuccess);
    }
  }

  Future<void> _reviewComplaint(int complaintId, String status) async {
    final l10n = context.l10n;
    try {
      await _taxiApi(
        ref,
      ).reviewAdminTaxiComplaint(complaintId: complaintId, status: status);
      await _load();
      _showSnack(l10n.commonDone);
    } catch (error) {
      _showSnack(
        mapAnyErrorL10n(error, fallbackBuilder: (l10n) => l10n.errorsUnknown),
        error: true,
      );
    }
  }

  String _couponTiersSummary(Map<String, dynamic> item) {
    final tiersRaw = item['tiers'];
    if (tiersRaw is! List) return '-';
    final tiers =
        tiersRaw
            .whereType<Map>()
            .map((e) => _asMap(e))
            .map(
              (tier) => (
                useIndex: _asInt(tier['useIndex']),
                discountType: (tier['discountType'] ?? '').toString(),
                discountValue: _asDouble(tier['discountValue']),
              ),
            )
            .toList()
          ..sort((a, b) => a.useIndex.compareTo(b.useIndex));

    if (tiers.isEmpty) return '-';
    return tiers
        .map((tier) {
          if (tier.discountType.toLowerCase() == 'percent') {
            return '#${tier.useIndex}: ${_money(tier.discountValue)}%';
          }
          return '#${tier.useIndex}: ${_money(tier.discountValue)}';
        })
        .join('  |  ');
  }

  ({double first, double second, double third}) _contestRewardsFromItem(
    Map<String, dynamic> item,
  ) {
    final rules = _asMap(item['eligibilityRules']);
    final centers = rules['rewardCenters'];
    if (centers is List) {
      double first = 0;
      double second = 0;
      double third = 0;
      for (final raw in centers.whereType<Map>()) {
        final center = _asMap(raw);
        final rank = _asInt(center['rank']);
        final reward = _asDouble(center['rewardValue']);
        if (rank == 1) first = reward;
        if (rank == 2) second = reward;
        if (rank == 3) third = reward;
      }
      if (first > 0 || second > 0 || third > 0) {
        return (first: first, second: second, third: third);
      }
    }
    final base = _asDouble(item['rewardValue']);
    return (first: base, second: base * 0.5, third: base * 0.25);
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required VoidCallback onCreate,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
          label: Text(context.l10n.commonCreate),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rides = _asMap(_kpi['rides']);
    final complaintsKpi = _asMap(_kpi['complaints']);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.adminTaxiGovernanceTitle)),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminTaxiGovernanceTitle),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [colors.primaryContainer, colors.secondaryContainer],
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.adminTaxiKpiOverview,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _KpiChip(
                          label: l10n.adminTaxiKpiTotalRides,
                          value: _asInt(rides['total']).toString(),
                        ),
                        _KpiChip(
                          label: l10n.adminTaxiKpiCompletedRides,
                          value: _asInt(rides['completed']).toString(),
                        ),
                        _KpiChip(
                          label: l10n.adminTaxiKpiOpenComplaints,
                          value: _asInt(complaintsKpi['open']).toString(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _sectionHeader(
                      context,
                      title: l10n.adminTaxiCouponsTitle,
                      onCreate: _createCoupon,
                    ),
                    const SizedBox(height: 10),
                    if (_coupons.isEmpty)
                      ListTile(title: Text(l10n.commonNoItems))
                    else
                      ..._coupons.map((item) {
                        final isActive = item['isActive'] == true;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item['title']?.toString() ?? '-',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                    ),
                                    Chip(
                                      label: Text(
                                        isActive
                                            ? l10n.commonActive
                                            : l10n.commonInactive,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Chip(
                                      label: Text(
                                        item['code']?.toString() ?? '-',
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    Chip(
                                      label: Text(
                                        '${l10n.couponManagementMaxUsesLabel}: ${_asInt(item['maxUsesPerUser'], 1)}',
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${l10n.couponManagementDiscountValueLabel}: ${_couponTiersSummary(item)}',
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
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _sectionHeader(
                      context,
                      title: l10n.adminTaxiContestsTitle,
                      onCreate: _createContest,
                    ),
                    const SizedBox(height: 10),
                    if (_contests.isEmpty)
                      ListTile(title: Text(l10n.adminCompetitionsListEmpty))
                    else
                      ..._contests.map((item) {
                        final id = _asInt(item['id']);
                        final reward = _contestRewardsFromItem(item);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(item['title']?.toString() ?? '-'),
                            subtitle: Text(
                              '${l10n.adminCompetitionsRequiredOrders}: ${item['targetValue'] ?? '-'}\n'
                              '${l10n.adminCompetitionsFirstPlace}: ${_money(reward.first)}\n'
                              '${l10n.adminCompetitionsSecondPlace}: ${_money(reward.second)}\n'
                              '${l10n.adminCompetitionsThirdPlace}: ${_money(reward.third)}',
                            ),
                            trailing: TextButton(
                              onPressed: id <= 0
                                  ? null
                                  : () async {
                                      try {
                                        await _taxiApi(
                                          ref,
                                        ).finalizeAdminTaxiContest(id);
                                        await _load();
                                        _showSnack(
                                          l10n.adminCompetitionsEndSuccess,
                                        );
                                      } catch (error) {
                                        _showSnack(
                                          mapAnyErrorL10n(
                                            error,
                                            fallbackBuilder: (l10n) =>
                                                l10n.errorsUnknown,
                                          ),
                                          error: true,
                                        );
                                      }
                                    },
                              child: Text(l10n.adminCompetitionsEndNowTooltip),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.adminTaxiComplaintsTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (_complaints.isEmpty)
                      ListTile(title: Text(l10n.commonNoItems))
                    else
                      ..._complaints.map((item) {
                        final complaintId = _asInt(item['id']);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(item['category']?.toString() ?? '-'),
                            subtitle: Text(
                              '${item['reason'] ?? '-'}\n'
                              '${l10n.commonStatus}: ${item['status'] ?? '-'}',
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                TextButton(
                                  onPressed: complaintId <= 0
                                      ? null
                                      : () => _reviewComplaint(
                                          complaintId,
                                          'resolved',
                                        ),
                                  child: Text(l10n.commonApprove),
                                ),
                                TextButton(
                                  onPressed: complaintId <= 0
                                      ? null
                                      : () => _reviewComplaint(
                                          complaintId,
                                          'rejected',
                                        ),
                                  child: Text(l10n.commonReject),
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

class _KpiChip extends StatelessWidget {
  const _KpiChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterRewardLine extends StatelessWidget {
  const _CenterRewardLine({
    required this.title,
    required this.percent,
    required this.value,
  });

  final String title;
  final String percent;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          Text('$percent  |  $value'),
        ],
      ),
    );
  }
}
