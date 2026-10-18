// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/media/cached_app_image.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../../core/workspaces/workspace_permissions.dart';
import '../data/services_api.dart';
import '../models/service_models.dart';
import '../state/service_provider_workspace_controller.dart';
import 'service_provider_onboarding_screen.dart';
import 'service_offering_details_screen.dart';
import 'service_request_details_screen.dart';

const double _servicePlatformCommissionRate = 0.10;

String _serviceRequestLifecycleStatus(ServiceRequestModel request) {
  final bookingStatus = (request.bookingStatus ?? '').trim();
  return bookingStatus.isNotEmpty ? bookingStatus : request.status.trim();
}

bool _isCompletedServiceRequest(ServiceRequestModel request) {
  return _serviceRequestLifecycleStatus(request).toLowerCase() == 'completed';
}

double _serviceRequestGrossAmount(ServiceRequestModel request) {
  final candidates = <double?>[
    request.bookingTotalIqd,
    request.finalPrice,
    request.bookingSubtotalIqd,
    if (request.quotes.isNotEmpty) request.quotes.first.amount,
    if (request.quotes.isNotEmpty) request.quotes.first.minAmount,
  ];
  for (final value in candidates) {
    if (value != null && value > 0) return value;
  }
  return 0;
}

double _servicePlatformCommission(double amount) {
  if (amount <= 0) return 0;
  return amount * _servicePlatformCommissionRate;
}

