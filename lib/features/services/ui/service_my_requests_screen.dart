import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../data/services_api.dart';
import '../models/service_models.dart';
import 'service_request_details_screen.dart';

class ServiceMyRequestsScreen extends ConsumerStatefulWidget {
  final String? initialStatus;

  const ServiceMyRequestsScreen({super.key, this.initialStatus});

  @override
  ConsumerState<ServiceMyRequestsScreen> createState() =>
      _ServiceMyRequestsScreenState();
}

class _ServiceMyRequestsScreenState
    extends ConsumerState<ServiceMyRequestsScreen> {
  bool _loading = true;
  String? _error;
  String? _status;
  List<ServiceRequestModel> _items = const <ServiceRequestModel>[];

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(servicesApiProvider).listMyRequests(
            status: (_status ?? '').trim().isEmpty ? null : _status,
            limit: 60,
          );
      if (!mounted) return;
      setState(() {
        _items = rows.map(ServiceRequestModel.fromJson).toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _setStatus(String? value) async {
    setState(() => _status = value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final servicesSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.services, displayName: 'الخدمات');
    if (servicesSection.isBlocked && !servicesSection.allowExistingActiveAccess) {
      return SectionUnavailableScreen(entry: servicesSection);
    }
    final visibleItems =
        servicesSection.isBlocked
            ? _items
                .where((item) => !_isTerminalServiceRequestStatus(item.status))
                .toList(growable: false)
            : _items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('طلباتي في الخدمات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (servicesSection.isBlocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Card(
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
                      const Text('يتم عرض الطلبات النشطة فقط أثناء الإغلاق.'),
                    ],
                  ),
                ),
              ),
            ),
          if (servicesSection.isOpen)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  _StatusChip(
                    label: 'الكل',
                    selected: (_status ?? '').isEmpty,
                    onTap: () => _setStatus(null),
                  ),
                  _StatusChip(
                    label: 'معلقة',
                    selected: _status == 'pending',
                    onTap: () => _setStatus('pending'),
                  ),
                  _StatusChip(
                    label: 'بانتظار الرد',
                    selected: _status == 'awaiting_provider',
                    onTap: () => _setStatus('awaiting_provider'),
                  ),
                  _StatusChip(
                    label: 'مقبولة',
                    selected: _status == 'accepted',
                    onTap: () => _setStatus('accepted'),
                  ),
                  _StatusChip(
                    label: 'قيد التنفيذ',
                    selected: _status == 'in_progress',
                    onTap: () => _setStatus('in_progress'),
                  ),
                  _StatusChip(
                    label: 'مكتملة',
                    selected: _status == 'completed',
                    onTap: () => _setStatus('completed'),
                  ),
                  _StatusChip(
                    label: 'ملغية',
                    selected: _status == 'cancelled',
                    onTap: () => _setStatus('cancelled'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_error != null && _items.isEmpty) {
                    return ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              'تعذر تحميل الطلبات.\n$_error',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  if (visibleItems.isEmpty) {
                    return ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            servicesSection.isBlocked
                                ? 'لا توجد طلبات خدمات نشطة يمكن متابعتها حاليًا.'
                                : 'لا توجد طلبات خدمات مطابقة حاليًا.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                    itemCount: visibleItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = visibleItems[index];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(14),
                          title: Text(item.offeringName ?? 'طلب خدمة'),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((item.providerBusinessName ?? '')
                                    .trim()
                                    .isNotEmpty)
                                  Text(item.providerBusinessName!),
                                const SizedBox(height: 4),
                                Text(
                                  'الحالة: ${serviceRequestStatusLabel(item.status)}',
                                ),
                                if ((item.requestCode).trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('الرمز: ${item.requestCode}'),
                                  ),
                              ],
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ServiceRequestDetailsScreen(requestId: item.id),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _isTerminalServiceRequestStatus(String? value) {
  return <String>{'completed', 'cancelled', 'rejected'}.contains(
    (value ?? '').trim().toLowerCase(),
  );
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

String serviceRequestStatusLabel(String? value) {
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
