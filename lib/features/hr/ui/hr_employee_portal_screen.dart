import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../state/hr_employee_controller.dart';

class HrEmployeePortalScreen extends ConsumerStatefulWidget {
  const HrEmployeePortalScreen({super.key});

  @override
  ConsumerState<HrEmployeePortalScreen> createState() =>
      _HrEmployeePortalScreenState();
}

class _HrEmployeePortalScreenState
    extends ConsumerState<HrEmployeePortalScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _attendanceNoteCtrl = TextEditingController();
  final TextEditingController _leaveFromCtrl = TextEditingController();
  final TextEditingController _leaveToCtrl = TextEditingController();
  final TextEditingController _leaveDaysCtrl = TextEditingController(text: '1');
  final TextEditingController _leaveReasonCtrl = TextEditingController();
  final TextEditingController _advanceAmountCtrl = TextEditingController();
  final TextEditingController _advanceReasonCtrl = TextEditingController();
  final GlobalKey _profileSectionKey = GlobalKey();
  final GlobalKey _attendanceSectionKey = GlobalKey();
  final GlobalKey _leaveSectionKey = GlobalKey();
  final GlobalKey _advanceSectionKey = GlobalKey();
  final GlobalKey _attendanceLogsSectionKey = GlobalKey();
  final GlobalKey _leaveLogsSectionKey = GlobalKey();
  final GlobalKey _advanceLogsSectionKey = GlobalKey();

  LocalImageFile? _attendanceImage;
  String _leaveType = 'annual';
  String _leavePayPolicy = 'paid';

  @override
  void initState() {
    super.initState();
    final today = DateTime.now().toIso8601String().split('T').first;
    _leaveFromCtrl.text = today;
    _leaveToCtrl.text = today;
    Future.microtask(
      () => ref.read(hrEmployeeControllerProvider.notifier).bootstrap(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _attendanceNoteCtrl.dispose();
    _leaveFromCtrl.dispose();
    _leaveToCtrl.dispose();
    _leaveDaysCtrl.dispose();
    _leaveReasonCtrl.dispose();
    _advanceAmountCtrl.dispose();
    _advanceReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAttendanceImage() async {
    final picked = await pickImageFromDevice();
    if (!mounted) return;
    setState(() => _attendanceImage = picked);
  }

  Future<void> _scrollToSection(GlobalKey sectionKey) async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sectionContext = sectionKey.currentContext;
      if (sectionContext == null) return;
      Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.04,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(hrEmployeeControllerProvider);

    ref.listen<HrEmployeeState>(hrEmployeeControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      if (next.success != null && next.success != previous?.success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.success!)));
      }
    });

    final profile = state.profile ?? const <String, dynamic>{};
    final shiftText =
        '${profile['shiftStartTime'] ?? '-'} -> ${profile['shiftEndTime'] ?? '-'}';
    final salary = num.tryParse('${profile['baseSalary'] ?? 0}') ?? 0;

    return Scaffold(
      drawer: AppUserDrawer(
        title: l10n.hrEmployeePortalTitle,
        subtitle: l10n.hrEmployeePortalSubtitle,
      ),
      appBar: AppBar(
        title: Text(l10n.hrEmployeePortalTitle),
        actions: [
          IconButton(
            onPressed: state.loading
                ? null
                : () => ref
                      .read(hrEmployeeControllerProvider.notifier)
                      .bootstrap(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const NotificationsBellButton(),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(hrEmployeeControllerProvider.notifier).bootstrap(),
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                children: [
                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      children: [
                        _EmployeePortalQuickCard(
                          icon: Icons.badge_outlined,
                          title: l10n.hrEmployeePortalProfile,
                          subtitle: l10n.hrEmployeePortalBaseInfo,
                          onTap: () => _scrollToSection(_profileSectionKey),
                        ),
                        const SizedBox(width: 8),
                        _EmployeePortalQuickCard(
                          icon: Icons.fingerprint_rounded,
                          title: l10n.hrEmployeePortalAttendance,
                          subtitle: l10n.hrEmployeePortalCheckInOut,
                          onTap: () => _scrollToSection(_attendanceSectionKey),
                        ),
                        const SizedBox(width: 8),
                        _EmployeePortalQuickCard(
                          icon: Icons.event_available_outlined,
                          title: l10n.hrEmployeePortalLeave,
                          subtitle: l10n.hrEmployeePortalRequestLeave,
                          onTap: () => _scrollToSection(_leaveSectionKey),
                        ),
                        const SizedBox(width: 8),
                        _EmployeePortalQuickCard(
                          icon: Icons.request_page_outlined,
                          title: l10n.hrEmployeePortalAdvance,
                          subtitle: l10n.hrEmployeePortalAdvanceRequest,
                          onTap: () => _scrollToSection(_advanceSectionKey),
                        ),
                        const SizedBox(width: 8),
                        _EmployeePortalQuickCard(
                          icon: Icons.history_rounded,
                          title: l10n.hrEmployeePortalLogs,
                          subtitle: l10n.hrEmployeePortalTrackHistory,
                          onTap: () =>
                              _scrollToSection(_attendanceLogsSectionKey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _profileSectionKey,
                    child: Card(
                      child: ListTile(
                        title: Text(
                          '${profile['merchantName'] ?? state.merchant?['name'] ?? '-'}',
                        ),
                        subtitle: Text(
                          '${l10n.hrEmployeePortalRole}: ${profile['roleTag'] ?? '-'}\n'
                          '${l10n.hrEmployeePortalShift}: $shiftText\n'
                          '${l10n.hrEmployeePortalWorkDaysPerWeek}: ${profile['workDaysPerWeek'] ?? '-'}\n'
                          '${l10n.hrEmployeePortalBaseSalary}: ${formatIqd(salary)}',
                        ),
                        isThreeLine: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _attendanceSectionKey,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.hrEmployeePortalAttendanceCheckIn,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _attendanceNoteCtrl,
                              decoration: InputDecoration(
                                labelText: l10n.hrEmployeePortalNoteOptional,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pickAttendanceImage,
                                  icon: const Icon(Icons.image_outlined),
                                  label: Text(
                                    _attendanceImage == null
                                        ? l10n.hrEmployeePortalOptionalPhoto
                                        : l10n.hrEmployeePortalPhotoSelected,
                                  ),
                                ),
                                if (_attendanceImage != null)
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _attendanceImage = null),
                                    child: Text(
                                      l10n.hrEmployeePortalRemovePhoto,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: state.saving
                                        ? null
                                        : () => ref
                                              .read(
                                                hrEmployeeControllerProvider
                                                    .notifier,
                                              )
                                              .checkIn(
                                                note:
                                                    _attendanceNoteCtrl.text
                                                        .trim()
                                                        .isEmpty
                                                    ? null
                                                    : _attendanceNoteCtrl.text
                                                          .trim(),
                                                imageFile: _attendanceImage,
                                              ),
                                    icon: const Icon(Icons.login_rounded),
                                    label: Text(l10n.hrEmployeePortalCheckIn),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: state.saving
                                        ? null
                                        : () => ref
                                              .read(
                                                hrEmployeeControllerProvider
                                                    .notifier,
                                              )
                                              .checkOut(
                                                note:
                                                    _attendanceNoteCtrl.text
                                                        .trim()
                                                        .isEmpty
                                                    ? null
                                                    : _attendanceNoteCtrl.text
                                                          .trim(),
                                                imageFile: _attendanceImage,
                                              ),
                                    icon: const Icon(Icons.logout_rounded),
                                    label: Text(l10n.hrEmployeePortalCheckOut),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _leaveSectionKey,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.hrEmployeePortalLeaveRequestTitle,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _leaveType,
                              decoration: InputDecoration(
                                labelText: l10n.hrEmployeePortalLeaveType,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'annual',
                                  child: Text(
                                    l10n.hrEmployeePortalLeaveTypeAnnual,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'sick',
                                  child: Text(
                                    l10n.hrEmployeePortalLeaveTypeSick,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'emergency',
                                  child: Text(
                                    l10n.hrEmployeePortalLeaveTypeEmergency,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'maternity',
                                  child: Text(
                                    l10n.hrEmployeePortalLeaveTypeMaternity,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'other',
                                  child: Text(
                                    l10n.hrEmployeePortalLeaveTypeOther,
                                  ),
                                ),
                              ],
                              onChanged: (value) => setState(
                                () => _leaveType = value ?? 'annual',
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _leavePayPolicy,
                              decoration: InputDecoration(
                                labelText: l10n.hrEmployeePortalPayPolicy,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'paid',
                                  child: Text(
                                    l10n.hrEmployeePortalPayPolicyPaid,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'half_paid',
                                  child: Text(
                                    l10n.hrEmployeePortalPayPolicyHalfPaid,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'unpaid',
                                  child: Text(
                                    l10n.hrEmployeePortalPayPolicyUnpaid,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'sick_paid',
                                  child: Text(
                                    l10n.hrEmployeePortalPayPolicySickPaid,
                                  ),
                                ),
                              ],
                              onChanged: (value) => setState(
                                () => _leavePayPolicy = value ?? 'paid',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _leaveFromCtrl,
                              decoration: InputDecoration(
                                labelText: l10n.hrEmployeePortalFromDate,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _leaveToCtrl,
                              decoration: InputDecoration(
                                labelText: l10n.hrEmployeePortalToDate,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _leaveDaysCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: l10n.hrEmployeePortalDaysCount,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _leaveReasonCtrl,
                              decoration: InputDecoration(
                                labelText: l10n.hrEmployeePortalReasonOptional,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: state.saving
                                  ? null
                                  : () {
                                      final days =
                                          num.tryParse(
                                            _leaveDaysCtrl.text.trim(),
                                          ) ??
                                          0;
                                      ref
                                          .read(
                                            hrEmployeeControllerProvider
                                                .notifier,
                                          )
                                          .submitLeaveRequest(
                                            leaveType: _leaveType,
                                            payPolicy: _leavePayPolicy,
                                            dateFrom: _leaveFromCtrl.text
                                                .trim(),
                                            dateTo: _leaveToCtrl.text.trim(),
                                            daysCount: days,
                                            reason:
                                                _leaveReasonCtrl.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : _leaveReasonCtrl.text.trim(),
                                          );
                                    },
                              icon: const Icon(Icons.send_rounded),
                              label: Text(
                                l10n.hrEmployeePortalSendLeaveRequest,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _advanceSectionKey,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.hrEmployeePortalSalaryAdvanceRequest,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _advanceAmountCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: l10n.hrEmployeePortalReasonOptional,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: state.saving
                                  ? null
                                  : () {
                                      final amount =
                                          num.tryParse(
                                            _advanceAmountCtrl.text.trim(),
                                          ) ??
                                          0;
                                      ref
                                          .read(
                                            hrEmployeeControllerProvider
                                                .notifier,
                                          )
                                          .submitAdvanceRequest(
                                            requestedAmount: amount,
                                            reason:
                                                _advanceReasonCtrl.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : _advanceReasonCtrl.text
                                                      .trim(),
                                          );
                                    },
                              icon: const Icon(Icons.request_page_outlined),
                              label: Text(
                                l10n.hrEmployeePortalSendAdvanceRequest,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _attendanceLogsSectionKey,
                    child: Text(
                      l10n.hrEmployeePortalMyAttendanceLogs,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...state.attendance.map(
                    (row) => ListTile(
                      dense: true,
                      title: Text('${row['attendanceDate'] ?? '-'}'),
                      subtitle: Text(
                        '${l10n.hrEmployeePortalStatus}: ${row['status'] ?? '-'} | '
                        '${l10n.hrEmployeePortalIn}: ${row['checkInAt'] ?? '-'} | '
                        '${l10n.hrEmployeePortalOut}: ${row['checkOutAt'] ?? '-'}',
                      ),
                    ),
                  ),
                  const Divider(height: 18),
                  KeyedSubtree(
                    key: _leaveLogsSectionKey,
                    child: Text(
                      l10n.hrEmployeePortalMyLeaveRequests,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...state.leaveRequests.map(
                    (row) => ListTile(
                      dense: true,
                      title: Text(
                        '${row['dateFrom'] ?? ''} -> ${row['dateTo'] ?? ''}',
                      ),
                      subtitle: Text(
                        '${row['leaveType'] ?? '-'} | ${row['payPolicy'] ?? '-'} | '
                        '${l10n.hrEmployeePortalStatus}: ${row['status'] ?? '-'}',
                      ),
                    ),
                  ),
                  const Divider(height: 18),
                  KeyedSubtree(
                    key: _advanceLogsSectionKey,
                    child: Text(
                      l10n.hrEmployeePortalMyAdvanceRequests,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...state.advanceRequests.map(
                    (row) => ListTile(
                      dense: true,
                      title: Text(formatIqd(row['requestedAmount'])),
                      subtitle: Text(
                        '${l10n.hrEmployeePortalStatus}: ${row['status'] ?? '-'} | '
                        '${l10n.hrEmployeePortalCreated}: ${row['createdAt'] ?? '-'}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

class _EmployeePortalQuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _EmployeePortalQuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          width: 168,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                scheme.primary.withValues(alpha: 0.2),
                scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ],
            ),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      textDirection: Directionality.of(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textDirection: Directionality.of(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.74),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
