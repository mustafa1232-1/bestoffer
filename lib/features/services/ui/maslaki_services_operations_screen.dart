import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/login_screen.dart';
import '../../auth/state/auth_controller.dart';
import '../models/service_models.dart';
import '../state/service_provider_workspace_controller.dart';
import 'service_provider_workspace_screen.dart';
import 'service_request_details_screen.dart';

class MaslakiServicesOperationsScreen extends ConsumerStatefulWidget {
  const MaslakiServicesOperationsScreen({super.key});

  @override
  ConsumerState<MaslakiServicesOperationsScreen> createState() =>
      _MaslakiServicesOperationsScreenState();
}

class _MaslakiServicesOperationsScreenState
    extends ConsumerState<MaslakiServicesOperationsScreen> {
  int _selectedSection = 0;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.isMaslakiServicesOperator) {
      return _ServicesOperatorAccessDenied(
        onLogout: () => _logout(context, ref),
      );
    }

    if (_selectedSection == 1) {
      return Scaffold(
        body: const ServiceProviderWorkspaceScreen(centralOperationsMode: true),
        bottomNavigationBar: _operationsNavigationBar(),
      );
    }

    final state = ref.watch(serviceProviderWorkspaceControllerProvider);
    final ctrl = ref.read(serviceProviderWorkspaceControllerProvider.notifier);
    final requests = _sortRequests(state.requests);
    final incoming = _filterRequests(requests, const {
      'pending',
      'awaiting_provider',
      'pending_provider_confirmation',
      'submitted',
      'quote_sent',
    });
    final inProgress = _filterRequests(requests, const {
      'accepted',
      'scheduled',
      'confirmed',
      'in_progress',
      'provider_completed',
    });
    final closed = _filterRequests(requests, const {
      'completed',
      'cancelled',
      'rejected',
      'cancelled_by_customer',
      'cancelled_by_provider',
      'cancelled_by_admin',
      'rejected_by_provider',
      'expired',
      'disputed',
    });
    final needsFollowUp = requests
        .where((request) => _needsFollowUp(_requestStatus(request)))
        .toList(growable: false);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('إدارة خدمات مسلكي'),
              SizedBox(height: 2),
              Text(
                'الطلبات، الحجوزات، المتابعة، والمحادثات من التفاصيل',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: () => _refresh(ctrl),
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'تسجيل خروج',
              onPressed: () => _logout(context, ref),
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'الكل ${requests.length}'),
              Tab(text: 'واردة ${incoming.length}'),
              Tab(text: 'تحتاج متابعة ${needsFollowUp.length}'),
              Tab(text: 'قيد التنفيذ ${inProgress.length}'),
              Tab(text: 'مغلقة ${closed.length}'),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () => _refresh(ctrl),
          child: TabBarView(
            children: [
              _OperationsRequestList(
                loading: state.loadingWorkspace || state.loadingRequests,
                error: state.error,
                requests: requests,
                emptyText: 'لا توجد طلبات خدمات حتى الآن.',
                onOpen: (request) => _openDetails(context, request),
                onStatus: (request, status) =>
                    _updateStatus(ctrl, request, status),
                onRoute: (request) => _routeRequest(context, ctrl, request),
              ),
              _OperationsRequestList(
                loading: state.loadingRequests,
                error: state.error,
                requests: incoming,
                emptyText: 'لا توجد طلبات واردة الآن.',
                onOpen: (request) => _openDetails(context, request),
                onStatus: (request, status) =>
                    _updateStatus(ctrl, request, status),
                onRoute: (request) => _routeRequest(context, ctrl, request),
              ),
              _OperationsRequestList(
                loading: state.loadingRequests,
                error: state.error,
                requests: needsFollowUp,
                emptyText: 'لا توجد طلبات تحتاج متابعة حاليًا.',
                onOpen: (request) => _openDetails(context, request),
                onStatus: (request, status) =>
                    _updateStatus(ctrl, request, status),
                onRoute: (request) => _routeRequest(context, ctrl, request),
              ),
              _OperationsRequestList(
                loading: state.loadingRequests,
                error: state.error,
                requests: inProgress,
                emptyText: 'لا توجد خدمات قيد التنفيذ الآن.',
                onOpen: (request) => _openDetails(context, request),
                onStatus: (request, status) =>
                    _updateStatus(ctrl, request, status),
                onRoute: (request) => _routeRequest(context, ctrl, request),
              ),
              _OperationsRequestList(
                loading: state.loadingRequests,
                error: state.error,
                requests: closed,
                emptyText: 'لا توجد طلبات مغلقة في هذا العرض.',
                onOpen: (request) => _openDetails(context, request),
                onStatus: (request, status) =>
                    _updateStatus(ctrl, request, status),
                onRoute: (request) => _routeRequest(context, ctrl, request),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _operationsNavigationBar(),
      ),
    );
  }

  Widget _operationsNavigationBar() {
    return NavigationBar(
      selectedIndex: _selectedSection,
      onDestinationSelected: (index) {
        if (_selectedSection == index) return;
        setState(() => _selectedSection = index);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.inbox_outlined),
          selectedIcon: Icon(Icons.inbox_rounded),
          label: 'استقبال الطلبات',
        ),
        NavigationDestination(
          icon: Icon(Icons.design_services_outlined),
          selectedIcon: Icon(Icons.design_services_rounded),
          label: 'نشر وإدارة الخدمات',
        ),
      ],
    );
  }

  static Future<void> _refresh(ServiceProviderWorkspaceController ctrl) async {
    await ctrl.loadWorkspace();
    await ctrl.loadRequests();
  }

  static Future<void> _updateStatus(
    ServiceProviderWorkspaceController ctrl,
    ServiceRequestModel request,
    String status,
  ) {
    final version = request.bookingVersion;
    return ctrl.updateRequestStatus(
      requestId: request.id,
      status: status,
      expectedVersion: version,
      idempotencyKey: version == null
          ? null
          : 'services-ops:${request.id}:$version:$status',
    );
  }

  static Future<void> _routeRequest(
    BuildContext context,
    ServiceProviderWorkspaceController ctrl,
    ServiceRequestModel request,
  ) async {
    final nameController = TextEditingController(
      text: request.assignedProfessionalName ?? '',
    );
    final phoneController = TextEditingController(
      text: request.assignedProfessionalPhone ?? '',
    );
    final noteController = TextEditingController(
      text: request.assignmentNote ?? '',
    );
    var routingStatus =
        request.routingStatus == null || request.routingStatus == 'new'
        ? 'triaged'
        : request.routingStatus!;
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('توجيه طلب الخدمة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: routingStatus,
                  decoration: const InputDecoration(labelText: 'مرحلة التوجيه'),
                  items: const [
                    DropdownMenuItem(
                      value: 'triaged',
                      child: Text('تمت المراجعة'),
                    ),
                    DropdownMenuItem(
                      value: 'assigned',
                      child: Text('تم تعيين مختص'),
                    ),
                    DropdownMenuItem(
                      value: 'contacted',
                      child: Text('تم التواصل مع المختص'),
                    ),
                    DropdownMenuItem(
                      value: 'en_route',
                      child: Text('المختص في الطريق'),
                    ),
                    DropdownMenuItem(
                      value: 'resolved',
                      child: Text('تم الإنجاز'),
                    ),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('إلغاء الطلب'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => routingStatus = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(labelText: 'اسم المختص'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(labelText: 'رقم المختص'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteController,
                  textDirection: TextDirection.rtl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة واضحة للزبون أو فريق التشغيل',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () {
                final needsProfessional = const {
                  'assigned',
                  'contacted',
                  'en_route',
                }.contains(routingStatus);
                if (needsProfessional &&
                    nameController.text.trim().isEmpty &&
                    phoneController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('أدخل اسم المختص أو رقم هاتفه.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, {
                  'routingStatus': routingStatus,
                  'professionalName': nameController.text.trim(),
                  'professionalPhone': phoneController.text.trim(),
                  'note': noteController.text.trim(),
                });
              },
              child: const Text('حفظ وإشعار الزبون'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    phoneController.dispose();
    noteController.dispose();
    if (result == null) return;
    await ctrl.routeCentralRequest(
      requestId: request.id,
      routingStatus: result['routingStatus']!,
      professionalName: result['professionalName'],
      professionalPhone: result['professionalPhone'],
      note: result['note'],
    );
  }

  static Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  static List<ServiceRequestModel> _sortRequests(
    List<ServiceRequestModel> requests,
  ) {
    final copy = List<ServiceRequestModel>.of(requests);
    copy.sort((a, b) {
      final urgencyOrder = {'emergency': 0, 'urgent': 1, 'normal': 2};
      final urgencyCompare = (urgencyOrder[a.urgency] ?? 3).compareTo(
        urgencyOrder[b.urgency] ?? 3,
      );
      if (urgencyCompare != 0) return urgencyCompare;
      final left = DateTime.tryParse(a.createdAt ?? '');
      final right = DateTime.tryParse(b.createdAt ?? '');
      if (left == null && right == null) return b.id.compareTo(a.id);
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
    return copy;
  }

  static List<ServiceRequestModel> _filterRequests(
    List<ServiceRequestModel> requests,
    Set<String> statuses,
  ) {
    return requests
        .where((request) => statuses.contains(_requestStatus(request)))
        .toList(growable: false);
  }

  static bool _needsFollowUp(String status) {
    return const {
      'pending',
      'awaiting_provider',
      'pending_provider_confirmation',
      'submitted',
      'quote_sent',
      'accepted',
      'scheduled',
      'confirmed',
      'provider_completed',
      'disputed',
    }.contains(status);
  }

  static String _normalizeStatus(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  static String _requestStatus(ServiceRequestModel request) {
    return _normalizeStatus(request.bookingStatus ?? request.status);
  }

  static void _openDetails(BuildContext context, ServiceRequestModel request) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceRequestDetailsScreen(requestId: request.id),
      ),
    );
  }
}

class _ServicesOperatorAccessDenied extends StatelessWidget {
  const _ServicesOperatorAccessDenied({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('تشغيل خدمات مسلكي'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 52,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              const Text(
                'هذه الصفحة مخصصة لحساب تشغيل خدمات مسلكي فقط.',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('تسجيل خروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationsRequestList extends StatelessWidget {
  const _OperationsRequestList({
    required this.loading,
    required this.error,
    required this.requests,
    required this.emptyText,
    required this.onOpen,
    required this.onStatus,
    required this.onRoute,
  });

  final bool loading;
  final String? error;
  final List<ServiceRequestModel> requests;
  final String emptyText;
  final ValueChanged<ServiceRequestModel> onOpen;
  final void Function(ServiceRequestModel request, String status) onStatus;
  final ValueChanged<ServiceRequestModel> onRoute;

  @override
  Widget build(BuildContext context) {
    if (loading && requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
      children: [
        _OperationsIntroCard(total: requests.length),
        if (error != null && error!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          _ErrorCard(message: error!),
        ],
        if (requests.isEmpty && !loading)
          Padding(
            padding: const EdgeInsets.only(top: 36),
            child: Center(
              child: Text(
                emptyText,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        for (final request in requests) ...[
          const SizedBox(height: 10),
          _OperationsRequestCard(
            request: request,
            onOpen: () => onOpen(request),
            onStatus: (status) => onStatus(request, status),
            onRoute:
                request.serviceKey == null ||
                    (request.bookingFlowKind ?? '').trim().toUpperCase() == 'V2'
                ? null
                : () => onRoute(request),
          ),
        ],
      ],
    );
  }
}

class _OperationsIntroCard extends StatelessWidget {
  const _OperationsIntroCard({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.42),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            CircleAvatar(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              child: const Icon(Icons.support_agent_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'مركز تشغيل خدمات مسلكي',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'راجع الطلب، افتح التفاصيل والمحادثة، ثم حدّث الحالة بوضوح. العناصر في هذا العرض: $total',
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationsRequestCard extends StatelessWidget {
  const _OperationsRequestCard({
    required this.request,
    required this.onOpen,
    required this.onStatus,
    required this.onRoute,
  });

  final ServiceRequestModel request;
  final VoidCallback onOpen;
  final ValueChanged<String> onStatus;
  final VoidCallback? onRoute;

  @override
  Widget build(BuildContext context) {
    final status = _normalizeStatus(request.bookingStatus ?? request.status);
    final actions = _actionsFor(request);
    final bookingLabel = _bookingLabel(request);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  _StatusBadge(status: status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _requestTitle(request),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                textDirection: TextDirection.rtl,
                children: [
                  _InfoChip(
                    icon: Icons.confirmation_number_outlined,
                    text: request.requestCode.trim().isEmpty
                        ? '#${request.id}'
                        : request.requestCode,
                  ),
                  if (bookingLabel.isNotEmpty)
                    _InfoChip(
                      icon: Icons.event_available_outlined,
                      text: bookingLabel,
                    ),
                  if ('${request.city ?? ''}${request.area ?? ''}'
                      .trim()
                      .isNotEmpty)
                    _InfoChip(
                      icon: Icons.location_on_outlined,
                      text: '${request.city ?? ''} ${request.area ?? ''}'
                          .trim(),
                    ),
                  if ((request.createdAt ?? '').trim().isNotEmpty)
                    _InfoChip(
                      icon: Icons.schedule_rounded,
                      text: _formatDate(request.createdAt),
                    ),
                  if (request.attachments.isNotEmpty)
                    _InfoChip(
                      icon: Icons.attach_file_rounded,
                      text: '${request.attachments.length} مرفق',
                    ),
                  if (request.quotes.isNotEmpty)
                    _InfoChip(
                      icon: Icons.request_quote_outlined,
                      text: '${request.quotes.length} عرض',
                    ),
                  if (request.serviceKey != null)
                    _InfoChip(
                      icon: request.urgency == 'emergency'
                          ? Icons.sos_rounded
                          : Icons.support_agent_rounded,
                      text: request.urgency == 'emergency'
                          ? 'طارئ'
                          : request.urgency == 'urgent'
                          ? 'عاجل'
                          : 'طلب مركزي',
                    ),
                  if ((request.routingStatus ?? '').isNotEmpty)
                    _InfoChip(
                      icon: Icons.route_rounded,
                      text: _routingLabel(request.routingStatus!),
                    ),
                ],
              ),
              if ((request.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  request.notes!.trim(),
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                textDirection: TextDirection.rtl,
                children: [
                  OutlinedButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.forum_outlined),
                    label: const Text('فتح التفاصيل والمحادثة'),
                  ),
                  if (onRoute != null)
                    FilledButton.icon(
                      onPressed: onRoute,
                      icon: const Icon(Icons.route_rounded),
                      label: const Text('توجيه الطلب'),
                    ),
                  for (final action in actions)
                    FilledButton.tonalIcon(
                      onPressed: () => onStatus(action.status),
                      icon: Icon(action.icon),
                      label: Text(action.label),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _requestTitle(ServiceRequestModel request) {
    final serviceTitle = (request.serviceTitle ?? '').trim();
    if (serviceTitle.isNotEmpty) return serviceTitle;
    final offering = (request.offeringName ?? '').trim();
    if (offering.isNotEmpty) return offering;
    return 'طلب خدمة';
  }

  static String _routingLabel(String status) => switch (status) {
    'new' => 'جديد',
    'triaged' => 'تمت المراجعة',
    'assigned' => 'تم تعيين مختص',
    'contacted' => 'تم التواصل',
    'en_route' => 'في الطريق',
    'resolved' => 'منجز',
    'cancelled' => 'ملغي',
    _ => status,
  };

  static String _bookingLabel(ServiceRequestModel request) {
    final bookingStatus = (request.bookingStatus ?? '').trim();
    if (bookingStatus.isEmpty) return '';
    return 'الحجز: ${_bookingStatusLabel(bookingStatus)}';
  }

  static String _bookingStatusLabel(String status) {
    return switch (status.trim().toLowerCase()) {
      'draft' => 'مسودة',
      'pending' => 'بانتظار التأكيد',
      'confirmed' => 'مؤكد',
      'provider_completed' => 'بانتظار الدفع',
      'payment_submitted' => 'بانتظار تأكيد الدفع',
      'payment_confirmed' => 'مكتمل ومدفوع',
      'completed' => 'مكتمل',
      'cancelled' => 'ملغي',
      _ => status,
    };
  }

  static String _normalizeStatus(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  static String _formatDate(String? value) {
    final parsed = DateTime.tryParse((value ?? '').trim());
    if (parsed == null) return (value ?? '').trim();
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  static List<_StatusAction> _actionsFor(ServiceRequestModel request) {
    final status = _normalizeStatus(request.bookingStatus ?? request.status);
    final isV2 = (request.bookingFlowKind ?? '').trim().toUpperCase() == 'V2';
    if (<String>{
      'pending',
      'awaiting_provider',
      'pending_provider_confirmation',
      'submitted',
      'quote_sent',
    }.contains(status)) {
      return [
        _StatusAction(
          status: isV2 ? 'CONFIRMED' : 'accepted',
          label: 'تأكيد الحجز',
          icon: Icons.check_circle_outline_rounded,
        ),
        const _StatusAction(
          status: 'REJECTED',
          label: 'رفض',
          icon: Icons.cancel_outlined,
        ),
      ];
    }
    if (<String>{'accepted', 'scheduled', 'confirmed'}.contains(status)) {
      return [
        _StatusAction(
          status: isV2 ? 'IN_PROGRESS' : 'in_progress',
          label: 'التوجه إلى الزبون',
          icon: Icons.play_arrow_rounded,
        ),
      ];
    }
    if (status == 'in_progress') {
      return [
        _StatusAction(
          status: isV2 ? 'PROVIDER_COMPLETED' : 'completed',
          label: 'تم إنجاز الخدمة',
          icon: Icons.task_alt_rounded,
        ),
      ];
    }
    return const [];
  }
}

class _StatusAction {
  const _StatusAction({
    required this.status,
    required this.label,
    required this.icon,
  });

  final String status;
  final String label;
  final IconData icon;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      'completed' => Colors.green,
      'provider_completed' => Colors.green,
      'in_progress' => Colors.blue,
      'accepted' || 'scheduled' || 'confirmed' => Colors.teal,
      'cancelled' || 'rejected' || 'expired' => scheme.error,
      _ => scheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _statusLabel(status),
        textDirection: TextDirection.rtl,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }

  static String _statusLabel(String status) {
    return switch (status) {
      'pending' ||
      'awaiting_provider' ||
      'pending_provider_confirmation' ||
      'submitted' => 'وارد',
      'quote_sent' => 'عرض مرسل',
      'accepted' || 'confirmed' => 'مقبول',
      'scheduled' => 'محجوز',
      'in_progress' => 'قيد التنفيذ',
      'provider_completed' => 'أنجزها مقدم الخدمة',
      'completed' => 'مكتمل',
      'cancelled' ||
      'cancelled_by_customer' ||
      'cancelled_by_provider' ||
      'cancelled_by_admin' => 'ملغي',
      'rejected' || 'rejected_by_provider' => 'مرفوض',
      'expired' => 'منتهي',
      'disputed' => 'نزاع',
      _ => status.isEmpty ? 'غير محدد' : status,
    };
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(text, textDirection: TextDirection.rtl),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }
}
