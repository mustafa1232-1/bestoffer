import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../auth/state/auth_controller.dart';
import '../data/admin_api.dart';
import '../models/managed_merchant_model.dart';
import '../models/pending_delivery_account_model.dart';
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
  final bool insightsLoading;
  final PeriodMetricsModel day;
  final PeriodMetricsModel month;
  final PeriodMetricsModel year;
  final List<PendingMerchantModel> pendingMerchants;
  final List<PendingDeliveryAccountModel> pendingDeliveryAccounts;
  final List<PendingSettlementModel> pendingSettlements;
  final List<ManagedMerchantModel> managedMerchants;
  final List<Map<String, dynamic>> customerInsights;
  final int customerInsightsTotal;
  final String customerInsightsQuery;
  final String? error;
  final String? success;

  const AdminState({
    this.loading = false,
    this.saving = false,
    this.insightsLoading = false,
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
    this.pendingDeliveryAccounts = const [],
    this.pendingSettlements = const [],
    this.managedMerchants = const [],
    this.customerInsights = const [],
    this.customerInsightsTotal = 0,
    this.customerInsightsQuery = '',
    this.error,
    this.success,
  });

  AdminState copyWith({
    bool? loading,
    bool? saving,
    bool? insightsLoading,
    PeriodMetricsModel? day,
    PeriodMetricsModel? month,
    PeriodMetricsModel? year,
    List<PendingMerchantModel>? pendingMerchants,
    List<PendingDeliveryAccountModel>? pendingDeliveryAccounts,
    List<PendingSettlementModel>? pendingSettlements,
    List<ManagedMerchantModel>? managedMerchants,
    List<Map<String, dynamic>>? customerInsights,
    int? customerInsightsTotal,
    String? customerInsightsQuery,
    String? error,
    String? success,
  }) {
    return AdminState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      insightsLoading: insightsLoading ?? this.insightsLoading,
      day: day ?? this.day,
      month: month ?? this.month,
      year: year ?? this.year,
      pendingMerchants: pendingMerchants ?? this.pendingMerchants,
      pendingDeliveryAccounts:
          pendingDeliveryAccounts ?? this.pendingDeliveryAccounts,
      pendingSettlements: pendingSettlements ?? this.pendingSettlements,
      managedMerchants: managedMerchants ?? this.managedMerchants,
      customerInsights: customerInsights ?? this.customerInsights,
      customerInsightsTotal:
          customerInsightsTotal ?? this.customerInsightsTotal,
      customerInsightsQuery:
          customerInsightsQuery ?? this.customerInsightsQuery,
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
      final isSuperAdmin = ref.read(authControllerProvider).isSuperAdmin;
      final analytics = await ref.read(adminApiProvider).analytics();
      final pendingMerchantsRaw = await ref
          .read(adminApiProvider)
          .pendingMerchants();
      final pendingDeliveryRaw = await ref
          .read(adminApiProvider)
          .pendingDeliveryAccounts();
      final pendingSettlementsRaw = await ref
          .read(adminApiProvider)
          .pendingSettlements();
      final merchantsRaw = await ref.read(adminApiProvider).merchants();
      Map<String, dynamic>? insightsRaw;
      if (isSuperAdmin) {
        insightsRaw = await ref
            .read(adminApiProvider)
            .customerInsights(limit: 40);
      }

      state = state.copyWith(
        loading: false,
        insightsLoading: false,
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
        pendingDeliveryAccounts: pendingDeliveryRaw
            .map(
              (e) => PendingDeliveryAccountModel.fromJson(
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
        customerInsights: _toMapList(insightsRaw?['items']),
        customerInsightsTotal: _readInsightTotal(insightsRaw),
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
          .toggleMerchantDisabled(
            merchantId: merchantId,
            isDisabled: isDisabled,
          );
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: isDisabled ? 'تم تعطيل المتجر' : 'تم تفعيل المتجر',
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل تحديث حالة المتجر');
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

  Future<void> approveDeliveryAccount(int deliveryUserId) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).approveDeliveryAccount(deliveryUserId);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: 'تمت الموافقة على حساب كابتن التكسي',
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: 'فشل الموافقة على حساب كابتن التكسي',
      );
    }
  }

  Future<void> searchCustomerInsights(String query) async {
    final isSuperAdmin = ref.read(authControllerProvider).isSuperAdmin;
    if (!isSuperAdmin) return;

    state = state.copyWith(
      insightsLoading: true,
      customerInsightsQuery: query.trim(),
      error: null,
      success: null,
    );

    try {
      final raw = await ref
          .read(adminApiProvider)
          .customerInsights(
            search: query.trim().isEmpty ? null : query.trim(),
            limit: 80,
          );
      state = state.copyWith(
        insightsLoading: false,
        customerInsights: _toMapList(raw['items']),
        customerInsightsTotal: _readInsightTotal(raw),
      );
    } on DioException catch (e) {
      state = state.copyWith(insightsLoading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        insightsLoading: false,
        error: 'تعذر تحميل ملفات العملاء',
      );
    }
  }

  Future<Map<String, dynamic>?> fetchCustomerInsightDetails(
    int customerUserId,
  ) async {
    final isSuperAdmin = ref.read(authControllerProvider).isSuperAdmin;
    if (!isSuperAdmin) return null;

    try {
      return await ref
          .read(adminApiProvider)
          .customerInsightDetails(customerUserId);
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
      return null;
    } catch (_) {
      state = state.copyWith(error: 'تعذر تحميل تفاصيل العميل');
      return null;
    }
  }

  String _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return 'حدث خطأ في الاتصال بالخادم';
  }

  List<Map<String, dynamic>> _toMapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  int _readInsightTotal(Map<String, dynamic>? raw) {
    if (raw == null) return 0;
    final value = raw['total'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
