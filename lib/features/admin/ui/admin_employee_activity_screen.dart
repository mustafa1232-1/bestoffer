import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/admin_controller.dart';

class AdminEmployeeActivityScreen extends ConsumerStatefulWidget {
  const AdminEmployeeActivityScreen({super.key});

  @override
  ConsumerState<AdminEmployeeActivityScreen> createState() =>
      _AdminEmployeeActivityScreenState();
}

class _AdminEmployeeActivityScreenState
    extends ConsumerState<AdminEmployeeActivityScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() =>
      ref.read(adminApiProvider).employeeActivity();

  void _refresh() => setState(() => _future = _load());

  String _value(dynamic value) => value == null ? '-' : '$value';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نشاط الموظفين'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('تعذر تحميل نشاط الموظفين: ${snapshot.error}'),
            );
          }
          final items = ((snapshot.data?['items'] as List?) ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(growable: false);
          if (items.isEmpty) {
            return const Center(child: Text('لا توجد نشاطات بعد'));
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(_value(item['summary'] ?? item['event_name'])),
                    subtitle: Text(
                      [
                        _value(item['full_name']),
                        _value(item['phone']),
                        _value(item['admin_role_key']),
                        _value(item['source']),
                        _value(item['created_at']),
                      ].join(' • '),
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
