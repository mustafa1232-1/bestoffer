// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../company_portal_text.dart';
import '../data/company_api.dart';
import '../models/company_models.dart';
import 'widgets/company_ui.dart';

class CompanySettingsScreen extends StatefulWidget {
  final CompanyApi api;
  final int companyId;
  final CompanyMembership activeMembership;
  final VoidCallback onLogout;

  const CompanySettingsScreen({
    super.key,
    required this.api,
    required this.companyId,
    required this.activeMembership,
    required this.onLogout,
  });

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  Future<CompanyHomeData>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.dashboard(widget.companyId);
  }

  @override
  void didUpdateWidget(covariant CompanySettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _future = widget.api.dashboard(widget.companyId);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.api.dashboard(widget.companyId);
    });
    await _future;
  }

  Future<void> _editPolicy(CompanyPolicy? policy) async {
    final l10n = context.l10n;
    final current =
        policy ??
        const CompanyPolicy(
          commissionRate: null,
          serviceFeeMode: null,
          serviceFeeValue: null,
          deliveryFeeMode: null,
          deliveryFeeValue: null,
          appDeliveryEnabled: null,
          merchantDeliveryEnabled: null,
          settlementCycle: null,
          inventoryEnabled: false,
          inventoryUpdateMode: 'manual_override',
          lowStockThreshold: 5,
          autoDisableOutOfStock: true,
          showAllWithoutAutoDisable: false,
        );
    final commissionController = TextEditingController(
      text: current.commissionRate?.toString() ?? '',
    );
    final serviceValueController = TextEditingController(
      text: current.serviceFeeValue?.toString() ?? '',
    );
    final deliveryValueController = TextEditingController(
      text: current.deliveryFeeValue?.toString() ?? '',
    );
    final thresholdController = TextEditingController(
      text: '${current.lowStockThreshold}',
    );
    final scrollCoordinator = FormScrollCoordinator();
    final fieldErrors = <String, String>{};
    String? formError;
    var saving = false;
    var dialogClosed = false;
    var serviceFeeMode = current.serviceFeeMode ?? 'fixed';
    var deliveryFeeMode = current.deliveryFeeMode ?? 'fixed';
    var settlementCycle = current.settlementCycle ?? 'weekly';
    var inventoryEnabled = current.inventoryEnabled;
    var inventoryUpdateMode = current.inventoryUpdateMode;
    var autoDisable = current.autoDisableOutOfStock;
    var showAll = current.showAllWithoutAutoDisable;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> submit() async {
            if (saving) return;
            final nextErrors = <String, String>{};
            if (commissionController.text.trim().isNotEmpty &&
                double.tryParse(commissionController.text.trim()) == null) {
              nextErrors['commissionRate'] = resolveFormFieldError(
                l10n: l10n,
                field: 'commissionRate',
                code: 'INVALID_NUMBER',
                fieldLabel: l10n.companySettingsCommissionRate,
              );
            }
            if (serviceValueController.text.trim().isNotEmpty &&
                double.tryParse(serviceValueController.text.trim()) == null) {
              nextErrors['serviceFeeValue'] = resolveFormFieldError(
                l10n: l10n,
                field: 'serviceFeeValue',
                code: 'INVALID_NUMBER',
                fieldLabel: l10n.companySettingsServiceFeeValue,
              );
            }
            if (deliveryValueController.text.trim().isNotEmpty &&
                double.tryParse(deliveryValueController.text.trim()) == null) {
              nextErrors['deliveryFeeValue'] = resolveFormFieldError(
                l10n: l10n,
                field: 'deliveryFeeValue',
                code: 'INVALID_NUMBER',
                fieldLabel: l10n.companySettingsDeliveryFeeValue,
              );
            }
            if (int.tryParse(thresholdController.text.trim()) == null) {
              nextErrors['lowStockThreshold'] = resolveFormFieldError(
                l10n: l10n,
                field: 'lowStockThreshold',
                code: 'INVALID_NUMBER',
                fieldLabel: l10n.companySettingsLowStockThreshold,
              );
            }

            if (nextErrors.isNotEmpty) {
              fieldErrors
                ..clear()
                ..addAll(nextErrors);
              setModalState(
                () => formError = l10n.validationReviewRequiredFields,
              );
              await scrollCoordinator.focusFirstError(nextErrors.keys);
              return;
            }

            setModalState(() {
              saving = true;
              formError = null;
              fieldErrors.clear();
            });

            try {
              await widget.api.updatePolicy(widget.companyId, {
                'commissionRate': double.tryParse(
                  commissionController.text.trim(),
                ),
                'serviceFeeMode': serviceFeeMode,
                'serviceFeeValue': double.tryParse(
                  serviceValueController.text.trim(),
                ),
                'deliveryFeeMode': deliveryFeeMode,
                'deliveryFeeValue': double.tryParse(
                  deliveryValueController.text.trim(),
                ),
                'settlementCycle': settlementCycle,
                'inventoryEnabled': inventoryEnabled,
                'inventoryUpdateMode': inventoryUpdateMode,
                'lowStockThreshold':
                    int.tryParse(thresholdController.text.trim()) ?? 5,
                'autoDisableOutOfStock': autoDisable,
                'showAllWithoutAutoDisable': showAll,
              });
              if (!mounted) return;
              dialogClosed = true;
              Navigator.of(context).pop(true);
            } on Exception catch (e) {
              final parsed = parseBackendFieldErrors(e);
              if (parsed.hasFieldErrors || parsed.formCode != null) {
                fieldErrors.clear();
                if (parsed.fieldCodes.containsKey('commissionRate')) {
                  fieldErrors['commissionRate'] = resolveFormFieldError(
                    l10n: l10n,
                    field: 'commissionRate',
                    code: parsed.codeFor('commissionRate'),
                    fieldLabel: l10n.companySettingsCommissionRate,
                  );
                }
                if (parsed.fieldCodes.containsKey('serviceFeeValue')) {
                  fieldErrors['serviceFeeValue'] = resolveFormFieldError(
                    l10n: l10n,
                    field: 'serviceFeeValue',
                    code: parsed.codeFor('serviceFeeValue'),
                    fieldLabel: l10n.companySettingsServiceFeeValue,
                  );
                }
                if (parsed.fieldCodes.containsKey('deliveryFeeValue')) {
                  fieldErrors['deliveryFeeValue'] = resolveFormFieldError(
                    l10n: l10n,
                    field: 'deliveryFeeValue',
                    code: parsed.codeFor('deliveryFeeValue'),
                    fieldLabel: l10n.companySettingsDeliveryFeeValue,
                  );
                }
                if (parsed.fieldCodes.containsKey('lowStockThreshold')) {
                  fieldErrors['lowStockThreshold'] = resolveFormFieldError(
                    l10n: l10n,
                    field: 'lowStockThreshold',
                    code: parsed.codeFor('lowStockThreshold'),
                    fieldLabel: l10n.companySettingsLowStockThreshold,
                  );
                }
                setModalState(() {
                  formError = resolveFormLevelError(
                    l10n,
                    code: parsed.formCode ?? parsed.messageCode,
                    fallback: l10n.validationReviewRequiredFields,
                  );
                });
                await scrollCoordinator.focusFirstError(fieldErrors.keys);
              } else {
                setModalState(() {
                  formError = mapAnyErrorL10n(
                    e,
                    fallbackBuilder: (l10n) => l10n.errorsUnknown,
                  );
                });
              }
            } finally {
              if (mounted && !dialogClosed) {
                setModalState(() => saving = false);
              }
            }
          }

          return AlertDialog(
            title: Text(l10n.companySettingsEditPolicyTitle),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FormErrorBanner(message: formError),
                    scrollCoordinator.anchor(
                      'commissionRate',
                      TextField(
                        controller: commissionController,
                        focusNode: scrollCoordinator.focusNodeFor(
                          'commissionRate',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) {
                          final removed =
                              fieldErrors.remove('commissionRate') != null;
                          if (removed && formError != null) {
                            setModalState(() => formError = null);
                          } else if (removed) {
                            setModalState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          labelText: l10n.companySettingsCommissionRate,
                          errorText: fieldErrors['commissionRate'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: serviceFeeMode,
                      decoration: InputDecoration(
                        labelText: l10n.companySettingsServiceFeeMode,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'fixed',
                          child: Text(l10n.companySettingsServiceFeeFixed),
                        ),
                        DropdownMenuItem(
                          value: 'percent',
                          child: Text(l10n.companySettingsServiceFeePercent),
                        ),
                      ],
                      onChanged: (value) => setModalState(
                        () => serviceFeeMode = value ?? serviceFeeMode,
                      ),
                    ),
                    const SizedBox(height: 12),
                    scrollCoordinator.anchor(
                      'serviceFeeValue',
                      TextField(
                        controller: serviceValueController,
                        focusNode: scrollCoordinator.focusNodeFor(
                          'serviceFeeValue',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) {
                          final removed =
                              fieldErrors.remove('serviceFeeValue') != null;
                          if (removed && formError != null) {
                            setModalState(() => formError = null);
                          } else if (removed) {
                            setModalState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          labelText: l10n.companySettingsServiceFeeValue,
                          errorText: fieldErrors['serviceFeeValue'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: deliveryFeeMode,
                      decoration: InputDecoration(
                        labelText: l10n.companySettingsDeliveryFeeMode,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'fixed',
                          child: Text(l10n.companySettingsServiceFeeFixed),
                        ),
                        DropdownMenuItem(
                          value: 'percent',
                          child: Text(l10n.companySettingsServiceFeePercent),
                        ),
                      ],
                      onChanged: (value) => setModalState(
                        () => deliveryFeeMode = value ?? deliveryFeeMode,
                      ),
                    ),
                    const SizedBox(height: 12),
                    scrollCoordinator.anchor(
                      'deliveryFeeValue',
                      TextField(
                        controller: deliveryValueController,
                        focusNode: scrollCoordinator.focusNodeFor(
                          'deliveryFeeValue',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) {
                          final removed =
                              fieldErrors.remove('deliveryFeeValue') != null;
                          if (removed && formError != null) {
                            setModalState(() => formError = null);
                          } else if (removed) {
                            setModalState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          labelText: l10n.companySettingsDeliveryFeeValue,
                          errorText: fieldErrors['deliveryFeeValue'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: settlementCycle,
                      decoration: InputDecoration(
                        labelText: l10n.companySettingsSettlementCycle,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'daily',
                          child: Text(l10n.companySettingsSettlementDaily),
                        ),
                        DropdownMenuItem(
                          value: 'weekly',
                          child: Text(l10n.companySettingsSettlementWeekly),
                        ),
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text(l10n.companySettingsSettlementMonthly),
                        ),
                      ],
                      onChanged: (value) => setModalState(
                        () => settlementCycle = value ?? settlementCycle,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: inventoryEnabled,
                      onChanged: (value) =>
                          setModalState(() => inventoryEnabled = value),
                      title: Text(l10n.companySettingsInventoryEnabledDefault),
                    ),
                    DropdownButtonFormField<String>(
                      value: inventoryUpdateMode,
                      decoration: InputDecoration(
                        labelText: l10n.companySettingsInventoryUpdateMode,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'strict_daily',
                          child: Text(
                            companyInventoryModeLabel(context, 'strict_daily'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'soft_reminder',
                          child: Text(
                            companyInventoryModeLabel(context, 'soft_reminder'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'manual_override',
                          child: Text(
                            companyInventoryModeLabel(
                              context,
                              'manual_override',
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) => setModalState(
                        () =>
                            inventoryUpdateMode = value ?? inventoryUpdateMode,
                      ),
                    ),
                    const SizedBox(height: 12),
                    scrollCoordinator.anchor(
                      'lowStockThreshold',
                      TextField(
                        controller: thresholdController,
                        focusNode: scrollCoordinator.focusNodeFor(
                          'lowStockThreshold',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) {
                          final removed =
                              fieldErrors.remove('lowStockThreshold') != null;
                          if (removed && formError != null) {
                            setModalState(() => formError = null);
                          } else if (removed) {
                            setModalState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          labelText: l10n.companySettingsLowStockThreshold,
                          errorText: fieldErrors['lowStockThreshold'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: autoDisable,
                      onChanged: (value) =>
                          setModalState(() => autoDisable = value),
                      title: Text(l10n.companySettingsAutoDisableOutOfStock),
                    ),
                    SwitchListTile.adaptive(
                      value: showAll,
                      onChanged: (value) =>
                          setModalState(() => showAll = value),
                      title: Text(
                        l10n.companySettingsShowAllWithoutAutoDisable,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: saving ? null : submit,
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.commonSave),
              ),
            ],
          );
        },
      ),
    );
    commissionController.dispose();
    serviceValueController.dispose();
    deliveryValueController.dispose();
    thresholdController.dispose();
    scrollCoordinator.dispose();
    if (saved == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<CompanyHomeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CompanyEmptyState(
            icon: Icons.settings_outlined,
            title: l10n.companySettingsLoadFailed,
            description: '${snapshot.error}',
            action: FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.commonRetry),
            ),
          );
        }
        final home = snapshot.data;
        if (home == null) {
          return CompanyEmptyState(
            icon: Icons.settings_outlined,
            title: l10n.companySettingsEmptyTitle,
            description: l10n.companySettingsEmptyDescription,
          );
        }
        final company = home.company;
        final policy = home.defaultPolicy;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CompanySectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanySectionHeader(
                      title: l10n.companySettingsTitle,
                      subtitle: l10n.companySettingsSubtitle,
                      actions: [
                        FilledButton.icon(
                          onPressed: () => _editPolicy(policy),
                          icon: const Icon(Icons.tune_rounded),
                          label: Text(l10n.companySettingsEditPolicy),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: 280,
                          child: CompanyInfoTile(
                            label: l10n.companyDashboardCompanyName,
                            value: company.name,
                            icon: Icons.apartment_rounded,
                          ),
                        ),
                        SizedBox(
                          width: 280,
                          child: CompanyInfoTile(
                            label: l10n.companySettingsCode,
                            value: company.code,
                            icon: Icons.qr_code_2_rounded,
                          ),
                        ),
                        SizedBox(
                          width: 280,
                          child: CompanyInfoTile(
                            label: l10n.companySettingsMyRole,
                            value: companyRoleLabel(
                              context,
                              widget.activeMembership.role,
                            ),
                            icon: Icons.verified_user_outlined,
                          ),
                        ),
                        SizedBox(
                          width: 280,
                          child: CompanyInfoTile(
                            label: l10n.commonStatus,
                            value: companyStatusLabel(context, company.status),
                            icon: Icons.shield_outlined,
                          ),
                        ),
                        if (company.primaryContactName?.isNotEmpty == true)
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardPrimaryContact,
                              value: company.primaryContactName!,
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                        if (company.contactPhone?.isNotEmpty == true)
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardContactPhone,
                              value: company.contactPhone!,
                              icon: Icons.phone_outlined,
                            ),
                          ),
                        if (company.headquartersAddress?.isNotEmpty == true)
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardHeadquarters,
                              value: company.headquartersAddress!,
                              icon: Icons.location_on_outlined,
                            ),
                          ),
                        if (company.summary?.isNotEmpty == true)
                          SizedBox(
                            width: 580,
                            child: CompanyInfoTile(
                              label: l10n.companyDashboardSummary,
                              value: company.summary!,
                              icon: Icons.notes_rounded,
                            ),
                          ),
                      ],
                    ),
                    if (policy != null) ...[
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          CompanyStatusChip(
                            label: l10n.companySettingsCommissionChip(
                              '${policy.commissionRate ?? 0}',
                            ),
                            color: Colors.lightBlueAccent,
                          ),
                          CompanyStatusChip(
                            label:
                                '${l10n.companyDashboardInventoryPolicy} ${companyInventoryModeLabel(context, policy.inventoryUpdateMode)}',
                            color: Colors.greenAccent.shade400,
                          ),
                          CompanyStatusChip(
                            label: policy.showAllWithoutAutoDisable
                                ? l10n.companySettingsShowAllChip
                                : l10n.companySettingsAutoDisableChip,
                            color: policy.showAllWithoutAutoDisable
                                ? Colors.orangeAccent
                                : Colors.greenAccent.shade400,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CompanySectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanySectionHeader(
                      title: l10n.companySettingsSessionTitle,
                      subtitle: l10n.companySettingsSessionDescription,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(l10n.companySettingsLogoutPortal),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
