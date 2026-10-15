import 'dart:async';

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

enum MonitoringDetailMode {
  taxiRide,
  order,
  deliveryCourier,
  serviceRequest,
  realEstateListing,
  carListing,
  job,
  communityUser,
}

class MonitoringDetailScreen extends ConsumerStatefulWidget {
  const MonitoringDetailScreen({
    super.key,
    required this.mode,
    required this.id,
    required this.title,
  });

  final MonitoringDetailMode mode;
  final int id;
  final String title;

  @override
  ConsumerState<MonitoringDetailScreen> createState() =>
      _MonitoringDetailScreenState();
}

class _MonitoringDetailScreenState
    extends ConsumerState<MonitoringDetailScreen> {
  static const Duration _autoRefreshInterval = Duration(seconds: 15);

  bool _loading = true;
  bool _loadInFlight = false;
  bool _includeSensitive = false;
  bool _assigningCourier = false;
  String? _reason;
  String? _error;
  Map<String, dynamic>? _payload;
  Timer? _autoRefreshTimer;

  bool get _canReveal => switch (widget.mode) {
    MonitoringDetailMode.taxiRide ||
    MonitoringDetailMode.order ||
    MonitoringDetailMode.deliveryCourier ||
    MonitoringDetailMode.serviceRequest ||
    MonitoringDetailMode.realEstateListing ||
    MonitoringDetailMode.carListing => true,
    MonitoringDetailMode.job || MonitoringDetailMode.communityUser => false,
  };

  @override
  void initState() {
    super.initState();
    _load();
    if (_supportsAutoRefresh) {
      _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
        if (!mounted || _loadInFlight || _assigningCourier) return;
        unawaited(_load(silent: true));
      });
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  bool get _supportsAutoRefresh =>
      widget.mode == MonitoringDetailMode.order ||
      widget.mode == MonitoringDetailMode.deliveryCourier;

  Future<void> _load({bool silent = false}) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    if (silent) {
      if (_error != null && mounted) {
        setState(() => _error = null);
      }
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = ref.read(adminApiProvider);
      final data = switch (widget.mode) {
        MonitoringDetailMode.taxiRide => await api.monitoringTaxiRideDetail(
          widget.id,
          includeLive: _includeSensitive,
          includeMessages: _includeSensitive,
          reason: _reason,
        ),
        MonitoringDetailMode.order => await api.monitoringOrderDetail(
          widget.id,
          includePhone: _includeSensitive,
          reason: _reason,
        ),
        MonitoringDetailMode.deliveryCourier =>
          await api.monitoringDeliveryCourierDetail(
            widget.id,
            includePhone: _includeSensitive,
            reason: _reason,
          ),
        MonitoringDetailMode.serviceRequest =>
          await api.monitoringServiceRequestDetail(
            widget.id,
            includeMessages: _includeSensitive,
            reason: _reason,
          ),
        MonitoringDetailMode.realEstateListing =>
          await api.monitoringRealEstateListingDetail(
            widget.id,
            includeContact: _includeSensitive,
            reason: _reason,
          ),
        MonitoringDetailMode.carListing => await api.monitoringCarListingDetail(
          widget.id,
          includeContact: _includeSensitive,
          reason: _reason,
        ),
        MonitoringDetailMode.job => await _loadJob(api),
        MonitoringDetailMode.communityUser => await _loadCommunityUser(api),
      };
      if (!mounted) return;
      setState(() => _payload = data);
    } catch (error) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _error = mapAnyError(
          error,
          fallback: 'Unable to load monitoring details.',
        );
      });
    } finally {
      _loadInFlight = false;
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _loadJob(dynamic api) async {
    final detail = await api.monitoringJobDetail(widget.id);
    final applications = await api.monitoringJobApplications(widget.id);
    return {
      ...detail,
      'applications': applications['items'] ?? const <dynamic>[],
      'applications_total': applications['total'] ?? 0,
    };
  }

  Future<Map<String, dynamic>> _loadCommunityUser(dynamic api) async {
    final detail = await api.monitoringCommunityUserDetail(widget.id);
    final content = await api.monitoringCommunityUserContent(widget.id);
    final reports = await api.monitoringCommunityUserReports(widget.id);
    return {
      ...detail,
      'content': content['items'] ?? const <dynamic>[],
      'content_total': content['total'] ?? 0,
      'reports': reports['items'] ?? const <dynamic>[],
      'reports_total': reports['total'] ?? 0,
    };
  }

  Map<String, dynamic> get _orderPayload {
    final order = _payload?['order'];
    if (order is Map) return Map<String, dynamic>.from(order);
    return const <String, dynamic>{};
  }

  int _asInt(Object? value) => int.tryParse('$value') ?? 0;

  String _presenceLabel(Map<String, dynamic> courier) {
    final online = courier['is_online'] == true;
    final fresh = courier['presence_fresh'] == true;
    final ageSeconds = _asInt(courier['presence_age_seconds']);
    if (!online) return 'offline';
    if (fresh) return 'fresh presence';
    if (ageSeconds <= 0) return 'online, no fresh heartbeat';
    if (ageSeconds < 60) return 'last heartbeat ${ageSeconds}s ago';
    final minutes = ageSeconds ~/ 60;
    if (minutes < 60) return 'last heartbeat ${minutes}m ago';
    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;
    if (restMinutes == 0) return 'last heartbeat ${hours}h ago';
    return 'last heartbeat ${hours}h ${restMinutes}m ago';
  }

  Future<void> _assignMonitoringCourier(
    int? courierUserId, {
    required bool allowBusyCourier,
    String? note,
  }) async {
    if (_assigningCourier) return;
    setState(() => _assigningCourier = true);
    try {
      final api = ref.read(adminApiProvider);
      await api.assignMonitoringOrderCourier(
        widget.id,
        courierUserId: courierUserId,
        allowBusyCourier: allowBusyCourier,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            courierUserId == null
                ? 'Courier removed from order.'
                : 'Courier assigned to order.',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: 'Unable to update courier assignment.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _assigningCourier = false);
    }
  }

  Future<void> _openCourierPicker() async {
    final api = ref.read(adminApiProvider);
    List<Map<String, dynamic>> couriers = const <Map<String, dynamic>>[];
    try {
      final data = await api.monitoringDeliveryCouriers(
        status: 'online',
        limit: 100,
      );
      couriers = ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: 'Unable to load couriers.'),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Assign courier'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: couriers.isEmpty
                ? const Center(child: Text('No couriers found.'))
                : ListView.separated(
                    itemCount: couriers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final courier = couriers[index];
                      final activeCount = _asInt(courier['active_order_count']);
                      final busy = courier['busy'] == true || activeCount > 0;
                      final fresh = courier['presence_fresh'] == true;
                      final presenceLabel = _presenceLabel(courier);
                      return ListTile(
                        leading: Icon(
                          busy
                              ? Icons.delivery_dining_rounded
                              : Icons.person_pin_circle_rounded,
                        ),
                        title: Text(
                          '${courier['full_name'] ?? courier['user_id']}',
                        ),
                        subtitle: Text(
                          '${courier['availability_status'] ?? '-'} - '
                          '${courier['coverage_block'] ?? '-'} - '
                          'active: $activeCount\n'
                          '$presenceLabel',
                        ),
                        trailing: courier['is_online'] == true
                            ? Icon(
                                Icons.wifi_tethering_rounded,
                                color: fresh ? Colors.green : Colors.orange,
                              )
                            : const Icon(Icons.wifi_off_rounded),
                        onTap: () => Navigator.of(context).pop(courier),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (selected == null || !mounted) return;

    final courierId = _asInt(selected['user_id']);
    if (courierId <= 0) return;
    final activeCount = _asInt(selected['active_order_count']);
    final busy = selected['busy'] == true || activeCount > 0;
    final stalePresence =
        selected['is_online'] == true && selected['presence_fresh'] != true;
    var allowBusy = false;
    if (busy) {
      allowBusy =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Courier already has an order'),
              content: Text(
                'This courier has $activeCount active order(s). Assign this order too?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Assign anyway'),
                ),
              ],
            ),
          ) ??
          false;
      if (!allowBusy) return;
    }
    if (!mounted) return;
    if (stalePresence) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Courier presence is stale'),
              content: Text(
                '${_presenceLabel(selected)}. Assign this order anyway?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Assign anyway'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }

    await _assignMonitoringCourier(
      courierId,
      allowBusyCourier: allowBusy,
      note: 'Monitoring manual assignment',
    );
  }

  Future<void> _removeCourier() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove courier'),
            content: const Text('Remove the current courier from this order?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _assignMonitoringCourier(
      null,
      allowBusyCourier: false,
      note: 'Monitoring manual removal',
    );
  }

  Future<void> _revealSensitive() async {
    final controller = TextEditingController(text: _reason ?? '');
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Access reason required'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Write the case number or business reason.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.length < 8) return;
                Navigator.of(context).pop(value);
              },
              child: const Text('Reveal'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    setState(() {
      _includeSensitive = true;
      _reason = reason;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_canReveal)
            IconButton(
              onPressed: _loading ? null : _revealSensitive,
              icon: Icon(
                _includeSensitive
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              tooltip: 'Reveal sensitive data',
            ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorPanel(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(MaslakiSpacing.md),
                children: _sections(context),
              ),
            ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final payload = _payload ?? const <String, dynamic>{};
    final children = <Widget>[
      _SectionCard(
        title: 'ملخص الحالة',
        subtitle: _modeHint(),
        icon: Icons.fact_check_rounded,
        rows: _summaryRows(payload),
      ),
    ];

    if (widget.mode == MonitoringDetailMode.order) {
      children.add(const SizedBox(height: MaslakiSpacing.sm));
      children.add(
        _OrderCourierActions(
          order: _orderPayload,
          busy: _assigningCourier,
          onAssign: _openCourierPicker,
          onRemove: _removeCourier,
        ),
      );
    }

    for (final entry in payload.entries) {
      if (_isScalar(entry.value)) continue;
      children.add(const SizedBox(height: MaslakiSpacing.sm));
      children.add(
        _SectionCard(
          title: _label(entry.key),
          subtitle: _sectionHint(entry.key),
          icon: _iconFor(entry.key),
          rows: _rowsFor(entry.value),
        ),
      );
    }
    return children;
  }

  List<_DetailRow> _summaryRows(Map<String, dynamic> payload) {
    final preferred = <String>[
      'id',
      'status',
      'assignment_status',
      'lifecycle_status',
      'customer_name',
      'captain_name',
      'courier_name',
      'merchant_name',
      'provider_name',
      'owner_name',
      'title',
      'full_name',
      'username',
      'total_amount',
      'final_price',
      'price',
      'created_at',
      'updated_at',
    ];
    final rows = <_DetailRow>[];
    for (final key in preferred) {
      if (payload.containsKey(key) && _isScalar(payload[key])) {
        rows.add(_DetailRow(_label(key), _format(payload[key])));
      }
    }
    if (rows.isEmpty) {
      for (final entry in payload.entries.take(12)) {
        if (_isScalar(entry.value)) {
          rows.add(_DetailRow(_label(entry.key), _format(entry.value)));
        }
      }
    }
    return rows;
  }

  List<_DetailRow> _rowsFor(Object? value) {
    if (value is Map) {
      return value.entries
          .map(
            (entry) => _DetailRow(_label('${entry.key}'), _format(entry.value)),
          )
          .toList(growable: false);
    }
    if (value is List) {
      if (value.isEmpty) return const [_DetailRow('العدد', '0')];
      return [
        _DetailRow('العدد', '${value.length}'),
        for (var i = 0; i < value.length && i < 20; i++)
          _DetailRow('العنصر ${i + 1}', _formatListItem(value[i])),
      ];
    }
    return [_DetailRow('القيمة', _format(value))];
  }

  bool _isScalar(Object? value) {
    return value == null || value is String || value is num || value is bool;
  }

  String _format(Object? value) {
    if (value == null) return '-';
    if (value is bool) return value ? 'نعم' : 'لا';
    if (value is String) {
      final date = DateTime.tryParse(value);
      if (date != null) return _formatDate(date);
      if (value.contains('_')) return value.replaceAll('_', ' ');
      return value;
    }
    if (value is Map) {
      final parts = value.entries
          .take(8)
          .map((entry) => '${_label('${entry.key}')}: ${_format(entry.value)}');
      return parts.join('\n');
    }
    if (value is List) {
      if (value.isEmpty) return '-';
      return value.take(4).map(_format).join('\n---\n');
    }
    return '$value';
  }

  String _formatListItem(Object? value) {
    if (value is! Map) return _format(value);
    final map = Map<dynamic, dynamic>.from(value);
    final keys = <String>[
      'id',
      'status',
      'title',
      'name',
      'full_name',
      'customer_name',
      'merchant_name',
      'captain_name',
      'courier_name',
      'total_amount',
      'created_at',
      'updated_at',
    ];
    final rows = <String>[];
    for (final key in keys) {
      if (map.containsKey(key) && _isScalar(map[key])) {
        rows.add('${_label(key)}: ${_format(map[key])}');
      }
    }
    if (rows.isEmpty) {
      for (final entry in map.entries.take(5)) {
        if (_isScalar(entry.value)) {
          rows.add('${_label('${entry.key}')}: ${_format(entry.value)}');
        }
      }
    }
    return rows.isEmpty ? _format(value) : rows.join('\n');
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  IconData _iconFor(String key) {
    if (key.contains('message')) return Icons.chat_bubble_outline_rounded;
    if (key.contains('location') || key.contains('live')) {
      return Icons.location_on_outlined;
    }
    if (key.contains('ticket') || key.contains('report')) {
      return Icons.support_agent_rounded;
    }
    if (key.contains('application')) return Icons.description_outlined;
    if (key.contains('content')) return Icons.collections_outlined;
    if (key.contains('assignment') || key.contains('delivery')) {
      return Icons.delivery_dining_rounded;
    }
    return Icons.list_alt_rounded;
  }

  String _label(String key) {
    const labels = <String, String>{
      'id': 'المعرف',
      'status': 'الحالة',
      'assignment_status': 'حالة التعيين',
      'lifecycle_status': 'حالة دورة العمل',
      'customer_name': 'اسم الزبون',
      'customer_phone': 'هاتف الزبون',
      'captain_name': 'اسم الكابتن',
      'captain_phone': 'هاتف الكابتن',
      'courier_name': 'اسم الدلفري',
      'courier_phone': 'هاتف الدلفري',
      'merchant_name': 'اسم المتجر',
      'merchant_phone': 'هاتف المتجر',
      'provider_name': 'مقدم الخدمة',
      'owner_name': 'المالك',
      'title': 'العنوان',
      'full_name': 'الاسم الكامل',
      'username': 'اسم المستخدم',
      'total_amount': 'المبلغ الكلي',
      'final_price': 'السعر النهائي',
      'price': 'السعر',
      'created_at': 'تاريخ الإنشاء',
      'updated_at': 'آخر تحديث',
      'pickup_location': 'نقطة الانطلاق',
      'dropoff_location': 'نقطة الوصول',
      'from_address': 'من',
      'to_address': 'إلى',
      'messages': 'المحادثات',
      'tickets': 'الشكاوى والتذاكر',
      'reports': 'البلاغات',
      'applications': 'طلبات التقديم',
      'content': 'المحتوى',
      'items': 'العناصر',
      'products': 'المنتجات',
      'invoice': 'الفاتورة',
      'delivery_job': 'مهمة التوصيل',
      'assignments': 'التعيينات',
      'timeline': 'السجل الزمني',
      'rating': 'التقييم',
      'reviews': 'المراجعات',
      'is_online': 'متصل',
      'busy': 'مشغول',
      'active': 'نشط',
      'reason': 'السبب',
      'note': 'ملاحظة',
      'notes': 'الملاحظات',
    };
    final mapped = labels[key];
    if (mapped != null) return mapped;
    return key
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .trim();
  }

  String _modeHint() {
    return switch (widget.mode) {
      MonitoringDetailMode.taxiRide =>
        'يعرض مسار الرحلة، الكابتن، الزبون، الأجرة، الرسائل، والحالة الحالية.',
      MonitoringDetailMode.order =>
        'يعرض الطلب، المتجر، الزبون، الدلفري، المنتجات، الفاتورة، وأي تعديلات أو شكاوى.',
      MonitoringDetailMode.deliveryCourier =>
        'يعرض حالة الدلفري، تواجده، انشغاله، المهام الحالية والسابقة.',
      MonitoringDetailMode.serviceRequest =>
        'يعرض طلب الخدمة، المزود، الزبون، الموعد، السعر، والمحادثات عند السماح.',
      MonitoringDetailMode.realEstateListing =>
        'يعرض إعلان العقار، صاحبه، بيانات التواصل، البلاغات، وحالة النشر.',
      MonitoringDetailMode.carListing =>
        'يعرض إعلان السيارة، صاحب الإعلان، بيانات التواصل، البلاغات، وحالة النشر.',
      MonitoringDetailMode.job =>
        'يعرض الوظيفة، صاحبها، وعدد المتقدمين وتفاصيل التقديم.',
      MonitoringDetailMode.communityUser =>
        'يعرض نشاط المستخدم في المجتمع، المحتوى، البلاغات، والقيود.',
    };
  }

  String? _sectionHint(String key) {
    final lower = key.toLowerCase();
    if (lower.contains('message')) return 'المحادثات المرتبطة بهذا السجل.';
    if (lower.contains('ticket') || lower.contains('report')) {
      return 'الشكاوى أو البلاغات المرتبطة، مع أسبابها وحالتها.';
    }
    if (lower.contains('assignment') || lower.contains('delivery')) {
      return 'معلومات التعيين، الدلفري، وحالة التسليم.';
    }
    if (lower.contains('invoice') || lower.contains('payment')) {
      return 'تفاصيل المبلغ، الدفع، والرسوم.';
    }
    if (lower.contains('item') || lower.contains('product')) {
      return 'العناصر التي يراها الطرف المسؤول في التطبيق.';
    }
    if (lower.contains('timeline') || lower.contains('history')) {
      return 'تسلسل الأحداث من الإنشاء حتى آخر تحديث.';
    }
    return null;
  }
}

class _OrderCourierActions extends StatelessWidget {
  const _OrderCourierActions({
    required this.order,
    required this.busy,
    required this.onAssign,
    required this.onRemove,
  });

  final Map<String, dynamic> order;
  final bool busy;
  final VoidCallback onAssign;
  final VoidCallback onRemove;

  int _asInt(Object? value) => int.tryParse('$value') ?? 0;

  @override
  Widget build(BuildContext context) {
    final deliveryUserId = _asInt(order['delivery_user_id']);
    final hasCourier = deliveryUserId > 0;
    final status = '${order['delivery_assignment_status'] ?? '-'}';
    final name = '${order['delivery_name'] ?? '-'}';

    return MaslakiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.delivery_dining_rounded, size: 20),
              const SizedBox(width: MaslakiSpacing.sm),
              Expanded(
                child: Text(
                  'Courier assignment',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: MaslakiSpacing.sm),
          Text('Current: $name - $status'),
          const SizedBox(height: MaslakiSpacing.md),
          Wrap(
            spacing: MaslakiSpacing.sm,
            runSpacing: MaslakiSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : onAssign,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_search_rounded),
                label: Text(hasCourier ? 'Change courier' : 'Assign courier'),
              ),
              OutlinedButton.icon(
                onPressed: busy || !hasCourier ? null : onRemove,
                icon: const Icon(Icons.person_remove_rounded),
                label: const Text('Remove courier'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MaslakiSpacing.lg),
        child: MaslakiEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Unable to load details',
          body: message,
          action: FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.rows,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return MaslakiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: MaslakiSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
          const SizedBox(height: MaslakiSpacing.sm),
          if (rows.isEmpty)
            Text('-', style: Theme.of(context).textTheme.bodyMedium)
          else
            for (final row in rows) _DetailRowTile(row: row),
        ],
      ),
    );
  }
}

class _DetailRowTile extends StatelessWidget {
  const _DetailRowTile({required this.row});

  final _DetailRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              row.label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(width: MaslakiSpacing.sm),
          Expanded(
            child: SelectableText(
              row.value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;
}
