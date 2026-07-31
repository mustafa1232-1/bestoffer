import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/currency.dart';
import '../state/admin_controller.dart';

/// The employee's own portal: their role, salary, what they've earned so far
/// this month, and their attendance summary. Self-scoped — every employee sees
/// only their own data.
class EmployeeSelfPortalScreen extends ConsumerStatefulWidget {
  const EmployeeSelfPortalScreen({super.key});

  @override
  ConsumerState<EmployeeSelfPortalScreen> createState() =>
      _EmployeeSelfPortalScreenState();
}

class _EmployeeSelfPortalScreenState
    extends ConsumerState<EmployeeSelfPortalScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ref.read(adminApiProvider).myEmployeeDashboard();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _num(dynamic v) => formatIqd((v as num?)?.toDouble() ?? 0);

  String _deptLabel(String? d) {
    switch (d) {
      case 'delivery':
        return 'التوصيل';
      case 'customer_service':
        return 'خدمة العملاء';
      case 'hr':
        return 'الموارد البشرية';
      case 'monitoring':
        return 'المتابعة';
      case 'accounting':
        return 'المحاسبة';
      case 'marketing':
        return 'التسويق';
      case 'management':
        return 'الإدارة';
      case 'tech':
        return 'التقنية';
      default:
        return 'أخرى';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('بوابتي — لوحة الموظف')),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _errorView()
              : _data == null
              ? _noProfileView()
              : _body(),
        ),
      ),
    );
  }

  Widget _errorView() => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text('تعذّر التحميل: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    ],
  );

  Widget _noProfileView() => ListView(
    children: const [
      Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'لا يوجد ملف موظف مرتبط بحسابك.',
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );

  Widget _body() {
    final profile = Map<String, dynamic>.from(_data!['profile'] as Map);
    final salary = Map<String, dynamic>.from(_data!['salary'] as Map);
    final att = Map<String, dynamic>.from(_data!['attendance'] as Map);
    final history = ((_data!['salaryHistory'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    final checkedIn = att['currentlyCheckedIn'] == true;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Identity header
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  child: Text(
                    '${profile['fullName'] ?? '?'}'.characters.first,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${profile['fullName'] ?? ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${profile['jobTitle'] ?? ''} · ${_deptLabel('${profile['department']}')}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if ('${profile['employeeCode'] ?? ''}'.isNotEmpty)
                        Text(
                          'معرّف الموظف: ${profile['employeeCode']}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: (checkedIn ? Colors.green : Colors.grey).withValues(
                      alpha: 0.18,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    checkedIn ? 'حاضر الآن' : 'خارج الدوام',
                    style: TextStyle(
                      color: checkedIn ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Salary cards
        _sectionTitle('الراتب'),
        Row(
          children: [
            _statCard(
              'الراتب الشهري',
              _num(salary['monthlySalaryIqd']),
              Icons.payments_rounded,
              Colors.blue,
            ),
            const SizedBox(width: 10),
            _statCard(
              'المكتسب هذا الشهر',
              _num(salary['earnedThisMonthIqd']),
              Icons.savings_rounded,
              Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statCard(
              'الأجر اليومي التقريبي',
              _num(salary['dailyRateIqd']),
              Icons.today_rounded,
              Colors.orange,
            ),
            const SizedBox(width: 10),
            _statCard(
              'حالة العقد',
              '${profile['status'] == 'active' ? 'نشط' : profile['status'] ?? '—'}',
              Icons.verified_rounded,
              Colors.teal,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Attendance cards
        _sectionTitle('الحضور — هذا الشهر'),
        Row(
          children: [
            _statCard(
              'أيام الحضور',
              '${att['presentDaysThisMonth'] ?? 0}',
              Icons.event_available_rounded,
              Colors.indigo,
            ),
            const SizedBox(width: 10),
            _statCard(
              'الساعات',
              '${att['hoursThisMonth'] ?? 0}',
              Icons.schedule_rounded,
              Colors.purple,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Salary history
        if (history.isNotEmpty) ...[
          _sectionTitle('سجل الراتب'),
          Card(
            child: Column(
              children: [
                for (final h in history)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history_rounded),
                    title: Text(_num(h['baseSalaryIqd'])),
                    subtitle: Text(
                      '${h['effectiveFrom'] ?? ''}${(h['reason'] ?? '').toString().isNotEmpty ? ' · ${h['reason']}' : ''}',
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'المكتسب تقديري بناءً على أيام الحضور والراتب الشهري.',
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      t,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
    ),
  );

  Widget _statCard(String label, String value, IconData icon, Color color) =>
      Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
}
