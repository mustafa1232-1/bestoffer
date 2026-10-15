import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/admin_controller.dart';

class AdminPinResetRequestsScreen extends ConsumerStatefulWidget {
  const AdminPinResetRequestsScreen({super.key});
  @override
  ConsumerState<AdminPinResetRequestsScreen> createState() =>
      _AdminPinResetRequestsScreenState();
}

class _AdminPinResetRequestsScreenState
    extends ConsumerState<AdminPinResetRequestsScreen> {
  late Future<List<dynamic>> future;
  @override
  void initState() {
    super.initState();
    future = ref.read(adminApiProvider).pinResetRequests();
  }

  void reload() => setState(() {
    future = ref.read(adminApiProvider).pinResetRequests();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('طلبات إعادة تعيين الرموز'),
      actions: [IconButton(onPressed: reload, icon: const Icon(Icons.refresh))],
    ),
    body: FutureBuilder<List<dynamic>>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!;
        if (rows.isEmpty) return const Center(child: Text('لا توجد طلبات'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = Map<String, dynamic>.from(rows[i] as Map);
            final pending = row['status'] == 'pending';
            return Card(
              child: ListTile(
                title: Text(
                  '${row['full_name'] ?? ''} - ${row['phone'] ?? ''}',
                ),
                subtitle: Text(
                  'الحالة: ${row['status']}\n${row['role'] ?? 'user'} | ${row['block'] ?? ''} ${row['building_number'] ?? ''}',
                ),
                isThreeLine: true,
                trailing: pending
                    ? Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'موافقة',
                            onPressed: () async {
                              await ref
                                  .read(adminApiProvider)
                                  .approvePinReset(int.parse('${row['id']}'));
                              reload();
                            },
                            icon: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                          ),
                          IconButton(
                            tooltip: 'رفض',
                            onPressed: () async {
                              await ref
                                  .read(adminApiProvider)
                                  .rejectPinReset(int.parse('${row['id']}'));
                              reload();
                            },
                            icon: const Icon(Icons.cancel, color: Colors.red),
                          ),
                        ],
                      )
                    : null,
              ),
            );
          },
        );
      },
    ),
  );
}
