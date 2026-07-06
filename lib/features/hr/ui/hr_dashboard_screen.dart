// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../../core/widgets/desktop_dashboard_frame.dart';
import '../../../core/workspaces/workspace_permissions.dart';
import '../../auth/state/auth_controller.dart';
import '../../jobs/ui/jobs_hub_screen.dart';
import '../../notifications/ui/notifications_bell.dart';
import 'hr_employee_portal_screen.dart';
import '../../settings/ui/pages/settings_account_screen.dart';
import '../../settings/ui/pages/settings_support_screen.dart';
import '../state/hr_controller.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

enum _HrTab {
  dashboard,
  employees,
  attendance,
  leaveRequests,
  advanceRequests,
  salaryActions,
  payroll,
  archive,
  profile,
}

class HrDashboardScreen extends ConsumerStatefulWidget {
  const HrDashboardScreen({super.key});

  @override
  ConsumerState<HrDashboardScreen> createState() => _HrDashboardScreenState();
}

class _HrDashboardScreenState extends ConsumerState<HrDashboardScreen> {
  _HrTab _tab = _HrTab.dashboard;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(hrControllerProvider.notifier).bootstrap());
  }

  void _setTab(_HrTab tab) {
    if (!mounted) return;
    setState(() => _tab = tab);
  }

  List<AppUserDrawerItem> _buildDrawerItems() {
    return [
      AppUserDrawerItem(
        icon: Icons.dashboard_outlined,
        label: context.l10n.hrDashboardHrDashboard,
        onTap: (_) async => _setTab(_HrTab.dashboard),
      ),
      AppUserDrawerItem(
        icon: Icons.groups_outlined,
        label: context.l10n.hrDashboardEmployeeDirectory,
        onTap: (_) async => _setTab(_HrTab.employees),
      ),
      AppUserDrawerItem(
        icon: Icons.fact_check_outlined,
        label: context.l10n.hrDashboardAttendance,
        onTap: (_) async => _setTab(_HrTab.attendance),
      ),
      AppUserDrawerItem(
        icon: Icons.event_note_outlined,
        label: context.l10n.hrDashboardLeaveRequests,
        onTap: (_) async => _setTab(_HrTab.leaveRequests),
      ),
      AppUserDrawerItem(
        icon: Icons.request_page_outlined,
        label: context.l10n.hrDashboardAdvanceRequests,
        onTap: (_) async => _setTab(_HrTab.advanceRequests),
      ),
      AppUserDrawerItem(
        icon: Icons.attach_money_rounded,
        label: context.l10n.hrDashboardCompensationActions,
        onTap: (_) async => _setTab(_HrTab.salaryActions),
      ),
      AppUserDrawerItem(
        icon: Icons.payments_outlined,
        label: context.l10n.hrDashboardPayroll,
        onTap: (_) async => _setTab(_HrTab.payroll),
      ),
      AppUserDrawerItem(
        icon: Icons.archive_outlined,
        label: context.l10n.commonArchive,
        onTap: (_) async => _setTab(_HrTab.archive),
      ),
      AppUserDrawerItem(
        icon: Icons.work_outline_rounded,
        label: context.l10n.hrDashboardJobsManagement,
        onTap: (_) async {
          Navigator.of(context).pop();
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const JobsHubScreen(startInManageMode: true),
            ),
          );
        },
      ),
      AppUserDrawerItem(
        icon: Icons.person_outline,
        label: context.l10n.hrDashboardProfile,
        onTap: (_) async => _setTab(_HrTab.profile),
      ),
      AppUserDrawerItem(
        icon: Icons.badge_outlined,
        label: context.l10n.hrDashboardEmployeePortal,
        onTap: (_) async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HrEmployeePortalScreen()),
          );
        },
      ),
      AppUserDrawerItem(
        icon: Icons.refresh_rounded,
        label: context.l10n.commonRefresh,
        onTap: (_) async => ref.read(hrControllerProvider.notifier).bootstrap(),
      ),
    ];
  }

  Map<String, dynamic>? _findEmployeeByUserId(
    List<Map<String, dynamic>> employees,
    int userId,
  ) {
    for (final employee in employees) {
      final id = int.tryParse('${employee['userId'] ?? ''}');
      if (id == userId) return employee;
    }
    return null;
  }

  Map<String, dynamic> _employeeStubFromRow(Map<String, dynamic> row) {
    return {
      'userId':
          row['employeeUserId'] ?? row['employee_user_id'] ?? row['userId'],
      'fullName':
          row['employeeFullName'] ??
          row['employee_full_name'] ??
          row['fullName'] ??
          context.l10n.hrDashboardEmployee,
      'phone':
          row['employeePhone'] ?? row['employee_phone'] ?? row['phone'] ?? '',
    };
  }

  Map<String, dynamic> _employeeForRow(
    HrState state,
    Map<String, dynamic> row,
  ) {
    final userId = int.tryParse(
      '${row['employeeUserId'] ?? row['employee_user_id'] ?? row['userId'] ?? ''}',
    );
    if (userId != null && userId > 0) {
      final full = _findEmployeeByUserId(state.employees, userId);
      if (full != null) return full;
    }
    return _employeeStubFromRow(row);
  }

  List<String> _merchantPermissionCatalog() {
    return workspacePermissionCatalog(WorkspacePermissionKind.merchant);
  }

  List<String> _permissionListFromProfile(Map<String, dynamic> profile) {
    final raw = profile['permissions'] ?? profile['permissions_json'];
    if (raw is List) {
      return raw.map((value) => '$value').where((value) => value.trim().isNotEmpty).toList(growable: false);
    }
    return const <String>[];
  }

  Widget _permissionChips(
    BuildContext context,
    List<String> permissions, {
    bool dense = true,
  }) {
    if (permissions.isEmpty) {
      return Text(
        'لا توجد صلاحيات محددة بعد / No permissions selected',
        style: TextStyle(color: Theme.of(context).hintColor),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: permissions
          .map(
            (permission) => Chip(
              visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
              label: Text(
                workspacePermissionLabelFor(
                  context,
                  permission,
                  kind: WorkspacePermissionKind.merchant,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _permissionSelector(
    BuildContext context, {
    required Set<String> selected,
    required void Function(String permission, bool enabled) onChanged,
  }) {
    final catalog = _merchantPermissionCatalog();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: catalog
          .map(
            (permission) => FilterChip(
              selected: selected.contains(permission),
              label: Text(
                workspacePermissionLabelFor(
                  context,
                  permission,
                  kind: WorkspacePermissionKind.merchant,
                ),
              ),
              onSelected: (enabled) => onChanged(permission, enabled),
            ),
          )
          .toList(growable: false),
    );
  }

  String _title(BuildContext context) {
    switch (_tab) {
      case _HrTab.dashboard:
        return context.l10n.hrDashboardHrDashboard;
      case _HrTab.employees:
        return context.l10n.hrDashboardEmployeeDirectory;
      case _HrTab.attendance:
        return context.l10n.hrDashboardAttendance;
      case _HrTab.leaveRequests:
        return context.l10n.hrDashboardLeaveRequests;
      case _HrTab.advanceRequests:
        return context.l10n.hrDashboardAdvanceRequests;
      case _HrTab.salaryActions:
        return context.l10n.hrDashboardCompensationActions;
      case _HrTab.payroll:
        return context.l10n.hrDashboardPayroll;
      case _HrTab.archive:
        return context.l10n.commonArchive;
      case _HrTab.profile:
        return context.l10n.hrDashboardProfile;
    }
  }

  Future<void> _openPayrollBuilder() async {
    final yearCtrl = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    final monthCtrl = TextEditingController(
      text: DateTime.now().month.toString(),
    );
    final noteCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.hrDashboardBuildPayrollBatch),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: yearCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.l10n.commonYear),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: monthCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.l10n.commonMonth),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.hrDashboardSummaryNoteOptional,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final year = int.tryParse(yearCtrl.text.trim());
              final month = int.tryParse(monthCtrl.text.trim());
              if (year == null || month == null) return;
              await ref
                  .read(hrControllerProvider.notifier)
                  .buildPayroll(
                    periodYear: year,
                    periodMonth: month,
                    summaryNote: noteCtrl.text.trim().isEmpty
                        ? null
                        : noteCtrl.text.trim(),
                  );
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(context.l10n.hrDashboardBuild),
          ),
        ],
      ),
    );
  }

  Future<void> _openEmployeeEditor(Map<String, dynamic> employee) async {
    await _openEmployeeFormDialog(employee: employee, inviteMode: false);
  }

  Future<void> _openEmployeeInviteDialog() async {
    await _openEmployeeFormDialog(inviteMode: true);
  }

  Future<void> _openEmployeeFormDialog({
    Map<String, dynamic>? employee,
    required bool inviteMode,
  }) async {
    final profile = employee?['profile'] is Map
        ? Map<String, dynamic>.from(employee!['profile'] as Map)
        : const <String, dynamic>{};
    final userId = inviteMode
        ? null
        : int.tryParse('${employee?['userId'] ?? ''}');
    if (!inviteMode && (userId == null || userId <= 0)) return;

    final fullNameCtrl = TextEditingController(
      text: inviteMode
          ? ''
          : '${employee?['fullName'] ?? context.l10n.hrDashboardEmployee}',
    );
    final phoneCtrl = TextEditingController(
      text: inviteMode ? '' : '${employee?['phone'] ?? ''}',
    );
    final pinCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController(
      text: '${profile['displayName'] ?? employee?['displayName'] ?? ''}',
    );
    final contactEmailCtrl = TextEditingController(
      text: '${profile['contactEmail'] ?? employee?['contactEmail'] ?? ''}',
    );
    final roleCtrl = TextEditingController(
      text: '${profile['roleTag'] ?? employee?['role'] ?? 'staff'}',
    );
    final salaryCtrl = TextEditingController(
      text: '${profile['baseSalary'] ?? 0}',
    );
    final daysCtrl = TextEditingController(
      text: '${profile['workDaysPerWeek'] ?? 6}',
    );
    final shiftStartCtrl = TextEditingController(
      text: '${profile['shiftStartTime'] ?? ''}',
    );
    final shiftEndCtrl = TextEditingController(
      text: '${profile['shiftEndTime'] ?? ''}',
    );
    final notesCtrl = TextEditingController(text: '${profile['notes'] ?? ''}');
    final reasonCtrl = TextEditingController();
    final selectedPermissions = <String>{
      ..._permissionListFromProfile(profile),
    };
    final bool initialActive = profile['isActive'] != false;
    var isActive = initialActive;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            inviteMode
                ? 'دعوة موظف جديد / Invite employee'
                : '${context.l10n.hrDashboardUpdate} ${employee?['fullName'] ?? context.l10n.hrDashboardEmployee}',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dialogError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        '$dialogError',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (inviteMode) ...[
                    TextField(
                      controller: fullNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'الاسم الكامل / Full name',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'الهاتف / Phone',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: pinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'PIN / رمز الدخول',
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الاسم المعروض / Display name',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: contactEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني / Contact email',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: roleCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.hrDashboardRoleTag,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: salaryCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.l10n.hrDashboardBaseSalary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: daysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.l10n.hrDashboardWorkDaysWeek,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: shiftStartCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.hrDashboardShiftStartHhMm,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: shiftEndCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.hrDashboardShiftEndHhMm,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات / Notes',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'سبب التعديل / Reason',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'الصلاحيات / Permissions',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _permissionSelector(
                    context,
                    selected: selectedPermissions,
                    onChanged: (permission, enabled) {
                      setDialogState(() {
                        if (enabled) {
                          selectedPermissions.add(permission);
                        } else {
                          selectedPermissions.remove(permission);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.socialProfileManageActive),
                    value: isActive,
                    onChanged: (value) => setDialogState(() => isActive = value),
                  ),
                  if (selectedPermissions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _permissionChips(
                      context,
                      selectedPermissions.toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.commonCancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final salary = num.tryParse(salaryCtrl.text.trim()) ?? 0;
                final days = int.tryParse(daysCtrl.text.trim()) ?? 6;
                final roleTag = roleCtrl.text.trim().isEmpty
                    ? 'staff'
                    : roleCtrl.text.trim();
                if (inviteMode) {
                  if (fullNameCtrl.text.trim().isEmpty) {
                    setDialogState(() => dialogError = 'الاسم الكامل مطلوب.');
                    return;
                  }
                  if (phoneCtrl.text.trim().isEmpty) {
                    setDialogState(() => dialogError = 'رقم الهاتف مطلوب.');
                    return;
                  }
                  if (pinCtrl.text.trim().isEmpty) {
                    setDialogState(() => dialogError = 'رمز PIN مطلوب.');
                    return;
                  }
                  await ref.read(hrControllerProvider.notifier).inviteEmployee(
                        fullName: fullNameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        pin: pinCtrl.text.trim(),
                        roleTag: roleTag,
                        baseSalary: salary,
                        workDaysPerWeek: days,
                        displayName: displayNameCtrl.text.trim().isEmpty
                            ? null
                            : displayNameCtrl.text.trim(),
                        contactEmail: contactEmailCtrl.text.trim().isEmpty
                            ? null
                            : contactEmailCtrl.text.trim(),
                        shiftStartTime: shiftStartCtrl.text.trim().isEmpty
                            ? null
                            : shiftStartCtrl.text.trim(),
                        shiftEndTime: shiftEndCtrl.text.trim().isEmpty
                            ? null
                            : shiftEndCtrl.text.trim(),
                        isActive: isActive,
                        notes: notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                        permissions:
                            selectedPermissions.toList(growable: false),
                        reason: reasonCtrl.text.trim().isEmpty
                            ? null
                            : reasonCtrl.text.trim(),
                      );
                } else {
                  await ref
                      .read(hrControllerProvider.notifier)
                      .upsertEmployeeProfile(
                        employeeUserId: userId!,
                        roleTag: roleTag,
                        baseSalary: salary,
                        workDaysPerWeek: days,
                        displayName: displayNameCtrl.text.trim().isEmpty
                            ? null
                            : displayNameCtrl.text.trim(),
                        contactEmail: contactEmailCtrl.text.trim().isEmpty
                            ? null
                            : contactEmailCtrl.text.trim(),
                        shiftStartTime: shiftStartCtrl.text.trim().isEmpty
                            ? null
                            : shiftStartCtrl.text.trim(),
                        shiftEndTime: shiftEndCtrl.text.trim().isEmpty
                            ? null
                            : shiftEndCtrl.text.trim(),
                        isActive: isActive,
                        notes: notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                        permissions:
                            selectedPermissions.toList(growable: false),
                        reason: reasonCtrl.text.trim().isEmpty
                            ? null
                            : reasonCtrl.text.trim(),
                      );
                }
                final latest = ref.read(hrControllerProvider);
                if (latest.error != null) {
                  setDialogState(() => dialogError = latest.error);
                  return;
                }
                if (mounted) Navigator.of(context).pop();
              },
              child: Text(inviteMode ? 'دعوة' : context.l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttendanceDialog(Map<String, dynamic> employee) async {
    final userId = int.tryParse('${employee['userId'] ?? ''}');
    if (userId == null || userId <= 0) return;
    final dateCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().split('T').first,
    );
    final statusCtrl = TextEditingController(text: 'present');
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          '${context.l10n.hrDashboardAttendance} ${employee['fullName'] ?? context.l10n.hrDashboardEmployee}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dateCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.hrDashboardDateYyyyMmDd,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: statusCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.hrDashboardAttendanceStatusHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(hrControllerProvider.notifier)
                  .markAttendance(
                    employeeUserId: userId,
                    attendanceDate: dateCtrl.text.trim(),
                    status: statusCtrl.text.trim().isEmpty
                        ? 'present'
                        : statusCtrl.text.trim(),
                  );
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(context.l10n.commonSave),
          ),
        ],
      ),
    );
  }

  Future<void> _openLeaveRequestDialog(Map<String, dynamic> employee) async {
    final userId = int.tryParse('${employee['userId'] ?? ''}');
    if (userId == null || userId <= 0) return;

    final fromCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().split('T').first,
    );
    final toCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().split('T').first,
    );
    final daysCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    String leaveType = 'annual';
    String payPolicy = 'paid';

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            '${context.l10n.hrDashboardLeave} ${employee['fullName'] ?? context.l10n.hrDashboardEmployee}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: leaveType,
                  decoration: InputDecoration(
                    labelText: context.l10n.hrDashboardLeaveType,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'annual',
                      child: Text(context.l10n.hrDashboardAnnual),
                    ),
                    DropdownMenuItem(
                      value: 'sick',
                      child: Text(context.l10n.hrDashboardSick),
                    ),
                    DropdownMenuItem(
                      value: 'emergency',
                      child: Text(context.l10n.hrDashboardEmergency),
                    ),
                    DropdownMenuItem(
                      value: 'maternity',
                      child: Text(context.l10n.hrDashboardMaternity),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text(
                        context.l10n.ownerFinancialRequestPaymentMethodOther,
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => leaveType = value ?? 'annual'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: payPolicy,
                  decoration: InputDecoration(
                    labelText: context.l10n.hrDashboardPayPolicy,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'paid',
                      child: Text(context.l10n.hrDashboardPaid),
                    ),
                    DropdownMenuItem(
                      value: 'half_paid',
                      child: Text(context.l10n.hrDashboardHalfPaid),
                    ),
                    DropdownMenuItem(
                      value: 'unpaid',
                      child: Text(context.l10n.hrDashboardUnpaid),
                    ),
                    DropdownMenuItem(
                      value: 'sick_paid',
                      child: Text(context.l10n.hrDashboardSickPaid),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => payPolicy = value ?? 'paid'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: fromCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.hrDashboardFromYyyyMmDd,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: toCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.hrDashboardToYyyyMmDd,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: daysCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.l10n.hrDashboardDaysCount,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.hrDashboardReasonOptional,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.commonCancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final days = num.tryParse(daysCtrl.text.trim()) ?? 0;
                await ref
                    .read(hrControllerProvider.notifier)
                    .createLeaveRequest(
                      employeeUserId: userId,
                      leaveType: leaveType,
                      payPolicy: payPolicy,
                      dateFrom: fromCtrl.text.trim(),
                      dateTo: toCtrl.text.trim(),
                      daysCount: days,
                      reason: reasonCtrl.text.trim().isEmpty
                          ? null
                          : reasonCtrl.text.trim(),
                    );
                if (mounted) Navigator.of(context).pop();
              },
              child: Text(context.l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSalaryActionDialog(Map<String, dynamic> employee) async {
    final userId = int.tryParse('${employee['userId'] ?? ''}');
    if (userId == null || userId <= 0) return;

    final now = DateTime.now();
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String actionType = 'bonus';
    final yearCtrl = TextEditingController(text: '${now.year}');
    final monthCtrl = TextEditingController(text: '${now.month}');

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            '${context.l10n.hrDashboardCompensation} ${employee['fullName'] ?? context.l10n.hrDashboardEmployee}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: actionType,
                  decoration: InputDecoration(
                    labelText: context.l10n.hrDashboardActionType,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'bonus',
                      child: Text(context.l10n.hrDashboardBonus),
                    ),
                    DropdownMenuItem(
                      value: 'allowance',
                      child: Text(context.l10n.hrDashboardAllowance),
                    ),
                    DropdownMenuItem(
                      value: 'deduction',
                      child: Text(context.l10n.hrDashboardDeduction),
                    ),
                    DropdownMenuItem(
                      value: 'advance',
                      child: Text(context.l10n.hrDashboardAdvance),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => actionType = value ?? 'bonus'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.l10n.adminFinancialMerchantHeaderAmount,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: yearCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.l10n.commonYear,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: monthCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.l10n.commonMonth,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.adminCompetitionsDescription,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.commonCancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = num.tryParse(amountCtrl.text.trim()) ?? 0;
                final year = int.tryParse(yearCtrl.text.trim()) ?? now.year;
                final month = int.tryParse(monthCtrl.text.trim()) ?? now.month;
                await ref
                    .read(hrControllerProvider.notifier)
                    .createSalaryAction(
                      employeeUserId: userId,
                      actionType: actionType,
                      amount: amount,
                      effectiveYear: year,
                      effectiveMonth: month,
                      description: descCtrl.text.trim().isEmpty
                          ? null
                          : descCtrl.text.trim(),
                    );
                if (mounted) Navigator.of(context).pop();
              },
              child: Text(context.l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEmployeeActionsSheet(Map<String, dynamic> employee) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(
                  '${employee['fullName'] ?? context.l10n.hrDashboardEmployee}',
                ),
                subtitle: Text('${employee['phone'] ?? '-'}'),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openEmployeeEditor(employee);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(context.l10n.commonEdit),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openAttendanceDialog(employee);
                    },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(context.l10n.hrDashboardAttendance),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openLeaveRequestDialog(employee);
                    },
                    icon: const Icon(Icons.event_note_outlined),
                    label: Text(context.l10n.hrDashboardLeave),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openSalaryActionDialog(employee);
                    },
                    icon: const Icon(Icons.attach_money_rounded),
                    label: Text(context.l10n.hrDashboardSalaryAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openArchivePeriodPicker() async {
    final now = DateTime.now();
    final yearCtrl = TextEditingController(text: '${now.year}');
    final monthCtrl = TextEditingController(text: '${now.month}');
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.hrDashboardLoadArchivePeriod),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: yearCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.l10n.commonYear),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: monthCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.commonMonth,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final year = int.tryParse(yearCtrl.text.trim()) ?? now.year;
              final month = int.tryParse(monthCtrl.text.trim()) ?? now.month;
              await ref
                  .read(hrControllerProvider.notifier)
                  .loadAttendanceArchive(periodYear: year, periodMonth: month);
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(context.l10n.hrDashboardLoad),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHero({
    required int totalEmployees,
    required int presentToday,
    required int pendingLeaveCount,
    required int openPayrollBatches,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.26),
            scheme.tertiary.withValues(alpha: 0.20),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.hrDashboardHrCommandCenter,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.hrDashboardManageDayFromOneWorkspace,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.86),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroStatPill(
                icon: Icons.groups_outlined,
                label: context.l10n.hrDashboardEmployees,
                value: '$totalEmployees',
              ),
              _HeroStatPill(
                icon: Icons.check_circle_outline,
                label: context.l10n.hrDashboardPresentToday,
                value: '$presentToday',
              ),
              _HeroStatPill(
                icon: Icons.event_note_outlined,
                label: context.l10n.hrDashboardPendingLeave,
                value: '$pendingLeaveCount',
              ),
              _HeroStatPill(
                icon: Icons.payments_outlined,
                label: context.l10n.hrDashboardOpenPayroll,
                value: '$openPayrollBatches',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DesktopQuickActionButton(
                icon: Icons.auto_fix_high_outlined,
                label: context.l10n.hrDashboardBuildPayroll,
                onPressed: _openPayrollBuilder,
              ),
              DesktopQuickActionButton(
                icon: Icons.work_outline_rounded,
                label: context.l10n.hrDashboardJobs,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const JobsHubScreen(startInManageMode: true),
                    ),
                  );
                },
              ),
              DesktopQuickActionButton(
                icon: Icons.badge_outlined,
                label: context.l10n.hrDashboardEmployeePortal,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HrEmployeePortalScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hrControllerProvider);
    final auth = ref.watch(authControllerProvider);

    ref.listen<HrState>(hrControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      if (next.successMessage != null &&
          next.successMessage != prev?.successMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.successMessage!)));
      }
    });

    final stats = state.stats;
    final merchantName = '${state.merchant?['name'] ?? '-'}';
    final totalEmployees = int.tryParse('${stats['totalEmployees'] ?? 0}') ?? 0;
    final presentToday = int.tryParse('${stats['presentToday'] ?? 0}') ?? 0;
    final openPayrollBatches =
        int.tryParse('${stats['openPayrollBatches'] ?? 0}') ?? 0;
    final pendingLeaveCount = state.leaveRequests
        .where(
          (row) => '${row['status'] ?? ''}'.trim().toLowerCase() == 'pending',
        )
        .length;
    final activeActionCount = state.salaryActions
        .where(
          (row) => '${row['status'] ?? ''}'.trim().toLowerCase() == 'active',
        )
        .length;
    final pendingAdvanceCount = state.advanceRequests
        .where(
          (row) => '${row['status'] ?? ''}'.trim().toLowerCase() == 'pending',
        )
        .length;
    final useDesktop = DesktopDashboardFrame.shouldUse(context);
    final drawerItems = _buildDrawerItems();

    return Scaffold(
      drawer: AppUserDrawer(
        title: _title(context),
        subtitle: merchantName,
        items: drawerItems,
        embedded: useDesktop,
      ),
      appBar: AppBar(
        title: Text(_title(context)),
        actions: [
          if (useDesktop)
            IconButton(
              tooltip: context.l10n.hrDashboardEmployeePortal,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HrEmployeePortalScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.badge_outlined),
            ),
          if (useDesktop)
            IconButton(
              tooltip: context.l10n.hrDashboardJobsManagement,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const JobsHubScreen(startInManageMode: true),
                  ),
                );
              },
              icon: const Icon(Icons.work_outline_rounded),
            ),
          const NotificationsBellButton(),
        ],
      ),
      body: (() {
        final baseBody = state.loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(hrControllerProvider.notifier).bootstrap(),
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _HrQuickTabs(activeTab: _tab, onSelectTab: _setTab),
                    const SizedBox(height: 10),
                    if (useDesktop && _tab == _HrTab.dashboard) ...[
                      _buildDesktopHero(
                        totalEmployees: totalEmployees,
                        presentToday: presentToday,
                        pendingLeaveCount: pendingLeaveCount,
                        openPayrollBatches: openPayrollBatches,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_tab == _HrTab.dashboard) ...[
                      _MetricCard(
                        title: context.l10n.hrDashboardTotalEmployees,
                        value: '$totalEmployees',
                        icon: Icons.groups_2_outlined,
                        onTap: () => _setTab(_HrTab.employees),
                      ),
                      const SizedBox(height: 8),
                      _MetricCard(
                        title: context.l10n.hrDashboardPresentToday,
                        value: '$presentToday',
                        icon: Icons.check_circle_outline,
                        onTap: () => _setTab(_HrTab.attendance),
                      ),
                      const SizedBox(height: 8),
                      _MetricCard(
                        title: context.l10n.hrDashboardOpenPayrollBatches,
                        value: '$openPayrollBatches',
                        icon: Icons.payments_outlined,
                        onTap: () => _setTab(_HrTab.payroll),
                      ),
                      const SizedBox(height: 8),
                      _MetricCard(
                        title: context.l10n.hrDashboardPendingLeaveRequests,
                        value: '$pendingLeaveCount',
                        icon: Icons.event_note_outlined,
                        onTap: () => _setTab(_HrTab.leaveRequests),
                      ),
                      const SizedBox(height: 8),
                      _MetricCard(
                        title: context.l10n.hrDashboardActiveSalaryActions,
                        value: '$activeActionCount',
                        icon: Icons.attach_money_rounded,
                        onTap: () => _setTab(_HrTab.salaryActions),
                      ),
                      const SizedBox(height: 8),
                      _MetricCard(
                        title: context.l10n.hrDashboardPendingAdvanceRequests,
                        value: '$pendingAdvanceCount',
                        icon: Icons.request_page_outlined,
                        onTap: () => _setTab(_HrTab.advanceRequests),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: state.saving ? null : _openPayrollBuilder,
                        icon: const Icon(Icons.auto_fix_high_outlined),
                        label: Text(context.l10n.hrDashboardBuildPayrollBatch),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const JobsHubScreen(startInManageMode: true),
                          ),
                        ),
                        icon: const Icon(Icons.work_outline_rounded),
                        label: Text(context.l10n.hrDashboardOpenJobsManagement),
                      ),
                    ],
                    if (_tab == _HrTab.employees) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.hrDashboardEmployeeDirectory,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: state.saving
                                ? null
                                : _openEmployeeInviteDialog,
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('دعوة موظف'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (state.employees.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(context.l10n.hrDashboardNoEmployeesFound),
                        )
                      else
                        ...state.employees.map((employee) {
                          final profile = employee['profile'] is Map
                              ? Map<String, dynamic>.from(
                                  employee['profile'] as Map,
                                )
                              : const <String, dynamic>{};
                          final salary =
                              num.tryParse('${profile['baseSalary'] ?? 0}') ??
                              0;
                          final permissions = _permissionListFromProfile(
                            profile,
                          );
                          final isActive = profile['isActive'] != false;
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _openEmployeeEditor(employee),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${employee['fullName'] ?? '-'}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            color: isActive
                                                ? Colors.green.withValues(
                                                    alpha: 0.12,
                                                  )
                                                : Colors.orange.withValues(
                                                    alpha: 0.12,
                                                  ),
                                          ),
                                          child: Text(
                                            isActive
                                                ? 'نشط / Active'
                                                : 'موقوف / Inactive',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text('${employee['phone'] ?? ''}'),
                                    if ('${profile['displayName'] ?? ''}'
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '${context.l10n.commonName}: ${profile['displayName']}',
                                      ),
                                    ],
                                    if ('${profile['contactEmail'] ?? ''}'
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Email: ${profile['contactEmail']}',
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      '${context.l10n.hrDashboardRole}: ${profile['roleTag'] ?? employee['role'] ?? '-'}',
                                    ),
                                    Text(
                                      '${context.l10n.commonSalary}: ${formatIqd(salary)}',
                                    ),
                                    const SizedBox(height: 10),
                                    if (permissions.isNotEmpty) ...[
                                      _permissionChips(context, permissions),
                                      const SizedBox(height: 10),
                                    ],
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        FilledButton.tonalIcon(
                                          onPressed: () =>
                                              _openEmployeeEditor(employee),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: Text(context.l10n.commonEdit),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _openAttendanceDialog(employee),
                                          icon: const Icon(
                                            Icons.fact_check_outlined,
                                          ),
                                          label: Text(
                                            context.l10n.hrDashboardAttendance,
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _openLeaveRequestDialog(employee),
                                          icon: const Icon(
                                            Icons.event_note_outlined,
                                          ),
                                          label: Text(
                                            context.l10n.hrDashboardLeave,
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _openSalaryActionDialog(employee),
                                          icon: const Icon(
                                            Icons.attach_money_rounded,
                                          ),
                                          label: Text(
                                            context.l10n.commonSalary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 16),
                      Text(
                        'سجل النشاط / Activity log',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (state.employeeActivityLogs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('لا يوجد سجل نشاط بعد.'),
                        )
                      else
                        ...state.employeeActivityLogs.take(12).map((row) {
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.history_rounded),
                              title: Text(
                                '${row['employeeFullName'] ?? '-'} • ${row['actionKey'] ?? '-'}',
                              ),
                              subtitle: Text(
                                [
                                  if ('${row['actorFullName'] ?? ''}'
                                      .trim()
                                      .isNotEmpty)
                                    'By: ${row['actorFullName']}',
                                  if ('${row['reason'] ?? ''}'
                                      .trim()
                                      .isNotEmpty)
                                    'Reason: ${row['reason']}',
                                  if ('${row['createdAt'] ?? ''}'
                                      .trim()
                                      .isNotEmpty)
                                    '${row['createdAt']}',
                                ].join('\n'),
                              ),
                              isThreeLine: true,
                            ),
                          );
                        }),
                    ],
                    if (_tab == _HrTab.attendance) ...[
                      if (state.attendance.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            context.l10n.hrDashboardNoAttendanceLogsYet,
                          ),
                        )
                      else
                        ...state.attendance.map((row) {
                          final employee = _employeeForRow(state, row);
                          return Card(
                            child: ListTile(
                              onTap: () => _openAttendanceDialog(employee),
                              leading: const Icon(Icons.access_time_outlined),
                              title: Text('${row['employeeFullName'] ?? '-'}'),
                              subtitle: Text(
                                '${row['attendanceDate'] ?? ''} | '
                                '${context.l10n.companyPromotionsCampaignStatus}: ${row['status'] ?? ''}\n'
                                '${context.l10n.hrDashboardIn}: ${row['checkInAt'] ?? '-'} | ${context.l10n.hrDashboardOut}: ${row['checkOutAt'] ?? '-'}',
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                tooltip: context.l10n.hrDashboardEditAttendance,
                                onPressed: () =>
                                    _openAttendanceDialog(employee),
                                icon: const Icon(Icons.edit_calendar_outlined),
                              ),
                            ),
                          );
                        }),
                    ],
                    if (_tab == _HrTab.leaveRequests) ...[
                      if (state.leaveRequests.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            context.l10n.hrDashboardNoLeaveRequestsYet,
                          ),
                        )
                      else
                        ...state.leaveRequests.map((row) {
                          final leaveId =
                              int.tryParse('${row['id'] ?? ''}') ?? 0;
                          final employee = _employeeForRow(state, row);
                          final status = '${row['status'] ?? 'pending'}'
                              .trim()
                              .toLowerCase();
                          final canDecide = leaveId > 0 && status == 'pending';
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${row['employeeFullName'] ?? '-'}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: context
                                            .l10n
                                            .hrDashboardEmployeeActions,
                                        onPressed: () =>
                                            _openEmployeeActionsSheet(employee),
                                        icon: const Icon(
                                          Icons.manage_accounts_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${row['leaveType'] ?? '-'} | ${row['payPolicy'] ?? '-'} | '
                                    '${row['dateFrom'] ?? ''} -> ${row['dateTo'] ?? ''}',
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${context.l10n.hrDashboardDays}: ${row['daysCount'] ?? 0} | ${context.l10n.companyPromotionsCampaignStatus}: $status',
                                  ),
                                  if ('${row['reason'] ?? ''}'
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${context.l10n.socialProfileReportReason}: ${row['reason']}',
                                    ),
                                  ],
                                  if (canDecide) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ElevatedButton(
                                          onPressed: state.saving
                                              ? null
                                              : () => ref
                                                    .read(
                                                      hrControllerProvider
                                                          .notifier,
                                                    )
                                                    .decideLeaveRequest(
                                                      leaveId: leaveId,
                                                      status: 'approved',
                                                    ),
                                          child: Text(
                                            context.l10n.hrDashboardApprove,
                                          ),
                                        ),
                                        OutlinedButton(
                                          onPressed: state.saving
                                              ? null
                                              : () => ref
                                                    .read(
                                                      hrControllerProvider
                                                          .notifier,
                                                    )
                                                    .decideLeaveRequest(
                                                      leaveId: leaveId,
                                                      status: 'rejected',
                                                    ),
                                          child: Text(
                                            context.l10n.deliveryCourierReject,
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _openEmployeeActionsSheet(
                                                employee,
                                              ),
                                          icon: const Icon(
                                            Icons.person_search_outlined,
                                          ),
                                          label: Text(
                                            context.l10n.hrDashboardEmployee,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                    if (_tab == _HrTab.advanceRequests) ...[
                      if (state.advanceRequests.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            context.l10n.hrDashboardNoAdvanceRequestsYet,
                          ),
                        )
                      else
                        ...state.advanceRequests.map((row) {
                          final requestId =
                              int.tryParse('${row['id'] ?? ''}') ?? 0;
                          final employee = _employeeForRow(state, row);
                          final status = '${row['status'] ?? 'pending'}'
                              .trim()
                              .toLowerCase();
                          final canDecide =
                              requestId > 0 && status == 'pending';
                          final amount =
                              num.tryParse('${row['requestedAmount'] ?? 0}') ??
                              0;
                          final reason = '${row['reason'] ?? ''}'.trim();
                          final decisionNote = '${row['decisionNote'] ?? ''}'
                              .trim();
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${row['employeeFullName'] ?? '-'}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: context
                                            .l10n
                                            .hrDashboardEmployeeActions,
                                        onPressed: () =>
                                            _openEmployeeActionsSheet(employee),
                                        icon: const Icon(
                                          Icons.manage_accounts_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${context.l10n.adminFinancialMerchantHeaderAmount}: ${formatIqd(amount)}',
                                  ),
                                  Text(
                                    '${context.l10n.companyPromotionsCampaignStatus}: $status',
                                  ),
                                  if (reason.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${context.l10n.socialProfileReportReason}: $reason',
                                    ),
                                  ],
                                  if (decisionNote.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${context.l10n.ownerFinancialRequestNotes}: $decisionNote',
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (canDecide)
                                        ElevatedButton(
                                          onPressed: state.saving
                                              ? null
                                              : () => ref
                                                    .read(
                                                      hrControllerProvider
                                                          .notifier,
                                                    )
                                                    .decideAdvanceRequest(
                                                      requestId: requestId,
                                                      status: 'approved',
                                                    ),
                                          child: Text(
                                            context.l10n.hrDashboardApprove,
                                          ),
                                        ),
                                      if (canDecide)
                                        OutlinedButton(
                                          onPressed: state.saving
                                              ? null
                                              : () => ref
                                                    .read(
                                                      hrControllerProvider
                                                          .notifier,
                                                    )
                                                    .decideAdvanceRequest(
                                                      requestId: requestId,
                                                      status: 'rejected',
                                                    ),
                                          child: Text(
                                            context.l10n.deliveryCourierReject,
                                          ),
                                        ),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _openEmployeeActionsSheet(employee),
                                        icon: const Icon(
                                          Icons.person_search_outlined,
                                        ),
                                        label: Text(
                                          context.l10n.hrDashboardEmployee,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                    if (_tab == _HrTab.payroll) ...[
                      if (state.payrollBatches.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            context.l10n.hrDashboardNoPayrollBatchesYet,
                          ),
                        )
                      else
                        ...state.payrollBatches.map((batch) {
                          final batchId =
                              int.tryParse('${batch['id'] ?? ''}') ?? 0;
                          final status = '${batch['status'] ?? '-'}';
                          final totalNet =
                              num.tryParse('${batch['totalNetSalary'] ?? 0}') ??
                              0;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '${context.l10n.hrDashboardBatch} #$batchId - ${batch['periodYear']}/${batch['periodMonth']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${context.l10n.companyPromotionsCampaignStatus}: $status',
                                  ),
                                  Text(
                                    '${context.l10n.deliveryCourierLabelTotal}: ${formatIqd(totalNet)}',
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton(
                                        onPressed: batchId <= 0
                                            ? null
                                            : () => ref
                                                  .read(
                                                    hrControllerProvider
                                                        .notifier,
                                                  )
                                                  .openPayrollBatch(batchId),
                                        child: Text(context.l10n.commonOpen),
                                      ),
                                      if (status == 'draft')
                                        ElevatedButton(
                                          onPressed:
                                              state.saving || batchId <= 0
                                              ? null
                                              : () => ref
                                                    .read(
                                                      hrControllerProvider
                                                          .notifier,
                                                    )
                                                    .submitPayrollBatch(
                                                      batchId,
                                                    ),
                                          child: Text(
                                            context.l10n.hrDashboardSubmit,
                                          ),
                                        ),
                                      if (status == 'processing')
                                        ElevatedButton(
                                          onPressed:
                                              state.saving || batchId <= 0
                                              ? null
                                              : () => ref
                                                    .read(
                                                      hrControllerProvider
                                                          .notifier,
                                                    )
                                                    .closePayrollBatch(batchId),
                                          child: Text(context.l10n.commonClose),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      if (state.payrollItems.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          context.l10n.hrDashboardOpenedBatchItems,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ...state.payrollItems.map((item) {
                          final employee = _employeeForRow(state, item);
                          return ListTile(
                            onTap: () => _openEmployeeActionsSheet(employee),
                            leading: const Icon(Icons.person_outline_rounded),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            title: Text('${item['employeeFullName'] ?? '-'}'),
                            subtitle: Text(
                              '${context.l10n.commonNet}: ${formatIqd(item['netSalary'])} | ${context.l10n.companyPromotionsCampaignStatus}: ${item['status']}',
                            ),
                          );
                        }),
                      ],
                    ],
                    if (_tab == _HrTab.archive) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _openArchivePeriodPicker,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(context.l10n.hrDashboardSelectPeriod),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (state.attendanceArchive.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            context.l10n.hrDashboardNoArchiveDataLoadedYet,
                          ),
                        )
                      else
                        ...state.attendanceArchive.map(
                          (row) => Card(
                            child: ListTile(
                              title: Text('${row['employeeFullName'] ?? '-'}'),
                              subtitle: Text(
                                '${context.l10n.deliveryCourierLabelTotal}: ${row['totalDays'] ?? 0} | '
                                '${context.l10n.hrDashboardPresent}: ${row['presentDays'] ?? 0} | '
                                '${context.l10n.hrDashboardAbsent}: ${row['absentDays'] ?? 0} | '
                                '${context.l10n.hrDashboardLeave}: ${row['leaveDays'] ?? 0}',
                              ),
                            ),
                          ),
                        ),
                    ],
                    if (_tab == _HrTab.profile) ...[
                      ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              auth.user?.imageUrl?.isNotEmpty == true
                              ? AppCachedImageProvider(auth.user!.imageUrl!)
                              : null,
                          child: auth.user?.imageUrl?.isNotEmpty == true
                              ? null
                              : const Icon(Icons.person_outline),
                        ),
                        title: Text(auth.user?.fullName ?? '-'),
                        subtitle: Text(auth.user?.phone ?? '-'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsAccountScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.security_outlined),
                        label: Text(context.l10n.hrDashboardAccountSettings),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsSupportScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.support_agent_rounded),
                        label: Text(context.l10n.settingsSupport),
                      ),
                    ],
                    const SizedBox(height: 80),
                  ],
                ),
              );

        if (!useDesktop) return baseBody;

        return Padding(
          padding: const EdgeInsets.all(14),
          child: DesktopDashboardFrame(
            sidebar: AppUserDrawer(
              title: _title(context),
              subtitle: merchantName,
              items: drawerItems,
              embedded: true,
            ),
            title: _title(context),
            subtitle: context.l10n.hrDashboardDesktopWorkspaceSubtitle,
            statusLabel: 'HR Desktop',
            statusIcon: Icons.badge_outlined,
            quickActions: [
              DesktopQuickActionButton(
                icon: Icons.dashboard_outlined,
                label: context.l10n.hrDashboardOverview,
                selected: _tab == _HrTab.dashboard,
                onPressed: () => _setTab(_HrTab.dashboard),
              ),
              DesktopQuickActionButton(
                icon: Icons.groups_outlined,
                label: context.l10n.hrDashboardEmployees,
                selected: _tab == _HrTab.employees,
                onPressed: () => _setTab(_HrTab.employees),
              ),
              DesktopQuickActionButton(
                icon: Icons.fact_check_outlined,
                label: context.l10n.hrDashboardAttendance,
                selected: _tab == _HrTab.attendance,
                onPressed: () => _setTab(_HrTab.attendance),
              ),
              DesktopQuickActionButton(
                icon: Icons.payments_outlined,
                label: context.l10n.hrDashboardPayroll,
                selected: _tab == _HrTab.payroll,
                onPressed: () => _setTab(_HrTab.payroll),
              ),
              DesktopQuickActionButton(
                icon: Icons.archive_outlined,
                label: context.l10n.commonArchive,
                selected: _tab == _HrTab.archive,
                onPressed: () => _setTab(_HrTab.archive),
              ),
            ],
            child: baseBody,
          ),
        );
      })(),
    );
  }
}

