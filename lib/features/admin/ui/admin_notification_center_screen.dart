import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminNotificationCenterScreen extends ConsumerStatefulWidget {
  const AdminNotificationCenterScreen({super.key});

  @override
  ConsumerState<AdminNotificationCenterScreen> createState() =>
      _AdminNotificationCenterScreenState();
}

class _AdminNotificationCenterScreenState
    extends ConsumerState<AdminNotificationCenterScreen> {
  bool _loading = true;
  String? _error;
  String _status = 'open';
  String _severity = 'all';
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(adminApiProvider)
          .opsAlerts(status: _status, severity: _severity, limit: 120);
      final raw = List<dynamic>.from(out['items'] as List? ?? const []);
      final items = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.adminOpsNotificationCenterLoadFailed,
        );
      });
    }
  }

  Future<void> _ackAlert({
    required int alertId,
    required String nextStatus,
  }) async {
    try {
      await ref.read(adminApiProvider).ackOpsAlert(alertId, status: nextStatus);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.adminOpsNotificationCenterAckFailed,
            ),
          ),
        ),
      );
    }
  }

  Color _severityColor(ColorScheme scheme, String value) {
    switch (value) {
      case 'critical':
        return scheme.error;
      case 'high':
        return const Color(0xFFF97316);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF22C55E);
      default:
        return scheme.primary;
    }
  }

  String _statusLabel(String status) {
    final l10n = context.l10n;
    switch (status) {
      case 'open':
        return l10n.adminOpsStatusOpen;
      case 'acknowledged':
        return l10n.adminOpsStatusAcknowledged;
      case 'resolved':
        return l10n.adminOpsStatusResolved;
      case 'ignored':
        return l10n.adminOpsStatusIgnored;
      default:
        return status;
    }
  }

  String _severityLabel(String severity) {
    final l10n = context.l10n;
    switch (severity) {
      case 'critical':
        return l10n.adminOpsSeverityCritical;
      case 'high':
        return l10n.adminOpsSeverityHigh;
      case 'medium':
        return l10n.adminOpsSeverityMedium;
      case 'low':
        return l10n.adminOpsSeverityLow;
      default:
        return l10n.adminOpsSeverityInfo;
    }
  }

  String _relativeTimestamp(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '';
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return '';
    return '${parsed.year}/${parsed.month.toString().padLeft(2, '0')}/${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminOpsNotificationCenterTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FilterChipDropdown(
                  label: l10n.adminOpsFilterStatus,
                  value: _status,
                  items: const <String>[
                    'open',
                    'acknowledged',
                    'resolved',
                    'ignored',
                    'all',
                  ],
                  itemLabel: (v) =>
                      v == 'all' ? l10n.commonAll : _statusLabel(v),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _status = v);
                    _load();
                  },
                ),
                _FilterChipDropdown(
                  label: l10n.adminOpsFilterSeverity,
                  value: _severity,
                  items: const <String>[
                    'critical',
                    'high',
                    'medium',
                    'low',
                    'info',
                    'all',
                  ],
                  itemLabel: (v) =>
                      v == 'all' ? l10n.commonAll : _severityLabel(v),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _severity = v);
                    _load();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _items.isEmpty
                ? Center(child: Text(l10n.adminOpsNotificationCenterEmpty))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final status = '${item['status'] ?? 'open'}'
                            .trim()
                            .toLowerCase();
                        final severity = '${item['severity'] ?? 'medium'}'
                            .trim()
                            .toLowerCase();
                        final title = '${item['title'] ?? ''}'.trim();
                        final source = '${item['source'] ?? ''}'.trim();
                        final type = '${item['event_type'] ?? ''}'.trim();
                        final createdAt = _relativeTimestamp(
                          item['created_at']?.toString(),
                        );
                        final color = _severityColor(scheme, severity);
                        final details = item['details'] is Map
                            ? item['details'] as Map
                            : null;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title.isEmpty
                                            ? l10n.adminOpsNotificationCenterUntitled
                                            : title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        _severityLabel(severity),
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${l10n.adminOpsFieldSource}: ${source.isEmpty ? '-' : source}  •  ${l10n.adminOpsFieldType}: ${type.isEmpty ? '-' : type}',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${l10n.commonStatus}: ${_statusLabel(status)}${createdAt.isEmpty ? '' : '  •  $createdAt'}',
                                ),
                                if (details != null && details.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    details.entries
                                        .take(3)
                                        .map((e) => '${e.key}: ${e.value}')
                                        .join(' • '),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                                if (status == 'open' ||
                                    status == 'acknowledged') ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _ackAlert(
                                          alertId:
                                              (item['id'] as num?)?.toInt() ??
                                              0,
                                          nextStatus: 'acknowledged',
                                        ),
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                        ),
                                        label: Text(
                                          l10n.adminOpsActionAcknowledge,
                                        ),
                                      ),
                                      FilledButton.icon(
                                        onPressed: () => _ackAlert(
                                          alertId:
                                              (item['id'] as num?)?.toInt() ??
                                              0,
                                          nextStatus: 'resolved',
                                        ),
                                        icon: const Icon(
                                          Icons.task_alt_rounded,
                                        ),
                                        label: Text(l10n.adminOpsActionResolve),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
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

class _FilterChipDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final String Function(String value) itemLabel;
  final ValueChanged<String?> onChanged;

  const _FilterChipDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          onChanged: onChanged,
          items: items
              .map(
                (v) => DropdownMenuItem<String>(
                  value: v,
                  child: Text(itemLabel(v)),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}
