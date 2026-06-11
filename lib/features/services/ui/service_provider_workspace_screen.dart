// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../data/services_api.dart';
import '../models/service_models.dart';
import '../state/service_provider_workspace_controller.dart';
import 'service_request_details_screen.dart';

class ServiceProviderWorkspaceScreen extends ConsumerWidget {
  const ServiceProviderWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serviceProviderWorkspaceControllerProvider);
    final ctrl = ref.read(serviceProviderWorkspaceControllerProvider.notifier);
    final servicesSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.services, displayName: 'الخدمات');
    final workspace = state.workspace;
    final visibleRequests =
        servicesSection.isBlocked
            ? state.requests
                .where(
                  (request) => !<String>{'completed', 'cancelled', 'rejected'}
                      .contains(request.status.trim().toLowerCase()),
                )
                .toList(growable: false)
            : state.requests;
    if (servicesSection.isBlocked && !servicesSection.allowExistingActiveAccess) {
      return SectionUnavailableScreen(entry: servicesSection);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة صاحب الخدمة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () {
              ctrl.loadWorkspace();
              ctrl.loadRequests();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: servicesSection.isOpen
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => _showCreateOfferingDialog(context, ref),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('خدمة جديدة'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          await ctrl.loadWorkspace();
          await ctrl.loadRequests();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
          children: [
            if (servicesSection.isBlocked)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        servicesSection.badgeLabel ?? 'غير متاح',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(servicesSection.effectiveMessage),
                      const SizedBox(height: 8),
                      const Text(
                        'تم تعطيل إنشاء الخدمات والعروض الجديدة. يمكنك متابعة الطلبات النشطة فقط.',
                      ),
                    ],
                  ),
                ),
              ),
            if (state.error != null)
              Card(
                color: Colors.red.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    state.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            if (state.loadingWorkspace && workspace == null)
              const Padding(
                padding: EdgeInsets.only(top: 90),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!state.loadingWorkspace && workspace == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'لا يوجد ملف مقدم خدمة لهذا الحساب بعد.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if (workspace != null) ...[
              _workspaceHeader(workspace),
              const SizedBox(height: 12),
              _requestCounts(workspace),
              const SizedBox(height: 12),
              _offeringsSection(workspace.provider.offerings),
              const SizedBox(height: 12),
              _promotionsSection(workspace.promotions),
            ],
            const SizedBox(height: 12),
            const Text(
              'الطلبات الواردة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (state.loadingRequests)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!state.loadingRequests && visibleRequests.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('لا توجد طلبات نشطة يمكن متابعتها حاليًا.'),
                ),
              ),
            ...visibleRequests.map(
              (request) => _RequestCard(
                request: request,
                onOpenDetails: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ServiceRequestDetailsScreen(requestId: request.id),
                    ),
                  );
                },
                onStatusTap: (status) => ctrl.updateRequestStatus(
                  requestId: request.id,
                  status: status,
                ),
                onQuoteTap: () => _showQuoteDialog(
                  context,
                  onSubmit: (payload) => ctrl.createQuote(
                    requestId: request.id,
                    pricingModel: payload.pricingModel,
                    pricingUnit: payload.pricingUnit,
                    amount: payload.amount,
                    minAmount: payload.minAmount,
                    maxAmount: payload.maxAmount,
                    visitFee: payload.visitFee,
                    note: payload.note,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceHeader(ServiceProviderWorkspaceModel workspace) {
    final profile = workspace.provider;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 26,
          backgroundImage: (profile.logoUrl ?? '').trim().isNotEmpty
              ? NetworkImage(profile.logoUrl!)
              : null,
          child: (profile.logoUrl ?? '').trim().isEmpty
              ? const Icon(Icons.business_center_rounded)
              : null,
        ),
        title: Text(
          profile.businessName,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          [
            profile.city,
            profile.area,
            'الحالة: ${_providerApprovalStatusLabel(profile.providerApprovalStatus)}',
          ].where((item) => (item ?? '').trim().isNotEmpty).join(' - '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${profile.ratingAvg.toStringAsFixed(1)} ★'),
            Text('${profile.ratingCount} تقييم'),
          ],
        ),
      ),
    );
  }

  Widget _requestCounts(ServiceProviderWorkspaceModel workspace) {
    final counts = workspace.requestCounts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _countChip('معلقة', counts['pending'] ?? 0),
            _countChip('بانتظارك', counts['awaiting_provider'] ?? 0),
            _countChip('مقبولة', counts['accepted'] ?? 0),
            _countChip('مجدولة', counts['scheduled'] ?? 0),
            _countChip('قيد التنفيذ', counts['in_progress'] ?? 0),
            _countChip('مكتملة', counts['completed'] ?? 0),
          ],
        ),
      ),
    );
  }

  Widget _countChip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withValues(alpha: 0.06),
      ),
      child: Text('$label: $count'),
    );
  }

  Widget _offeringsSection(List<ServiceOfferingModel> offerings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الخدمات',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (offerings.isEmpty) const Text('لا توجد خدمات مضافة بعد.'),
            ...offerings
                .take(8)
                .map(
                  (offering) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(offering.name),
                    subtitle: Text(
                      '${offering.displayPriceText} - ${_offeringModerationStatusLabel(offering.moderationStatus)}',
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _promotionsSection(List<ServicePromotionModel> promotions) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('العروض', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (promotions.isEmpty) const Text('لا توجد عروض فعالة.'),
            ...promotions
                .take(8)
                .map(
                  (promo) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(promo.title),
                    subtitle: Text(promo.description ?? ''),
                    trailing: Text(promo.isActive ? 'فعال' : 'غير فعال'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final ServiceRequestModel request;
  final VoidCallback onOpenDetails;
  final ValueChanged<String> onStatusTap;
  final VoidCallback onQuoteTap;

  const _RequestCard({
    required this.request,
    required this.onOpenDetails,
    required this.onStatusTap,
    required this.onQuoteTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.offeringName ?? 'خدمة',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  _requestStatusLabel(request.status),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('العميل: ${request.customerUserId}'),
            if ((request.notes ?? '').trim().isNotEmpty)
              Text('ملاحظات: ${request.notes}'),
            if ((request.city ?? '').trim().isNotEmpty ||
                (request.area ?? '').trim().isNotEmpty)
              Text('الموقع: ${request.city ?? ''} ${request.area ?? ''}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: onOpenDetails,
                  child: const Text('إدارة الطلب'),
                ),
                OutlinedButton(
                  onPressed: onQuoteTap,
                  child: const Text('إرسال عرض سعر'),
                ),
                if (<String>{'pending', 'awaiting_provider'}
                    .contains(request.status.trim().toLowerCase()))
                  OutlinedButton(
                    onPressed: () => onStatusTap('accepted'),
                    child: const Text('قبول'),
                  ),
                if (<String>{'accepted', 'scheduled'}
                    .contains(request.status.trim().toLowerCase()))
                  OutlinedButton(
                    onPressed: () => onStatusTap('in_progress'),
                    child: const Text('بدء التنفيذ'),
                  ),
                if (request.status.trim().toLowerCase() == 'in_progress')
                  OutlinedButton(
                    onPressed: () => onStatusTap('completed'),
                    child: const Text('إكمال'),
                  ),
                if (<String>{'pending', 'awaiting_provider'}
                    .contains(request.status.trim().toLowerCase()))
                  OutlinedButton(
                    onPressed: () => onStatusTap('rejected'),
                    child: const Text('رفض'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotePayload {
  final String pricingModel;
  final String pricingUnit;
  final double? amount;
  final double? minAmount;
  final double? maxAmount;
  final double? visitFee;
  final String? note;

  const _QuotePayload({
    required this.pricingModel,
    required this.pricingUnit,
    required this.amount,
    required this.minAmount,
    required this.maxAmount,
    required this.visitFee,
    required this.note,
  });
}

String _providerApprovalStatusLabel(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'approved':
      return 'مقبول';
    case 'pending':
      return 'بانتظار المراجعة';
    case 'rejected':
      return 'مرفوض';
    case 'suspended':
      return 'معلق';
    default:
      return value == null || value.trim().isEmpty ? 'غير محدد' : value;
  }
}

String _offeringModerationStatusLabel(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'approved':
      return 'منشورة';
    case 'pending':
      return 'بانتظار المراجعة';
    case 'rejected':
      return 'مرفوضة';
    case 'paused':
      return 'موقوفة';
    default:
      return value == null || value.trim().isEmpty ? 'غير محدد' : value;
  }
}

String _requestStatusLabel(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'pending':
      return 'معلق';
    case 'awaiting_provider':
      return 'بانتظار مقدم الخدمة';
    case 'accepted':
      return 'مقبول';
    case 'scheduled':
      return 'مجدول';
    case 'in_progress':
      return 'قيد التنفيذ';
    case 'completed':
      return 'مكتمل';
    case 'cancelled':
      return 'ملغي';
    case 'rejected':
      return 'مرفوض';
    default:
      return value == null || value.trim().isEmpty ? 'غير محدد' : value;
  }
}

Future<void> _showQuoteDialog(
  BuildContext context, {
  required Future<void> Function(_QuotePayload payload) onSubmit,
}) async {
  final amountCtrl = TextEditingController();
  final minCtrl = TextEditingController();
  final maxCtrl = TextEditingController();
  final feeCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  var pricingModel = 'custom_quote';
  var pricingUnit = 'job';

  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('إرسال عرض سعر'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: pricingModel,
                  items: const [
                    DropdownMenuItem(
                      value: 'custom_quote',
                      child: Text('تسعير مخصص'),
                    ),
                    DropdownMenuItem(
                      value: 'inspection_required',
                      child: Text('حسب المعاينة'),
                    ),
                    DropdownMenuItem(
                      value: 'starting_from',
                      child: Text('يبدأ من'),
                    ),
                    DropdownMenuItem(
                      value: 'per_hour',
                      child: Text('لكل ساعة'),
                    ),
                    DropdownMenuItem(
                      value: 'per_visit',
                      child: Text('لكل زيارة'),
                    ),
                    DropdownMenuItem(
                      value: 'fixed_package',
                      child: Text('باقة ثابتة'),
                    ),
                  ],
                  onChanged: (value) => pricingModel = value ?? 'custom_quote',
                  decoration: const InputDecoration(labelText: 'نوع التسعير'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: pricingUnit,
                  items: const [
                    DropdownMenuItem(value: 'job', child: Text('خدمة')),
                    DropdownMenuItem(value: 'hour', child: Text('ساعة')),
                    DropdownMenuItem(value: 'visit', child: Text('زيارة')),
                    DropdownMenuItem(value: 'day', child: Text('يوم')),
                    DropdownMenuItem(value: 'device', child: Text('جهاز')),
                    DropdownMenuItem(value: 'room', child: Text('غرفة')),
                  ],
                  onChanged: (value) => pricingUnit = value ?? 'job',
                  decoration: const InputDecoration(labelText: 'وحدة التسعير'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'السعر'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'أدنى سعر',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: maxCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'أعلى سعر',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: feeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'رسوم الكشف/الزيارة',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              await onSubmit(
                _QuotePayload(
                  pricingModel: pricingModel,
                  pricingUnit: pricingUnit,
                  amount: double.tryParse(amountCtrl.text.trim()),
                  minAmount: double.tryParse(minCtrl.text.trim()),
                  maxAmount: double.tryParse(maxCtrl.text.trim()),
                  visitFee: double.tryParse(feeCtrl.text.trim()),
                  note: noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim(),
                ),
              );
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            child: const Text('إرسال'),
          ),
        ],
      );
    },
  );
}

Future<void> _showCreateOfferingDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final roots = <ServiceCategoryModel>[];
  try {
    final rows = await ref.read(servicesApiProvider).listPublicCategories();
    roots.addAll(
      rows
          .map(ServiceCategoryModel.fromJson)
          .where((item) => item.level == 1 && item.isActive && item.isPublic),
    );
    roots.sort(
      (a, b) => a.sortOrder == b.sortOrder
          ? a.name.compareTo(b.name)
          : a.sortOrder.compareTo(b.sortOrder),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('تعذر تحميل الفئات: $e')));
    return;
  }
  if (!context.mounted) return;
  if (roots.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('لا توجد فئات متاحة الآن.')),
    );
    return;
  }

  final nameCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();
  final startsFromCtrl = TextEditingController();
  int? selectedMainCategoryId = roots.first.id;
  final initialSubcategories = roots.first.children
      .where((item) => item.level == 2 && item.isActive && item.isPublic)
      .toList();
  int? selectedSubcategoryId = initialSubcategories.isNotEmpty
      ? initialSubcategories.first.id
      : null;
  String executionMode = 'both';
  String pricingModel = 'custom_quote';
  String? dialogError;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        ServiceCategoryModel selectedRoot = roots.first;
        for (final root in roots) {
          if (root.id == selectedMainCategoryId) {
            selectedRoot = root;
            break;
          }
        }
        final subcategories = selectedRoot.children
            .where((item) => item.level == 2 && item.isActive && item.isPublic)
            .toList();
        final subcategoryIsValid =
            selectedSubcategoryId != null &&
            subcategories.any((item) => item.id == selectedSubcategoryId);
        if (!subcategoryIsValid) {
          selectedSubcategoryId = subcategories.isEmpty
              ? null
              : subcategories.first.id;
        }

        return AlertDialog(
          title: const Text('إنشاء خدمة جديدة'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dialogError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        dialogError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'اسم الخدمة'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'الوصف'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedMainCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'الفئة الرئيسية',
                    ),
                    items: roots
                        .map(
                          (item) => DropdownMenuItem<int>(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedMainCategoryId = value;
                        final nextRoot = roots.firstWhere(
                          (item) => item.id == value,
                          orElse: () => roots.first,
                        );
                        final nextSubcategories = nextRoot.children
                            .where(
                              (item) =>
                                  item.level == 2 &&
                                  item.isActive &&
                                  item.isPublic,
                            )
                            .toList();
                        selectedSubcategoryId = nextSubcategories.isEmpty
                            ? null
                            : nextSubcategories.first.id;
                        dialogError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedSubcategoryId,
                    decoration: const InputDecoration(
                      labelText: 'الفئة الفرعية',
                    ),
                    items: subcategories
                        .map(
                          (item) => DropdownMenuItem<int>(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: subcategories.isEmpty
                        ? null
                        : (value) => setDialogState(() {
                            selectedSubcategoryId = value;
                            dialogError = null;
                          }),
                  ),
                  if (subcategories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'لا توجد فئات فرعية متاحة لهذه الفئة.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: executionMode,
                    items: const [
                      DropdownMenuItem(value: 'home', child: Text('منزلية')),
                      DropdownMenuItem(
                        value: 'provider_location',
                        child: Text('داخل المحل'),
                      ),
                      DropdownMenuItem(value: 'both', child: Text('كلاهما')),
                      DropdownMenuItem(value: 'remote', child: Text('عن بُعد')),
                    ],
                    onChanged: (value) => setDialogState(() {
                      executionMode = value ?? 'both';
                    }),
                    decoration: const InputDecoration(labelText: 'نمط التنفيذ'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: pricingModel,
                    items: const [
                      DropdownMenuItem(
                        value: 'custom_quote',
                        child: Text('تسعير مخصص'),
                      ),
                      DropdownMenuItem(
                        value: 'inspection_required',
                        child: Text('حسب المعاينة'),
                      ),
                      DropdownMenuItem(
                        value: 'starting_from',
                        child: Text('يبدأ من'),
                      ),
                      DropdownMenuItem(
                        value: 'fixed_package',
                        child: Text('باقة ثابتة'),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      pricingModel = value ?? 'custom_quote';
                    }),
                    decoration: const InputDecoration(labelText: 'نمط السعر'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: startsFromCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'السعر (اختياري حسب نمط التسعير)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final startsFromPrice = double.tryParse(
                  startsFromCtrl.text.trim(),
                );
                if (nameCtrl.text.trim().isEmpty) {
                  setDialogState(() => dialogError = 'يرجى إدخال اسم الخدمة.');
                  return;
                }
                if (selectedMainCategoryId == null) {
                  setDialogState(
                    () => dialogError = 'يرجى اختيار الفئة الرئيسية.',
                  );
                  return;
                }
                if (selectedSubcategoryId == null) {
                  setDialogState(
                    () => dialogError = 'يرجى اختيار الفئة الفرعية.',
                  );
                  return;
                }
                if ((pricingModel == 'starting_from' ||
                        pricingModel == 'fixed_package') &&
                    startsFromPrice == null) {
                  setDialogState(
                    () => dialogError = 'يرجى إدخال السعر لهذا النمط.',
                  );
                  return;
                }

                try {
                  await ref.read(servicesApiProvider).createOffering({
                    'name': nameCtrl.text.trim(),
                    'description': descriptionCtrl.text.trim(),
                    'mainCategoryId': selectedMainCategoryId,
                    'subcategoryId': selectedSubcategoryId,
                    'executionMode': executionMode,
                    'startsFromPrice': startsFromPrice,
                    'pricingOptions': [
                      {
                        'pricingModel': pricingModel,
                        'pricingUnit': pricingModel == 'fixed_package'
                            ? 'package'
                            : 'job',
                        if (pricingModel == 'starting_from')
                          'amount': startsFromPrice,
                        if (pricingModel == 'fixed_package')
                          'amount': startsFromPrice,
                        'isDefault': true,
                      },
                    ],
                  });
                } catch (e) {
                  if (!context.mounted) return;
                  setDialogState(() => dialogError = 'تعذر إنشاء الخدمة: $e');
                  return;
                }
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('إنشاء'),
            ),
          ],
        );
      },
    ),
  );

  nameCtrl.dispose();
  descriptionCtrl.dispose();
  startsFromCtrl.dispose();

  if (!context.mounted) return;
  ref.read(serviceProviderWorkspaceControllerProvider.notifier).loadWorkspace();
}
