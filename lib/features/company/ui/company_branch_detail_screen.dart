// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../company_portal_text.dart';
import '../models/company_models.dart';
import '../state/company_session_controller.dart';
import 'widgets/company_ui.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class CompanyBranchDetailScreen extends ConsumerStatefulWidget {
  final int companyId;
  final int merchantId;
  final String branchName;

  const CompanyBranchDetailScreen({
    super.key,
    required this.companyId,
    required this.merchantId,
    required this.branchName,
  });

  @override
  ConsumerState<CompanyBranchDetailScreen> createState() =>
      _CompanyBranchDetailScreenState();
}

class _CompanyBranchDetailScreenState
    extends ConsumerState<CompanyBranchDetailScreen> {
  Future<CompanyBranchDetail>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<CompanyBranchDetail> _load() {
    return ref
        .read(companyApiProvider)
        .branchDetail(widget.companyId, widget.merchantId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _editSettings(CompanyInventorySettings? settings) async {
    final l10n = context.l10n;
    final scrollCoordinator = FormScrollCoordinator();
    final initial =
        settings ??
        CompanyInventorySettings(
          merchantId: widget.merchantId,
          companyId: widget.companyId,
          inventoryEnabled: false,
          dailyUpdateMode: 'manual_override',
          lowStockThreshold: 5,
          autoDisableOutOfStock: true,
          showAllWithoutAutoDisable: false,
          lastDailyCheckAt: null,
          lastStockUpdateAt: null,
        );
    var inventoryEnabled = initial.inventoryEnabled;
    var autoDisable = initial.autoDisableOutOfStock;
    var showAll = initial.showAllWithoutAutoDisable;
    var dailyMode = initial.dailyUpdateMode;
    final thresholdController = TextEditingController(
      text: '${initial.lowStockThreshold}',
    );
    var fieldErrors = <String, String>{};
    var formError = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) {
          Future<void> submit() async {
            final threshold = int.tryParse(thresholdController.text.trim());
            if (threshold == null || threshold < 0) {
              setModalState(() {
                fieldErrors = {
                  'threshold': threshold == null
                      ? l10n.validationInvalidNumber
                      : l10n.validationMinValue('0'),
                };
                formError = l10n.validationReviewRequiredFields;
              });
              await scrollCoordinator.focusFirstError(const ['threshold']);
              return;
            }

            setModalState(() {
              fieldErrors = <String, String>{};
              formError = '';
            });

            try {
              await ref.read(companyApiProvider).updateInventorySettings(
                widget.companyId,
                widget.merchantId,
                {
                  'inventoryEnabled': inventoryEnabled,
                  'dailyUpdateMode': dailyMode,
                  'lowStockThreshold': threshold,
                  'autoDisableOutOfStock': autoDisable,
                  'showAllWithoutAutoDisable': showAll,
                },
              );
              if (!mounted) return;
              Navigator.of(dialogContext).pop(true);
            } catch (error) {
              if (!dialogContext.mounted) return;
              setModalState(() {
                formError = mapAnyError(
                  error,
                  fallback: l10n.companyBranchDetailInventorySettingsSaveFailed,
                );
              });
            }
          }

          return AlertDialog(
            title: Text(l10n.companyBranchDetailInventorySettingsTitle),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FormErrorBanner(
                      message: formError.isEmpty ? null : formError,
                    ),
                    SwitchListTile.adaptive(
                      value: inventoryEnabled,
                      onChanged: (value) =>
                          setModalState(() => inventoryEnabled = value),
                      title: Text(l10n.companyBranchDetailEnableInventoryTitle),
                      subtitle: Text(
                        l10n.companyBranchDetailEnableInventorySubtitle,
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      value: dailyMode,
                      decoration: InputDecoration(
                        labelText: l10n.companyBranchDetailDailyModeLabel,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'strict_daily',
                          child: Text(l10n.companyInventoryModeStrictDaily),
                        ),
                        DropdownMenuItem(
                          value: 'soft_reminder',
                          child: Text(l10n.companyInventoryModeSoftReminder),
                        ),
                        DropdownMenuItem(
                          value: 'manual_override',
                          child: Text(l10n.companyInventoryModeManualOverride),
                        ),
                      ],
                      onChanged: (value) =>
                          setModalState(() => dailyMode = value ?? dailyMode),
                    ),
                    const SizedBox(height: 12),
                    scrollCoordinator.anchor(
                      'threshold',
                      TextFormField(
                        controller: thresholdController,
                        focusNode: scrollCoordinator.focusNodeFor('threshold'),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText:
                              l10n.companyBranchDetailLowStockThresholdLabel,
                          errorText: fieldErrors['threshold'],
                        ),
                        onChanged: (_) {
                          if (fieldErrors.remove('threshold') != null ||
                              formError.isNotEmpty) {
                            setModalState(() => formError = '');
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: autoDisable,
                      onChanged: (value) =>
                          setModalState(() => autoDisable = value),
                      title: Text(
                        l10n.companyBranchDetailAutoDisableOutOfStockTitle,
                      ),
                    ),
                    SwitchListTile.adaptive(
                      value: showAll,
                      onChanged: (value) =>
                          setModalState(() => showAll = value),
                      title: Text(
                        l10n.companyBranchDetailShowAllWithoutDisableTitle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(onPressed: submit, child: Text(l10n.commonSave)),
            ],
          );
        },
      ),
    );
    thresholdController.dispose();
    scrollCoordinator.dispose();
    if (saved == true) {
      await _refresh();
    }
  }

  Future<void> _editItem(CompanyInventoryItem item) async {
    final l10n = context.l10n;
    final scrollCoordinator = FormScrollCoordinator();
    final quantityController = TextEditingController(text: '${item.quantity}');
    final thresholdController = TextEditingController(
      text: '${item.reorderThreshold ?? 5}',
    );
    var manualDisabled = item.manualDisabled;
    var fieldErrors = <String, String>{};
    var formError = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) {
          Future<void> submit() async {
            final quantity = int.tryParse(quantityController.text.trim());
            final threshold = int.tryParse(thresholdController.text.trim());
            final nextErrors = <String, String>{};
            if (quantity == null || quantity < 0) {
              nextErrors['quantity'] = quantity == null
                  ? l10n.validationInvalidNumber
                  : l10n.validationMinValue('0');
            }
            if (threshold == null || threshold < 0) {
              nextErrors['threshold'] = threshold == null
                  ? l10n.validationInvalidNumber
                  : l10n.validationMinValue('0');
            }
            if (nextErrors.isNotEmpty) {
              setModalState(() {
                fieldErrors = nextErrors;
                formError = l10n.validationReviewRequiredFields;
              });
              await scrollCoordinator.focusFirstError(
                const ['quantity', 'threshold'].where(nextErrors.containsKey),
              );
              return;
            }

            setModalState(() {
              fieldErrors = <String, String>{};
              formError = '';
            });

            try {
              await ref.read(companyApiProvider).patchInventoryItem(
                widget.companyId,
                widget.merchantId,
                item.productId,
                {
                  'quantity': quantity,
                  'reorderThreshold': threshold,
                  'manualDisabled': manualDisabled,
                },
              );
              if (!mounted) return;
              Navigator.of(dialogContext).pop(true);
            } catch (error) {
              if (!dialogContext.mounted) return;
              setModalState(() {
                formError = mapAnyError(
                  error,
                  fallback: l10n.companyBranchDetailItemSaveFailed,
                );
              });
            }
          }

          return AlertDialog(
            title: Text(item.productName),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FormErrorBanner(
                    message: formError.isEmpty ? null : formError,
                  ),
                  scrollCoordinator.anchor(
                    'quantity',
                    TextFormField(
                      controller: quantityController,
                      focusNode: scrollCoordinator.focusNodeFor('quantity'),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.companyBranchDetailQuantityLabel,
                        errorText: fieldErrors['quantity'],
                      ),
                      onChanged: (_) {
                        if (fieldErrors.remove('quantity') != null ||
                            formError.isNotEmpty) {
                          setModalState(() => formError = '');
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  scrollCoordinator.anchor(
                    'threshold',
                    TextFormField(
                      controller: thresholdController,
                      focusNode: scrollCoordinator.focusNodeFor('threshold'),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            l10n.companyBranchDetailReorderThresholdLabel,
                        errorText: fieldErrors['threshold'],
                      ),
                      onChanged: (_) {
                        if (fieldErrors.remove('threshold') != null ||
                            formError.isNotEmpty) {
                          setModalState(() => formError = '');
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: manualDisabled,
                    onChanged: (value) =>
                        setModalState(() => manualDisabled = value),
                    title: Text(l10n.companyBranchDetailManualDisableTitle),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(onPressed: submit, child: Text(l10n.commonSave)),
            ],
          );
        },
      ),
    );
    quantityController.dispose();
    thresholdController.dispose();
    scrollCoordinator.dispose();
    if (saved == true) {
      await _refresh();
    }
  }

  Future<void> _confirmDailyCheck() async {
    final l10n = context.l10n;
    final noteController = TextEditingController();
    var formError = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => AlertDialog(
          title: Text(l10n.companyBranchDetailConfirmDailyCheckTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FormErrorBanner(message: formError.isEmpty ? null : formError),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.companyBranchDetailCheckNoteLabel,
                ),
                onChanged: (_) {
                  if (formError.isEmpty) return;
                  setModalState(() => formError = '');
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await ref
                      .read(companyApiProvider)
                      .confirmDailyCheck(
                        widget.companyId,
                        widget.merchantId,
                        note: noteController.text.trim().isEmpty
                            ? null
                            : noteController.text.trim(),
                      );
                  if (!mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setModalState(() {
                    formError = mapAnyError(
                      error,
                      fallback: l10n.companyBranchDetailDailyCheckConfirmFailed,
                    );
                  });
                }
              },
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
    if (saved == true) {
      await _refresh();
    }
  }

  String _formatDate(BuildContext context, String? value) {
    if (value == null || value.isEmpty) {
      return context.l10n.companyBranchDetailNotAvailable;
    }
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return DateFormat('yyyy/MM/dd HH:mm').format(date.toLocal());
  }

  Color _stockColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'out_of_stock':
        return scheme.error;
      case 'low_stock':
        return Colors.orangeAccent;
      case 'manual_disabled':
        return Colors.deepPurpleAccent;
      default:
        return Colors.greenAccent.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.branchName),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<CompanyBranchDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return CompanyEmptyState(
              icon: Icons.error_outline_rounded,
              title: l10n.companyBranchDetailLoadFailedTitle,
              description: mapAnyError(
                snapshot.error!,
                fallback: l10n.companyBranchDetailLoadFailedDescription,
              ),
              action: FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.commonRetry),
              ),
            );
          }
          final detail = snapshot.data;
          if (detail == null) {
            return CompanyEmptyState(
              icon: Icons.store_mall_directory_outlined,
              title: l10n.companyBranchDetailEmptyTitle,
              description: l10n.companyBranchDetailEmptyDescription,
            );
          }
          final branch = detail.branch;
          final settings = detail.inventorySettings;
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
                        title: branch.name,
                        subtitle: l10n.companyBranchDetailHeaderSubtitle,
                        actions: [
                          CompanyStatusChip(
                            label: branch.inventoryEnabled
                                ? l10n.companyBranchDetailInventoryEnabledChip
                                : l10n.companyBranchDetailManualAvailabilityChip,
                            color: branch.inventoryEnabled
                                ? Colors.greenAccent.shade400
                                : Colors.orangeAccent,
                          ),
                          CompanyStatusChip(
                            label: branch.isApproved
                                ? l10n.commonApproved
                                : l10n.companyBranchesPendingApproval,
                            color: branch.isApproved
                                ? Colors.lightBlueAccent
                                : Colors.orangeAccent,
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
                              label: l10n.companyBranchDetailOwnerLabel,
                              value: branch.ownerFullName ?? l10n.commonNotSet,
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n.commonPhone,
                              value:
                                  branch.phone ??
                                  branch.ownerPhone ??
                                  l10n.commonNotSet,
                              icon: Icons.phone_rounded,
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label: l10n
                                  .companyBranchDetailLastInventoryUpdateLabel,
                              value: _formatDate(
                                context,
                                branch.lastInventoryUpdateAt,
                              ),
                              icon: Icons.inventory_2_outlined,
                            ),
                          ),
                          SizedBox(
                            width: 280,
                            child: CompanyInfoTile(
                              label:
                                  l10n.companyBranchDetailLastDailyCheckLabel,
                              value: _formatDate(
                                context,
                                branch.lastDailyCheckAt,
                              ),
                              icon: Icons.event_available_rounded,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width >= 1100
                      ? 4
                      : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                  children: [
                    CompanyMetricTile(
                      label: l10n.commonTotalOrders,
                      value: '${branch.totalOrders}',
                      icon: Icons.shopping_bag_outlined,
                    ),
                    CompanyMetricTile(
                      label: l10n.commonSales,
                      value: formatIqd(branch.grossSales),
                      icon: Icons.payments_outlined,
                      color: Colors.greenAccent.shade400,
                    ),
                    CompanyMetricTile(
                      label: l10n.commonOutstanding,
                      value: formatIqd(branch.outstandingAmount),
                      icon: Icons.account_balance_wallet_outlined,
                      color: Colors.orangeAccent,
                    ),
                    CompanyMetricTile(
                      label: l10n.companyBranchDetailOutOfStockItemsLabel,
                      value: '${branch.outOfStockItems}',
                      icon: Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CompanySectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CompanySectionHeader(
                        title: l10n.companyBranchDetailInventoryPolicyTitle,
                        subtitle:
                            l10n.companyBranchDetailInventoryPolicySubtitle,
                        actions: [
                          OutlinedButton.icon(
                            onPressed: () => _editSettings(settings),
                            icon: const Icon(Icons.tune_rounded),
                            label: Text(
                              l10n.companyBranchDetailEditSettingsAction,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _confirmDailyCheck,
                            icon: const Icon(Icons.fact_check_outlined),
                            label: Text(
                              l10n.companyBranchDetailConfirmTodayAction,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          CompanyStatusChip(
                            label: settings?.inventoryEnabled == true
                                ? l10n.companyBranchDetailInventoryEnabledChip
                                : l10n.companyBranchDetailInventoryDisabledChip,
                            color: settings?.inventoryEnabled == true
                                ? Colors.greenAccent.shade400
                                : Colors.orangeAccent,
                          ),
                          CompanyStatusChip(
                            label: l10n.companyBranchDetailModeChip(
                              companyInventoryModeLabel(
                                context,
                                settings?.dailyUpdateMode ??
                                    branch.dailyUpdateMode ??
                                    'manual_override',
                              ),
                            ),
                            color: Colors.lightBlueAccent,
                          ),
                          CompanyStatusChip(
                            label: l10n.companyBranchDetailThresholdChip(
                              settings?.lowStockThreshold ?? 5,
                            ),
                            color: Colors.deepPurpleAccent,
                          ),
                          CompanyStatusChip(
                            label: settings?.showAllWithoutAutoDisable == true
                                ? l10n.companyBranchDetailShowAllChip
                                : l10n.companyBranchDetailAutoDisableChip,
                            color: settings?.showAllWithoutAutoDisable == true
                                ? Colors.orangeAccent
                                : Colors.greenAccent.shade400,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                CompanySectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CompanySectionHeader(
                        title: l10n.companyBranchDetailInventoryItemsTitle,
                        subtitle: l10n
                            .companyBranchDetailInventoryItemsSubtitle(
                              detail.inventoryItems.length,
                              detail.products.length,
                              detail.categories.length,
                            ),
                      ),
                      const SizedBox(height: 16),
                      if (detail.inventoryItems.isEmpty)
                        CompanyEmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: l10n.companyBranchDetailInventoryEmptyTitle,
                          description:
                              l10n.companyBranchDetailInventoryEmptyDescription,
                        )
                      else
                        ...detail.inventoryItems.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _editItem(item),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: Colors.white.withValues(alpha: 0.04),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 54,
                                        height: 54,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.05,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: item.productImageUrl == null
                                            ? const Icon(Icons.fastfood_rounded)
                                            : ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: CachedAppImage(
                                                  imageUrl:
                                                      item.productImageUrl!,
                                                  fit: BoxFit.cover,
                                                  errorWidget:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) => const Icon(
                                                        Icons.fastfood_rounded,
                                                      ),
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.productName,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                CompanyStatusChip(
                                                  label: l10n
                                                      .companyBranchDetailQuantityChip(
                                                        item.quantity,
                                                      ),
                                                  color: Colors.lightBlueAccent,
                                                ),
                                                CompanyStatusChip(
                                                  label:
                                                      companyStockStatusLabel(
                                                        context,
                                                        item.stockStatus,
                                                      ),
                                                  color: _stockColor(
                                                    context,
                                                    item.stockStatus,
                                                  ),
                                                ),
                                                CompanyStatusChip(
                                                  label: item.productIsAvailable
                                                      ? l10n.companyBranchDetailAvailableForOrder
                                                      : l10n.companyBranchDetailUnavailableForOrder,
                                                  color: item.productIsAvailable
                                                      ? Colors
                                                            .greenAccent
                                                            .shade400
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.error,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.edit_rounded,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
