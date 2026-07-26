import 'package:core_design_system/core_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/parsers.dart';
import '../state/admin_controller.dart';
import 'admin_rbac_management_screen.dart';

const _departments = <String>[
  'delivery', 'customer_service', 'hr', 'monitoring', 'accounting',
  'marketing', 'management', 'tech', 'other',
];
const _employmentTypes = <String>['full_time', 'part_time', 'contract', 'temporary'];
const _statuses = <String>['active', 'suspended', 'terminated'];

String deptLabel(BuildContext c, String key) {
  const ar = {
    'delivery': 'دلفري', 'customer_service': 'خدمة عملاء', 'hr': 'موارد بشرية',
    'monitoring': 'متابعة', 'accounting': 'محاسبة', 'marketing': 'تسويق',
    'management': 'إدارة', 'tech': 'تقنية', 'other': 'أخرى',
  };
  return c.lt(ar: ar[key] ?? key, en: key);
}

String _empTypeLabel(BuildContext c, String key) {
  const ar = {
    'full_time': 'دوام كامل', 'part_time': 'دوام جزئي',
    'contract': 'عقد', 'temporary': 'مؤقت',
  };
  return c.lt(ar: ar[key] ?? key, en: key);
}

String _statusLabel(BuildContext c, String key) {
  const ar = {'active': 'نشط', 'suspended': 'موقوف', 'terminated': 'منتهٍ'};
  return c.lt(ar: ar[key] ?? key, en: key);
}

class AdminEmployeesScreen extends ConsumerStatefulWidget {
  const AdminEmployeesScreen({super.key});

  @override
  ConsumerState<AdminEmployeesScreen> createState() => _AdminEmployeesScreenState();
}