class _HrQuickTabs extends StatelessWidget {
  final _HrTab activeTab;
  final ValueChanged<_HrTab> onSelectTab;

  const _HrQuickTabs({required this.activeTab, required this.onSelectTab});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _HrQuickTabChip(
            label: context.l10n.hrDashboardOverview,
            selected: activeTab == _HrTab.dashboard,
            onTap: () => onSelectTab(_HrTab.dashboard),
          ),
          _HrQuickTabChip(
            label: context.l10n.hrDashboardEmployees,
            selected: activeTab == _HrTab.employees,
            onTap: () => onSelectTab(_HrTab.employees),
          ),
          _HrQuickTabChip(
            label: context.l10n.hrDashboardAttendance,
            selected: activeTab == _HrTab.attendance,
            onTap: () => onSelectTab(_HrTab.attendance),
          ),
          _HrQuickTabChip(
            label: context.l10n.hrDashboardLeave,
            selected: activeTab == _HrTab.leaveRequests,
            onTap: () => onSelectTab(_HrTab.leaveRequests),
          ),
          _HrQuickTabChip(
            label: context.l10n.hrDashboardAdvanceRequests,
            selected: activeTab == _HrTab.advanceRequests,
            onTap: () => onSelectTab(_HrTab.advanceRequests),
          ),
          _HrQuickTabChip(
            label: context.l10n.hrDashboardSalaryAction,
            selected: activeTab == _HrTab.salaryActions,
            onTap: () => onSelectTab(_HrTab.salaryActions),
          ),
          _HrQuickTabChip(
            label: context.l10n.hrDashboardPayroll,
            selected: activeTab == _HrTab.payroll,
            onTap: () => onSelectTab(_HrTab.payroll),
          ),
          _HrQuickTabChip(
            label: context.l10n.commonArchive,
            selected: activeTab == _HrTab.archive,
            onTap: () => onSelectTab(_HrTab.archive),
          ),
        ],
      ),
    );
  }
}

class _HrQuickTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HrQuickTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? scheme.primary : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDesktop = DesktopDashboardFrame.shouldUse(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.12),
            scheme.surface.withValues(alpha: 0.64),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 16 : 12,
          vertical: isDesktop ? 8 : 4,
        ),
        leading: Container(
          width: isDesktop ? 42 : 36,
          height: isDesktop ? 42 : 36,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: scheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          value,
          style: TextStyle(
            fontSize: isDesktop ? 16 : 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HeroStatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
