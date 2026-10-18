// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../orders/models/order_model.dart';
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
  Future<_CompanyBranchPayload>? _future;
  int? _busyOrderId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_CompanyBranchPayload> _load() async {
    final api = ref.read(companyApiProvider);
    final results = await Future.wait<dynamic>([
      api.branchDetail(widget.companyId, widget.merchantId),
      api.currentOrders(widget.companyId, merchantId: widget.merchantId),
    ]);
    return _CompanyBranchPayload(
      detail: results[0] as CompanyBranchDetail,
      orders: results[1] as List<OrderModel>,
    );
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

  Future<void> _updateOrderStatus(OrderModel order, String status) async {
    final normalized = normalizeOrderStatusForUi(status);
    if (normalized == 'cancelled') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.lt(ar: 'رفض الطلب', en: 'Reject order')),
          content: Text(
            context.lt(ar: 'هل تريد رفض هذا الطلب؟', en: 'Reject this order?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.lt(ar: 'رجوع', en: 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.lt(ar: 'رفض', en: 'Reject')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busyOrderId = order.id);
    try {
      await ref
          .read(companyApiProvider)
          .updateOrderStatus(widget.companyId, order.id, status: status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(ar: 'تم تحديث الطلب.', en: 'Order updated.'),
          ),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(
              ar: 'تعذر تحديث الطلب: $error',
              en: 'Could not update order: $error',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
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
      body: SafeArea(
        top: false,
        child: FutureBuilder<_CompanyBranchPayload>(
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
            final payload = snapshot.data;
            if (payload == null) {
              return CompanyEmptyState(
                icon: Icons.store_mall_directory_outlined,
                title: l10n.companyBranchDetailEmptyTitle,
                description: l10n.companyBranchDetailEmptyDescription,
              );
            }
            final detail = payload.detail;
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
                                value:
                                    branch.ownerFullName ?? l10n.commonNotSet,
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
                  _BranchOrdersSection(
                    orders: payload.orders,
                    busyOrderId: _busyOrderId,
                    onAction: _updateOrderStatus,
                    onRefresh: _refresh,
                  ),
                  const SizedBox(height: 16),
                  _BranchProductsSection(
                    detail: detail,
                    onEditInventory: _editItem,
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
                            description: l10n
                                .companyBranchDetailInventoryEmptyDescription,
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
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
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
                                              ? const Icon(
                                                  Icons.fastfood_rounded,
                                                )
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
                                                          Icons
                                                              .fastfood_rounded,
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
                                                      fontWeight:
                                                          FontWeight.w800,
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
                                                    color:
                                                        Colors.lightBlueAccent,
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
                                                    label:
                                                        item.productIsAvailable
                                                        ? l10n.companyBranchDetailAvailableForOrder
                                                        : l10n.companyBranchDetailUnavailableForOrder,
                                                    color:
                                                        item.productIsAvailable
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
      ),
    );
  }
}

class _CompanyBranchPayload {
  final CompanyBranchDetail detail;
  final List<OrderModel> orders;

  const _CompanyBranchPayload({required this.detail, required this.orders});
}

class _BranchOrdersSection extends StatelessWidget {
  final List<OrderModel> orders;
  final int? busyOrderId;
  final Future<void> Function(OrderModel order, String status) onAction;
  final Future<void> Function() onRefresh;

  const _BranchOrdersSection({
    required this.orders,
    required this.busyOrderId,
    required this.onAction,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return CompanySectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompanySectionHeader(
            title: context.lt(
              ar: 'طلبات الفرع الحالية',
              en: 'Current branch orders',
            ),
            subtitle: context.lt(
              ar: 'الموافقة والرفض وتغيير حالة طلبات هذا المتجر من نفس الصفحة.',
              en: 'Approve, reject, and progress this branch orders from here.',
            ),
            actions: [
              IconButton.filledTonal(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: context.lt(ar: 'تحديث', en: 'Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 180,
                child: CompanyMetricTile(
                  label: context.lt(ar: 'بانتظار القرار', en: 'Waiting'),
                  value: '${_countStatus({'pending'})}',
                  icon: Icons.pending_actions_rounded,
                  color: Colors.orangeAccent,
                ),
              ),
              SizedBox(
                width: 180,
                child: CompanyMetricTile(
                  label: context.lt(ar: 'قيد التجهيز', en: 'Preparing'),
                  value: '${_countStatus({'approved', 'preparing'})}',
                  icon: Icons.restaurant_menu_rounded,
                  color: Colors.amberAccent,
                ),
              ),
              SizedBox(
                width: 180,
                child: CompanyMetricTile(
                  label: context.lt(ar: 'جاهزة أو بالطريق', en: 'Ready'),
                  value:
                      '${_countStatus({'ready_for_delivery', 'on_the_way', 'arrived'})}',
                  icon: Icons.delivery_dining_rounded,
                  color: Colors.lightBlueAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (orders.isEmpty)
            CompanyEmptyState(
              icon: Icons.inbox_outlined,
              title: context.lt(
                ar: 'لا توجد طلبات حالية',
                en: 'No current orders',
              ),
              description: context.lt(
                ar: 'ستظهر طلبات هذا الفرع هنا عند وصولها.',
                en: 'New orders for this branch will appear here.',
              ),
            )
          else
            ...orders.map(
              (order) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BranchOrderCard(
                  order: order,
                  busy: busyOrderId == order.id,
                  onAction: (status) => onAction(order, status),
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _countStatus(Set<String> statuses) {
    return orders
        .where(
          (order) => statuses.contains(normalizeOrderStatusForUi(order.status)),
        )
        .length;
  }
}

class _BranchProductsSection extends StatelessWidget {
  final CompanyBranchDetail detail;
  final ValueChanged<CompanyInventoryItem> onEditInventory;

  const _BranchProductsSection({
    required this.detail,
    required this.onEditInventory,
  });

  @override
  Widget build(BuildContext context) {
    final inventoryByProductId = <int, CompanyInventoryItem>{
      for (final item in detail.inventoryItems) item.productId: item,
    };
    return CompanySectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompanySectionHeader(
            title: context.lt(ar: 'منتجات المتجر', en: 'Store products'),
            subtitle: context.lt(
              ar: 'كل المنتجات والفئات وحالة التوفر المرتبطة بهذا الفرع.',
              en: 'All products, categories, and availability for this branch.',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 180,
                child: CompanyMetricTile(
                  label: context.lt(ar: 'المنتجات', en: 'Products'),
                  value: '${detail.products.length}',
                  icon: Icons.shopping_basket_outlined,
                ),
              ),
              SizedBox(
                width: 180,
                child: CompanyMetricTile(
                  label: context.lt(ar: 'الفئات', en: 'Categories'),
                  value: '${detail.categories.length}',
                  icon: Icons.category_outlined,
                  color: Colors.lightBlueAccent,
                ),
              ),
              SizedBox(
                width: 180,
                child: CompanyMetricTile(
                  label: context.lt(ar: 'مخزون متتبع', en: 'Tracked stock'),
                  value: '${detail.inventoryItems.length}',
                  icon: Icons.inventory_2_outlined,
                  color: Colors.greenAccent.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (detail.products.isEmpty)
            CompanyEmptyState(
              icon: Icons.shopping_basket_outlined,
              title: context.lt(ar: 'لا توجد منتجات', en: 'No products'),
              description: context.lt(
                ar: 'عند إضافة منتجات لهذا المتجر ستظهر هنا.',
                en: 'Products added to this store will appear here.',
              ),
            )
          else
            ...detail.products.map((row) {
              final product = _BranchProductData.fromMap(row);
              final inventoryItem = inventoryByProductId[product.id];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BranchProductCard(
                  product: product,
                  inventoryItem: inventoryItem,
                  onEditInventory: inventoryItem == null
                      ? null
                      : () => onEditInventory(inventoryItem),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _BranchOrderCard extends StatelessWidget {
  final OrderModel order;
  final bool busy;
  final ValueChanged<String> onAction;

  const _BranchOrderCard({
    required this.order,
    required this.busy,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = normalizeOrderStatusForUi(order.status);
    final statusColor = orderStatusColor(status);
    final createdAt = order.createdAt == null
        ? null
        : DateFormat('yyyy/MM/dd HH:mm').format(order.createdAt!.toLocal());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.26),
                    ),
                  ),
                  child: Icon(Icons.receipt_long_rounded, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${context.lt(ar: 'طلب', en: 'Order')} #${order.id}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      if (createdAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          createdAt,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                CompanyStatusChip(
                  label: orderStatusLabel(status),
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: Icons.person_rounded,
                  text: order.customerFullName.isEmpty
                      ? context.lt(ar: 'زبون', en: 'Customer')
                      : order.customerFullName,
                ),
                if (order.customerPhone.isNotEmpty)
                  _InfoPill(
                    icon: Icons.phone_rounded,
                    text: order.customerPhone,
                  ),
                _InfoPill(
                  icon: Icons.payments_rounded,
                  text: formatIqd(order.totalAmount),
                ),
                _InfoPill(
                  icon: order.isMerchantDelivery
                      ? Icons.storefront_rounded
                      : Icons.delivery_dining_rounded,
                  text: order.isMerchantDelivery
                      ? context.lt(ar: 'توصيل الفرع', en: 'Branch delivery')
                      : context.lt(ar: 'توصيل التطبيق', en: 'App delivery'),
                ),
              ],
            ),
            if (order.items.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...order.items
                  .take(5)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${item.quantity} x ${formatIqd(item.unitPrice)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (order.items.length > 5)
                Text(
                  context.lt(
                    ar: '+${order.items.length - 5} عناصر أخرى',
                    en: '+${order.items.length - 5} more items',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (order.note?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                order.note!.trim(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.74),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (busy)
              const LinearProgressIndicator(minHeight: 2)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _actionsFor(order)
                    .map(
                      (action) => action.destructive
                          ? OutlinedButton.icon(
                              onPressed: () => onAction(action.status),
                              icon: Icon(action.icon),
                              label: Text(action.label(context)),
                            )
                          : FilledButton.icon(
                              onPressed: () => onAction(action.status),
                              icon: Icon(action.icon),
                              label: Text(action.label(context)),
                            ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  List<_OrderAction> _actionsFor(OrderModel order) {
    switch (normalizeOrderStatusForUi(order.status)) {
      case 'pending':
        return const [
          _OrderAction('approved', Icons.check_rounded, 'approve'),
          _OrderAction('cancelled', Icons.close_rounded, 'reject', true),
        ];
      case 'approved':
        return const [
          _OrderAction('preparing', Icons.restaurant_menu_rounded, 'prepare'),
          _OrderAction('cancelled', Icons.close_rounded, 'reject', true),
        ];
      case 'preparing':
        return const [
          _OrderAction('ready_for_delivery', Icons.done_all_rounded, 'ready'),
          _OrderAction('cancelled', Icons.close_rounded, 'reject', true),
        ];
      case 'ready_for_delivery':
        if (!order.isMerchantDelivery) return const [];
        return const [
          _OrderAction('on_the_way', Icons.delivery_dining_rounded, 'way'),
        ];
      case 'on_the_way':
        if (!order.isMerchantDelivery) return const [];
        return const [
          _OrderAction('arrived', Icons.location_on_rounded, 'arrived'),
        ];
      case 'arrived':
        if (!order.isMerchantDelivery) return const [];
        return const [
          _OrderAction('delivered', Icons.task_alt_rounded, 'delivered'),
        ];
      default:
        return const [];
    }
  }
}

class _BranchProductCard extends StatelessWidget {
  final _BranchProductData product;
  final CompanyInventoryItem? inventoryItem;
  final VoidCallback? onEditInventory;

  const _BranchProductCard({
    required this.product,
    required this.inventoryItem,
    required this.onEditInventory,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stockStatus = inventoryItem?.stockStatus;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: product.imageUrl == null
                  ? const Icon(Icons.shopping_basket_rounded)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedAppImage(
                        imageUrl: product.imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (context, error, stackTrace) =>
                            const Icon(Icons.shopping_basket_rounded),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (product.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      CompanyStatusChip(
                        label: formatIqd(
                          product.discountedPrice ?? product.price,
                        ),
                        color: Colors.greenAccent.shade400,
                      ),
                      if (product.discountedPrice != null)
                        CompanyStatusChip(
                          label: context.lt(ar: 'خصم', en: 'Discount'),
                          color: Colors.orangeAccent,
                        ),
                      if (product.categoryName?.isNotEmpty == true)
                        CompanyStatusChip(
                          label: product.categoryName!,
                          color: Colors.lightBlueAccent,
                        ),
                      CompanyStatusChip(
                        label: product.isAvailable
                            ? context.lt(ar: 'متاح', en: 'Available')
                            : context.lt(ar: 'غير متاح', en: 'Unavailable'),
                        color: product.isAvailable
                            ? Colors.greenAccent.shade400
                            : scheme.error,
                      ),
                      if (stockStatus != null)
                        CompanyStatusChip(
                          label: companyStockStatusLabel(context, stockStatus),
                          color: _stockStatusColor(context, stockStatus),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onEditInventory == null)
              Tooltip(
                message: context.lt(
                  ar: 'لا يوجد مخزون متتبع لهذا المنتج',
                  en: 'No tracked inventory for this product',
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.54),
                ),
              )
            else
              IconButton.filledTonal(
                onPressed: onEditInventory,
                icon: const Icon(Icons.tune_rounded),
                tooltip: context.lt(ar: 'تعديل المخزون', en: 'Edit inventory'),
              ),
          ],
        ),
      ),
    );
  }

  Color _stockStatusColor(BuildContext context, String status) {
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
}

class _BranchProductData {
  final int id;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? categoryName;
  final double price;
  final double? discountedPrice;
  final bool isAvailable;

  const _BranchProductData({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.categoryName,
    required this.price,
    required this.discountedPrice,
    required this.isAvailable,
  });

  factory _BranchProductData.fromMap(Map<String, dynamic> json) {
    return _BranchProductData(
      id: _readInt(json, const ['id']),
      name: _readText(json, const [
        'name',
        'productName',
        'product_name',
      ], fallback: '-'),
      description: _readNullableText(json, const ['description']),
      imageUrl: _readNullableText(json, const ['imageUrl', 'image_url']),
      categoryName: _readNullableText(json, const [
        'categoryName',
        'category_name',
      ]),
      price: _readDouble(json, const ['price']),
      discountedPrice: _readNullableDouble(json, const [
        'discountedPrice',
        'discounted_price',
      ]),
      isAvailable: _readBool(json, const [
        'isAvailable',
        'is_available',
      ], fallback: true),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _OrderAction {
  final String status;
  final IconData icon;
  final String key;
  final bool destructive;

  const _OrderAction(
    this.status,
    this.icon,
    this.key, [
    this.destructive = false,
  ]);

  String label(BuildContext context) {
    switch (key) {
      case 'approve':
        return context.lt(ar: 'قبول', en: 'Approve');
      case 'reject':
        return context.lt(ar: 'رفض', en: 'Reject');
      case 'prepare':
        return context.lt(ar: 'تجهيز', en: 'Prepare');
      case 'ready':
        return context.lt(ar: 'جاهز', en: 'Ready');
      case 'way':
        return context.lt(ar: 'بالطريق', en: 'On the way');
      case 'arrived':
        return context.lt(ar: 'وصل', en: 'Arrived');
      case 'delivered':
        return context.lt(ar: 'تم التسليم', en: 'Delivered');
      default:
        return status;
    }
  }
}

int _readInt(Map<String, dynamic> json, List<String> keys, {int fallback = 0}) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toInt();
    final parsed = int.tryParse('$value');
    if (parsed != null) return parsed;
  }
  return fallback;
}

double _readDouble(
  Map<String, dynamic> json,
  List<String> keys, {
  double fallback = 0,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toDouble();
    final parsed = double.tryParse('$value');
    if (parsed != null) return parsed;
  }
  return fallback;
}

double? _readNullableDouble(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse('$value');
    if (parsed != null) return parsed;
  }
  return null;
}

bool _readBool(
  Map<String, dynamic> json,
  List<String> keys, {
  bool fallback = false,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) return value;
    final normalized = '$value'.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return fallback;
}

String _readText(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  return _readNullableText(json, keys) ?? fallback;
}

String? _readNullableText(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final text = '$value'.trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}
