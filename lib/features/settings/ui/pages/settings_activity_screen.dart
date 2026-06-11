import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_formatters.dart';
import '../../../../core/i18n/app_localizations_context.dart';
import '../../../behavior/data/behavior_api.dart';

class SettingsActivityScreen extends ConsumerStatefulWidget {
  const SettingsActivityScreen({super.key});

  @override
  ConsumerState<SettingsActivityScreen> createState() =>
      _SettingsActivityScreenState();
}

class _SettingsActivityScreenState
    extends ConsumerState<SettingsActivityScreen> {
  bool _initialLoading = true;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _events = const [];
  int? _nextCursor;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadInitial);
  }

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      final page = await ref.read(behaviorApiProvider).myEvents(limit: 50);
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _events = page.items;
        _nextCursor = page.nextCursor;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _error = context.l10n.settingsActivityLoadFailed;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(behaviorApiProvider)
          .myEvents(limit: 50, beforeId: _nextCursor);
      if (!mounted) return;

      final knownIds = _events
          .map((row) => int.tryParse('${row['id']}'))
          .whereType<int>()
          .toSet();
      final merged = <Map<String, dynamic>>[..._events];
      for (final row in page.items) {
        final id = int.tryParse('${row['id']}');
        if (id != null && knownIds.contains(id)) continue;
        merged.add(row);
      }

      setState(() {
        _loadingMore = false;
        _events = merged;
        _nextCursor = page.nextCursor;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = context.l10n.settingsActivityLoadMoreFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsMyActivityLog),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _initialLoading ? null : _loadInitial,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _events.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _loadInitial,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.commonRetry),
                  ),
                ],
              ),
            )
          : _events.isEmpty
          ? Center(child: Text(l10n.settingsActivityNoEntries))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _events.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == _events.length) {
                  if (_loadingMore) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (_nextCursor == null) {
                    return Center(
                      child: Text(
                        l10n.settingsActivityEndOfLog,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }
                  return Center(
                    child: OutlinedButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(l10n.settingsActivityLoadMore),
                    ),
                  );
                }

                final item = _events[index];
                final event = _stringValue(item['eventName'] ?? item['event_name']);
                final category = _stringValue(item['category']);
                final action = _stringValue(item['action']);
                final at = _formatDate(item['createdAt'] ?? item['created_at']);

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(
                      event.isEmpty ? l10n.settingsActivityEventLabel : event,
                    ),
                    subtitle: Text(
                      [
                        if (category.isNotEmpty)
                          '${l10n.settingsActivityCategoryLabel}: $category',
                        if (action.isNotEmpty)
                          '${l10n.settingsActivityActionLabel}: $action',
                        '${l10n.settingsActivityTimeLabel}: $at',
                      ].join('\n'),
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }

  String _stringValue(dynamic value) => value == null ? '' : '$value'.trim();

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return '$value';
    return formatDateTimeLocalized(
      parsed,
      localeCode: Localizations.localeOf(context).languageCode,
    );
  }
}
