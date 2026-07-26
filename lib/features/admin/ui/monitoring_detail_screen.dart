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
        title: 'Summary',
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
      if (value.isEmpty) return const [_DetailRow('Items', '0')];
      return [
        _DetailRow('Items', '${value.length}'),
        for (var i = 0; i < value.length && i < 20; i++)
          _DetailRow('#${i + 1}', _format(value[i])),
      ];
    }
    return [_DetailRow('Value', _format(value))];
  }

  bool _isScalar(Object? value) {
    return value == null || value is String || value is num || value is bool;
  }

  String _format(Object? value) {
    if (value == null) return '-';
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
    return key
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .trim();
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
    required this.icon,
    required this.rows,
  });

  final String title;
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
