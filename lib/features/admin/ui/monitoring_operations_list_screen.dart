import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../state/admin_controller.dart';

enum MonitoringOperationsMode { orders, delivery }

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
    if (widget.mode == MonitoringOperationsMode.delivery) {
      return const ['fresh_online', 'online', 'offline', 'busy'];
    }
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
      final data = widget.mode == MonitoringOperationsMode.delivery
          ? await api.monitoringDeliveryCouriers(
              status: _status,
              search: _search,
              limit: _pageSize,
              offset: _offset,
            )
          : await api.monitoringOrders(
              status: _status,
              search: _search,
              limit: _pageSize,
              offset: _offset,
            );
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

  String _title(BuildContext context) {
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
                        return widget.mode == MonitoringOperationsMode.delivery
                            ? _CourierTile(item: item)
                            : _OrderTile(item: item);
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
