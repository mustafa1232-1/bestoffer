// ignore_for_file: use_null_aware_elements

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../auth/state/auth_controller.dart';
import '../data/hr_api.dart';

final hrApiProvider = Provider<HrApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return HrApi(dio);
});

class HrState {
  final bool loading;
  final bool saving;
  final Map<String, dynamic>? merchant;
  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> attendance;
  final List<Map<String, dynamic>> payrollBatches;
  final List<Map<String, dynamic>> payrollItems;
  final List<Map<String, dynamic>> leaveRequests;
  final List<Map<String, dynamic>> salaryActions;
  final List<Map<String, dynamic>> advanceRequests;
  final List<Map<String, dynamic>> attendanceArchive;
  final String? error;
  final String? successMessage;

  const HrState({
    this.loading = false,
    this.saving = false,
    this.merchant,
    this.stats = const {},
    this.employees = const [],
    this.attendance = const [],
    this.payrollBatches = const [],
    this.payrollItems = const [],
    this.leaveRequests = const [],
    this.salaryActions = const [],
    this.advanceRequests = const [],
    this.attendanceArchive = const [],
    this.error,
    this.successMessage,
  });

  HrState copyWith({
    bool? loading,
    bool? saving,
    Map<String, dynamic>? merchant,
    Map<String, dynamic>? stats,
    List<Map<String, dynamic>>? employees,
    List<Map<String, dynamic>>? attendance,
    List<Map<String, dynamic>>? payrollBatches,
    List<Map<String, dynamic>>? payrollItems,
    List<Map<String, dynamic>>? leaveRequests,
    List<Map<String, dynamic>>? salaryActions,
    List<Map<String, dynamic>>? advanceRequests,
    List<Map<String, dynamic>>? attendanceArchive,
    String? error,
    String? successMessage,
  }) {
    return HrState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      merchant: merchant ?? this.merchant,
      stats: stats ?? this.stats,
      employees: employees ?? this.employees,
      attendance: attendance ?? this.attendance,
      payrollBatches: payrollBatches ?? this.payrollBatches,
      payrollItems: payrollItems ?? this.payrollItems,
      leaveRequests: leaveRequests ?? this.leaveRequests,
      salaryActions: salaryActions ?? this.salaryActions,
      advanceRequests: advanceRequests ?? this.advanceRequests,
      attendanceArchive: attendanceArchive ?? this.attendanceArchive,
      error: error,
      successMessage: successMessage,
    );
  }
}

final hrControllerProvider = StateNotifierProvider<HrController, HrState>(
  (ref) => HrController(ref),
);

class HrController extends StateNotifier<HrState> {
  final Ref ref;

  HrController(this.ref) : super(const HrState());

  bool get _isEnglish =>
      ref
          .read(appSettingsControllerProvider)
          .locale
          .languageCode
          .toLowerCase() ==
      'en';

  String _tr(String ar, String en) => _isEnglish ? en : ar;

