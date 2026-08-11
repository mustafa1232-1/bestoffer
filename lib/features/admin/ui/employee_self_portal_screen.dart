import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../../settings/ui/pages/settings_account_screen.dart';
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
  bool _toggling = false;
  String? _error;
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _coupon;

  Future<void> _toggleAttendance(bool currentlyIn) async {
    setState(() => _toggling = true);
    try {
      final api = ref.read(adminApiProvider);
      if (currentlyIn) {
        await api.staffCheckOut();
      } else {
        await api.staffCheckIn();
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentlyIn ? 'تم تسجيل الانصراف' : 'تم تسجيل الحضور'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is DioException
          ? mapDioError(e, fallback: 'تعذّر تسجيل الحضور/الانصراف.')
          : 'تعذّر تسجيل الحضور/الانصراف.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

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
      final api = ref.read(adminApiProvider);
      final d = await api.myEmployeeDashboard();
      // "كوبوني" earnings — best-effort; the portal still loads without it.
      Map<String, dynamic>? coupon;
      try {
        coupon = await api.myCouponEarnings();
      } catch (_) {
        coupon = null;
      }
      if (!mounted) return;
      setState(() {
        _data = d;
        _coupon = coupon;
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
        appBar: AppBar(
          title: const Text('بوابتي — لوحة الموظف'),
          actions: [
            IconButton(
              tooltip: 'أمان الحساب',
              icon: const Icon(Icons.lock_reset_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsAccountScreen(),
                ),
              ),
            ),
          ],
        ),
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

        // Check-in / check-out — the employee records attendance directly.
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _toggling ? null : () => _toggleAttendance(checkedIn),
            icon: _toggling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(checkedIn ? Icons.logout_rounded : Icons.login_rounded),
            label: Text(checkedIn ? 'تسجيل انصراف' : 'تسجيل حضور'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: checkedIn ? Colors.orange : Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 14),

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

        // "كوبوني" — the employee's referral coupon and earnings from it.
        ..._couponSection(),

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

  List<Widget> _couponSection() {
    final c = _coupon;
    if (c == null || c['hasCoupon'] != true) {
      return [
        _sectionTitle('كوبوني'),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'لا يوجد كوبون إحالة خاص بك بعد. تواصل مع الإدارة لإنشائه.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ];
    }
    final summary = Map<String, dynamic>.from(
      (c['summary'] as Map?) ?? const {},
    );
    final coupons = ((c['coupons'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    final primary = coupons.isNotEmpty ? coupons.first : <String, dynamic>{};
    final code = '${primary['code'] ?? ''}';
    final share = (primary['sharePercent'] as num?) ?? (c['sharePercent'] as num?) ?? 25;
    final redemptions = (summary['totalRedemptions'] as num?)?.toInt() ?? 0;

    return [
      _sectionTitle('كوبوني'),
      // Coupon code header with copy + share badge.
      Card(
        color: Colors.teal.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.confirmation_number_rounded,
                color: Colors.teal,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'رمز كوبونك',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      code.isEmpty ? '—' : code,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'حصّتك: $share% من عمولة الشركة على كل طلب',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (code.isNotEmpty)
                IconButton(
                  tooltip: 'نسخ',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ رمز الكوبون')),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _statCard(
            'أرباح كوبوني',
            _num(summary['totalEarnings']),
            Icons.savings_rounded,
            Colors.green,
          ),
          const SizedBox(width: 10),
          _statCard(
            'عمولة الشركة (طلباتك)',
            _num(summary['totalCompanyCommission']),
            Icons.account_balance_rounded,
            Colors.blue,
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _statCard(
            'مرات الاستخدام',
            '$redemptions',
            Icons.shopping_bag_rounded,
            Colors.deepPurple,
          ),
          const SizedBox(width: 10),
          _statCard(
            'نسبة حصّتك',
            '$share%',
            Icons.percent_rounded,
            Colors.orange,
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'تُحتسب الأرباح عند اكتمال الطلب (تسليمه) فقط.',
        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
    ];
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
