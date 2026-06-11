import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminDeviceReliabilityScreen extends ConsumerStatefulWidget {
  const AdminDeviceReliabilityScreen({super.key});

  @override
  ConsumerState<AdminDeviceReliabilityScreen> createState() =>
      _AdminDeviceReliabilityScreenState();
}

class _AdminDeviceReliabilityScreenState
    extends ConsumerState<AdminDeviceReliabilityScreen> {
  bool _loading = true;
  String? _error;
  String _status = 'all';
  List<Map<String, dynamic>> _items = const [];

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
          .opsDevicePushHealth(status: _status, limit: 180);
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
          fallback: context.l10n.adminOpsDeviceReliabilityLoadFailed,
        );
      });
    }
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'sent':
      case 'delivered':
      case 'opened':
        return const Color(0xFF22C55E);
      case 'retry':
        return const Color(0xFFF59E0B);
      case 'failed':
        return scheme.error;
      case 'dead_token':
        return const Color(0xFFF97316);
      default:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminOpsDeviceReliabilityTitle),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(
                labelText: l10n.adminOpsFilterStatus,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _status = value);
                _load();
              },
              items:
                  const [
                        'all',
                        'sent',
                        'retry',
                        'failed',
                        'dead_token',
                        'opened',
                      ]
                      .map(
                        (v) => DropdownMenuItem<String>(
                          value: v,
                          child: Text(v == 'all' ? l10n.commonAll : v),
                        ),
                      )
                      .toList(growable: false),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _items.isEmpty
                ? Center(child: Text(l10n.adminOpsDeviceReliabilityEmpty))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final status = '${item['last_status'] ?? 'unknown'}'
                            .trim();
                        final color = _statusColor(status, scheme);
                        final successCount =
                            int.tryParse('${item['success_count']}') ?? 0;
                        final failureCount =
                            int.tryParse('${item['failure_count']}') ?? 0;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.16),
                              foregroundColor: color,
                              child: const Icon(Icons.phonelink_lock_rounded),
                            ),
                            title: Text(
                              '${item['user_name'] ?? l10n.commonUnknown} (${item['platform'] ?? '-'})',
                            ),
                            subtitle: Text(
                              '${l10n.commonStatus}: $status\n${l10n.adminOpsDeviceReliabilitySuccess}: $successCount • ${l10n.adminOpsDeviceReliabilityFailures}: $failureCount\n${item['push_token'] ?? '-'}',
                            ),
                            isThreeLine: true,
                            trailing: item['last_error_code'] == null
                                ? null
                                : Tooltip(
                                    message: '${item['last_error_code']}',
                                    child: const Icon(
                                      Icons.error_outline_rounded,
                                    ),
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
