import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../auth/state/auth_controller.dart';
import '../data/admin_api.dart';
import '../models/managed_merchant_model.dart';
import '../models/pending_merchant_model.dart';
import '../models/pending_settlement_model.dart';
import '../models/period_metrics_model.dart';

final adminApiProvider = Provider<AdminApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return AdminApi(dio);
});

final adminControllerProvider =
    StateNotifierProvider<AdminController, AdminState>((ref) {
      return AdminController(ref);
    });

class AdminState {
  final bool loading;
  final bool saving;
  final PeriodMetricsModel day;
  final PeriodMetricsModel month;
  final PeriodMetricsModel year;
  final List<PendingMerchantModel> pendingMerchants;
  final List<PendingSettlementModel> pendingSettlements;
  final List<ManagedMerchantModel> managedMerchants;
  final String? error;
  final String? success;

  const AdminState({
    this.loading = false,
    this.saving = false,
    this.day = const PeriodMetricsModel(
      ordersCount: 0,
      deliveredOrdersCount: 0,
      cancelledOrdersCount: 0,
      deliveryFees: 0,
      totalAmount: 0,
      appFees: 0,
      avgDeliveryRating: 0,
      avgMerchantRating: 0,
    ),
    this.month = const PeriodMetricsModel(
      ordersCount: 0,
      deliveredOrdersCount: 0,
      cancelledOrdersCount: 0,
      deliveryFees: 0,
      totalAmount: 0,
      appFees: 0,
      avgDeliveryRating: 0,
      avgMerchantRating: 0,
    ),
    this.year = const PeriodMetricsModel(
      ordersCount: 0,
      deliveredOrdersCount: 0,
      cancelledOrdersCount: 0,
      deliveryFees: 0,
      totalAmount: 0,
      appFees: 0,
      avgDeliveryRating: 0,
      avgMerchantRating: 0,
    ),
    this.pendingMerchants = const [],
    this.pendingSettlements = const [],
    this.managedMerchants = const [],
    this.error,
    this.success,
  });

  AdminState copyWith({
    bool? loading,
    bool? saving,
    PeriodMetricsModel? day,
    PeriodMetricsModel? month,
    PeriodMetricsModel? year,
    List<PendingMerchantModel>? pendingMerchants,
    List<PendingSettlementModel>? pendingSettlements,
    List<ManagedMerchantModel>? managedMerchants,
    String? error,
    String? success,
  }) {
    return AdminState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      day: day ?? this.day,
      month: month ?? this.month,
      year: year ?? this.year,
      pendingMerchants: pendingMerchants ?? this.pendingMerchants,
      pendingSettlements: pendingSettlements ?? this.pendingSettlements,
      managedMerchants: managedMerchants ?? this.managedMerchants,
      error: error,
      success: success,
    );
  }
}

class AdminController extends StateNotifier<AdminState> {
  final Ref ref;

  AdminController(this.ref) : super(const AdminState());

  Future<void> bootstrap() async {
    state = state.copyWith(loading: true, error: null, success: null);
    try {
      final analytics = await ref.read(adminApiProvider).analytics();
      final pendingMerchantsRaw = await ref
          .read(adminApiProvider)
          .pendingMerchants();
      final pendingSettlementsRaw = await ref
          .read(adminApiProvider)
          .pendingSettlements();
      final merchantsRaw = await ref.read(adminApiProvider).merchants();

      state = state.copyWith(
        loading: false,
        day: PeriodMetricsModel.fromJson(
          Map<String, dynamic>.from(analytics['day'] as Map),
        ),
        month: PeriodMetricsModel.fromJson(
          Map<String, dynamic>.from(analytics['month'] as Map),
        ),
        year: PeriodMetricsModel.fromJson(
          Map<String, dynamic>.from(analytics['year'] as Map),
        ),
        pendingMerchants: pendingMerchantsRaw
            .map(
              (e) => PendingMerchantModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        pendingSettlements: pendingSettlementsRaw
            .map(
              (e) => PendingSettlementModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        managedMerchants: merchantsRaw
            .map(
              (e) => ManagedMerchantModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'فشل تحميل بيانات لوحة التحكم',
      );
    }
  }

  Future<void> createUser(
    Map<String, dynamic> dto, {
    LocalImageFile? imageFile,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).createUser(dto, imageFile: imageFile);
      await bootstrap();
      state = state.copyWith(saving: false, success: 'تم إنشاء الحساب بنجاح');
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل إنشاء الحساب');
    }
  }

  Future<void> approveMerchant(int merchantId) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).approveMerchant(merchantId);
      await bootstrap();
      state = state.copyWith(saving: false, success: 'تمت الموافقة على المتجر');
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل الموافقة على المتجر');
    }
  }

  Future<void> toggleMerchantDisabled({
    required int merchantId,
    required bool isDisabled,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .toggleMerchantDisabled(merchantId: merchantId, isDisabled: isDisabled);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: isDisabled ? 'تم تعطيل المتجر' : 'تم تفعيل المتجر',
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: 'فشل تحديث حالة المتجر',
      );
    }
  }

  Future<void> approveSettlement(int settlementId, {String? note}) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .approveSettlement(settlementId, adminNote: note?.trim());
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: 'تمت المصادقة على التسديد',
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل المصادقة على التسديد');
    }
  }

  String _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    return 'حدث خطأ في الاتصال بالخادم';
  }
}
