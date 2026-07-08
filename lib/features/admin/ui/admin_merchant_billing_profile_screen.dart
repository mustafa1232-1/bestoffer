import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/parsers.dart';
import '../state/admin_controller.dart';

class AdminMerchantBillingProfileScreen extends ConsumerStatefulWidget {
  final int merchantId;
  final String merchantName;
  final bool approvalMode;

  const AdminMerchantBillingProfileScreen({
    super.key,
    required this.merchantId,
    required this.merchantName,
    this.approvalMode = false,
  });

  @override
  ConsumerState<AdminMerchantBillingProfileScreen> createState() =>
      _AdminMerchantBillingProfileScreenState();
}

class _AdminMerchantBillingProfileScreenState
    extends ConsumerState<AdminMerchantBillingProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _commissionValueCtrl = TextEditingController();
  final _serviceValueCtrl = TextEditingController();
  final _appDeliveryValueCtrl = TextEditingController();
  final _storeDeliveryValueCtrl = TextEditingController();
  final _graceDaysCtrl = TextEditingController();

  String _commissionType = 'percentage';
  String _commissionModel = 'percentage';
  String _serviceFeeType = 'fixed';
  String _deliveryFeeMode = 'dynamic';
  String _settlementCycle = 'weekly';
  String _distributionPolicy = 'commission_service_delivery';
  bool _appDeliveryEnabled = true;
  bool _merchantDeliveryEnabled = true;
  bool _loading = true;
  DateTime? _effectiveFrom;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _commissionValueCtrl.dispose();
    _serviceValueCtrl.dispose();
    _appDeliveryValueCtrl.dispose();
    _storeDeliveryValueCtrl.dispose();
    _graceDaysCtrl.dispose();
    super.dispose();
  }

  num _num(dynamic value) =>
      value is num ? value : (tryParseLocalizedDouble(value) ?? 0);

  double? _parseDoubleInput(String raw) => tryParseLocalizedDouble(raw);
  int? _parseIntInput(String raw) => tryParseLocalizedInt(raw);

  Future<void> _load() async {
    setState(() => _loading = true);
    final details = await ref
        .read(adminControllerProvider.notifier)
        .fetchMerchantReceivablesDetailsV2(widget.merchantId);
    if (!mounted) return;

    final billing = Map<String, dynamic>.from(
      (details?['billingProfile'] as Map?) ?? const {},
    );
    final commissionValue = billing['commission_value'];
    final commissionRate = billing['commission_rate'];

    _commissionType = '${billing['commission_type'] ?? 'percentage'}';
    _commissionModel = '${billing['commission_model'] ?? 'percentage'}';
    _serviceFeeType =
        '${billing['service_fee_type'] ?? billing['service_fee_mode'] ?? 'fixed'}';
    _deliveryFeeMode = '${billing['delivery_fee_mode'] ?? 'dynamic'}';
    _settlementCycle = '${billing['settlement_cycle'] ?? 'weekly'}';
    _distributionPolicy =
        '${billing['distribution_policy'] ?? 'commission_service_delivery'}';
    _appDeliveryEnabled = billing['app_delivery_enabled'] != false;
    _merchantDeliveryEnabled = billing['merchant_delivery_enabled'] != false;

    _commissionValueCtrl.text = commissionValue != null
        ? _num(commissionValue).toStringAsFixed(
            _commissionType == 'percentage' ? 2 : 0,
          )
        : (_num(commissionRate) * 100).toStringAsFixed(2);
    _serviceValueCtrl.text = _num(billing['service_fee_value']).toStringAsFixed(
      0,
    );
    _appDeliveryValueCtrl.text = _num(
      billing['app_delivery_fee_value'] ?? billing['delivery_fee_value'],
    ).toStringAsFixed(0);
    _storeDeliveryValueCtrl.text = _num(
      billing['store_delivery_fee_value'],
    ).toStringAsFixed(0);
    _graceDaysCtrl.text = _num(billing['grace_period_days']).toInt().toString();
    final effectiveFromRaw = billing['effective_from'];
    _effectiveFrom = effectiveFromRaw == null
        ? DateTime.now()
        : DateTime.tryParse(effectiveFromRaw.toString()) ?? DateTime.now();

    setState(() => _loading = false);
  }

  Future<void> _pickEffectiveFrom() async {
    final now = DateTime.now();
    final current = _effectiveFrom ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() {
      _effectiveFrom = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _commissionTypeLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    switch (value) {
      case 'fixed':
        return l10n.adminMerchantBillingFixed;
      case 'percentage':
      default:
        return l10n.adminMerchantBillingPercentage;
    }
  }

  String _commissionModelLabel(BuildContext context, String value) {
    switch (value) {
      case 'monthly_subscription':
        return context.lt(
          ar: 'اشتراك شهري',
          en: 'Monthly subscription',
        );
      case 'percentage':
      default:
        return context.lt(
          ar: 'نسبة مئوية',
          en: 'Percentage',
        );
    }
  }

  String _serviceFeeTypeLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    switch (value) {
      case 'percentage':
        return l10n.adminMerchantBillingPercentage;
      case 'per_order':
        return l10n.adminMerchantBillingPerOrder;
      case 'global_rule':
        return l10n.adminMerchantBillingGlobalRule;
      case 'fixed':
      default:
        return l10n.adminMerchantBillingFixed;
    }
  }

  String _deliveryFeeModeLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    switch (value) {
      case 'app_defined':
        return l10n.adminMerchantBillingAppDefined;
      case 'store_defined':
        return l10n.adminMerchantBillingStoreDefined;
      case 'dynamic':
      default:
        return l10n.adminMerchantBillingDynamic;
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final body = <String, dynamic>{
      'commissionType': _commissionType,
      'commissionValue': _parseDoubleInput(_commissionValueCtrl.text.trim()) ?? 0,
      'commissionModel': _commissionModel,
      'monthlySubscriptionAmount': _commissionModel == 'monthly_subscription'
          ? (_parseDoubleInput(_commissionValueCtrl.text.trim()) ?? 0)
          : 0,
      'serviceFeeType': _serviceFeeType,
      'serviceFeeValue': _parseDoubleInput(_serviceValueCtrl.text.trim()) ?? 0,
      'deliveryFeeMode': _deliveryFeeMode,
      'appDeliveryFeeValue':
          _parseDoubleInput(_appDeliveryValueCtrl.text.trim()) ?? 0,
      'storeDeliveryFeeValue':
          _parseDoubleInput(_storeDeliveryValueCtrl.text.trim()) ?? 0,
      'appDeliveryEnabled': _appDeliveryEnabled,
      'merchantDeliveryEnabled': _merchantDeliveryEnabled,
      'settlementCycle': _settlementCycle,
      'distributionPolicy': _distributionPolicy,
      'gracePeriodDays': _parseIntInput(_graceDaysCtrl.text.trim()) ?? 0,
      'effectiveFrom': (_effectiveFrom ?? DateTime.now()).toIso8601String(),
    };

    bool ok;
    if (widget.approvalMode) {
      await ref
          .read(adminControllerProvider.notifier)
          .approveMerchant(widget.merchantId, body: body);
      ok = ref.read(adminControllerProvider).error == null;
    } else {
      ok = await ref
          .read(adminControllerProvider.notifier)
          .patchMerchantBillingProfileV2(
            merchantId: widget.merchantId,
            commissionRate: _commissionType == 'percentage'
                ? ((_parseDoubleInput(_commissionValueCtrl.text.trim()) ?? 0) /
                    100)
                : 0,
            commissionType: _commissionType,
            commissionValue:
                _parseDoubleInput(_commissionValueCtrl.text.trim()) ?? 0,
            serviceFeeMode: _serviceFeeType,
            serviceFeeType: _serviceFeeType,
            commissionModel: _commissionModel,
            monthlySubscriptionAmount: _commissionModel == 'monthly_subscription'
                ? (_parseDoubleInput(_commissionValueCtrl.text.trim()) ?? 0)
                : 0,
            serviceFeeValue:
                _parseDoubleInput(_serviceValueCtrl.text.trim()) ?? 0,
            deliveryFeeMode: _deliveryFeeMode,
            deliveryFeeValue:
                _parseDoubleInput(_appDeliveryValueCtrl.text.trim()) ?? 0,
            appDeliveryFeeValue:
                _parseDoubleInput(_appDeliveryValueCtrl.text.trim()) ?? 0,
            storeDeliveryFeeValue:
                _parseDoubleInput(_storeDeliveryValueCtrl.text.trim()) ?? 0,
            appDeliveryEnabled: _appDeliveryEnabled,
            merchantDeliveryEnabled: _merchantDeliveryEnabled,
            settlementCycle: _settlementCycle,
            distributionPolicy: _distributionPolicy,
            gracePeriodDays: _parseIntInput(_graceDaysCtrl.text.trim()) ?? 0,
            effectiveFrom: (_effectiveFrom ?? DateTime.now()).toIso8601String(),
          );
    }

    if (!mounted) return;
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? widget.approvalMode
                    ? l10n.adminMerchantBillingSentSuccess
                    : l10n.adminMerchantBillingSavedSuccess
              : l10n.adminMerchantBillingSaveFailed,
        ),
      ),
    );

    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  InputDecoration _decoration(BuildContext context, String label) {
    return InputDecoration(labelText: label);
  }

  String? _validateAmount(String? value) {
    final l10n = context.l10n;
    final parsed = _parseDoubleInput((value ?? '').trim());
    if (parsed == null || parsed < 0) {
      return l10n.adminMerchantBillingInvalidValue;
    }
    return null;
  }

  String? _validatePercentage(String? value) {
    final invalid = _validateAmount(value);
    if (invalid != null) return invalid;
    final parsed = _parseDoubleInput((value ?? '').trim()) ?? 0;
    if (parsed > 100) {
      return context.l10n.adminMerchantBillingRateRange;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.approvalMode
              ? l10n.adminMerchantBillingApprovalTitle
              : l10n.adminMerchantBillingSettingsTitle,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      title: Text(widget.merchantName),
                      subtitle: Text(
                        '${l10n.commonId}: ${widget.merchantId}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _commissionType,
                    decoration: _decoration(
                      context,
                      l10n.adminMerchantBillingCommissionType,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'percentage',
                        child: Text(
                          _commissionTypeLabel(context, 'percentage'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text(_commissionTypeLabel(context, 'fixed')),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _commissionType = value ?? 'percentage'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _commissionModel,
                    decoration: _decoration(
                      context,
                      context.lt(
                        ar: 'نموذج العمولة',
                        en: 'Commission model',
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'percentage',
                        child: Text(
                          _commissionModelLabel(context, 'percentage'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'monthly_subscription',
                        child: Text(
                          _commissionModelLabel(
                            context,
                            'monthly_subscription',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(
                      () => _commissionModel = value ?? 'percentage',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _commissionValueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoration(
                      context,
                      _commissionModel == 'monthly_subscription'
                          ? context.lt(
                              ar: 'قيمة الاشتراك الشهري',
                              en: 'Monthly subscription amount',
                            )
                          : (_commissionType == 'percentage'
                              ? l10n.adminMerchantBillingCommissionValuePercentage
                              : l10n.adminMerchantBillingCommissionValueFixed),
                    ),
                    validator: _commissionModel == 'monthly_subscription'
                        ? _validateAmount
                        : (_commissionType == 'percentage'
                            ? _validatePercentage
                            : _validateAmount),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _serviceFeeType,
                    decoration: _decoration(
                      context,
                      l10n.adminMerchantBillingServiceFeeType,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text(_serviceFeeTypeLabel(context, 'fixed')),
                      ),
                      DropdownMenuItem(
                        value: 'percentage',
                        child: Text(
                          _serviceFeeTypeLabel(context, 'percentage'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'per_order',
                        child: Text(
                          _serviceFeeTypeLabel(context, 'per_order'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'global_rule',
                        child: Text(
                          _serviceFeeTypeLabel(context, 'global_rule'),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _serviceFeeType = value ?? 'fixed'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _serviceValueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoration(
                      context,
                      l10n.adminMerchantBillingServiceFeeValue,
                    ),
                    validator: _serviceFeeType == 'percentage'
                        ? _validatePercentage
                        : _validateAmount,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _deliveryFeeMode,
                    decoration: _decoration(
                      context,
                      l10n.adminMerchantBillingDeliveryFeeMode,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'dynamic',
                        child: Text(_deliveryFeeModeLabel(context, 'dynamic')),
                      ),
                      DropdownMenuItem(
                        value: 'app_defined',
                        child: Text(
                          _deliveryFeeModeLabel(context, 'app_defined'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'store_defined',
                        child: Text(
                          _deliveryFeeModeLabel(context, 'store_defined'),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _deliveryFeeMode = value ?? 'dynamic'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _appDeliveryValueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoration(
                      context,
                      l10n.adminMerchantBillingAppDeliveryFeeValue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _storeDeliveryValueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoration(
                      context,
                      l10n.adminMerchantBillingStoreDeliveryFeeValue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: _appDeliveryEnabled,
                    onChanged: (value) =>
                        setState(() => _appDeliveryEnabled = value),
                    title: Text(l10n.adminMerchantBillingEnableAppDelivery),
                  ),
                  SwitchListTile.adaptive(
                    value: _merchantDeliveryEnabled,
                    onChanged: (value) =>
                        setState(() => _merchantDeliveryEnabled = value),
                    title: Text(l10n.adminMerchantBillingEnableMerchantDelivery),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _graceDaysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _decoration(
                      context,
                      l10n.adminMerchantBillingGracePeriodDays,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.adminMerchantBillingEffectiveFrom),
                    subtitle: Text(_effectiveFrom?.toLocal().toString() ?? '-'),
                    trailing: OutlinedButton.icon(
                      onPressed: _pickEffectiveFrom,
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text(l10n.commonChoose),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: Icon(
                      widget.approvalMode
                          ? Icons.send_rounded
                          : Icons.save_outlined,
                    ),
                    label: Text(
                      widget.approvalMode
                          ? l10n.adminMerchantBillingSendTerms
                          : l10n.adminMerchantBillingSaveSettings,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
