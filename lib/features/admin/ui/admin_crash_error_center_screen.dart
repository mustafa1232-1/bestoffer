import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminCrashErrorCenterScreen extends ConsumerStatefulWidget {
  const AdminCrashErrorCenterScreen({super.key});

  @override
  ConsumerState<AdminCrashErrorCenterScreen> createState() =>
      _AdminCrashErrorCenterScreenState();
}

class _AdminCrashErrorCenterScreenState
    extends ConsumerState<AdminCrashErrorCenterScreen> {
  bool _loading = true;
  String? _error;
  String _platform = 'all';
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
          .opsCrashEvents(platform: _platform, limit: 120);
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
          fallback: context.l10n.adminOpsCrashCenterLoadFailed,
        );
      });
    }
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '-';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminOpsCrashCenterTitle),
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
              initialValue: _platform,
              decoration: InputDecoration(
                labelText: l10n.adminOpsCrashCenterPlatformFilter,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _platform = value);
                _load();
              },
              items: const ['all', 'android', 'ios', 'web', 'windows']
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
                ? Center(child: Text(l10n.adminOpsCrashCenterEmpty))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final message = '${item['message'] ?? ''}'.trim();
                        final stack = '${item['stack_trace'] ?? ''}'.trim();
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ExpansionTile(
                            leading: const Icon(Icons.bug_report_outlined),
                            title: Text(
                              message.isEmpty
                                  ? l10n.adminOpsCrashCenterUnknownCrash
                                  : message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${item['platform'] ?? '-'} • ${item['source'] ?? '-'} • ${_formatTime(item['created_at']?.toString())}',
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            children: [
                              if ('${item['user_name'] ?? ''}'
                                  .trim()
                                  .isNotEmpty)
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    '${l10n.commonCustomer}: ${item['user_name']}',
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  stack.isEmpty
                                      ? l10n.adminOpsCrashCenterNoStackTrace
                                      : stack,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
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