  Future<void> bootstrap() async {
    state = state.copyWith(loading: true, error: null, successMessage: null);
    try {
      final api = ref.read(hrApiProvider);
      final dashboardFuture = api.getDashboard();
      final employeesFuture = api.listEmployees();
      final attendanceFuture = api.listAttendance(limit: 120);
      final payrollFuture = api.listPayrollBatches();
      final leaveRequestsFuture = api.listLeaveRequests(limit: 120);
      final salaryActionsFuture = api.listSalaryActions(limit: 200);
      final advanceRequestsFuture = api.listAdvanceRequests(limit: 120);
      final now = DateTime.now();
      final archiveFuture = api.getAttendanceArchive(
        periodYear: now.year,
        periodMonth: now.month,
      );
      await Future.wait([
        dashboardFuture,
        employeesFuture,
        attendanceFuture,
        payrollFuture,
        leaveRequestsFuture,
        salaryActionsFuture,
        advanceRequestsFuture,
        archiveFuture,
      ]);
      final dashboard = await dashboardFuture;
      final employees = await employeesFuture;
      final attendance = await attendanceFuture;
      final payroll = await payrollFuture;
      final leaveRequests = await leaveRequestsFuture;
      final salaryActions = await salaryActionsFuture;
      final advanceRequests = await advanceRequestsFuture;
      final archive = await archiveFuture;
      state = state.copyWith(
        loading: false,
        merchant: dashboard['merchant'] is Map
            ? Map<String, dynamic>.from(dashboard['merchant'] as Map)
            : null,
        stats: dashboard['stats'] is Map
            ? Map<String, dynamic>.from(dashboard['stats'] as Map)
            : const {},
        employees: ((employees['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        attendance: ((attendance['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        payrollBatches: ((payroll['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        leaveRequests: ((leaveRequests['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        salaryActions: ((salaryActions['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        advanceRequests: ((advanceRequests['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        attendanceArchive: ((archive['attendance'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: _tr(
          'تعذر تحميل لوحة الموارد البشرية.',
          'Failed to load HR dashboard.',
        ),
      );
    }
  }

  Future<void> searchEmployees(String search) async {
    try {
      final employees = await ref
          .read(hrApiProvider)
          .listEmployees(search: search);
      state = state.copyWith(
        employees: ((employees['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
      );
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
    }
  }

  Future<void> upsertEmployeeProfile({
    required int employeeUserId,
    required String roleTag,
    required num baseSalary,
    required int workDaysPerWeek,
    String? employmentType,
    String? shiftStartTime,
    String? shiftEndTime,
    bool isActive = true,
    String? notes,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref.read(hrApiProvider).upsertEmployee({
        'employeeUserId': employeeUserId,
        'roleTag': roleTag,
        'employmentType': employmentType ?? 'full_time',
        'baseSalary': baseSalary,
        'workDaysPerWeek': workDaysPerWeek,
        'shiftStartTime': shiftStartTime,
        'shiftEndTime': shiftEndTime,
        'isActive': isActive,
        'notes': notes,
      });
      await bootstrap();
      state = state.copyWith(
        saving: false,
        successMessage: _tr(
          'تم تحديث ملف الموظف.',
          'Employee profile updated.',
        ),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr('تعذر تحديث الملف.', 'Failed to update profile.'),
      );
    }
  }

  Future<void> markAttendance({
    required int employeeUserId,
    required String attendanceDate,
    required String status,
    String? checkInAt,
    String? checkOutAt,
    String? note,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref.read(hrApiProvider).upsertAttendance({
        'employeeUserId': employeeUserId,
        'attendanceDate': attendanceDate,
        'status': status,
        if (checkInAt != null) 'checkInAt': checkInAt,
        if (checkOutAt != null) 'checkOutAt': checkOutAt,
        if (note != null) 'note': note,
      });
      final attendance = await ref
          .read(hrApiProvider)
          .listAttendance(limit: 120);
      state = state.copyWith(
        saving: false,
        attendance: ((attendance['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        successMessage: _tr('تم تحديث الحضور.', 'Attendance updated.'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr('تعذر تحديث الحضور.', 'Failed to update attendance.'),
      );
    }
  }

  Future<void> buildPayroll({
    required int periodYear,
    required int periodMonth,
    List<Map<String, dynamic>> adjustments = const [],
    String? summaryNote,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      final payload = await ref.read(hrApiProvider).buildPayroll({
        'periodYear': periodYear,
        'periodMonth': periodMonth,
        'adjustments': adjustments,
        if (summaryNote != null) 'summaryNote': summaryNote,
      });
      final batch = payload['batch'] is Map
          ? Map<String, dynamic>.from(payload['batch'] as Map)
          : null;
      state = state.copyWith(
        saving: false,
        payrollItems: ((payload['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        successMessage: batch == null
            ? _tr('تم إنشاء دفعة الرواتب.', 'Payroll batch built.')
            : _tr(
                'تم إنشاء دفعة الرواتب رقم ${batch['id']}.',
                'Payroll batch #${batch['id']} built.',
              ),
      );
      final payroll = await ref.read(hrApiProvider).listPayrollBatches();
      state = state.copyWith(
        payrollBatches: ((payroll['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr(
          'تعذر إنشاء دفعة الرواتب.',
          'Failed to build payroll batch.',
        ),
      );
    }
  }

  Future<void> openPayrollBatch(int batchId) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final payload = await ref
          .read(hrApiProvider)
          .getPayrollBatch(batchId: batchId);
      state = state.copyWith(
        loading: false,
        payrollItems: ((payload['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: _tr('تعذر فتح دفعة الرواتب.', 'Failed to open payroll batch.'),
      );
    }
  }

  Future<void> submitPayrollBatch(int batchId) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref.read(hrApiProvider).submitPayrollBatch(batchId: batchId);
      final payroll = await ref.read(hrApiProvider).listPayrollBatches();
      state = state.copyWith(
        saving: false,
        payrollBatches: ((payroll['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        successMessage: _tr(
          'تم إرسال دفعة الرواتب إلى المحاسب.',
          'Payroll batch submitted to accountant.',
        ),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr('تعذر إرسال الرواتب.', 'Failed to submit payroll.'),
      );
    }
  }

  Future<void> closePayrollBatch(int batchId) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref.read(hrApiProvider).closePayrollBatch(batchId: batchId);
      final payroll = await ref.read(hrApiProvider).listPayrollBatches();
      state = state.copyWith(
        saving: false,
        payrollBatches: ((payroll['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        successMessage: _tr('تم إغلاق دفعة الرواتب.', 'Payroll batch closed.'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr(
          'تعذر إغلاق دفعة الرواتب.',
          'Failed to close payroll batch.',
        ),
      );
    }
  }

  Future<void> createLeaveRequest({
    required int employeeUserId,
    required String leaveType,
    required String payPolicy,
    required String dateFrom,
    required String dateTo,
    required num daysCount,
    String? reason,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref.read(hrApiProvider).createLeaveRequest({
        'employeeUserId': employeeUserId,
        'leaveType': leaveType,
        'payPolicy': payPolicy,
        'dateFrom': dateFrom,
        'dateTo': dateTo,
        'daysCount': daysCount,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
      final leaveRequests = await ref
          .read(hrApiProvider)
          .listLeaveRequests(limit: 120);
      state = state.copyWith(
        saving: false,
        leaveRequests: ((leaveRequests['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        successMessage: _tr('تمت إضافة طلب الإجازة.', 'Leave request added.'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr(
          'تعذر إنشاء طلب الإجازة.',
          'Failed to create leave request.',
        ),
      );
    }
  }

  Future<void> decideLeaveRequest({
    required int leaveId,
    required String status,
    String? decisionNote,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref
          .read(hrApiProvider)
          .decideLeaveRequest(
            leaveId: leaveId,
            status: status,
            decisionNote: decisionNote,
          );
      final leaveRequests = await ref
          .read(hrApiProvider)
          .listLeaveRequests(limit: 120);
      state = state.copyWith(
        saving: false,
        leaveRequests: ((leaveRequests['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        successMessage: _tr('تم تحديث طلب الإجازة.', 'Leave request updated.'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr(
          'تعذر تحديث طلب الإجازة.',
          'Failed to update leave request.',
        ),
      );
    }
  }

  Future<void> createSalaryAction({
    required int employeeUserId,
    required String actionType,
    required num amount,
    required int effectiveYear,
    required int effectiveMonth,
    String currency = 'IQD',
    String? description,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref.read(hrApiProvider).createSalaryAction({
        'employeeUserId': employeeUserId,
        'actionType': actionType,
        'amount': amount,
        'currency': currency,
        'effectiveYear': effectiveYear,
        'effectiveMonth': effectiveMonth,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
      });
      final salaryActions = await ref
          .read(hrApiProvider)
          .listSalaryActions(limit: 200);
      state = state.copyWith(
        saving: false,
        salaryActions: ((salaryActions['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        successMessage: _tr('تم إنشاء إجراء راتب.', 'Salary action created.'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr(
          'تعذر إنشاء إجراء الراتب.',
          'Failed to create salary action.',
        ),
      );
    }
  }

  Future<void> updateSalaryActionStatus({
    required int actionId,
    required String status,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref
          .read(hrApiProvider)
          .updateSalaryActionStatus(actionId: actionId, status: status);
      final salaryActions = await ref
          .read(hrApiProvider)
          .listSalaryActions(limit: 200);
      state = state.copyWith(
        saving: false,
        salaryActions: ((salaryActions['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        successMessage: _tr('تم تحديث إجراء الراتب.', 'Salary action updated.'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr(
          'تعذر تحديث إجراء الراتب.',
          'Failed to update salary action.',
        ),
      );
    }
  }

  Future<void> decideAdvanceRequest({
    required int requestId,
    required String status,
    String? decisionNote,
    int? effectiveYear,
    int? effectiveMonth,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref
          .read(hrApiProvider)
          .decideAdvanceRequest(
            requestId: requestId,
            status: status,
            decisionNote: decisionNote,
            effectiveYear: effectiveYear,
            effectiveMonth: effectiveMonth,
          );
      final advanceRequests = await ref
          .read(hrApiProvider)
          .listAdvanceRequests(limit: 120);
      final salaryActions = await ref
          .read(hrApiProvider)
          .listSalaryActions(limit: 200);
      state = state.copyWith(
        saving: false,
        advanceRequests: ((advanceRequests['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        salaryActions: ((salaryActions['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        successMessage: _tr('تم تحديث طلب السلفة.', 'Advance request updated.'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr(
          'تعذر تحديث طلب السلفة.',
          'Failed to update advance request.',
        ),
      );
    }
  }

  Future<void> loadAttendanceArchive({
    required int periodYear,
    required int periodMonth,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final archive = await ref
          .read(hrApiProvider)
          .getAttendanceArchive(
            periodYear: periodYear,
            periodMonth: periodMonth,
          );
      state = state.copyWith(
        loading: false,
        attendanceArchive: ((archive['attendance'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        leaveRequests: ((archive['leaveRequests'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        salaryActions: ((archive['salaryActions'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: _tr('تعذر تحميل الأرشيف.', 'Failed to load archive.'),
      );
    }
  }

  String _mapError(DioException e) {
    return mapDioError(
      e,
      fallback: _tr(
        'تعذر الاتصال بخدمة الموارد البشرية.',
        'Unable to connect to HR service.',
      ),
      appendRequestId: true,
    );
  }
}