String _formatIqd(num value) {
  final rounded = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < rounded.length; i++) {
    final remaining = rounded.length - i;
    buffer.write(rounded[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return '${buffer.toString()} IQD';
}

class ServiceProviderWorkspaceScreen extends ConsumerWidget {
  const ServiceProviderWorkspaceScreen({
    super.key,
    this.centralOperationsMode = false,
  });

  final bool centralOperationsMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serviceProviderWorkspaceControllerProvider);
    final ctrl = ref.read(serviceProviderWorkspaceControllerProvider.notifier);
    final servicesSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.services, displayName: 'الخدمات');
    final sectionBlocked = !centralOperationsMode && servicesSection.isBlocked;
    final sectionOpen = centralOperationsMode || servicesSection.isOpen;
    final workspace = state.workspace;
    final access = workspace?.access;
    final canCreateServices =
        centralOperationsMode ||
        access?.isOwner == true ||
        access?.permissionMap['create_services'] == true;
    final canEditServices =
        centralOperationsMode ||
        access?.isOwner == true ||
        access?.permissionMap['edit_services'] == true;
    final canManageOffers =
        centralOperationsMode ||
        access?.isOwner == true ||
        access?.permissionMap['manage_offers'] == true;
    final canViewRequests =
        centralOperationsMode ||
        access?.isOwner == true ||
        access?.permissionMap['view_service_requests'] == true;
    final canManageEmployees =
        centralOperationsMode ||
        access?.isOwner == true ||
        access?.permissionMap['manage_employees'] == true;
    final canViewAuditLog =
        centralOperationsMode ||
        access?.isOwner == true ||
        access?.permissionMap['view_audit_log'] == true;
    final visibleRequests = canViewRequests
        ? (sectionBlocked
              ? state.requests
                    .where(
                      (request) => !<String>{
                        'completed',
                        'cancelled',
                        'rejected',
                        'COMPLETED',
                        'CANCELLED_BY_CUSTOMER',
                        'CANCELLED_BY_PROVIDER',
                        'CANCELLED_BY_ADMIN',
                        'REJECTED_BY_PROVIDER',
                        'EXPIRED',
                        'DISPUTED',
                      }.contains(request.status.trim()),
                    )
                    .toList(growable: false)
              : state.requests)
        : const <ServiceRequestModel>[];
    if (sectionBlocked && !servicesSection.allowExistingActiveAccess) {
      return SectionUnavailableScreen(entry: servicesSection);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          centralOperationsMode ? 'نشر وإدارة خدمات مسلكي' : 'لوحة صاحب الخدمة',
        ),
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
      floatingActionButton: sectionOpen && canCreateServices
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => _showCreateOfferingDialog(context, ref),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('خدمة جديدة'),
            )
          : null,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await ctrl.loadWorkspace();
            await ctrl.loadRequests();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
            children: [
              if (sectionBlocked)
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
              if (state.workspaceMissingProfile)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [Icon(Icons.info_outline_rounded)],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'لا يوجد ملف مقدم خدمة لهذا الحساب بعد.',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'افتح شاشة التسجيل المجاني لإرسال طلبك أو متابعة مراجعته.',
                          textAlign: TextAlign.end,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.end,
                          children: [
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ServiceProviderOnboardingScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('فتح التسجيل المجاني'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                ctrl.loadWorkspace();
                                ctrl.loadRequests();
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (state.loadingWorkspace && workspace == null)
                const Padding(
                  padding: EdgeInsets.only(top: 90),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!state.loadingWorkspace &&
                  workspace == null &&
                  !state.workspaceMissingProfile)
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
                _serviceFinancialReport(state.requests),
                const SizedBox(height: 12),
                _offeringsSection(
                  context,
                  ref,
                  workspace.provider.offerings,
                  canEditServices: canEditServices,
                ),
                const SizedBox(height: 12),
                _promotionsSection(
                  context,
                  ref,
                  workspace.promotions,
                  offerings: workspace.provider.offerings,
                  canManageOffers: canManageOffers,
                ),
                const SizedBox(height: 12),
                _employeesSection(
                  context,
                  ref,
                  workspace: workspace,
                  canManageEmployees: canManageEmployees,
                  canViewAuditLog: canViewAuditLog,
                ),
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
              if (workspace != null && !canViewRequests)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'ليس لديك صلاحية عرض الطلبات / You do not have permission to view service requests.',
                    ),
                  ),
                ),
              if (workspace != null &&
                  canViewRequests &&
                  !state.loadingRequests &&
                  visibleRequests.isEmpty)
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

  Widget _serviceFinancialReport(List<ServiceRequestModel> requests) {
    final completedRequests = requests
        .where(_isCompletedServiceRequest)
        .toList(growable: false);
    final gross = completedRequests.fold<double>(
      0,
      (sum, request) => sum + _serviceRequestGrossAmount(request),
    );
    final commission = _servicePlatformCommission(gross);
    final net = gross - commission;
    final latestRows = completedRequests.take(6).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.receipt_long_rounded),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تقرير الحجوزات المكتملة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'التسجيل مجاني. عمولة مسلكي 10% من كل حجز مكتمل، والدفع نقداً عبر المكتب ثم يسلم صافي المبلغ لصاحب الخدمة بعد انتهاء الخدمة.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _financeTile(
                  title: 'الحجوزات المكتملة',
                  value: '${completedRequests.length}',
                  icon: Icons.task_alt_rounded,
                ),
                _financeTile(
                  title: 'إجمالي قيمة الحجوزات',
                  value: _formatIqd(gross),
                  icon: Icons.payments_outlined,
                ),
                _financeTile(
                  title: 'استقطاع مسلكي 10%',
                  value: _formatIqd(commission),
                  icon: Icons.percent_rounded,
                ),
                _financeTile(
                  title: 'صافي مقدم الخدمة',
                  value: _formatIqd(net),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (latestRows.isEmpty)
              const Text(
                'لا توجد حجوزات مكتملة بعد. سيظهر هنا مجموع الحجوزات والعمولة تلقائياً بعد إكمال أول خدمة.',
              )
            else ...[
              const Text(
                'آخر الحجوزات المكتملة',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              ...latestRows.map((request) {
                final amount = _serviceRequestGrossAmount(request);
                final rowCommission = _servicePlatformCommission(amount);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.black.withValues(alpha: 0.04),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${request.requestCode} - ${request.offeringName ?? 'خدمة'}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text('قيمة الحجز: ${_formatIqd(amount)}'),
                          Text('استقطاع مسلكي: ${_formatIqd(rowCommission)}'),
                          Text('الصافي: ${_formatIqd(amount - rowCommission)}'),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _financeTile({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 145),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black.withValues(alpha: 0.05),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offeringsSection(
    BuildContext context,
    WidgetRef ref,
    List<ServiceOfferingModel> offerings, {
    required bool canEditServices,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الخدمات (${offerings.length})',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (offerings.length > 8)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _AllServiceOfferingsScreen(
                          canEdit: canEditServices,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.view_list_outlined),
                    label: const Text('عرض وإدارة الكل'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (offerings.isEmpty) const Text('لا توجد خدمات مضافة بعد.'),
            ...offerings
                .take(8)
                .map(
                  (offering) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ServiceOfferingWorkspaceCard(
                      offering: offering,
                      canEdit: canEditServices,
                      onOpen: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ServiceOfferingDetailsScreen(
                              offeringId: offering.id,
                            ),
                          ),
                        );
                      },
                      onEdit: canEditServices
                          ? () => _showCreateOfferingDialog(
                              context,
                              ref,
                              existingOffering: offering,
                            )
                          : null,
                    ),
                  ),
                ),
            if (offerings.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _AllServiceOfferingsScreen(canEdit: canEditServices),
                    ),
                  ),
                  icon: const Icon(Icons.manage_search_rounded),
                  label: Text('عرض بقية الخدمات (${offerings.length - 8})'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _promotionsSection(
    BuildContext context,
    WidgetRef ref,
    List<ServicePromotionModel> promotions, {
    required List<ServiceOfferingModel> offerings,
    required bool canManageOffers,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'العروض والأسعار المخفضة',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (canManageOffers && offerings.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        _showCreatePromotionDialog(context, ref, offerings),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('عرض جديد'),
                  ),
              ],
            ),
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

  Future<void> _showCreatePromotionDialog(
    BuildContext context,
    WidgetRef ref,
    List<ServiceOfferingModel> offerings,
  ) async {
    final titleCtrl = TextEditingController(text: 'عرض خاص');
    final valueCtrl = TextEditingController();
    var offeringId = offerings.first.id;
    var discountType = 'percentage';
    String? error;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة سعر مخفض للخدمة'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: offeringId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الخدمة'),
                    items: offerings
                        .map(
                          (item) => DropdownMenuItem<int>(
                            value: item.id,
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => offeringId = value ?? offeringId),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'عنوان العرض'),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'percentage',
                        label: Text('نسبة خصم'),
                      ),
                      ButtonSegment(
                        value: 'special_price',
                        label: Text('سعر خاص'),
                      ),
                    ],
                    selected: {discountType},
                    onSelectionChanged: (values) =>
                        setDialogState(() => discountType = values.first),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: valueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: discountType == 'percentage'
                          ? 'نسبة الخصم %'
                          : 'السعر الجديد IQD',
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(valueCtrl.text.trim());
                if (titleCtrl.text.trim().isEmpty ||
                    value == null ||
                    value <= 0 ||
                    (discountType == 'percentage' && value > 100)) {
                  setDialogState(() => error = 'أدخل عنواناً وقيمة خصم صحيحة.');
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('نشر العرض'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) {
      titleCtrl.dispose();
      valueCtrl.dispose();
      return;
    }

    try {
      final value = double.parse(valueCtrl.text.trim());
      final now = DateTime.now();
      await ref.read(servicesApiProvider).createPromotion({
        'title': titleCtrl.text.trim(),
        'description': discountType == 'percentage'
            ? 'خصم ${value.toStringAsFixed(0)}% على الخدمة'
            : 'سعر خاص لفترة محدودة',
        'discountType': discountType,
        if (discountType == 'percentage') 'discountValue': value,
        if (discountType == 'special_price') 'specialPrice': value,
        'startsAt': now.toUtc().toIso8601String(),
        'endsAt': now.add(const Duration(days: 30)).toUtc().toIso8601String(),
        'offeringIds': [offeringId],
      });
      await ref
          .read(serviceProviderWorkspaceControllerProvider.notifier)
          .loadWorkspace();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نشر العرض على الخدمة.')),
        );
      }
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر نشر العرض: $exception')));
      }
    } finally {
      titleCtrl.dispose();
      valueCtrl.dispose();
    }
  }

  Widget _employeesSection(
    BuildContext context,
    WidgetRef ref, {
    required ServiceProviderWorkspaceModel workspace,
    required bool canManageEmployees,
    required bool canViewAuditLog,
  }) {
    final employees = workspace.employees;
    final activityLogs = workspace.activityLogs;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الموظفون / Employees',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (canManageEmployees)
                  FilledButton.tonalIcon(
                    onPressed: () => _openServiceProviderEmployeeDialog(
                      context,
                      ref,
                      workspace,
                    ),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('دعوة'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!canManageEmployees)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'لا تملك صلاحية إدارة الموظفين / You cannot manage employees.',
                ),
              ),
            if (employees.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('لا يوجد موظفون بعد.'),
              )
            else
              ...employees.map(
                (employee) => _employeeCard(
                  context,
                  ref,
                  workspace: workspace,
                  employee: employee,
                  canManageEmployees: canManageEmployees,
                ),
              ),
            if (canViewAuditLog) ...[
              const SizedBox(height: 12),
              Text(
                'سجل النشاط / Activity log',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              if (activityLogs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('لا يوجد سجل نشاط بعد.'),
                )
              else
                ...activityLogs
                    .take(12)
                    .map(
                      (row) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.history_rounded),
                          title: Text(
                            '${row.employeeFullName} • ${row.actionKey}',
                          ),
                          subtitle: Text(
                            [
                              if ((row.actorFullName ?? '').trim().isNotEmpty)
                                'By: ${row.actorFullName}',
                              if ((row.reason ?? '').trim().isNotEmpty)
                                'Reason: ${row.reason}',
                              if ((row.createdAt ?? '').trim().isNotEmpty)
                                '${row.createdAt}',
                            ].join('\n'),
                          ),
                          isThreeLine: true,
                        ),
                      ),
                    ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _employeeCard(
    BuildContext context,
    WidgetRef ref, {
    required ServiceProviderWorkspaceModel workspace,
    required ServiceProviderEmployeeModel employee,
    required bool canManageEmployees,
  }) {
    final profile = employee.profile;
    final permissions = profile?.permissions ?? const <String>[];
    final isActive = profile?.isActive ?? true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: canManageEmployees
            ? () => _openServiceProviderEmployeeDialog(
                context,
                ref,
                workspace,
                employee: employee,
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      employee.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: isActive
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.12),
                    ),
                    child: Text(isActive ? 'نشط / Active' : 'موقوف / Inactive'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(employee.phone),
              if ((employee.displayName ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Display name: ${employee.displayName}'),
              ],
              if ((employee.contactEmail ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Email: ${employee.contactEmail}'),
              ],
              const SizedBox(height: 4),
              Text('Role: ${profile?.roleTag ?? employee.role}'),
              if ((profile?.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Notes: ${profile!.notes}'),
              ],
              if (permissions.isNotEmpty) ...[
                const SizedBox(height: 8),
                _permissionChips(
                  context,
                  permissions,
                  kind: WorkspacePermissionKind.serviceProvider,
                ),
              ],
              if (canManageEmployees) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: OutlinedButton.icon(
                    onPressed: () => _openServiceProviderEmployeeDialog(
                      context,
                      ref,
                      workspace,
                      employee: employee,
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _permissionChips(
    BuildContext context,
    List<String> permissions, {
    WorkspacePermissionKind kind = WorkspacePermissionKind.serviceProvider,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: permissions
          .map(
            (permission) => Chip(
              label: Text(
                workspacePermissionLabelFor(context, permission, kind: kind),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _permissionSelector(
    BuildContext context, {
    required Set<String> selected,
    required ValueChanged<String> onToggle,
  }) {
    final catalog = workspacePermissionCatalog(
      WorkspacePermissionKind.serviceProvider,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: catalog
          .map(
            (permission) => FilterChip(
              selected: selected.contains(permission),
              label: Text(
                workspacePermissionLabelFor(
                  context,
                  permission,
                  kind: WorkspacePermissionKind.serviceProvider,
                ),
              ),
              onSelected: (_) {
                onToggle(permission);
              },
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _openServiceProviderEmployeeDialog(
    BuildContext context,
    WidgetRef ref,
    ServiceProviderWorkspaceModel workspace, {
    ServiceProviderEmployeeModel? employee,
  }) async {
    final profile = employee?.profile;
    final isInvite = employee == null;
    final fullNameCtrl = TextEditingController(text: employee?.fullName ?? '');
    final phoneCtrl = TextEditingController(text: employee?.phone ?? '');
    final pinCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController(
      text: profile?.displayName ?? employee?.displayName ?? '',
    );
    final emailCtrl = TextEditingController(
      text: profile?.contactEmail ?? employee?.contactEmail ?? '',
    );
    final roleCtrl = TextEditingController(
      text: profile?.roleTag ?? employee?.role ?? 'staff',
    );
    final notesCtrl = TextEditingController(text: profile?.notes ?? '');
    final reasonCtrl = TextEditingController();
    final selectedPermissions = <String>{
      if (profile?.permissions != null) ...profile!.permissions,
    };
    var isActive = profile?.isActive ?? true;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                isInvite
                    ? 'دعوة موظف / Invite employee'
                    : 'تعديل موظف / Edit employee',
              ),
              content: SizedBox(
                width: 540,
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
                      if (isInvite) ...[
                        TextField(
                          controller: fullNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'الاسم الكامل / Full name',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'الهاتف / Phone',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: pinCtrl,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'PIN / رمز الدخول',
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        controller: displayNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الاسم المعروض / Display name',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني / Email',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: roleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Role tag',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes / ملاحظات',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: reasonCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Reason / السبب',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'الصلاحيات / Permissions',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _permissionSelector(
                        context,
                        selected: selectedPermissions,
                        onToggle: (permission) {
                          setDialogState(() {
                            if (selectedPermissions.contains(permission)) {
                              selectedPermissions.remove(permission);
                            } else {
                              selectedPermissions.add(permission);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active / نشط'),
                        value: isActive,
                        onChanged: (value) =>
                            setDialogState(() => isActive = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () async {
                    final roleTag = roleCtrl.text.trim().isEmpty
                        ? 'staff'
                        : roleCtrl.text.trim();
                    if (isInvite) {
                      if (fullNameCtrl.text.trim().isEmpty) {
                        setDialogState(
                          () => dialogError = 'Full name is required.',
                        );
                        return;
                      }
                      if (phoneCtrl.text.trim().isEmpty) {
                        setDialogState(
                          () => dialogError = 'Phone is required.',
                        );
                        return;
                      }
                      if (pinCtrl.text.trim().isEmpty) {
                        setDialogState(() => dialogError = 'PIN is required.');
                        return;
                      }
                      await ref
                          .read(
                            serviceProviderWorkspaceControllerProvider.notifier,
                          )
                          .inviteEmployee({
                            'fullName': fullNameCtrl.text.trim(),
                            'phone': phoneCtrl.text.trim(),
                            'pin': pinCtrl.text.trim(),
                            'roleTag': roleTag,
                            if (displayNameCtrl.text.trim().isNotEmpty)
                              'displayName': displayNameCtrl.text.trim(),
                            if (emailCtrl.text.trim().isNotEmpty)
                              'contactEmail': emailCtrl.text.trim(),
                            if (notesCtrl.text.trim().isNotEmpty)
                              'notes': notesCtrl.text.trim(),
                            if (reasonCtrl.text.trim().isNotEmpty)
                              'reason': reasonCtrl.text.trim(),
                            'isActive': isActive,
                            if (selectedPermissions.isNotEmpty)
                              'permissions': selectedPermissions.toList(
                                growable: false,
                              ),
                          });
                    } else {
                      final employeeUserId = employee.userId;
                      if (employeeUserId <= 0) {
                        setDialogState(
                          () => dialogError = 'Employee is required.',
                        );
                        return;
                      }
                      await ref
                          .read(
                            serviceProviderWorkspaceControllerProvider.notifier,
                          )
                          .upsertEmployee({
                            'employeeUserId': employeeUserId,
                            'roleTag': roleTag,
                            if (displayNameCtrl.text.trim().isNotEmpty)
                              'displayName': displayNameCtrl.text.trim(),
                            if (emailCtrl.text.trim().isNotEmpty)
                              'contactEmail': emailCtrl.text.trim(),
                            if (notesCtrl.text.trim().isNotEmpty)
                              'notes': notesCtrl.text.trim(),
                            if (reasonCtrl.text.trim().isNotEmpty)
                              'reason': reasonCtrl.text.trim(),
                            'isActive': isActive,
                            if (selectedPermissions.isNotEmpty)
                              'permissions': selectedPermissions.toList(
                                growable: false,
                              ),
                          });
                    }
                    final latest = ref.read(
                      serviceProviderWorkspaceControllerProvider,
                    );
                    if (latest.error != null) {
                      setDialogState(() => dialogError = latest.error);
                      return;
                    }
                    if (!context.mounted) return;
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(isInvite ? 'دعوة' : 'حفظ'),
                ),
              ],
            );
          },
        );
      },
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
    final amount = _serviceRequestGrossAmount(request);
    final commission = _servicePlatformCommission(amount);
    final lifecycleStatus = _serviceRequestLifecycleStatus(
      request,
    ).toLowerCase();
    final isV2Booking =
        (request.bookingFlowKind ?? '').trim().toUpperCase() == 'V2';
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
                  _requestStatusLabel(_serviceRequestLifecycleStatus(request)),
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
            if (amount > 0) ...[
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black.withValues(alpha: 0.04),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('قيمة الحجز: ${_formatIqd(amount)}'),
                      Text('استقطاع مسلكي 10%: ${_formatIqd(commission)}'),
                      Text(
                        'صافي مقدم الخدمة: ${_formatIqd(amount - commission)}',
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
                if (<String>{
                  'pending',
                  'awaiting_provider',
                  'pending_provider_confirmation',
                }.contains(lifecycleStatus))
                  OutlinedButton(
                    onPressed: () => onStatusTap('accepted'),
                    child: const Text('قبول'),
                  ),
                if (<String>{
                  'accepted',
                  'scheduled',
                  'confirmed',
                }.contains(lifecycleStatus))
                  OutlinedButton(
                    onPressed: () => onStatusTap('in_progress'),
                    child: const Text('بدء التنفيذ'),
                  ),
                if (lifecycleStatus == 'in_progress')
                  OutlinedButton(
                    onPressed: () => onStatusTap(
                      isV2Booking ? 'PROVIDER_COMPLETED' : 'completed',
                    ),
                    child: const Text('إكمال'),
                  ),
                if (<String>{
                  'pending',
                  'awaiting_provider',
                  'pending_provider_confirmation',
                }.contains(lifecycleStatus))
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

class _AllServiceOfferingsScreen extends ConsumerStatefulWidget {
  const _AllServiceOfferingsScreen({required this.canEdit});

  final bool canEdit;

  @override
  ConsumerState<_AllServiceOfferingsScreen> createState() =>
      _AllServiceOfferingsScreenState();
}

class _AllServiceOfferingsScreenState
    extends ConsumerState<_AllServiceOfferingsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String _status = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serviceProviderWorkspaceControllerProvider);
    final offerings =
        state.workspace?.provider.offerings ?? const <ServiceOfferingModel>[];
    final query = _search.trim().toLowerCase();
    final filtered = offerings
        .where((offering) {
          final matchesStatus =
              _status == 'all' || offering.moderationStatus == _status;
          if (!matchesStatus) return false;
          if (query.isEmpty) return true;
          return <String>[
            offering.name,
            offering.description ?? '',
            offering.mainCategoryName ?? '',
            offering.subcategoryName ?? '',
          ].any((value) => value.toLowerCase().contains(query));
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text('كل الخدمات (${offerings.length})'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: state.loadingWorkspace
                ? null
                : () => ref
                      .read(serviceProviderWorkspaceControllerProvider.notifier)
                      .loadWorkspace(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  labelText: 'البحث باسم الخدمة أو القسم',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _search = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('الكل')),
                  ButtonSegment(value: 'approved', label: Text('منشورة')),
                  ButtonSegment(
                    value: 'pending',
                    label: Text('بانتظار المراجعة'),
                  ),
                  ButtonSegment(
                    value: 'changes_requested',
                    label: Text('تحتاج تعديل'),
                  ),
                  ButtonSegment(value: 'hidden', label: Text('مخفية')),
                ],
                selected: {_status},
                onSelectionChanged: (value) {
                  if (value.isEmpty) return;
                  setState(() => _status = value.first);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'النتائج: ${filtered.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Expanded(
              child: state.loadingWorkspace && offerings.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? const Center(child: Text('لا توجد خدمات مطابقة.'))
                  : RefreshIndicator(
                      onRefresh: () => ref
                          .read(
                            serviceProviderWorkspaceControllerProvider.notifier,
                          )
                          .loadWorkspace(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final offering = filtered[index];
                          final category =
                              [
                                    offering.mainCategoryName,
                                    offering.subcategoryName,
                                  ]
                                  .whereType<String>()
                                  .where((value) => value.isNotEmpty)
                                  .join(' • ');
                          return Card(
                            child: ListTile(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ServiceOfferingDetailsScreen(
                                    offeringId: offering.id,
                                  ),
                                ),
                              ),
                              leading: CircleAvatar(
                                child: Text('${index + 1}'),
                              ),
                              title: Text(
                                offering.name,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (category.isNotEmpty) category,
                                  offering.displayPriceText,
                                  _offeringModerationStatusLabel(
                                    offering.moderationStatus,
                                  ),
                                ].join(' • '),
                                textDirection: TextDirection.rtl,
                              ),
                              trailing: widget.canEdit
                                  ? IconButton(
                                      tooltip: 'تعديل الخدمة',
                                      onPressed: () =>
                                          _showCreateOfferingDialog(
                                            context,
                                            ref,
                                            existingOffering: offering,
                                          ),
                                      icon: const Icon(Icons.edit_outlined),
                                    )
                                  : const Icon(Icons.chevron_right_rounded),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceOfferingWorkspaceCard extends StatelessWidget {
  final ServiceOfferingModel offering;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;

  const _ServiceOfferingWorkspaceCard({
    required this.offering,
    required this.canEdit,
    required this.onOpen,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final coverUrl = offering.primaryMediaUrl ?? offering.provider.logoUrl;
    final statusLabel = _offeringModerationStatusLabel(
      offering.moderationStatus,
    );
    final moderationNote = (offering.moderationNote ?? '').trim();
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if ((coverUrl ?? '').trim().isNotEmpty)
                    CachedAppImage(
                      imageUrl: coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (placeholderContext, placeholderChild) =>
                          _offeringPlaceholder(),
                      errorWidget: (errorContext, errorChild, errorProgress) =>
                          _offeringPlaceholder(),
                    )
                  else
                    _offeringPlaceholder(),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.08),
                            Colors.black.withValues(alpha: 0.58),
                          ],
                        ),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: 10,
                    start: 10,
                    child: _statusBadge(context, statusLabel),
                  ),
                  if (offering.hasActivePromotion)
                    PositionedDirectional(
                      top: 10,
                      end: 10,
                      child: _statusBadge(
                        context,
                        'عرض',
                        color: Colors.orangeAccent,
                        icon: Icons.local_offer_outlined,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        child: Text(
                          offering.name,
                          textDirection: TextDirection.rtl,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        offering.displayPriceText,
                        textDirection: TextDirection.rtl,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    offering.provider.businessName ?? '',
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (moderationNote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        moderationNote,
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if ((offering.mainCategoryName ?? '').trim().isNotEmpty)
                        _smallChip(
                          context,
                          offering.mainCategoryName!,
                          Icons.category_outlined,
                        ),
                      if ((offering.subcategoryName ?? '').trim().isNotEmpty)
                        _smallChip(
                          context,
                          offering.subcategoryName!,
                          Icons.subdirectory_arrow_left_rounded,
                        ),
                      _smallChip(context, statusLabel, Icons.verified_outlined),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('عرض'),
                      ),
                      const Spacer(),
                      if (canEdit && onEdit != null)
                        FilledButton.tonalIcon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('تعديل'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _offeringPlaceholder() {
    return Container(
      color: Colors.black.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: const Icon(Icons.design_services_outlined, size: 38),
    );
  }

  Widget _statusBadge(
    BuildContext context,
    String label, {
    Color? color,
    IconData? icon,
  }) {
    final badgeColor = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: badgeColor.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: badgeColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(color: badgeColor, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _smallChip(BuildContext context, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 14), const SizedBox(width: 4), Text(label)],
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
    case 'changes_requested':
      return 'تحتاج تعديلات';
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
    case 'pending_provider_confirmation':
      return 'بانتظار قبول مقدم الخدمة';
    case 'accepted':
    case 'confirmed':
      return 'مقبول';
    case 'scheduled':
      return 'مجدول';
    case 'in_progress':
      return 'قيد التنفيذ';
    case 'provider_completed':
      return 'تم الإنجاز - بانتظار تأكيد الزبون';
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
  WidgetRef ref, {
  ServiceOfferingModel? existingOffering,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final roots = <ServiceCategoryModel>[];

  List<ServiceCategoryModel> sortRoots(List<ServiceCategoryModel> items) {
    items.sort(
      (a, b) => a.sortOrder == b.sortOrder
          ? a.name.compareTo(b.name)
          : a.sortOrder.compareTo(b.sortOrder),
    );
    for (final root in items) {
      root.children.sort(
        (a, b) => a.sortOrder == b.sortOrder
            ? a.name.compareTo(b.name)
            : a.sortOrder.compareTo(b.sortOrder),
      );
    }
    return items;
  }

  try {
    final rows = await ref.read(servicesApiProvider).listPublicCategories();
    roots.addAll(
      rows
          .map(ServiceCategoryModel.fromJson)
          .where((item) => item.level == 1 && item.isActive && item.isPublic),
    );
    sortRoots(roots);
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

  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CreateServiceOfferingDialog(
      roots: sortRoots(roots),
      sortRoots: sortRoots,
      existingOffering: existingOffering,
    ),
  );

  if (!context.mounted) return;
  if (saved == true) {
    await ref
        .read(serviceProviderWorkspaceControllerProvider.notifier)
        .loadWorkspace();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          existingOffering == null
              ? 'تم إنشاء الخدمة بنجاح.'
              : 'تم حفظ تعديلات الخدمة بنجاح.',
        ),
      ),
    );
  }
}

class _CreateServiceOfferingDialog extends ConsumerStatefulWidget {
  final List<ServiceCategoryModel> roots;
  final List<ServiceCategoryModel> Function(List<ServiceCategoryModel>)
  sortRoots;
  final ServiceOfferingModel? existingOffering;

  const _CreateServiceOfferingDialog({
    required this.roots,
    required this.sortRoots,
    this.existingOffering,
  });

  @override
  ConsumerState<_CreateServiceOfferingDialog> createState() =>
      _CreateServiceOfferingDialogState();
}

class _CreateServiceOfferingDialogState
    extends ConsumerState<_CreateServiceOfferingDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _startsFromCtrl;
  late final TextEditingController _priceLabelCtrl;
  late List<ServiceCategoryModel> _roots;
  final List<LocalImageFile> _selectedMedia = <LocalImageFile>[];
  int? _selectedMainCategoryId;
  int? _selectedSubcategoryId;
  String _executionMode = 'both';
  String _pricingModel = 'custom_quote';
  String? _dialogError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final offering = widget.existingOffering;
    _nameCtrl = TextEditingController(text: offering?.name ?? '');
    _descriptionCtrl = TextEditingController(text: offering?.description ?? '');
    _startsFromCtrl = TextEditingController(
      text: offering?.startsFromPrice == null
          ? ''
          : offering!.startsFromPrice!.toString(),
    );
    _roots = widget.sortRoots(
      widget.roots.map((item) => item).toList(growable: true),
    );
    final requestedMainCategoryId = offering?.mainCategoryId;
    final matchingRoot = requestedMainCategoryId == null
        ? null
        : _roots
              .where((item) => item.id == requestedMainCategoryId)
              .firstOrNull;
    final rootContainingSubcategory = offering?.subcategoryId == null
        ? null
        : _roots
              .where(
                (item) => item.children.any(
                  (child) => child.id == offering!.subcategoryId,
                ),
              )
              .firstOrNull;
    final initialMainCategoryId =
        matchingRoot?.id ??
        rootContainingSubcategory?.id ??
        (_roots.isNotEmpty ? _roots.first.id : null);
    _selectedMainCategoryId = initialMainCategoryId;
    final initialChildren = _roots
        .where((item) => item.id == initialMainCategoryId)
        .expand((item) => item.children)
        .toList(growable: false);
    _selectedSubcategoryId =
        initialChildren.any((child) => child.id == offering?.subcategoryId)
        ? offering?.subcategoryId
        : null;
    _executionMode = offering?.executionMode ?? 'both';
    final pricingOptions =
        offering?.pricingOptions ?? const <ServicePricingOptionModel>[];
    final leadPricing = pricingOptions.isEmpty
        ? null
        : pricingOptions.firstWhere(
            (item) => item.isDefault,
            orElse: () => pricingOptions.first,
          );
    if (leadPricing != null) {
      _pricingModel = leadPricing.pricingModel;
      _priceLabelCtrl = TextEditingController(text: leadPricing.label ?? '');
      if (leadPricing.amount != null) {
        _startsFromCtrl.text = leadPricing.amount.toString();
      }
    } else {
      _pricingModel = 'custom_quote';
      _priceLabelCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _startsFromCtrl.dispose();
    _priceLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final startsFromPrice = double.tryParse(_startsFromCtrl.text.trim());

    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _dialogError = 'يرجى إدخال اسم الخدمة.');
      return;
    }
    if (_selectedMainCategoryId == null) {
      setState(() => _dialogError = 'يرجى اختيار الفئة الرئيسية.');
      return;
    }
    if (!['custom_quote', 'inspection_required'].contains(_pricingModel) &&
        startsFromPrice == null) {
      setState(() => _dialogError = 'يرجى إدخال السعر لهذا النمط.');
      return;
    }

    try {
      setState(() {
        _submitting = true;
        _dialogError = null;
      });
      final payload = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
        'mainCategoryId': _selectedMainCategoryId,
        if (_selectedSubcategoryId != null)
          'subcategoryId': _selectedSubcategoryId,
        'executionMode': _executionMode,
        'startsFromPrice': startsFromPrice,
        'pricingOptions': [
          {
            'pricingModel': _pricingModel,
            'pricingUnit': switch (_pricingModel) {
              'per_hour' => 'hour',
              'per_day' => 'day',
              'per_device' => 'device',
              'per_room' => 'room',
              'per_meter' => 'meter',
              'per_item' => 'item',
              'per_visit' => 'visit',
              'fixed_package' => 'package',
              _ => 'job',
            },
            if (_priceLabelCtrl.text.trim().isNotEmpty)
              'label': _priceLabelCtrl.text.trim(),
            if (![
              'custom_quote',
              'inspection_required',
            ].contains(_pricingModel))
              'amount': startsFromPrice,
            'isDefault': true,
          },
        ],
      };
      final mediaFiles = List<LocalImageFile>.unmodifiable(_selectedMedia);
      if (widget.existingOffering == null) {
        await ref
            .read(servicesApiProvider)
            .createOffering(payload, mediaFiles: mediaFiles);
      } else {
        await ref
            .read(servicesApiProvider)
            .updateOffering(
              widget.existingOffering!.id,
              payload,
              mediaFiles: mediaFiles,
            );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _dialogError = mapDioError(
          e,
          fallback: widget.existingOffering != null
              ? 'تعذر تعديل الخدمة. تحقق من البيانات ثم حاول مرة أخرى.'
              : 'تعذر إنشاء الخدمة. تحقق من البيانات ثم حاول مرة أخرى.',
        );
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _dialogError = 'تعذر حفظ الخدمة: $e';
      });
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dropdownMenuHeight = MediaQuery.sizeOf(context).height * 0.42;
    final dropdownTextStyle = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );
    final dropdownBorderRadius = BorderRadius.circular(14);
    final isEditing = widget.existingOffering != null;
    final existingMediaUrl =
        widget.existingOffering?.primaryMediaUrl ??
        widget.existingOffering?.provider.logoUrl;

    return AlertDialog(
      title: Text(isEditing ? 'تعديل الخدمة' : 'إنشاء خدمة جديدة'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_dialogError != null) ...[
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
                    _dialogError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم الخدمة'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'الوصف'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'صور وفيديو الخدمة',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _selectedMedia.length >= 10
                    ? null
                    : () async {
                        final picked = await pickMultipleImagesFromDevice(
                          maxFiles: 10 - _selectedMedia.length,
                        );
                        if (!mounted || picked.isEmpty) return;
                        setState(() {
                          _selectedMedia.addAll(picked);
                          _dialogError = null;
                        });
                      },
                icon: const Icon(Icons.collections_outlined),
                label: Text(
                  _selectedMedia.isEmpty
                      ? 'إضافة عدة صور'
                      : 'إضافة صور أخرى (${_selectedMedia.length}/10)',
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _selectedMedia.length >= 10
                    ? null
                    : () async {
                        final picked = await pickVideoFromDevice();
                        if (!mounted || picked == null) return;
                        setState(() {
                          _selectedMedia.add(picked);
                          _dialogError = null;
                        });
                      },
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('إضافة فيديو'),
              ),
              if (_selectedMedia.isEmpty &&
                  (existingMediaUrl ?? '').trim().isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'سيتم الاحتفاظ بالوسائط الحالية ما لم ترفع وسائط جديدة.',
                  ),
                ),
              if (_selectedMedia.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedMedia.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final file = _selectedMedia[index];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: file.isVideo
                                ? Container(
                                    width: 72,
                                    height: 72,
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.play_circle_fill_rounded,
                                      size: 34,
                                    ),
                                  )
                                : Image.memory(
                                    file.bytes!,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            child: IconButton.filledTonal(
                              tooltip: 'حذف',
                              visualDensity: VisualDensity.compact,
                              iconSize: 15,
                              onPressed: () => setState(
                                () => _selectedMedia.removeAt(index),
                              ),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: const Key('service_main_category_dropdown'),
                value: _selectedMainCategoryId,
                isExpanded: true,
                menuMaxHeight: dropdownMenuHeight,
                borderRadius: dropdownBorderRadius,
                dropdownColor: theme.canvasColor,
                style: dropdownTextStyle,
                decoration: InputDecoration(
                  labelText: 'القسم الرئيسي (${_roots.length})',
                ),
                items: _roots
                    .map(
                      (item) => DropdownMenuItem<int>(
                        value: item.id,
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedMainCategoryId = value;
                    _selectedSubcategoryId = null;
                    _dialogError = null;
                  });
                },
              ),
              if (_selectedMainCategoryId != null &&
                  _roots
                      .where((item) => item.id == _selectedMainCategoryId)
                      .expand((item) => item.children)
                      .isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  key: const Key('service_subcategory_dropdown'),
                  value: _selectedSubcategoryId,
                  isExpanded: true,
                  menuMaxHeight: dropdownMenuHeight,
                  borderRadius: dropdownBorderRadius,
                  dropdownColor: theme.canvasColor,
                  style: dropdownTextStyle,
                  hint: const Text('اختر القسم الفرعي'),
                  decoration: InputDecoration(
                    labelText:
                        'القسم الفرعي (${_roots.where((item) => item.id == _selectedMainCategoryId).expand((item) => item.children).length})',
                    suffixIcon: _selectedSubcategoryId == null
                        ? null
                        : IconButton(
                            tooltip: 'إلغاء اختيار القسم الفرعي',
                            onPressed: () =>
                                setState(() => _selectedSubcategoryId = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  items: _roots
                      .where((item) => item.id == _selectedMainCategoryId)
                      .expand((item) => item.children)
                      .map(
                        (item) => DropdownMenuItem<int>(
                          value: item.id,
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() {
                    _selectedSubcategoryId = value;
                    _dialogError = null;
                  }),
                ),
              ],
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _executionMode,
                isExpanded: true,
                menuMaxHeight: dropdownMenuHeight,
                borderRadius: dropdownBorderRadius,
                dropdownColor: theme.canvasColor,
                style: dropdownTextStyle,
                items: const [
                  DropdownMenuItem(value: 'home', child: Text('منزلية')),
                  DropdownMenuItem(
                    value: 'provider_location',
                    child: Text('داخل المحل'),
                  ),
                  DropdownMenuItem(value: 'both', child: Text('كلاهما')),
                  DropdownMenuItem(value: 'remote', child: Text('عن بُعد')),
                ],
                onChanged: (value) => setState(() {
                  _executionMode = value ?? 'both';
                }),
                decoration: const InputDecoration(labelText: 'نمط التنفيذ'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _pricingModel,
                isExpanded: true,
                menuMaxHeight: dropdownMenuHeight,
                borderRadius: dropdownBorderRadius,
                dropdownColor: theme.canvasColor,
                style: dropdownTextStyle,
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
                  DropdownMenuItem(value: 'per_hour', child: Text('بالساعة')),
                  DropdownMenuItem(value: 'per_day', child: Text('باليوم')),
                  DropdownMenuItem(
                    value: 'per_device',
                    child: Text('لكل جهاز'),
                  ),
                  DropdownMenuItem(value: 'per_room', child: Text('لكل غرفة')),
                  DropdownMenuItem(value: 'per_meter', child: Text('بالمتر')),
                  DropdownMenuItem(value: 'per_item', child: Text('لكل قطعة')),
                  DropdownMenuItem(value: 'per_visit', child: Text('للزيارة')),
                ],
                onChanged: (value) => setState(() {
                  _pricingModel = value ?? 'custom_quote';
                }),
                decoration: const InputDecoration(labelText: 'نمط السعر'),
              ),
              const SizedBox(height: 8),
              if (![
                'custom_quote',
                'inspection_required',
              ].contains(_pricingModel)) ...[
                TextField(
                  key: const Key('service_price_field'),
                  controller: _startsFromCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'السعر'),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                key: const Key('service_price_label_field'),
                controller: _priceLabelCtrl,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'السعر مقابل ماذا؟',
                  hintText: 'مثال: للساعة، للمتر، للعملية كاملة، بعد المعاينة',
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'حفظ التعديلات' : 'إنشاء'),
        ),
      ],
    );
  }
}
