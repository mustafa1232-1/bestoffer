import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminAuditSecurityCenterScreen extends ConsumerStatefulWidget {
  const AdminAuditSecurityCenterScreen({super.key});

  @override
  ConsumerState<AdminAuditSecurityCenterScreen> createState() =>
      _AdminAuditSecurityCenterScreenState();
}

class _AdminAuditSecurityCenterScreenState
    extends ConsumerState<AdminAuditSecurityCenterScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = const [];

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
      final out = await ref.read(adminApiProvider).auditFeed(limit: 80);
      final raw = List<dynamic>.from(out['items'] as List? ?? const []);
      final events = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.adminOpsAuditSecurityLoadFailed,
        );
      });
    }
  }

  String _formatDate(String? iso) {
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
        title: Text(l10n.adminOpsAuditSecurityTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _events.isEmpty
          ? Center(child: Text(l10n.adminOpsAuditSecurityEmpty))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                itemCount: _events.length,
                itemBuilder: (context, index) {
                  final item = _events[index];
                  final actor =
                      '${item['actorName'] ?? item['full_name'] ?? ''}'.trim();
                  final action = '${item['action'] ?? item['eventType'] ?? '-'}'
                      .trim();
                  final scope = '${item['scope'] ?? item['source'] ?? '-'}'
                      .trim();
                  final notes = '${item['note'] ?? item['description'] ?? ''}'
                      .trim();
                  final createdAt = _formatDate(
                    item['createdAt']?.toString() ??
                        item['created_at']?.toString(),
                  );
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: const Icon(Icons.security_rounded),
                      title: Text(action.isEmpty ? '-' : action),
                      subtitle: Text(
                        '${l10n.adminOpsAuditSecurityActor}: ${actor.isEmpty ? '-' : actor}\n${l10n.adminOpsAuditSecurityScope}: $scope\n$createdAt${notes.isEmpty ? '' : '\n$notes'}',
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ),
    );
  }
}