class _AdminEmployeesScreenState extends ConsumerState<AdminEmployeesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  String _search = '';
  String? _department;

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
      final data = await ref.read(adminApiProvider).listEmployees(
            department: _department,
            search: _search,
          );
      final items = ((data['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر تحميل الموظفين.')
          : 'تعذّر تحميل الموظفين.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _EmployeeFormSheet(),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'إدارة الموظفين', en: 'Employees')),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(context.lt(ar: 'موظف جديد', en: 'New employee')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(MaslakiSpacing.md),
            child: TextField(
              onChanged: (v) => _search = v,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: context.lt(ar: 'ابحث بالاسم أو الهاتف', en: 'Search name/phone'),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: MaslakiSpacing.md),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(context.lt(ar: 'الكل', en: 'All')),
                    selected: _department == null,
                    onSelected: (_) {
                      setState(() => _department = null);
                      _load();
                    },
                  ),
                ),
                for (final d in _departments)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(deptLabel(context, d)),
                      selected: _department == d,
                      onSelected: (_) {
                        setState(() => _department = d);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(MaslakiSpacing.md),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? MaslakiEmptyState(
                        icon: Icons.badge_outlined,
                        title: context.lt(ar: 'لا يوجد موظفون', en: 'No employees'),
                        body: context.lt(
                          ar: 'أضف موظفاً جديداً من الزر بالأسفل.',
                          en: 'Add a new employee from the button below.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(MaslakiSpacing.md),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: MaslakiSpacing.sm),
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          return MaslakiCard(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('${e['full_name'] ?? '—'}'),
                              subtitle: Text(
                                '${deptLabel(context, '${e['department'] ?? ''}')} · '
                                '${_statusLabel(context, '${e['status'] ?? ''}')}',
                              ),
                              trailing: const Icon(Icons.chevron_left_rounded),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AdminEmployeeDetailScreen(
                                      userId: parseInt(e['user_id']),
                                    ),
                                  ),
                                );
                                _load();
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// نموذج إنشاء/تعديل موظف (مع قالب دور اختياري يُسند عند الحفظ).
class _EmployeeFormSheet extends ConsumerStatefulWidget {
  const _EmployeeFormSheet({this.existing});
  final Map<String, dynamic>? existing;

  @override
  ConsumerState<_EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends ConsumerState<_EmployeeFormSheet> {
  final _userId = TextEditingController();
  final _jobTitle = TextEditingController();
  final _salary = TextEditingController();
  String _department = 'customer_service';
  String _employmentType = 'full_time';
  String _status = 'active';
  String? _roleKey;
  List<String> _roleKeys = const [];
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _userId.text = '${e['user_id'] ?? ''}';
      _jobTitle.text = '${e['job_title'] ?? ''}';
      _salary.text = e['base_salary_iqd'] == null ? '' : '${e['base_salary_iqd']}';
      _department = '${e['department'] ?? 'customer_service'}';
      _employmentType = '${e['employment_type'] ?? 'full_time'}';
      _status = '${e['status'] ?? 'active'}';
      _roleKey = e['admin_role_key'] as String?;
    }
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    try {
      final cat = await ref.read(adminApiProvider).rbacCatalog();
      final templates = (cat['roleTemplates'] as List?) ?? const [];
      if (!mounted) return;
      setState(() => _roleKeys = templates
          .map((t) => '${(t as Map)['key']}')
          .where((k) => k.isNotEmpty)
          .toList());
    } catch (_) {/* roles optional */}
  }

  @override
  void dispose() {
    _userId.dispose();
    _jobTitle.dispose();
    _salary.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uid = int.tryParse(_userId.text.trim());
    if (uid == null || uid <= 0) {
      setState(() => _error = context.lt(ar: 'أدخل معرّف مستخدم صحيحاً.', en: 'Enter a valid user id.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'userId': uid,
      'department': _department,
      'employmentType': _employmentType,
      'status': _status,
      if (_jobTitle.text.trim().isNotEmpty) 'jobTitle': _jobTitle.text.trim(),
      if (_salary.text.trim().isNotEmpty) 'baseSalaryIqd': int.tryParse(_salary.text.trim()),
      if (_roleKey != null) 'adminRoleKey': _roleKey,
    };
    try {
      final api = ref.read(adminApiProvider);
      if (_isEdit) {
        await api.updateEmployee(uid, body);
      } else {
        await api.saveEmployee(body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر حفظ الموظف.')
          : 'تعذّر حفظ الموظف.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit
                  ? context.lt(ar: 'تعديل موظف', en: 'Edit employee')
                  : context.lt(ar: 'موظف جديد', en: 'New employee'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            TextField(
              controller: _userId,
              enabled: !_isEdit,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: context.lt(ar: 'معرّف المستخدم (app_user id)', en: 'User id'),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _department,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: context.lt(ar: 'القسم', en: 'Department'),
              ),
              items: [
                for (final d in _departments)
                  DropdownMenuItem(value: d, child: Text(deptLabel(context, d))),
              ],
              onChanged: (v) => setState(() => _department = v ?? _department),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _jobTitle,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: context.lt(ar: 'المسمى الوظيفي', en: 'Job title'),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _employmentType,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: context.lt(ar: 'نوع الدوام', en: 'Employment type'),
              ),
              items: [
                for (final t in _employmentTypes)
                  DropdownMenuItem(value: t, child: Text(_empTypeLabel(context, t))),
              ],
              onChanged: (v) => setState(() => _employmentType = v ?? _employmentType),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: context.lt(ar: 'الحالة', en: 'Status'),
              ),
              items: [
                for (final s in _statuses)
                  DropdownMenuItem(value: s, child: Text(_statusLabel(context, s))),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _salary,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: context.lt(ar: 'الراتب الأساسي (د.ع)', en: 'Base salary (IQD)'),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _roleKey,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: context.lt(ar: 'قالب الدور (صلاحيات)', en: 'Role template'),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(context.lt(ar: 'بلا دور', en: 'No role')),
                ),
                for (final r in _roleKeys)
                  DropdownMenuItem<String?>(value: r, child: Text(r)),
              ],
              onChanged: (v) => setState(() => _roleKey = v),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
              label: Text(context.lt(ar: 'حفظ', en: 'Save')),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminEmployeeDetailScreen extends ConsumerStatefulWidget {
  const AdminEmployeeDetailScreen({super.key, required this.userId});
  final int userId;

  @override
  ConsumerState<AdminEmployeeDetailScreen> createState() =>
      _AdminEmployeeDetailScreenState();
}

class _AdminEmployeeDetailScreenState
    extends ConsumerState<AdminEmployeeDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _employee = const {};
  List<Map<String, dynamic>> _salaryHistory = const [];

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
      final data = await ref.read(adminApiProvider).getEmployee(widget.userId);
      if (!mounted) return;
      setState(() {
        _employee = Map<String, dynamic>.from(data['employee'] as Map? ?? {});
        _salaryHistory = ((data['salaryHistory'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر تحميل الملف.')
          : 'تعذّر تحميل الملف.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EmployeeFormSheet(existing: _employee),
    );
    if (ok == true) _load();
  }

  Future<void> _updateSalary() async {
    final controller = TextEditingController();
    final reason = TextEditingController();
    final amount = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.lt(ar: 'تحديث الراتب', en: 'Update salary')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.lt(ar: 'الراتب الجديد (د.ع)', en: 'New salary (IQD)'),
              ),
            ),
            TextField(
              controller: reason,
              decoration: InputDecoration(labelText: context.lt(ar: 'السبب', en: 'Reason')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.lt(ar: 'إلغاء', en: 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: Text(context.lt(ar: 'حفظ', en: 'Save')),
          ),
        ],
      ),
    );
    if (amount == null || amount < 0) return;
    try {
      await ref.read(adminApiProvider).updateEmployeeSalary(
            widget.userId,
            baseSalaryIqd: amount,
            reason: reason.text.trim(),
          );
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is DioException
          ? mapDioError(e, fallback: 'تعذّر تحديث الراتب.')
          : 'تعذّر تحديث الراتب.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _employee;
    return Scaffold(
      appBar: AppBar(
        title: Text('${e['full_name'] ?? context.lt(ar: 'ملف الموظف', en: 'Employee')}'),
        actions: [
          if (!_loading)
            IconButton(onPressed: _edit, icon: const Icon(Icons.edit_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(MaslakiSpacing.md),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                MaslakiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(context, 'القسم', 'Department', deptLabel(context, '${e['department'] ?? ''}')),
                      _row(context, 'المسمى', 'Job', '${e['job_title'] ?? '—'}'),
                      _row(context, 'نوع الدوام', 'Type', _empTypeLabel(context, '${e['employment_type'] ?? ''}')),
                      _row(context, 'الحالة', 'Status', _statusLabel(context, '${e['status'] ?? ''}')),
                      _row(context, 'الهاتف', 'Phone', '${e['phone'] ?? '—'}'),
                      _row(context, 'قالب الدور', 'Role', '${e['admin_role_key'] ?? '—'}'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                MaslakiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${context.lt(ar: 'الراتب الحالي', en: 'Current salary')}: '
                              '${e['base_salary_iqd'] ?? '—'} د.ع',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _updateSalary,
                            icon: const Icon(Icons.payments_rounded, size: 18),
                            label: Text(context.lt(ar: 'تحديث', en: 'Update')),
                          ),
                        ],
                      ),
                      const Divider(),
                      for (final h in _salaryHistory)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${h['base_salary_iqd']} د.ع — ${h['effective_from'] ?? ''}'
                            '${h['reason'] != null ? ' (${h['reason']})' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminRbacManagementScreen()),
                  ),
                  icon: const Icon(Icons.admin_panel_settings_rounded),
                  label: Text(context.lt(
                    ar: 'إدارة صلاحيات هذا الموظف',
                    en: 'Manage this employee\'s permissions',
                  )),
                ),
              ],
            ),
    );
  }

  Widget _row(BuildContext c, String ar, String en, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(c.lt(ar: ar, en: en), style: Theme.of(c).textTheme.labelMedium)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
