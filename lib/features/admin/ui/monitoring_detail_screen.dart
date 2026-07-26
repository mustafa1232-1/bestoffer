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
  bool _loading = true;
  bool _includeSensitive = false;
  String? _reason;
  String? _error;
  Map<String, dynamic>? _payload;

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
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
      setState(() {
        _error = mapAnyError(
          error,
          fallback: 'Unable to load monitoring details.',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
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
