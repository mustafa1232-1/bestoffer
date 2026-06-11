import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminNotificationsOperationsScreen extends ConsumerStatefulWidget {
  const AdminNotificationsOperationsScreen({super.key});

  @override
  ConsumerState<AdminNotificationsOperationsScreen> createState() =>
      _AdminNotificationsOperationsScreenState();
}

class _AdminNotificationsOperationsScreenState
    extends ConsumerState<AdminNotificationsOperationsScreen> {
  bool _loading = true;
  String? _error;
  int _windowHours = 24;
  Map<String, int> _statusCounts = const {};
  List<Map<String, dynamic>> _topErrors = const [];
  double _avgLatency = 0;
  double _p95Latency = 0;

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
          .opsNotificationOverview(windowHours: _windowHours);
      final rawCounts = out['statusCounts'] is Map
          ? out['statusCounts'] as Map
          : const {};
      final counts = <String, int>{};
      for (final entry in rawCounts.entries) {
        counts['${entry.key}'] = int.tryParse('${entry.value}') ?? 0;
      }
      final rawErrors = List<dynamic>.from(
        out['topErrors'] as List? ?? const [],
      );
      final errors = rawErrors
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      final latency = out['latency'] is Map ? out['latency'] as Map : const {};
      if (!mounted) return;
      setState(() {
        _statusCounts = counts;
        _topErrors = errors;
        _avgLatency = double.tryParse('${latency['avgMs']}') ?? 0;
        _p95Latency = double.tryParse('${latency['p95Ms']}') ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.adminOpsNotificationsOperationsLoadFailed,
        );
      });
    }
  }

  int _count(String key) => _statusCounts[key] ?? 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminOpsNotificationsOperationsTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [6, 24, 72, 168]
                        .map(
                          (hours) => ChoiceChip(
                            label: Text(l10n.adminOpsWindowHours(hours)),
                            selected: _windowHours == hours,
                            onSelected: (_) {
                              setState(() => _windowHours = hours);
                              _load();
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  _SummaryCardGrid(
                    cards: [
                      _SummaryCardData(
                        title: l10n.adminOpsDeliverySent,
                        value: _count('sent').toString(),
                        color: const Color(0xFF22C55E),
                        icon: Icons.send_rounded,
                      ),
                      _SummaryCardData(
                        title: l10n.adminOpsDeliveryRetry,
                        value: _count('retry').toString(),
                        color: const Color(0xFFF59E0B),
                        icon: Icons.refresh_rounded,
                      ),
                      _SummaryCardData(
                        title: l10n.adminOpsDeliveryFailed,
                        value: _count('failed').toString(),
                        color: const Color(0xFFEF4444),
                        icon: Icons.error_outline_rounded,
                      ),
                      _SummaryCardData(
                        title: l10n.adminOpsDeliveryDeadTokens,
                        value: _count('dead_token').toString(),
                        color: const Color(0xFFF97316),
                        icon: Icons.block_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.speed_rounded),
                      title: Text(l10n.adminOpsLatencyTitle),
                      subtitle: Text(
                        '${l10n.adminOpsLatencyAverage}: ${_avgLatency.toStringAsFixed(1)} ms\n${l10n.adminOpsLatencyP95}: ${_p95Latency.toStringAsFixed(1)} ms',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.adminOpsTopErrorsTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_topErrors.isEmpty)
                    Text(l10n.adminOpsTopErrorsEmpty)
                  else
                    ..._topErrors.map((row) {
                      final code = '${row['code'] ?? ''}'.trim();
                      final count = int.tryParse('${row['count']}') ?? 0;
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.warning_amber_rounded),
                          title: Text(code.isEmpty ? '-' : code),
                          trailing: Text(
                            '$count',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _SummaryCardGrid extends StatelessWidget {
  final List<_SummaryCardData> cards;

  const _SummaryCardGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;
        if (isCompact) {
          return Column(
            children: cards
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SummaryCard(data: card),
                  ),
                )
                .toList(growable: false),
          );
        }
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: cards
              .map(
                (card) => SizedBox(
                  width: width,
                  child: _SummaryCard(data: card),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final _SummaryCardData data;

  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: data.color.withValues(alpha: 0.16),
          foregroundColor: data.color,
          child: Icon(data.icon),
        ),
        title: Text(data.title),
        trailing: Text(
          data.value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _SummaryCardData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
}
