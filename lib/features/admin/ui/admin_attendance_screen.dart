import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/parsers.dart';
import '../state/admin_controller.dart';
import 'admin_employees_screen.dart';

class AdminAttendanceScreen extends ConsumerStatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  ConsumerState<AdminAttendanceScreen> createState() =>
      _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends ConsumerState<AdminAttendanceScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await ref.read(adminApiProvider).listAttendance(limit: 200);
    return ((data['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'جدول الحضور', en: 'Attendance')),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            final message = error is DioException
                ? mapDioError(error, fallback: 'تعذر تحميل الحضور.')
                : 'تعذر تحميل الحضور.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: Text(
                        context.lt(ar: 'إعادة المحاولة', en: 'Retry'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return Center(
              child: Text(
                context.lt(
                  ar: 'لا توجد سجلات حضور.',
                  en: 'No attendance records.',
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = rows[index];
                final checkedOut = '${row['check_out_at'] ?? ''}'
                    .trim()
                    .isNotEmpty;
                return ListTile(
                  leading: Icon(
                    checkedOut
                        ? Icons.event_available_rounded
                        : Icons.timer_rounded,
                    color: checkedOut
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.tertiary,
                  ),
                  title: Text(parseString(row['full_name'], fallback: 'موظف')),
                  subtitle: Text(
                    '${context.lt(ar: 'حضور', en: 'In')}: ${_fmt(row['check_in_at'])}\n'
                    '${context.lt(ar: 'انصراف', en: 'Out')}: ${_fmt(row['check_out_at'])}',
                  ),
                  trailing: Text(
                    checkedOut
                        ? context.lt(ar: 'مكتمل', en: 'Done')
                        : context.lt(ar: 'حاضر', en: 'In'),
                  ),
                  onTap: () {
                    final userId = parseInt(row['employee_user_id']);
                    if (userId <= 0) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AdminEmployeeDetailScreen(userId: userId),
                      ),
                    );
                  },
                  isThreeLine: true,
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _fmt(Object? value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
