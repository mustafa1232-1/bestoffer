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
import '../../../core/utils/parsers.dart';
import '../../../core/utils/currency.dart';
import '../data/coupons_api.dart';

enum CouponManagerMode { superAdmin, owner }

class CouponManagementScreen extends ConsumerStatefulWidget {
  final CouponManagerMode mode;

  const CouponManagementScreen({super.key, required this.mode});

  @override
  ConsumerState<CouponManagementScreen> createState() =>
      _CouponManagementScreenState();
}

class _CouponManagementScreenState
    extends ConsumerState<CouponManagementScreen> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  final TextEditingController _discountValueCtrl = TextEditingController();
  final TextEditingController _minOrderTotalCtrl = TextEditingController(
    text: '0',
  );
  final TextEditingController _maxUsesCtrl = TextEditingController();

  bool _loadingCoupons = false;
  bool _loadingStats = false;
  bool _saving = false;
  bool _activeOnly = false;
  String _discountType = 'percent';
  DateTime? _validFrom;
  DateTime? _validUntil;
  final FormScrollCoordinator _scrollCoordinator = FormScrollCoordinator();
  final Map<String, String> _fieldErrors = <String, String>{};
  String? _formError;
  int _statsWindowDays = 30;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _coupons = const [];
  final Set<int> _busyCouponIds = <int>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(_refreshAll);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _descriptionCtrl.dispose();
    _discountValueCtrl.dispose();
    _minOrderTotalCtrl.dispose();
    _maxUsesCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  String? _fieldLabel(String field) {
    final l10n = context.l10n;
    switch (field) {
      case 'code':
        return l10n.couponManagementCodeLabel;
      case 'discountType':
        return l10n.couponManagementDiscountTypeLabel;
      case 'discountValue':
        return l10n.couponManagementDiscountValueLabel;
      case 'minOrderTotal':
        return l10n.couponManagementMinOrderTotalLabel;
      case 'maxUses':
        return l10n.couponManagementMaxUsesLabel;
      case 'validFrom':
        return l10n.couponManagementStartDateLabel;
      case 'validUntil':
        return l10n.couponManagementEndDateLabel;
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

  Future<void> _focusFirstError(Iterable<String> fields) {
    const ordered = <String>[
      'code',
      'discountType',
      'discountValue',
      'minOrderTotal',
      'maxUses',
      'validFrom',
      'validUntil',
    ];
    final wanted = fields.toSet();
    return _scrollCoordinator.focusFirstError(ordered.where(wanted.contains));
  }

  String? _couponCustomFieldError(String field, String? code) {
    final l10n = context.l10n;
    switch (code?.trim().toUpperCase()) {
      case 'PERCENT_DISCOUNT_TOO_HIGH':
        return l10n.couponValidationPercentMax;
      case 'INVALID_DATE_RANGE':
        return l10n.couponValidationDateRange;
      case 'SUPER_ADMIN_COUPON_MUST_BE_GLOBAL':
        return l10n.couponManagementGlobalOnlyError;
    }
    return null;
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadCoupons(), _loadStats()]);
  }

  Future<void> _loadCoupons() async {
    final l10n = context.l10n;
    setState(() => _loadingCoupons = true);
    try {
      final items = await ref
          .read(couponsApiProvider)
          .listCoupons(activeOnly: _activeOnly, limit: 200);
      if (!mounted) return;
      setState(() {
        _coupons = items;
        _loadingCoupons = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCoupons = false);
      _showSnack(mapAnyError(e, fallback: l10n.couponManagementLoadFailed));
    }
  }

  Future<void> _loadStats() async {
    final l10n = context.l10n;
    setState(() => _loadingStats = true);
    try {
      final data = await ref
          .read(couponsApiProvider)
          .getCouponStats(days: _statsWindowDays);
      if (!mounted) return;
      setState(() {
        _stats = data;
        _loadingStats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingStats = false);
      _showSnack(
        mapAnyError(e, fallback: l10n.couponManagementLoadStatsFailed),
      );
    }
  }

  Future<void> _createCoupon() async {
    final l10n = context.l10n;
    final code = _codeCtrl.text.trim().toUpperCase();
    final discountValue = tryParseLocalizedDouble(_discountValueCtrl.text.trim());
    final minOrderTotal =
        tryParseLocalizedDouble(_minOrderTotalCtrl.text.trim()) ?? 0;
    final maxUsesText = _maxUsesCtrl.text.trim();
    final maxUses = maxUsesText.isEmpty
        ? null
        : tryParseLocalizedInt(maxUsesText);
    final nextErrors = <String, String>{};

    if (code.isEmpty) {
      nextErrors['code'] = resolveFormFieldError(
        l10n: l10n,
        field: 'code',
        fieldLabel: _fieldLabel('code'),
      );
    }
    if (discountValue == null || discountValue <= 0) {
      nextErrors['discountValue'] = resolveFormFieldError(
        l10n: l10n,
        field: 'discountValue',
        code: 'INVALID_NUMBER',
        fieldLabel: _fieldLabel('discountValue'),
      );
    }
    if (_discountType == 'percent' &&
        discountValue != null &&
        discountValue > 100) {
      nextErrors['discountValue'] = l10n.couponValidationPercentMax;
    }
    if (minOrderTotal < 0) {
      nextErrors['minOrderTotal'] = resolveFormFieldError(
        l10n: l10n,
        field: 'minOrderTotal',
        code: 'INVALID_NUMBER',
        fieldLabel: _fieldLabel('minOrderTotal'),
      );
    }
    if (maxUsesText.isNotEmpty && (maxUses == null || maxUses <= 0)) {
      nextErrors['maxUses'] = resolveFormFieldError(
        l10n: l10n,
        field: 'maxUses',
        code: 'INVALID_NUMBER',
        fieldLabel: _fieldLabel('maxUses'),
      );
    }
    if (_validFrom != null &&
        _validUntil != null &&
        _validUntil!.isBefore(_validFrom!)) {
      nextErrors['validUntil'] = l10n.couponValidationDateRange;
    }

    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(nextErrors);
        _formError = l10n.validationReviewRequiredFields;
      });
      await _focusFirstError(nextErrors.keys);
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
      _fieldErrors.clear();
    });

    try {
      await ref.read(couponsApiProvider).createCoupon({
        'code': code,
        if (_descriptionCtrl.text.trim().isNotEmpty)
          'description': _descriptionCtrl.text.trim(),
        'discountType': _discountType,
        'discountValue': discountValue,
        'minOrderTotal': minOrderTotal,
        ...?(maxUses == null ? null : {'maxUses': maxUses}),
        ...?(_validFrom == null
            ? null
            : {'validFrom': _validFrom!.toUtc().toIso8601String()}),
        ...?(_validUntil == null
            ? null
            : {'validUntil': _validUntil!.toUtc().toIso8601String()}),
      });

      _codeCtrl.clear();
      _descriptionCtrl.clear();
      _discountValueCtrl.clear();
      _maxUsesCtrl.clear();
      _minOrderTotalCtrl.text = '0';
      _validFrom = null;
      _validUntil = null;

      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack(l10n.couponManagementCreatedSuccess);
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      final parsed = parseBackendFieldErrors(e);
      final backendErrors = <String, String>{};
      if (parsed.hasAnyErrors) {
        for (final entry in parsed.fieldCodes.entries) {
          if (entry.key == '_form') continue;
          backendErrors[entry.key] = resolveFormFieldError(
            l10n: l10n,
            field: entry.key,
            code: entry.value,
            fieldLabel: _fieldLabel(entry.key),
            customResolver: (l10n, field, code) =>
                _couponCustomFieldError(field, code),
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
            fallback: mapAnyError(
              e,
              fallback: l10n.couponManagementCreateFailed,
            ),
          );
        } else {
          _formError = mapAnyError(
            e,
            fallback: l10n.couponManagementCreateFailed,
          );
        }
      });
      if (backendErrors.isNotEmpty) {
        await _focusFirstError(backendErrors.keys);
      }
    }
  }

  Future<void> _toggleCoupon(int couponId, bool isActive) async {
    final l10n = context.l10n;
    if (_busyCouponIds.contains(couponId)) return;
    setState(() => _busyCouponIds.add(couponId));
    try {
      await ref
          .read(couponsApiProvider)
          .toggleCouponActive(couponId: couponId, isActive: isActive);
      if (!mounted) return;
      setState(() {
        _busyCouponIds.remove(couponId);
        _coupons = _coupons
            .map((item) {
              if (_readInt(item['id']) != couponId) return item;
              return {...item, 'is_active': isActive, 'isActive': isActive};
            })
            .toList(growable: false);
      });
      await _loadStats();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyCouponIds.remove(couponId));
      _showSnack(mapAnyError(e, fallback: l10n.couponManagementToggleFailed));
    }
  }

  Future<void> _deleteCoupon(int couponId) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.couponManagementDeleteTitle),
          content: Text(l10n.couponManagementDeleteMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    if (_busyCouponIds.contains(couponId)) return;
    setState(() => _busyCouponIds.add(couponId));
    try {
      await ref.read(couponsApiProvider).deleteCoupon(couponId);
      if (!mounted) return;
      setState(() {
        _busyCouponIds.remove(couponId);
        _coupons = _coupons
            .where((item) => _readInt(item['id']) != couponId)
            .toList(growable: false);
      });
      _showSnack(l10n.couponManagementDeletedSuccess);
      await _loadStats();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyCouponIds.remove(couponId));
      _showSnack(mapAnyError(e, fallback: l10n.couponManagementDeleteFailed));
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_validFrom ?? now)
        : (_validUntil ?? _validFrom ?? now);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      initialDate: initial,
      locale: Localizations.localeOf(context),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _validFrom = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        _fieldErrors.remove('validFrom');
      } else {
        _validUntil = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
        _fieldErrors.remove('validUntil');
      }
      if (_fieldErrors.isEmpty) {
        _formError = null;
      }
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _scopeText(Map<String, dynamic> coupon) {
    final l10n = context.l10n;
    final merchantId = _readNullableInt(
      coupon['merchant_id'] ?? coupon['merchantId'],
    );
    final merchantName =
        '${coupon['merchant_name'] ?? coupon['merchantName'] ?? ''}'.trim();
    if (merchantId == null || merchantId <= 0) {
      return l10n.couponManagementScopeAllMerchants;
    }
    if (merchantName.isNotEmpty) {
      return l10n.couponManagementScopeMerchantNamed(merchantName);
    }
    return l10n.couponManagementScopeMerchantById(merchantId);
  }

  Future<void> _showCouponDetails(Map<String, dynamic> coupon) async {
    final code = '${coupon['code'] ?? ''}'.trim();
    final completedOrders = _readInt(
      coupon['completed_orders_count'] ?? coupon['completedOrdersCount'],
    );
    final grossSales = _readDouble(
      coupon['gross_sales_total'] ?? coupon['grossSalesTotal'],
    );
    final discountTotal = _readDouble(
      coupon['discount_total'] ?? coupon['discountTotal'],
    );
    final netSales = _readDouble(
      coupon['net_sales_total'] ?? coupon['netSalesTotal'],
    );
    final avgOrderValue = _readDouble(
      coupon['avg_order_value'] ?? coupon['avgOrderValue'],
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  code.isEmpty ? 'تفاصيل الكوبون' : 'تفاصيل الكوبون $code',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 12),
                _DetailRow('عدد الطلبات المكتملة', '$completedOrders'),
                _DetailRow('إجمالي المبيعات المرتبطة', formatIqd(grossSales)),
                _DetailRow(
                  'إجمالي الخصومات الممنوحة',
                  formatIqd(discountTotal),
                ),
                _DetailRow('صافي المبيعات بعد الخصومات', formatIqd(netSales)),
                _DetailRow('متوسط قيمة الطلب', formatIqd(avgOrderValue)),
                _DetailRow('النطاق', _scopeText(coupon)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSuperAdmin = widget.mode == CouponManagerMode.superAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isSuperAdmin
              ? l10n.couponManagementTitleAdmin
              : l10n.couponManagementTitleOwner,
        ),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _loadingCoupons || _loadingStats ? null : _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: context.appTextDirection,
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _buildStatsCard(),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FormErrorBanner(message: _formError),
                      Text(
                        isSuperAdmin
                            ? l10n.couponManagementCreateGlobalDescription
                            : l10n.couponManagementCreateOwnerDescription,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        focusNode: _scrollCoordinator.focusNodeFor('code'),
                        onChanged: (_) => _clearFieldError('code'),
                        decoration: InputDecoration(
                          errorText: _fieldErrors['code'],
                          labelText: l10n.couponManagementCodeLabel,
                          hintText: l10n.couponManagementCodeHint,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _descriptionCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.couponManagementDescriptionLabel,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _discountType,
                              decoration: InputDecoration(
                                labelText:
                                    l10n.couponManagementDiscountTypeLabel,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'percent',
                                  child: Text(
                                    l10n.couponManagementDiscountTypePercentOption,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'fixed',
                                  child: Text(
                                    l10n.couponManagementDiscountTypeFixedOption,
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setState(
                                  () => _discountType = value ?? 'percent',
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _discountValueCtrl,
                              focusNode: _scrollCoordinator.focusNodeFor(
                                'discountValue',
                              ),
                              onChanged: (_) =>
                                  _clearFieldError('discountValue'),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                errorText: _fieldErrors['discountValue'],
                                labelText:
                                    l10n.couponManagementDiscountValueLabel,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _minOrderTotalCtrl,
                              focusNode: _scrollCoordinator.focusNodeFor(
                                'minOrderTotal',
                              ),
                              onChanged: (_) =>
                                  _clearFieldError('minOrderTotal'),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                errorText: _fieldErrors['minOrderTotal'],
                                labelText:
                                    l10n.couponManagementMinOrderTotalLabel,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _maxUsesCtrl,
                              focusNode: _scrollCoordinator.focusNodeFor(
                                'maxUses',
                              ),
                              onChanged: (_) => _clearFieldError('maxUses'),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                errorText: _fieldErrors['maxUses'],
                                labelText: l10n.couponManagementMaxUsesLabel,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(isFrom: true),
                              icon: const Icon(Icons.event_available_rounded),
                              label: Text(
                                _validFrom == null
                                    ? l10n.couponManagementStartDateLabel
                                    : 'من: ${_validFrom!.toLocal().toString().split(' ').first}',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(isFrom: false),
                              icon: const Icon(Icons.event_busy_rounded),
                              label: Text(
                                _validUntil == null
                                    ? l10n.couponManagementEndDateLabel
                                    : 'إلى: ${_validUntil!.toLocal().toString().split(' ').first}',
                              ),
                            ),
                          ),
                        ],
                      ),
                      InlineFieldErrorText(
                        text:
                            _fieldErrors['validFrom'] ??
                            _fieldErrors['validUntil'],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _saving ? null : _createCoupon,
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_circle_outline),
                        label: Text(l10n.couponManagementCreateAction),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _activeOnly,
                onChanged: (value) async {
                  setState(() => _activeOnly = value);
                  await _loadCoupons();
                },
                title: Text(l10n.couponManagementActiveOnly),
              ),
              const SizedBox(height: 6),
              if (_loadingCoupons)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_coupons.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      l10n.couponManagementEmpty,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ..._coupons.map((coupon) {
                  final couponId = _readInt(coupon['id']);
                  final code = '${coupon['code'] ?? ''}'.trim();
                  final description = '${coupon['description'] ?? ''}'.trim();
                  final discountType =
                      '${coupon['discount_type'] ?? coupon['discountType'] ?? ''}'
                          .trim();
                  final discountValue = _readDouble(
                    coupon['discount_value'] ?? coupon['discountValue'],
                  );
                  final minOrderTotal = _readDouble(
                    coupon['min_order_total'] ?? coupon['minOrderTotal'],
                  );
                  final usesCount = _readInt(
                    coupon['uses_count'] ?? coupon['usesCount'],
                  );
                  final maxUses = _readNullableInt(
                    coupon['max_uses'] ?? coupon['maxUses'],
                  );
                  final isActive = _readBool(
                    coupon['is_active'] ?? coupon['isActive'],
                  );
                  final busy = _busyCouponIds.contains(couponId);

                  return Card(
                    child: ListTile(
                      onTap: () => _showCouponDetails(coupon),
                      title: Text(
                        code.isEmpty
                            ? l10n.couponManagementCouponFallback(couponId)
                            : code,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        [
                          if (description.isNotEmpty) description,
                          l10n.couponManagementTypeLine(
                            discountType == 'percent'
                                ? l10n.couponManagementDiscountTypePercentOption
                                : l10n.couponManagementDiscountTypeFixedOption,
                          ),
                          l10n.couponManagementDiscountLine(
                            discountType == 'percent'
                                ? '$discountValue%'
                                : formatIqd(discountValue),
                          ),
                          l10n.couponManagementMinOrderLine(
                            formatIqd(minOrderTotal),
                          ),
                          l10n.couponManagementUsageLine(
                            maxUses == null
                                ? '$usesCount'
                                : '$usesCount/$maxUses',
                          ),
                          l10n.couponManagementScopeLine(_scopeText(coupon)),
                        ].join('\n'),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Switch(
                            value: isActive,
                            onChanged: busy
                                ? null
                                : (value) => _toggleCoupon(couponId, value),
                          ),
                          IconButton(
                            tooltip: l10n.commonDelete,
                            onPressed: busy
                                ? null
                                : () => _deleteCoupon(couponId),
                            icon: const Icon(Icons.delete_outline),
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
    );
  }

  Widget _buildStatsCard() {
    final totals = _readMap(_stats?['totals']);
    final performance = _readMap(_stats?['performance']);
    final topCoupons = _readList(_stats?['topCoupons']);

    final usageRate = _readNullableDouble(performance['usageRate']);
    final avgDiscountPerUse = _readDouble(performance['avgDiscountPerUse']);
    final totalCoupons = _readInt(totals['totalCoupons']);
    final activeCoupons = _readInt(totals['activeCoupons']);
    final totalUses = _readInt(totals['totalUses']);
    final totalDiscountGiven = _readDouble(totals['totalDiscountGiven']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.insights_rounded),
                SizedBox(width: 8),
                Text(
                  'تقارير الكوبونات',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [14, 30, 90].map((days) {
                return ChoiceChip(
                  selected: _statsWindowDays == days,
                  label: Text('آخر $days يوم'),
                  onSelected: (value) async {
                    if (!value || _statsWindowDays == days) return;
                    setState(() => _statsWindowDays = days);
                    await _loadStats();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            if (_loadingStats)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricTile(
                    label: 'إجمالي الكوبونات',
                    value: '$totalCoupons',
                    icon: Icons.confirmation_number_outlined,
                  ),
                  _MetricTile(
                    label: 'الكوبونات النشطة',
                    value: '$activeCoupons',
                    icon: Icons.verified_outlined,
                    accent: Colors.green,
                  ),
                  _MetricTile(
                    label: 'مرات الاستخدام',
                    value: '$totalUses',
                    icon: Icons.local_offer_outlined,
                  ),
                  _MetricTile(
                    label: 'إجمالي الخصم',
                    value: formatIqd(totalDiscountGiven),
                    icon: Icons.savings_outlined,
                    accent: Colors.teal,
                  ),
                  _MetricTile(
                    label: 'متوسط الخصم/استخدام',
                    value: formatIqd(avgDiscountPerUse),
                    icon: Icons.calculate_outlined,
                  ),
                  _MetricTile(
                    label: 'معدل الاستغلال',
                    value: usageRate == null
                        ? '--'
                        : '${usageRate.toStringAsFixed(1)}%',
                    icon: Icons.show_chart_rounded,
                    accent: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'أعلى الكوبونات استخدامًا',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              if (topCoupons.isEmpty)
                Text(
                  'لا توجد بيانات استخدام حتى الآن.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                )
              else
                ...topCoupons.take(5).map((entry) {
                  final code = '${entry['code'] ?? ''}'.trim();
                  final uses = _readInt(
                    entry['uses_count'] ?? entry['usesCount'],
                  );
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 14,
                      child: Text(
                        '${topCoupons.indexOf(entry) + 1}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    title: Text(
                      code.isEmpty ? 'Coupon #${_readInt(entry['id'])}' : code,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(_scopeText(entry)),
                    trailing: Text(
                      '$uses استخدام',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return tryParseLocalizedInt(value) ?? 0;
  }

  int? _readNullableInt(dynamic value) {
    final parsed = _readInt(value);
    return parsed <= 0 ? null : parsed;
  }

  double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return tryParseLocalizedDouble(value) ?? 0;
  }

  double? _readNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return tryParseLocalizedDouble(value);
  }

  bool _readBool(dynamic value) {
    if (value == true) return true;
    final normalized = '$value'.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  Map<String, dynamic> _readMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, entry) => MapEntry('$key', entry));
    }
    return const {};
  }

  List<Map<String, dynamic>> _readList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((e) => _readMap(e)).toList();
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Colors.lightBlueAccent;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              color.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.72),
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
          ),
        ],
      ),
    );
  }
}
