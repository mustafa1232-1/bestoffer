import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/emergency/emergency_contacts.dart';
import '../../services/ui/emergency_request_tracking_screen.dart';
import '../state/admin_controller.dart';

class AdminEmergencyRequestsScreen extends ConsumerStatefulWidget {
  const AdminEmergencyRequestsScreen({super.key});

  @override
  ConsumerState<AdminEmergencyRequestsScreen> createState() =>
      _AdminEmergencyRequestsScreenState();
}

class _AdminEmergencyRequestsScreenState
    extends ConsumerState<AdminEmergencyRequestsScreen> {
  Timer? _timer;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = await ref.read(adminApiProvider).listEmergencyRequests();
      final raw = data['items'];
      final items = raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (item) => item.map(
                    (key, value) => MapEntry<String, dynamic>('$key', value),
                  ),
                )
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = 'تعذر تحميل طلبات الطوارئ.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات الطوارئ'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : _items.isEmpty
            ? const Center(child: Text('لا توجد طلبات طوارئ حالياً'))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final id = int.tryParse('${item['id']}') ?? 0;
                    final contact = emergencyContactByKey(
                      '${item['emergencyTarget'] ?? ''}',
                    );
                    final active = !const {
                      'completed',
                      'cancelled',
                      'rejected',
                      'expired',
                    }.contains('${item['status']}');
                    return Card(
                      child: ListTile(
                        onTap: id <= 0
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EmergencyRequestTrackingScreen(
                                        requestId: id,
                                        adminMode: true,
                                      ),
                                ),
                              ),
                        leading: CircleAvatar(
                          backgroundColor: active
                              ? Theme.of(context).colorScheme.errorContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                          child: Icon(contact?.icon ?? Icons.sos_rounded),
                        ),
                        title: Text(
                          '${contact?.title ?? 'طوارئ'} - ${item['customerFullName'] ?? 'مستخدم'}',
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${item['requestCode'] ?? '#$id'}  •  ${active ? 'نشط الآن' : 'مغلق'}\n${item['customerPhone'] ?? ''}',
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
