import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../data/company_api.dart';
import '../data/company_dio_client.dart';
import '../data/company_secure_store.dart';
import '../models/company_models.dart';

final companySecureStoreProvider = Provider<CompanySecureStore>((ref) {
  return CompanySecureStore();
});

final companyDioClientProvider = Provider<CompanyDioClient>((ref) {
  return CompanyDioClient(ref.read(companySecureStoreProvider));
});

final companyApiProvider = Provider<CompanyApi>((ref) {
  return CompanyApi(ref.read(companyDioClientProvider).dio);
});

final companySessionControllerProvider =
    StateNotifierProvider<CompanySessionController, CompanySessionState>((ref) {
      return CompanySessionController(ref);
    });

/// حالة جلسة بوابة الشركات: المستخدم، العضويات، والشركة النشطة حالياً.
///
/// Critical notes:
/// - `activeCompanyId` هو المرجع التشغيلي الذي تعتمد عليه معظم شاشات
///   البوابة في استدعاءات الـ API.
class CompanySessionState {
  final bool bootstrapping;
  final bool loggingIn;
  final String? error;
  final CompanyPortalUser? user;
  final List<CompanyMembership> memberships;
  final int? activeCompanyId;

  const CompanySessionState({
    this.bootstrapping = false,
    this.loggingIn = false,
    this.error,
    this.user,
    this.memberships = const [],
    this.activeCompanyId,
  });

  bool get isAuthenticated =>
      user != null && memberships.isNotEmpty && activeCompanyId != null;

  CompanyMembership? get activeMembership {
    final companyId = activeCompanyId;
    if (companyId == null) return null;
    for (final membership in memberships) {
      if (membership.companyId == companyId) return membership;
    }
    return memberships.isEmpty ? null : memberships.first;
  }

  CompanySessionState copyWith({
    bool? bootstrapping,
    bool? loggingIn,
    String? error,
    bool clearError = false,
    CompanyPortalUser? user,
    bool clearUser = false,
    List<CompanyMembership>? memberships,
    int? activeCompanyId,
    bool clearActiveCompanyId = false,
  }) {
    return CompanySessionState(
      bootstrapping: bootstrapping ?? this.bootstrapping,
      loggingIn: loggingIn ?? this.loggingIn,
      error: clearError ? null : (error ?? this.error),
      user: clearUser ? null : (user ?? this.user),
      memberships: memberships ?? this.memberships,
      activeCompanyId: clearActiveCompanyId
          ? null
          : (activeCompanyId ?? this.activeCompanyId),
    );
  }
}

/// يدير دورة حياة جلسة بوابة الشركات بشكل مستقل عن جلسة التطبيق العامة.
///
/// Maintenance notes:
/// - عند شكاوى "تم تسجيل الدخول لكن لا تظهر الشركات" افحص هذا الملف مع
///   `CompanySecureStore`, `CompanyApi.bootstrap` وmembership payload.
class CompanySessionController extends StateNotifier<CompanySessionState> {
  final Ref ref;

  CompanySessionController(this.ref) : super(const CompanySessionState());

  CompanySecureStore get _store => ref.read(companySecureStoreProvider);
  CompanyApi get _api => ref.read(companyApiProvider);

  /// يعيد بناء الجلسة من التخزين ويحدد الشركة النشطة المناسبة.
  Future<void> bootstrap() async {
    state = state.copyWith(bootstrapping: true, clearError: true);
    final token = await _store.readToken();
    if (token == null || token.isEmpty) {
      state = state.copyWith(
        bootstrapping: false,
        memberships: const [],
        clearUser: true,
        clearActiveCompanyId: true,
      );
      return;
    }
    try {
      final bootstrap = await _api.bootstrap();
      final activeCompanyId = await _resolveActiveCompanyId(bootstrap.memberships);
      state = CompanySessionState(
        bootstrapping: false,
        user: bootstrap.user,
        memberships: bootstrap.memberships,
        activeCompanyId: activeCompanyId,
      );
    } catch (error) {
      await _store.clear();
      state = CompanySessionState(
        bootstrapping: false,
        error: mapAnyError(
          error,
          fallback: 'تعذر تحميل بوابة الشركات. يرجى تسجيل الدخول من جديد.',
        ),
      );
    }
  }

  /// يسجل الدخول إلى بوابة الشركات ويحفظ token البوابة المنفصل.
  Future<void> login({required String phone, required String pin}) async {
    state = state.copyWith(loggingIn: true, clearError: true);
    try {
      final result = await _api.login(phone: phone, pin: pin);
      await _store.saveToken(result.token);
      final activeCompanyId = await _resolveActiveCompanyId(result.memberships);
      state = CompanySessionState(
        bootstrapping: false,
        loggingIn: false,
        user: result.user,
        memberships: result.memberships,
        activeCompanyId: activeCompanyId,
      );
    } catch (error) {
      state = state.copyWith(
        loggingIn: false,
        error: mapAnyError(
          error,
          fallback: 'تعذر تسجيل الدخول إلى بوابة الشركات.',
        ),
      );
    }
  }

  /// يبدل الشركة النشطة مع حفظ التفضيل محلياً لاستخدامه بعد restart.
  Future<void> selectCompany(int companyId) async {
    final exists = state.memberships.any((item) => item.companyId == companyId);
    if (!exists) return;
    await _store.saveActiveCompanyId(companyId);
    state = state.copyWith(activeCompanyId: companyId, clearError: true);
  }

  /// يمسح جلسة البوابة بالكامل.
  Future<void> logout() async {
    await _store.clear();
    state = const CompanySessionState(bootstrapping: false);
  }

  /// يختار الشركة النشطة المخزنة إن كانت ما زالت ضمن العضويات، وإلا يرجع
  /// إلى أول عضوية صالحة لتفادي شاشة عالقة على company قد حذفت عضويتها.
  Future<int?> _resolveActiveCompanyId(List<CompanyMembership> memberships) async {
    if (memberships.isEmpty) return null;
    final saved = await _store.readActiveCompanyId();
    final match = memberships.where((item) => item.companyId == saved).firstOrNull;
    final effective = match?.companyId ?? memberships.first.companyId;
    await _store.saveActiveCompanyId(effective);
    return effective;
  }
}
