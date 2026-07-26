import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../state/admin_controller.dart';
import 'monitoring_detail_screen.dart';

enum MonitoringOperationsMode {
  orders,
  delivery,
  services,
  realEstate,
  cars,
  jobs,
  community,
}

class MonitoringOperationsListScreen extends ConsumerStatefulWidget {
  const MonitoringOperationsListScreen({super.key, required this.mode});

  final MonitoringOperationsMode mode;

  @override
  ConsumerState<MonitoringOperationsListScreen> createState() =>
      _MonitoringOperationsListScreenState();
}

class _MonitoringOperationsListScreenState
    extends ConsumerState<MonitoringOperationsListScreen> {
  static const int _pageSize = 25;

  String? _status;
  String _search = '';
  int _offset = 0;
  int _total = 0;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  List<String> get _statuses {
    switch (widget.mode) {
      case MonitoringOperationsMode.delivery:
        return const ['fresh_online', 'online', 'offline', 'busy'];
      case MonitoringOperationsMode.services:
        return const [
          'pending',
          'awaiting_provider',
          'accepted',
          'scheduled',
          'in_progress',
          'completed',
          'cancelled',
        ];
      case MonitoringOperationsMode.realEstate:
        return const [
          'pending_admin_review',
          'active',
          'sold',
          'rented',
          'archived',
          'hidden_due_subscription_expiry',
        ];
      case MonitoringOperationsMode.cars:
        return const [
          'active',
          'sold',
          'archived',
          'hidden_due_subscription_expiry',
        ];
      case MonitoringOperationsMode.jobs:
        return const ['draft', 'active', 'paused', 'closed'];
      case MonitoringOperationsMode.community:
        return const ['normal', 'gray_zone', 'reported', 'restricted'];
      case MonitoringOperationsMode.orders:
        return const [
          'pending',
          'accepted_by_store',
          'preparing',
          'ready_for_delivery',
          'courier_requested',
          'courier_assigned',
          'on_the_way',
          'completed',
          'cancelled',
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(adminApiProvider);
      final data = switch (widget.mode) {
        MonitoringOperationsMode.delivery =>
          await api.monitoringDeliveryCouriers(
            status: _status,
            search: _search,
            limit: _pageSize,
            offset: _offset,
          ),
        MonitoringOperationsMode.services =>
          await api.monitoringServiceRequests(
            status: _status,
            search: _search,
            limit: _pageSize,
            offset: _offset,
          ),
        MonitoringOperationsMode.realEstate =>
          await api.monitoringRealEstateListings(
            status: _status,
            search: _search,
            limit: _pageSize,
            offset: _offset,
          ),
        MonitoringOperationsMode.cars => await api.monitoringCarListings(
          status: _status,
          search: _search,
          limit: _pageSize,
          offset: _offset,
        ),
        MonitoringOperationsMode.jobs => await api.monitoringJobs(
          status: _status,
          search: _search,
          limit: _pageSize,
          offset: _offset,
        ),
        MonitoringOperationsMode.community =>
          await api.monitoringCommunityUsers(
            status: _status,
            search: _search,
            limit: _pageSize,
            offset: _offset,
          ),
        MonitoringOperationsMode.orders => await api.monitoringOrders(
          status: _status,
          search: _search,
          limit: _pageSize,
          offset: _offset,
        ),
      };
      final items = ((data['items'] as List?) ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = items;
        _total = (data['total'] as num?)?.toInt() ?? items.length;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.lt(
          ar: 'تعذر تحميل البيانات.',
          en: 'Unable to load data.',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectStatus(String? status) {
    setState(() {
      _status = status;
      _offset = 0;
    });
    _load();
  }

  void _openDetail(Map<String, dynamic> item) {
    final id = _detailId(item);
    if (id == null || id <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MonitoringDetailScreen(
          mode: _detailMode,
          id: id,
          title: _detailTitle(item, id),
        ),
      ),
    );
  }

  MonitoringDetailMode get _detailMode {
    return switch (widget.mode) {
      MonitoringOperationsMode.delivery => MonitoringDetailMode.deliveryCourier,
      MonitoringOperationsMode.services => MonitoringDetailMode.serviceRequest,
      MonitoringOperationsMode.realEstate =>
        MonitoringDetailMode.realEstateListing,
      MonitoringOperationsMode.cars => MonitoringDetailMode.carListing,
      MonitoringOperationsMode.jobs => MonitoringDetailMode.job,
      MonitoringOperationsMode.community => MonitoringDetailMode.communityUser,
      MonitoringOperationsMode.orders => MonitoringDetailMode.order,
    };
  }

  int? _detailId(Map<String, dynamic> item) {
    final value = widget.mode == MonitoringOperationsMode.delivery
        ? item['user_id']
        : item['id'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  String _detailTitle(Map<String, dynamic> item, int id) {
    final rawTitle = switch (widget.mode) {
      MonitoringOperationsMode.delivery => item['full_name'],
      MonitoringOperationsMode.services =>
        item['offering_name'] ?? item['request_code'],
      MonitoringOperationsMode.realEstate => item['title'],
      MonitoringOperationsMode.cars =>
        '${item['brand'] ?? ''} ${item['model'] ?? ''}',
      MonitoringOperationsMode.jobs => item['title'],
      MonitoringOperationsMode.community =>
        item['full_name'] ?? item['username'],
      MonitoringOperationsMode.orders => null,
    };
    final title = '${rawTitle ?? ''}'.trim();
    return title.isNotEmpty ? title : '${_title(context)} #$id';
  }

  String _title(BuildContext context) {
    if (widget.mode == MonitoringOperationsMode.services) {
      return context.lt(ar: 'متابعة الخدمات', en: 'Services monitoring');
    }
    if (widget.mode == MonitoringOperationsMode.realEstate) {
      return context.lt(ar: 'متابعة العقارات', en: 'Real estate monitoring');
    }
    if (widget.mode == MonitoringOperationsMode.cars) {
      return context.lt(ar: 'متابعة السيارات', en: 'Cars monitoring');
    }
    if (widget.mode == MonitoringOperationsMode.jobs) {
      return context.lt(ar: 'متابعة الوظائف', en: 'Jobs monitoring');
    }
    if (widget.mode == MonitoringOperationsMode.community) {
      return context.lt(ar: 'متابعة المجتمع', en: 'Community monitoring');
    }
    return widget.mode == MonitoringOperationsMode.delivery
        ? context.lt(ar: 'متابعة الدلفري', en: 'Delivery monitoring')
        : context.lt(ar: 'متابعة الطلبات', en: 'Orders monitoring');
  }

  String _statusLabel(BuildContext context, String status) {
    switch (status) {
      case 'fresh_online':
        return context.lt(ar: 'متصل حديثاً', en: 'Fresh online');
      case 'online':
        return context.lt(ar: 'متاح', en: 'Online');
      case 'offline':
        return context.lt(ar: 'غير متاح', en: 'Offline');
      case 'busy':
        return context.lt(ar: 'مشغول', en: 'Busy');
      case 'ready_for_delivery':
      case 'courier_requested':
        return context.lt(ar: 'بانتظار دلفري', en: 'Needs courier');
      case 'courier_assigned':
        return context.lt(ar: 'دلفري معين', en: 'Courier assigned');
      case 'on_the_way':
        return context.lt(ar: 'قيد التوصيل', en: 'On the way');
      case 'completed':
        return context.lt(ar: 'مكتمل', en: 'Completed');
      case 'cancelled':
        return context.lt(ar: 'ملغى', en: 'Cancelled');
      case 'pending_admin_review':
        return context.lt(ar: 'بانتظار المراجعة', en: 'Pending review');
      case 'hidden_due_subscription_expiry':
        return context.lt(ar: 'مخفي', en: 'Hidden');
      case 'active':
        return context.lt(ar: 'نشط', en: 'Active');
      case 'sold':
        return context.lt(ar: 'مباع', en: 'Sold');
      case 'rented':
        return context.lt(ar: 'مؤجر', en: 'Rented');
      case 'archived':
        return context.lt(ar: 'مؤرشف', en: 'Archived');
      case 'awaiting_provider':
        return context.lt(ar: 'بانتظار مقدم الخدمة', en: 'Awaiting provider');
      case 'accepted':
        return context.lt(ar: 'مقبول', en: 'Accepted');
      case 'scheduled':
        return context.lt(ar: 'مجدول', en: 'Scheduled');
      case 'in_progress':
        return context.lt(ar: 'قيد التنفيذ', en: 'In progress');
      case 'draft':
        return context.lt(ar: 'مسودة', en: 'Draft');
      case 'paused':
        return context.lt(ar: 'متوقف', en: 'Paused');
      case 'closed':
        return context.lt(ar: 'مغلق', en: 'Closed');
      case 'normal':
        return context.lt(ar: 'طبيعي', en: 'Normal');
      case 'gray_zone':
        return context.lt(ar: 'تحت المراقبة', en: 'Gray zone');
      case 'reported':
        return context.lt(ar: 'عليه بلاغ', en: 'Reported');
      case 'restricted':
        return context.lt(ar: 'مقيد', en: 'Restricted');
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(context)),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MaslakiSpacing.md,
              MaslakiSpacing.md,
              MaslakiSpacing.md,
              0,
            ),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                labelText: context.lt(ar: 'بحث', en: 'Search'),
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
              onChanged: (value) => _search = value.trim(),
              onSubmitted: (_) {
                _offset = 0;
                _load();
              },
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: MaslakiSpacing.md,
                vertical: MaslakiSpacing.sm,
              ),
              children: [
                ChoiceChip(
                  label: Text(context.lt(ar: 'الكل', en: 'All')),
                  selected: _status == null,
                  onSelected: (_) => _selectStatus(null),
                ),
                for (final status in _statuses)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: ChoiceChip(
                      label: Text(_statusLabel(context, status)),
                      selected: _status == status,
                      onSelected: (_) => _selectStatus(status),
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(MaslakiSpacing.md),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? MaslakiEmptyState(
                    icon: widget.mode == MonitoringOperationsMode.delivery
                        ? Icons.delivery_dining_rounded
                        : Icons.receipt_long_rounded,
                    title: context.lt(ar: 'لا توجد نتائج', en: 'No results'),
                    body: context.lt(
                      ar: 'لا توجد بيانات مطابقة للفلاتر الحالية.',
                      en: 'No data matches the current filters.',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(MaslakiSpacing.md),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: MaslakiSpacing.sm),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final child = switch (widget.mode) {
                          MonitoringOperationsMode.delivery => _CourierTile(
                            item: item,
                          ),
                          MonitoringOperationsMode.services => _ServiceTile(
                            item: item,
                          ),
                          MonitoringOperationsMode.realEstate =>
                            _RealEstateTile(item: item),
                          MonitoringOperationsMode.cars => _CarTile(item: item),
                          MonitoringOperationsMode.jobs => _JobTile(item: item),
                          MonitoringOperationsMode.community => _CommunityTile(
                            item: item,
                          ),
                          MonitoringOperationsMode.orders => _OrderTile(
                            item: item,
                          ),
                        };
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _openDetail(item),
                          child: child,
                        );
                      },
                    ),
                  ),
          ),
          _Pager(
            offset: _offset,
            pageSize: _pageSize,
            total: _total,
            loading: _loading,
            onPrev: _offset > 0
                ? () {
                    setState(() {
                      _offset = (_offset - _pageSize).clamp(0, _offset);
                    });
                    _load();
                  }
                : null,
            onNext: (_offset + _pageSize) < _total
                ? () {
                    setState(() => _offset += _pageSize);
                    _load();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return MaslakiCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('${context.lt(ar: 'طلب', en: 'Order')} #${item['id']}'),
        subtitle: Text(
          '${item['status']} • ${item['merchant_name'] ?? '-'}\n'
          '${context.lt(ar: 'الزبون', en: 'Customer')}: ${item['customer_full_name'] ?? '-'}\n'
          '${context.lt(ar: 'الدلفري', en: 'Courier')}: ${item['delivery_name'] ?? '-'}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${item['total_amount'] ?? 0}'),
            if (item['has_open_ticket'] == true)
              Icon(
                Icons.support_agent_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 18,
              ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _CourierTile extends StatelessWidget {
  const _CourierTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final fresh =
        item['is_online'] == true &&
        DateTime.tryParse('${item['presence_updated_at'] ?? ''}') != null;
    return MaslakiCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          item['busy'] == true
              ? Icons.delivery_dining_rounded
              : Icons.person_pin_circle_outlined,
        ),
        title: Text('${item['full_name'] ?? item['user_id']}'),
        subtitle: Text(
          '${item['availability_status'] ?? '-'} • ${item['coverage_block'] ?? '-'}\n'
          '${context.lt(ar: 'طلبات اليوم', en: 'Today')}: ${item['deliveries_today'] ?? 0} • '
          '${context.lt(ar: 'التقييم', en: 'Rating')}: ${item['rating'] ?? 0}',
        ),
        trailing: Icon(
          fresh ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded,
          color: fresh
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return MaslakiCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.handyman_rounded),
        title: Text(
          '${item['offering_name'] ?? item['request_code'] ?? item['id']}',
        ),
        subtitle: Text(
          '${item['status'] ?? '-'} • ${item['provider_name'] ?? '-'}\n'
          '${context.lt(ar: 'الزبون', en: 'Customer')}: ${item['customer_name'] ?? '-'} • '
          '${context.lt(ar: 'المنطقة', en: 'Area')}: ${item['city'] ?? item['area'] ?? '-'}',
        ),
        trailing: _TicketBadge(
          active:
              item['has_open_ticket'] == true ||
              item['has_open_report'] == true,
          value: '${item['booking_total_iqd'] ?? item['final_price'] ?? 0}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _RealEstateTile extends StatelessWidget {
  const _RealEstateTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return MaslakiCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.apartment_rounded),
        title: Text('${item['title'] ?? item['id']}'),
        subtitle: Text(
          '${item['status'] ?? '-'} • ${item['purpose'] ?? '-'} • ${item['city'] ?? '-'}\n'
          '${context.lt(ar: 'المعلن', en: 'Owner')}: ${item['owner_name'] ?? '-'} • '
          '${context.lt(ar: 'الصور', en: 'Media')}: ${item['media_count'] ?? 0} • '
          '${context.lt(ar: 'الحفظ', en: 'Saved')}: ${item['saved_count'] ?? 0}',
        ),
        trailing: _TicketBadge(
          active: item['has_open_ticket'] == true,
          value: '${item['price'] ?? 0}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _CarTile extends StatelessWidget {
  const _CarTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return MaslakiCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.directions_car_filled_rounded),
        title: Text('${item['brand'] ?? '-'} ${item['model'] ?? ''}'),
        subtitle: Text(
          '${item['status'] ?? '-'} • ${item['model_year'] ?? '-'} • ${item['city'] ?? '-'}\n'
          '${context.lt(ar: 'المعلن', en: 'Owner')}: ${item['owner_name'] ?? '-'} • '
          '${context.lt(ar: 'الصور', en: 'Media')}: ${item['media_count'] ?? 0} • '
          '${item['condition'] ?? '-'}',
        ),
        trailing: _TicketBadge(
          active: item['has_open_ticket'] == true,
          value: '${item['price'] ?? 0}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return MaslakiCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.work_rounded),
        title: Text('${item['title'] ?? item['id']}'),
        subtitle: Text(
          '${item['status'] ?? '-'} • ${item['company_name'] ?? '-'} • ${item['city'] ?? '-'}\n'
          '${context.lt(ar: 'الناشر', en: 'Publisher')}: ${item['publisher_name'] ?? '-'} • '
          '${context.lt(ar: 'المتقدمون', en: 'Applications')}: ${item['application_count'] ?? 0} • '
          '${context.lt(ar: 'سير ذاتية', en: 'CVs')}: ${item['resume_count'] ?? 0}',
        ),
        trailing: _TicketBadge(
          active: item['has_open_ticket'] == true,
          value: '${item['vacancies'] ?? 0}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _CommunityTile extends StatelessWidget {
  const _CommunityTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return MaslakiCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.groups_rounded),
        title: Text('${item['full_name'] ?? item['username'] ?? item['id']}'),
        subtitle: Text(
          '@${item['username'] ?? '-'} • ${item['social_visibility_tier'] ?? 'normal'}\n'
          '${context.lt(ar: 'منشورات', en: 'Posts')}: ${item['post_count'] ?? 0} • '
          '${context.lt(ar: 'ريلز', en: 'Reels')}: ${item['reel_count'] ?? 0} • '
          '${context.lt(ar: 'قصص', en: 'Stories')}: ${item['story_count'] ?? 0} • '
          '${context.lt(ar: 'بلاغات', en: 'Reports')}: ${item['report_count'] ?? 0}',
        ),
        trailing: _TicketBadge(
          active:
              item['has_open_ticket'] == true ||
              ((item['active_restriction_count'] as num?)?.toInt() ?? 0) > 0,
          value: '${item['social_violation_strikes'] ?? 0}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _TicketBadge extends StatelessWidget {
  const _TicketBadge({required this.active, required this.value});

  final bool active;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(value),
        if (active)
          Icon(
            Icons.support_agent_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 18,
          ),
      ],
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.offset,
    required this.pageSize,
    required this.total,
    required this.loading,
    this.onPrev,
    this.onNext,
  });

  final int offset;
  final int pageSize;
  final int total;
  final bool loading;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final start = total == 0 ? 0 : offset + 1;
    final end = (offset + pageSize) < total ? offset + pageSize : total;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MaslakiSpacing.md,
          vertical: MaslakiSpacing.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: loading ? null : onPrev,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Text('$start-$end / $total'),
            IconButton(
              onPressed: loading ? null : onNext,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
