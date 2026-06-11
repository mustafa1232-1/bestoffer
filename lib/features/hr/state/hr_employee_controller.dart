import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/settings/app_settings_controller.dart';
import 'hr_controller.dart';

class HrEmployeeState {
  final bool loading;
  final bool saving;
  final Map<String, dynamic>? merchant;
  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> attendance;
  final List<Map<String, dynamic>> leaveRequests;
  final List<Map<String, dynamic>> advanceRequests;
  final String? error;
  final String? success;

  const HrEmployeeState({
    this.loading = false,
    this.saving = false,
    this.merchant,
    this.profile,
    this.attendance = const [],
    this.leaveRequests = const [],
    this.advanceRequests = const [],
    this.error,
    this.success,
  });

  HrEmployeeState copyWith({
    bool? loading,
    bool? saving,
    Map<String, dynamic>? merchant,
    Map<String, dynamic>? profile,
    List<Map<String, dynamic>>? attendance,
    List<Map<String, dynamic>>? leaveRequests,
    List<Map<String, dynamic>>? advanceRequests,
    String? error,
    String? success,
  }) {
    return HrEmployeeState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      merchant: merchant ?? this.merchant,
      profile: profile ?? this.profile,
      attendance: attendance ?? this.attendance,
      leaveRequests: leaveRequests ?? this.leaveRequests,
      advanceRequests: advanceRequests ?? this.advanceRequests,
      error: error,
      success: success,
    );
  }
}

final hrEmployeeControllerProvider =
    StateNotifierProvider<HrEmployeeController, HrEmployeeState>(
      (ref) => HrEmployeeController(ref),
    );

class HrEmployeeController extends StateNotifier<HrEmployeeState> {
  final Ref ref;

  HrEmployeeController(this.ref) : super(const HrEmployeeState());

  bool get _isEnglish =>
      ref
          .read(appSettingsControllerProvider)
          .locale
          .languageCode
          .toLowerCase() ==
      'en';

  String _tr(String ar, String en) => _isEnglish ? en : ar;

  Future<void> bootstrap() async {
    state = state.copyWith(loading: true, error: null, success: null);
    try {
      final profilePayload = await ref.read(hrApiProvider).myProfiles();
      final merchant = profilePayload['merchant'] is Map
          ? Map<String, dynamic>.from(profilePayload['merchant'] as Map)
          : null;
      final profile = profilePayload['profile'] is Map
          ? Map<String, dynamic>.from(profilePayload['profile'] as Map)
          : null;
      final merchantId = int.tryParse(
        '${profile?['merchantId'] ?? merchant?['id'] ?? ''}',
      );

      final leavePayload = await ref
          .read(hrApiProvider)
          .listMyLeaveRequests(merchantId: merchantId, limit: 120);
      final advancePayload = await ref
          .read(hrApiProvider)
          .listMyAdvanceRequests(merchantId: merchantId, limit: 120);
      final attendancePayload = await ref
          .read(hrApiProvider)
          .listMyAttendance(merchantId: merchantId, limit: 120);

      state = state.copyWith(
        loading: false,
        merchant: merchant,
        profile: profile,
        leaveRequests: ((leavePayload['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        advanceRequests: ((advancePayload['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
        attendance: ((attendancePayload['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: _tr(
          'تعذر تحميل بوابة الموظف.',
          'Unable to load employee HR portal.',
        ),
      );
    }
  }

  Future<void> _reloadLists() async {
    final merchantId = int.tryParse(
      '${state.profile?['merchantId'] ?? state.merchant?['id'] ?? ''}',
    );
    final leavePayload = await ref
        .read(hrApiProvider)
        .listMyLeaveRequests(merchantId: merchantId, limit: 120);
    final advancePayload = await ref
        .read(hrApiProvider)
        .listMyAdvanceRequests(merchantId: merchantId, limit: 120);
    final attendancePayload = await ref
        .read(hrApiProvider)
        .listMyAttendance(merchantId: merchantId, limit: 120);
    state = state.copyWith(
      leaveRequests: ((leavePayload['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false),
      advanceRequests: ((advancePayload['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false),
      attendance: ((attendancePayload['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false),
    );
  }

  Future<void> submitLeaveRequest({
    required String leaveType,
    required String payPolicy,
    required String dateFrom,
    required String dateTo,
    required num daysCount,
    String? reason,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(hrApiProvider).createMyLeaveRequest({
        'merchantId': state.profile?['merchantId'] ?? state.merchant?['id'],
        'leaveType': leaveType,
        'payPolicy': payPolicy,
        'dateFrom': dateFrom,
        'dateTo': dateTo,
        'daysCount': daysCount,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
      await _reloadLists();
      state = state.copyWith(
        saving: false,
        success: _tr(
          'تم إرسال طلب الإجازة إلى الموارد البشرية.',
          'Leave request sent to HR.',
        ),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr('تعذر إرسال طلب الإجازة.', 'Failed to send leave request.'),
      );
    }
  }

  Future<void> submitAdvanceRequest({
    required num requestedAmount,
    String? reason,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(hrApiProvider).createMyAdvanceRequest({
        'merchantId': state.profile?['merchantId'] ?? state.merchant?['id'],
        'requestedAmount': requestedAmount,
        'currency': state.profile?['currency'] ?? 'IQD',
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
      await _reloadLists();
      state = state.copyWith(
        saving: false,
        success: _tr(
          'تم إرسال طلب السلفة إلى الموارد البشرية.',
          'Advance request sent to HR.',
        ),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr('تعذر إرسال طلب السلفة.', 'Failed to send advance request.'),
      );
    }
  }

  Future<void> checkIn({String? note, LocalImageFile? imageFile}) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(hrApiProvider)
          .selfCheckIn(
            merchantId: int.tryParse(
              '${state.profile?['merchantId'] ?? state.merchant?['id'] ?? ''}',
            ),
            note: note,
            imageFile: imageFile,
          );
      await _reloadLists();
      state = state.copyWith(
        saving: false,
        success: _tr('تم تسجيل الحضور.', 'Attendance check-in saved.'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr('تعذر تسجيل الحضور.', 'Failed to check in.'),
      );
    }
  }

  Future<void> checkOut({String? note, LocalImageFile? imageFile}) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(hrApiProvider)
          .selfCheckOut(
            merchantId: int.tryParse(
              '${state.profile?['merchantId'] ?? state.merchant?['id'] ?? ''}',
            ),
            note: note,
            imageFile: imageFile,
          );
      await _reloadLists();
      state = state.copyWith(
        saving: false,
        success: _tr('تم تسجيل الانصراف.', 'Attendance check-out saved.'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _tr('تعذر تسجيل الانصراف.', 'Failed to check out.'),
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
