import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../state/admin_controller.dart';

/// Dedicated, standalone employee-account creation. Not linked to any user.
/// Fields: name, phone, residence, employee code, PIN, job role, salary — then
/// a job role auto-fills its permissions, and every permission is an Arabic
/// checkbox with an inline explanation you can toggle.
class AdminCreateEmployeeScreen extends ConsumerStatefulWidget {
  const AdminCreateEmployeeScreen({super.key});

  @override
  ConsumerState<AdminCreateEmployeeScreen> createState() =>
      _AdminCreateEmployeeScreenState();
}

class _AdminCreateEmployeeScreenState
    extends ConsumerState<AdminCreateEmployeeScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _residence = TextEditingController();
  final _employeeCode = TextEditingController();
  final _pin = TextEditingController();
  final _salary = TextEditingController();
  final _jobTitle = TextEditingController();
  final _couponShare = TextEditingController(text: '25');
  final _couponDiscount = TextEditingController(text: '0');

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  // "كوبوني": give the employee a referral coupon. When a customer uses it, the
  // employee earns [_couponShare]% of the company's commission on that order.
  bool _createCoupon = true;
  String _couponDiscountType = 'percent'; // percent | fixed

  List<Map<String, dynamic>> _groups = const [];
  List<Map<String, dynamic>> _perms = const [];
  List<Map<String, dynamic>> _jobRoles = const [];
  bool _canManagePermissions = false;

  String? _jobRoleKey;
  final Set<String> _checked = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _phone,
      _residence,
      _employeeCode,
      _pin,
      _salary,
      _jobTitle,
      _couponShare,
      _couponDiscount,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(adminApiProvider);
      final permissionsData = await api.myPermissions();
      final isSuper =
          permissionsData['isSuperAdmin'] == true ||
          permissionsData['wildcard'] == true ||
          ref.read(authControllerProvider).isSuperAdmin;
      final permissions =
          List<dynamic>.from(
                permissionsData['permissions'] as List? ?? const [],
              )
              .whereType<Map>()
              .map((item) => '${item['key'] ?? ''}'.trim())
              .where((item) => item.isNotEmpty)
              .toSet();
      final canManagePermissions =
          isSuper || permissions.contains('employees.permissions.manage');
      final data = await api.rbacCatalog();
      final groups = ((data['groups'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      final perms = ((data['permissionDetails'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      final roles = ((data['roleTemplates'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) => r['isJobRole'] == true)
          .where((r) => isSuper || !_roleHasSensitivePermission(r))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _perms = perms;
        _jobRoles = roles;
        _canManagePermissions = canManagePermissions;
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

  List<String> _rolePermissions(String? key) {
    if (key == null) return const [];
    final role = _jobRoles.firstWhere(
      (r) => r['key'] == key,
      orElse: () => const {},
    );
    return ((role['permissions'] as List?) ?? const [])
        .map((e) => '$e')
        .toList(growable: false);
  }

  static const Set<String> _sensitivePermissionKeys = {
    'employees.permissions.manage',
    'accounts.delete_approve',
    'payroll.release',
    'payroll.approve',
    'taxi.rides.emergency_cancel',
  };

  bool _roleHasSensitivePermission(Map<String, dynamic> role) {
    final permissions = (role['permissions'] as List?) ?? const [];
    return permissions.any((key) => _sensitivePermissionKeys.contains('$key'));
  }

  void _selectJobRole(String? key) {
    setState(() {
      _jobRoleKey = key;
      _checked
        ..clear()
        ..addAll(_rolePermissions(key));
      if (_jobTitle.text.trim().isEmpty && key != null) {
        final role = _jobRoles.firstWhere(
          (r) => r['key'] == key,
          orElse: () => const {},
        );
        _jobTitle.text = '${role['labelAr'] ?? ''}';
      }
    });
  }

  Future<void> _submit() async {
    final name = _fullName.text.trim();
    final phone = _phone.text.trim();
    final pin = _pin.text.trim();
    if (name.length < 2) {
      _snack('أدخل اسم الموظف.');
      return;
    }
    if (!RegExp(r'^\d{6,15}$').hasMatch(phone)) {
      _snack('أدخل رقم هاتف صحيحاً (أرقام فقط).');
      return;
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      _snack('الرقم السري يجب أن يكون 4 إلى 8 أرقام.');
      return;
    }
    if (_jobRoleKey == null) {
      _snack('اختر وظيفة الموظف.');
      return;
    }

    // Overrides = the diff between the checked set and the job-role defaults.
    final defaults = _rolePermissions(_jobRoleKey).toSet();
    final overrides = <Map<String, dynamic>>[];
    if (_canManagePermissions) {
      for (final key in _checked) {
        if (!defaults.contains(key)) {
          overrides.add({'permissionKey': key, 'effect': 'grant'});
        }
      }
      for (final key in defaults) {
        if (!_checked.contains(key)) {
          overrides.add({'permissionKey': key, 'effect': 'revoke'});
        }
      }
    }

    setState(() => _submitting = true);
    try {
      final salary = int.tryParse(_salary.text.trim());
      final share = num.tryParse(_couponShare.text.trim()) ?? 25;
      final discount = num.tryParse(_couponDiscount.text.trim()) ?? 0;
      await ref.read(adminApiProvider).createEmployeeAccount({
        'fullName': name,
        'phone': phone,
        'pin': pin,
        'residence': _residence.text.trim(),
        'employeeCode': _employeeCode.text.trim(),
        'jobRoleKey': _jobRoleKey,
        'jobTitle': _jobTitle.text.trim(),
        'baseSalaryIqd': salary,
        if (_canManagePermissions) 'permissions': overrides,
        'createReferralCoupon': _createCoupon,
        if (_createCoupon) 'agentCommissionSharePercent': share,
        if (_createCoupon) 'couponDiscountType': _couponDiscountType,
        if (_createCoupon) 'couponDiscountValue': discount,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء حساب الموظف بنجاح')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e is DioException
          ? mapDioError(e, fallback: 'تعذّر إنشاء حساب الموظف.')
          : 'تعذّر إنشاء حساب الموظف.';
      _snack(msg);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final isSuper = ref.watch(authControllerProvider).isSuperAdmin;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إنشاء حساب موظف')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _errorView()
            : _form(isSuper || _canManagePermissions),
        bottomNavigationBar: (_loading || _error != null)
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('إنشاء الحساب'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
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
            FilledButton(
              onPressed: _loadCatalog,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _form(bool isSuper) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _section('بيانات الموظف'),
        _text(_fullName, 'الاسم الكامل *'),
        _text(_phone, 'رقم الهاتف *', keyboard: TextInputType.phone),
        _text(_residence, 'السكن'),
        _text(_employeeCode, 'معرّف الموظف'),
        _text(
          _pin,
          'الرقم السري (PIN) * — 4 إلى 8 أرقام',
          keyboard: TextInputType.number,
          obscure: true,
        ),
        const SizedBox(height: 12),
        _section('الوظيفة والراتب'),
        DropdownButtonFormField<String>(
          initialValue: _jobRoleKey,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'الوظيفة *',
            border: OutlineInputBorder(),
          ),
          items: _jobRoles
              .map(
                (r) => DropdownMenuItem<String>(
                  value: '${r['key']}',
                  child: Text('${r['labelAr'] ?? r['key']}'),
                ),
              )
              .toList(growable: false),
          onChanged: _selectJobRole,
        ),
        if (_jobRoleKey != null) _jobRoleHint(),
        const SizedBox(height: 8),
        _text(_jobTitle, 'المسمّى الوظيفي (اختياري)'),
        _text(_salary, 'الراتب الشهري (د.ع)', keyboard: TextInputType.number),
        const SizedBox(height: 16),
        _couponSection(),
        const SizedBox(height: 16),
        // Permissions are auto-filled by the chosen job role, so they're tucked
        // into a single collapsible section — the fast path never needs to open
        // it. Expand only to fine-tune.
        if (_canManagePermissions)
          Card(
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.shield_outlined),
              title: const Text(
                'الصلاحيات (اختياري)',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                _jobRoleKey == null
                    ? 'ستُفعَّل تلقائياً حسب الوظيفة — اختر وظيفة'
                    : 'مفعّلة تلقائياً حسب الوظيفة · ${_checked.length} صلاحية — اضغط للتخصيص',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: _groups.map((g) => _permGroup(g, isSuper)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _jobRoleHint() {
    final role = _jobRoles.firstWhere(
      (r) => r['key'] == _jobRoleKey,
      orElse: () => const {},
    );
    final desc = '${role['descriptionAr'] ?? ''}';
    if (desc.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.secondaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(desc, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }

  Widget _permGroup(Map<String, dynamic> group, bool isSuper) {
    final groupKey = '${group['key']}';
    final items = _perms.where((p) => p['group'] == groupKey).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final selectedInGroup = items
        .where((p) => _checked.contains('${p['key']}'))
        .length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(
          '${group['labelAr'] ?? groupKey}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('$selectedInGroup / ${items.length} مفعّلة'),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: items.map((p) => _permTile(p, isSuper)).toList(),
      ),
    );
  }

  Widget _permTile(Map<String, dynamic> p, bool isSuper) {
    final key = '${p['key']}';
    final sensitive = p['sensitive'] == true;
    final locked = sensitive && !isSuper;
    return CheckboxListTile(
      value: _checked.contains(key),
      onChanged: locked
          ? null
          : (v) => setState(() {
              if (v == true) {
                _checked.add(key);
              } else {
                _checked.remove(key);
              }
            }),
      controlAffinity: ListTileControlAffinity.leading,
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${p['labelAr'] ?? key}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (sensitive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                locked ? 'حسّاسة — سوبر أدمن' : 'حسّاسة',
                style: const TextStyle(fontSize: 10, color: Colors.orange),
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${p['descriptionAr'] ?? ''}',
        style: const TextStyle(fontSize: 12),
      ),
      dense: false,
    );
  }

  Widget _couponSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: _createCoupon,
              onChanged: (v) => setState(() => _createCoupon = v),
              secondary: const Icon(Icons.confirmation_number_rounded),
              title: const Text(
                'كوبون الموظف (كوبوني)',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text(
                'أنشئ كوبون إحالة خاصاً بالموظف — عند استخدامه يكسب حصّته من عمولة الشركة على الطلب.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (_createCoupon) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _text(
                      _couponShare,
                      'حصّة الموظف من عمولة الشركة (%) — الافتراضي 25',
                      keyboard: TextInputType.number,
                    ),
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'مثال: إذا كانت قيمة الطلب 10,000 وعمولة الشركة 10% (=1,000)، '
                        'فبحصّة 25% يكسب الموظف 250 د.ع عن كل طلب يُستخدم فيه كوبونه.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const Text(
                      'خصم للزبون (اختياري) — 0 يعني كوبون إحالة فقط بدون خصم',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: _couponDiscountType,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'نوع الخصم',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'percent',
                                child: Text('نسبة %'),
                              ),
                              DropdownMenuItem(
                                value: 'fixed',
                                child: Text('مبلغ ثابت'),
                              ),
                            ],
                            onChanged: (v) => setState(
                              () => _couponDiscountType = v ?? 'percent',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _couponDiscount,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'قيمة الخصم',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
    ),
  );

  Widget _text(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: c,
      keyboardType: keyboard,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
