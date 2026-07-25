import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../state/admin_controller.dart';

/// قائمة الرحلات المُصفّحة خادمياً (المرحلة 3) — deep link من بطاقة التاكسي.
class MonitoringTaxiRidesScreen extends ConsumerStatefulWidget {
  const MonitoringTaxiRidesScreen({super.key});

  @override
  ConsumerState<MonitoringTaxiRidesScreen> createState() =>
      _MonitoringTaxiRidesScreenState();
}

class _MonitoringTaxiRidesScreenState
    extends ConsumerState<MonitoringTaxiRidesScreen> {
  static const int _pageSize = 25;
  static const List<String> _statuses = [
    'searching',
    'captain_assigned',
    'captain_arriving',
    'ride_started',
    'completed',
    'cancelled',
  ];

  String? _status;
  int _offset = 0;
  int _total = 0;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

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
      final data = await ref.read(adminApiProvider).monitoringTaxiRides(
            status: _status,
            limit: _pageSize,
            offset: _offset,
          );
      final items = ((data['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
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
          ar: 'تعذّر تحميل الرحلات.',
          en: 'Unable to load rides.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'متابعة الرحلات', en: 'Rides monitoring')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: MaslakiSpacing.md,
                vertical: MaslakiSpacing.sm,
              ),
              children: [
                _StatusChip(
                  label: context.lt(ar: 'الكل', en: 'All'),
                  selected: _status == null,
                  onTap: () => _selectStatus(null),
                ),
                for (final status in _statuses)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _StatusChip(
                      label: _statusLabel(context, status),
                      selected: _status == status,
                      onTap: () => _selectStatus(status),
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
                        icon: Icons.local_taxi_outlined,
                        title: context.lt(ar: 'لا توجد رحلات', en: 'No rides'),
                        body: context.lt(
                          ar: 'لا توجد رحلات مطابقة للفلتر الحالي.',
                          en: 'No rides match the current filter.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(MaslakiSpacing.md),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: MaslakiSpacing.sm),
                        itemBuilder: (context, index) =>
                            _RideTile(ride: _items[index]),
                      ),
          ),
          _Pager(
            offset: _offset,
            pageSize: _pageSize,
            total: _total,
            loading: _loading,
            onPrev: _offset > 0
                ? () {
                    setState(() => _offset =
                        (_offset - _pageSize).clamp(0, _offset));
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

  String _statusLabel(BuildContext context, String status) {
    switch (status) {
      case 'searching':
        return context.lt(ar: 'بحث', en: 'Searching');
      case 'captain_assigned':
        return context.lt(ar: 'مُسندة', en: 'Assigned');
      case 'captain_arriving':
        return context.lt(ar: 'متوجّه', en: 'En route');
      case 'ride_started':
        return context.lt(ar: 'جارية', en: 'Started');
      case 'completed':
        return context.lt(ar: 'مكتملة', en: 'Completed');
      case 'cancelled':
        return context.lt(ar: 'ملغاة', en: 'Cancelled');
      default:
        return status;
    }
  }
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.ride});

  final Map<String, dynamic> ride;

  @override
  Widget build(BuildContext context) {
    final id = ride['id'];
    final status = '${ride['status'] ?? ''}';
    final customer = '${ride['customer_name'] ?? '—'}';
    final captain = '${ride['captain_name'] ?? '—'}';
    final hasEmergency = ride['has_open_emergency'] == true;
    final cancelledByRole = ride['cancelled_by_role'];

    return MaslakiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${context.lt(ar: 'رحلة', en: 'Ride')} #$id',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (hasEmergency)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.sos_rounded,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                ),
              Text(status, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text('${context.lt(ar: 'الزبون', en: 'Customer')}: $customer'),
          Text('${context.lt(ar: 'الكابتن', en: 'Captain')}: $captain'),
          if (cancelledByRole != null)
            Text(
              '${context.lt(ar: 'أُلغيت بواسطة', en: 'Cancelled by')}: $cancelledByRole'
              '${ride['cancel_is_emergency'] == true ? ' (${context.lt(ar: 'طارئ', en: 'emergency')})' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
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
            Text('$start–$end / $total'),
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
