import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminRbacManagementScreen extends ConsumerStatefulWidget {
  const AdminRbacManagementScreen({super.key});

  @override
  ConsumerState<AdminRbacManagementScreen> createState() =>
      _AdminRbacManagementScreenState();
}

class _AdminRbacManagementScreenState
    extends ConsumerState<AdminRbacManagementScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _roles = const [];
  List<String> _permissions = const [];
  List<Map<String, dynamic>> _changeLog = const [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    return List<dynamic>.from(raw as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(adminApiProvider);
      final results = await Future.wait<Map<String, dynamic>>([
        api.rbacCatalog(),
        api.rbacRoles(search: _searchCtrl.text.trim()),
        api.rbacChangeLog(limit: 80),
      ]);
      if (!mounted) return;
      setState(() {
        _permissions = List<dynamic>.from(
          results[0]['permissions'] as List? ?? const [],
        ).map((item) => '$item').toList(growable: false);
        _roles = _asMapList(results[1]['items']);
        _changeLog = _asMapList(results[2]['items']);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(error, fallback: 'تعذر تحميل إدارة الصلاحيات.');
      });
    }
  }

  Map<String, List<String>> _groupPermissions(Iterable<String> permissions) {
    final out = <String, List<String>>{};
    for (final permission in permissions) {
      final group = permission.split('.').first;
      out.putIfAbsent(group, () => <String>[]).add(permission);
    }
    return out;
  }

  Future<void> _openRoleDialog({Map<String, dynamic>? sourceRole}) async {
    final roleKeyCtrl = TextEditingController();
    final nameCtrl = TextEditingController(
      text: '${sourceRole?['display_name'] ?? ''}'.trim(),
    );
    final descriptionCtrl = TextEditingController(
      text: '${sourceRole?['description'] ?? ''}'.trim(),
    );
    final reasonCtrl = TextEditingController();
    final permissionSearchCtrl = TextEditingController();
    final selected = <String>{};
    var filter = '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final visiblePermissions = _permissions
                .where((permission) => permission.contains(filter))
                .toList(growable: false);
            final groups = _groupPermissions(visiblePermissions);
            return AlertDialog(
              title: Text(
                sourceRole == null ? 'إنشاء دور جديد' : 'نسخ دور مخصص',
              ),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: roleKeyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Role key',
                          helperText: 'مثال: taxi_monitor_l2',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم الدور',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: descriptionCtrl,
                        decoration: const InputDecoration(labelText: 'الوصف'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: reasonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'سبب التغيير',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: permissionSearchCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          labelText: 'بحث في الصلاحيات',
                        ),
                        onChanged: (value) {
                          setDialogState(() => filter = value.trim());
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                setDialogState(() {
                                  selected.addAll(visiblePermissions);
                                });
                              },
                              icon: const Icon(Icons.done_all_rounded),
                              label: const Text('تحديد الظاهر'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                setDialogState(() {
                                  selected.removeAll(visiblePermissions);
                                });
                              },
                              icon: const Icon(Icons.remove_done_rounded),
                              label: const Text('إلغاء الظاهر'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...groups.entries.map((entry) {
                        final groupSelected = entry.value
                            .where(selected.contains)
                            .length;
                        return ExpansionTile(
                          title: Text(entry.key),
                          subtitle: Text(
                            '$groupSelected / ${entry.value.length}',
                          ),
                          children: entry.value
                              .map((permission) {
                                return CheckboxListTile(
                                  value: selected.contains(permission),
                                  dense: true,
                                  title: Text(permission),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selected.add(permission);
                                      } else {
                                        selected.remove(permission);
                                      }
                                    });
                                  },
                                );
                              })
                              .toList(growable: false),
                        );
                      }),
                      if (selected.any(_isSensitivePermission))
                        const ListTile(
                          leading: Icon(Icons.warning_amber_rounded),
                          title: Text('يتضمن الدور صلاحيات حساسة'),
                          subtitle: Text(
                            'الخادم يرفض هذا التغيير ما لم يكن المنفذ سوبر أدمن.',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    try {
      final permissions = selected
          .map(
            (permissionKey) => {'permissionKey': permissionKey, 'scope': 'all'},
          )
          .toList(growable: false);
      final api = ref.read(adminApiProvider);
      if (sourceRole == null) {
        await api.createRbacRole(
          roleKey: roleKeyCtrl.text.trim(),
          displayName: nameCtrl.text.trim(),
          description: descriptionCtrl.text.trim(),
          permissions: permissions,
          reason: reasonCtrl.text.trim(),
        );
      } else {
        await api.copyRbacRole(
          sourceRoleKey: '${sourceRole['role_key']}',
          roleKey: roleKeyCtrl.text.trim(),
          displayName: nameCtrl.text.trim(),
          description: descriptionCtrl.text.trim(),
          reason: reasonCtrl.text.trim(),
        );
      }
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapAnyError(error, fallback: 'فشل حفظ الدور.'))),
      );
    }
  }

  bool _isSensitivePermission(String permission) {
    return const {
      'employees.permissions.manage',
      'accounts.delete_approve',
      'payroll.release',
      'payroll.approve',
      'taxi.rides.emergency_cancel',
    }.contains(permission);
  }

  Future<void> _archiveRole(Map<String, dynamic> role) async {
    try {
      await ref
          .read(adminApiProvider)
          .archiveRbacRole(roleKey: '${role['role_key']}', reason: 'archive');
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapAnyError(error, fallback: 'فشل أرشفة الدور.')),
        ),
      );
    }
  }

  Widget _rolesTab() {
    if (_roles.isEmpty) {
      return const Center(child: Text('لا توجد أدوار مخصصة.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _roles.length,
        itemBuilder: (context, index) {
          final role = _roles[index];
          final archived = role['is_archived'] == true;
          return Card(
            child: ListTile(
              leading: Icon(
                archived ? Icons.archive_outlined : Icons.admin_panel_settings,
              ),
              title: Text('${role['display_name'] ?? role['role_key']}'),
              subtitle: Text(
                '${role['role_key']} • موظفون: ${role['employee_count'] ?? 0} • صلاحيات: ${role['permission_count'] ?? 0}',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'نسخ',
                    onPressed: () => _openRoleDialog(sourceRole: role),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton(
                    tooltip: 'أرشفة',
                    onPressed: archived ? null : () => _archiveRole(role),
                    icon: const Icon(Icons.archive_outlined),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _permissionsTab() {
    final groups = _groupPermissions(_permissions);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: groups.entries
          .map((entry) {
            return Card(
              child: ExpansionTile(
                title: Text(entry.key),
                subtitle: Text('${entry.value.length} صلاحية'),
                children: entry.value
                    .map(
                      (permission) => ListTile(
                        dense: true,
                        leading: Icon(
                          _isSensitivePermission(permission)
                              ? Icons.lock_rounded
                              : Icons.key_rounded,
                        ),
                        title: Text(permission),
                      ),
                    )
                    .toList(growable: false),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _changeLogTab() {
    if (_changeLog.isEmpty) {
      return const Center(child: Text('لا يوجد سجل تغييرات.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _changeLog.length,
        itemBuilder: (context, index) {
          final item = _changeLog[index];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text('${item['action'] ?? item['action_key'] ?? ''}'),
              subtitle: Text(
                'actor=${item['actor_user_id'] ?? '-'} target=${item['target_user_id'] ?? item['target_role_key'] ?? '-'}\n${item['reason'] ?? ''}',
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الأدوار والصلاحيات'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.badge_outlined), text: 'الأدوار'),
              Tab(icon: Icon(Icons.key_rounded), text: 'الصلاحيات'),
              Tab(icon: Icon(Icons.history_rounded), text: 'السجل'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null,
          onPressed: _loading ? null : () => _openRoleDialog(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('دور جديد'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        labelText: 'بحث في الأدوار',
                        suffixIcon: IconButton(
                          onPressed: _load,
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _rolesTab(),
                        _permissionsTab(),
                        _changeLogTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
