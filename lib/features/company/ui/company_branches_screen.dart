// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../company_portal_text.dart';
import '../data/company_api.dart';
import '../models/company_models.dart';
import 'company_branch_detail_screen.dart';
import 'widgets/company_ui.dart';

class CompanyBranchesScreen extends StatefulWidget {
  final CompanyApi api;
  final int companyId;

  const CompanyBranchesScreen({
    super.key,
    required this.api,
    required this.companyId,
  });

  @override
  State<CompanyBranchesScreen> createState() => _CompanyBranchesScreenState();
}

class _CompanyBranchesScreenState extends State<CompanyBranchesScreen> {
  Future<_CompanyBranchesPayload>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant CompanyBranchesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _future = _load();
    }
  }

  Future<_CompanyBranchesPayload> _load() async {
    final results = await Future.wait<dynamic>([
      widget.api.branches(widget.companyId),
      widget.api.branchRequests(widget.companyId),
    ]);
    return _CompanyBranchesPayload(
      branches: results[0] as List<CompanyBranch>,
      requests: results[1] as List<CompanyBranchRequest>,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _openBranch(CompanyBranch branch) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompanyBranchDetailScreen(
          companyId: widget.companyId,
          merchantId: branch.id,
          branchName: branch.name,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _showCreateBranchRequest() async {
    final l10n = context.l10n;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final phoneController = TextEditingController();
    final locationController = TextEditingController();
    final ownerNameController = TextEditingController();
    final ownerPhoneController = TextEditingController();
    final ownerPinController = TextEditingController();
    final ownerBlockController = TextEditingController();
    final ownerBuildingController = TextEditingController();
    final ownerApartmentController = TextEditingController();
    var type = 'restaurant';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.companyBranchRequestCreateTitle),
        content: SizedBox(
          width: 560,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestName,
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? l10n.commonRequiredField : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestType,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'restaurant',
                        child: Text(l10n.companyBranchTypeRestaurant),
                      ),
                      DropdownMenuItem(
                        value: 'market',
                        child: Text(l10n.companyBranchTypeMarket),
                      ),
                    ],
                    onChanged: (value) => type = value ?? 'restaurant',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestDescription,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestBusinessPhone,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: locationController,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestLocation,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.companyBranchRequestOwnerAccount,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ownerNameController,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestOwnerName,
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? l10n.commonRequiredField : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ownerPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestOwnerPhone,
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? l10n.commonRequiredField : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ownerPinController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestOwnerPin,
                    ),
                    validator: (value) => (value ?? '').trim().length < 4
                        ? l10n.authPinInvalidFormat
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ownerBlockController,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestOwnerBlock,
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? l10n.commonRequiredField : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ownerBuildingController,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestOwnerBuilding,
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? l10n.commonRequiredField : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ownerApartmentController,
                    decoration: InputDecoration(
                      labelText: l10n.companyBranchRequestOwnerApartment,
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? l10n.commonRequiredField : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await widget.api.createBranchRequest(widget.companyId, {
                'name': nameController.text.trim(),
                'type': type,
                'description': descriptionController.text.trim(),
                'phone': phoneController.text.trim(),
                'branchLocationLabel': locationController.text.trim(),
                'ownerFullName': ownerNameController.text.trim(),
                'ownerPhone': ownerPhoneController.text.trim(),
                'ownerPin': ownerPinController.text.trim(),
                'ownerBlock': ownerBlockController.text.trim(),
                'ownerBuildingNumber': ownerBuildingController.text.trim(),
                'ownerApartment': ownerApartmentController.text.trim(),
              });
              if (!mounted) return;
              Navigator.of(context).pop(true);
            },
            child: Text(l10n.companyBranchRequestSubmit),
          ),
        ],
      ),
    );
    for (final controller in [
      nameController,
      descriptionController,
      phoneController,
      locationController,
      ownerNameController,
      ownerPhoneController,
      ownerPinController,
      ownerBlockController,
      ownerBuildingController,
      ownerApartmentController,
    ]) {
      controller.dispose();
    }
    if (created == true) {
      await _refresh();
    }
  }

  Future<void> _showProductCopy(List<CompanyBranch> branches) async {
    final l10n = context.l10n;
    if (branches.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.companyBranchCopyNeedAtLeastTwo),
            ),
      );
      return;
    }
    int? sourceId = branches.first.id;
    final selectedTargets = <int>{};
    var conflictStrategy = 'skip';
    var copyImages = true;
    var copyPrices = true;
    final productIdsController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.companyBranchCopyTitle),
        content: StatefulBuilder(
          builder: (context, setModalState) {
            return SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: sourceId,
                      decoration: InputDecoration(
                        labelText: l10n.companyBranchCopySource,
                      ),
                      items: branches
                          .map(
                            (branch) => DropdownMenuItem(
                              value: branch.id,
                              child: Text(branch.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setModalState(() {
                        sourceId = value;
                        selectedTargets.remove(value);
                      }),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l10n.companyBranchCopyTargets,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...branches
                        .where((branch) => branch.id != sourceId)
                        .map(
                          (branch) => CheckboxListTile.adaptive(
                            value: selectedTargets.contains(branch.id),
                            onChanged: (value) {
                              setModalState(() {
                                if (value == true) {
                                  selectedTargets.add(branch.id);
                                } else {
                                  selectedTargets.remove(branch.id);
                                }
                              });
                            },
                            title: Text(branch.name),
                            subtitle: Text(
                              '${l10n.companyDashboardGrossSales} ${formatIqd(branch.grossSales)} | ${l10n.companyNavInventory} ${branch.trackedItems}',
                            ),
                          ),
                        ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: productIdsController,
                      decoration: InputDecoration(
                        labelText: l10n.companyBranchCopyProductIds,
                        hintText: l10n.companyBranchCopyProductIdsHint,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: conflictStrategy,
                      decoration: InputDecoration(
                        labelText: l10n.companyBranchCopyConflictStrategy,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'skip',
                          child: Text(l10n.companyBranchCopyConflictSkip),
                        ),
                        DropdownMenuItem(
                          value: 'update',
                          child: Text(l10n.companyBranchCopyConflictUpdate),
                        ),
                        DropdownMenuItem(
                          value: 'duplicate',
                          child: Text(l10n.companyBranchCopyConflictDuplicate),
                        ),
                      ],
                      onChanged: (value) => setModalState(
                        () => conflictStrategy = value ?? conflictStrategy,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: copyImages,
                      onChanged: (value) =>
                          setModalState(() => copyImages = value),
                      title: Text(l10n.companyBranchCopyImages),
                    ),
                    SwitchListTile.adaptive(
                      value: copyPrices,
                      onChanged: (value) =>
                          setModalState(() => copyPrices = value),
                      title: Text(l10n.companyBranchCopyPrices),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () async {
              if (sourceId == null || selectedTargets.isEmpty) return;
              final productIds = productIdsController.text
                  .split(',')
                  .map((item) => int.tryParse(item.trim()))
                  .whereType<int>()
                  .toList();
              final result = await widget.api.copyProducts(widget.companyId, {
                'sourceMerchantId': sourceId,
                'targetMerchantIds': selectedTargets.toList(),
                'productIds': productIds.isEmpty ? null : productIds,
                'conflictStrategy': conflictStrategy,
                'copyImages': copyImages,
                'copyPrices': copyPrices,
              });
              if (!mounted) return;
              Navigator.of(context).pop(true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.companyBranchCopyCompleted(
                      '${result['summary'] ?? l10n.commonDone}',
                    ),
                  ),
                ),
              );
            },
            child: Text(l10n.companyBranchCopyExecute),
          ),
        ],
      ),
    );
    productIdsController.dispose();
    if (saved == true) {
      await _refresh();
    }
  }

  Color _branchStateColor(CompanyBranch branch) {
    if (branch.isDisabled) return Theme.of(context).colorScheme.error;
    if (!branch.isApproved) return Colors.orangeAccent;
    if (branch.inventoryEnabled && branch.staleDailyCheck) {
      return Colors.deepOrangeAccent;
    }
    return Colors.greenAccent.shade400;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<_CompanyBranchesPayload>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CompanyEmptyState(
            icon: Icons.error_outline_rounded,
            title: l10n.companyBranchesLoadFailed,
            description: mapAnyError(
              snapshot.error!,
              fallback: l10n.companyBranchesLoadFailedDescription,
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
            title: l10n.companyBranchesEmptyTitle,
            description: l10n.companyBranchesEmptyDescription,
          );
        }
        final branches = payload.branches;
        final requests = payload.requests;
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
                      title: l10n.companyBranchesTitle,
                      subtitle: l10n.companyBranchesSubtitle,
                      actions: [
                        OutlinedButton.icon(
                          onPressed: () => _showProductCopy(branches),
                          icon: const Icon(Icons.copy_all_rounded),
                          label: Text(l10n.companyBranchesCopyProducts),
                        ),
                        FilledButton.icon(
                          onPressed: _showCreateBranchRequest,
                          icon: const Icon(Icons.add_business_rounded),
                          label: Text(l10n.companyBranchesRequestNew),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (branches.isEmpty)
                      CompanyEmptyState(
                        icon: Icons.domain_add_outlined,
                        title: l10n.companyBranchesEmptyTitle,
                        description: l10n.companyBranchesFirstDescription,
                        action: FilledButton.icon(
                          onPressed: _showCreateBranchRequest,
                          icon: const Icon(Icons.add_business_rounded),
                          label: Text(l10n.companyBranchesAddFirst),
                        ),
                      )
                    else
                      ...branches.map(
                        (branch) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _openBranch(branch),
                            child: Ink(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: Colors.white.withValues(alpha: 0.04),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            branch.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                        ),
                                        CompanyStatusChip(
                                          label:
                                              companyBranchTypeLabel(context, branch.type),
                                          color: Colors.lightBlueAccent,
                                        ),
                                        const SizedBox(width: 8),
                                        CompanyStatusChip(
                                          label: branch.isDisabled
                                              ? l10n.companyBranchesDisabled
                                              : branch.isApproved
                                                  ? l10n.companyBranchesActive
                                                  : l10n.companyBranchesPendingApproval,
                                          color: _branchStateColor(branch),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      branch.description?.isNotEmpty == true
                                          ? branch.description!
                                          : l10n.companyBranchesNoDescription,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        CompanyStatusChip(
                                          label: l10n.companyBranchesOrders(
                                            '${branch.totalOrders}',
                                          ),
                                          color: Colors.lightBlueAccent,
                                        ),
                                        CompanyStatusChip(
                                          label: formatIqd(branch.grossSales),
                                          color: Colors.greenAccent.shade400,
                                        ),
                                        CompanyStatusChip(
                                          label: l10n.companyBranchesOutstanding(
                                            formatIqd(branch.outstandingAmount),
                                          ),
                                          color: Colors.orangeAccent,
                                        ),
                                        CompanyStatusChip(
                                          label: branch.inventoryEnabled
                                              ? l10n.companyBranchesInventorySummary(
                                                  '${branch.outOfStockItems}',
                                                  '${branch.trackedItems}',
                                                )
                                              : l10n.companyBranchesManualAvailability,
                                          color: branch.inventoryEnabled
                                              ? _branchStateColor(branch)
                                              : Colors.deepPurpleAccent,
                                        ),
                                      ],
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
              const SizedBox(height: 16),
              CompanySectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanySectionHeader(
                      title: l10n.companyBranchRequestsTitle,
                      subtitle: l10n.companyBranchRequestsSubtitle,
                      actions: [
                        OutlinedButton.icon(
                          onPressed: _showCreateBranchRequest,
                          icon: const Icon(Icons.add_business_rounded),
                          label: Text(l10n.companyBranchesRequestNew),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (requests.isEmpty)
                      CompanyEmptyState(
                        icon: Icons.rule_folder_outlined,
                        title: l10n.companyBranchRequestsEmptyTitle,
                        description: l10n.companyBranchRequestsEmptyDescription,
                      )
                    else
                      ...requests.map(
                        (request) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: Colors.white.withValues(alpha: 0.04),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        request.requestedName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                    CompanyStatusChip(
                                      label:
                                          companyStatusLabel(context, request.status),
                                      color: request.status == 'approved'
                                          ? Colors.greenAccent.shade400
                                          : request.status == 'rejected'
                                          ? Theme.of(context)
                                              .colorScheme
                                              .error
                                          : Colors.orangeAccent,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${companyBranchTypeLabel(context, request.requestedType)} | ${request.branchLocationLabel ?? l10n.companyBranchRequestNoLocation}',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.companyBranchRequestSuggestedOwner(
                                    request.ownerFullName ??
                                        l10n.companyBranchRequestNoOwner,
                                    request.ownerPhone ??
                                        l10n.companyBranchRequestNoPhone,
                                  ),
                                ),
                                if (request.reviewNote?.isNotEmpty == true) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n.companyBranchRequestReviewNote(
                                      '${request.reviewNote}',
                                    ),
                                  ),
                                ],
                                if (request.approvedMerchantName?.isNotEmpty == true) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n.companyBranchRequestApprovedBranch(
                                      '${request.approvedMerchantName}',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
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
            ],
          ),
        );
      },
    );
  }
}

class _CompanyBranchesPayload {
  final List<CompanyBranch> branches;
  final List<CompanyBranchRequest> requests;

  const _CompanyBranchesPayload({
    required this.branches,
    required this.requests,
  });
}

