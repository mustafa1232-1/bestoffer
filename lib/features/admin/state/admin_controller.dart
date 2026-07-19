import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/admin_api.dart';
import '../models/admin_approval_inbox_item_model.dart';
import '../models/admin_audit_event_model.dart';
import '../models/managed_merchant_model.dart';
import '../models/pending_delivery_account_model.dart';
import '../models/pending_merchant_model.dart';
import '../models/pending_settlement_model.dart';
import '../models/pending_taxi_cash_payment_model.dart';
import '../models/pending_taxi_profile_edit_request_model.dart';
import '../models/period_metrics_model.dart';

final adminApiProvider = Provider<AdminApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return AdminApi(dio);
});

final adminControllerProvider =
    StateNotifierProvider<AdminController, AdminState>((ref) {
      return AdminController(ref);
    });

/// حالة الأدمن المركزية: KPIs، قوائم pending، صندوق الموافقات، وسجل التدقيق.
class AdminState {
  static const Object _sentinel = Object();

  final bool loading;
  final bool saving;
  final bool insightsLoading;
  final bool auditFeedLoadingMore;
  final PeriodMetricsModel day;
  final PeriodMetricsModel month;
  final PeriodMetricsModel year;
  final List<PendingMerchantModel> pendingMerchants;
  final List<PendingDeliveryAccountModel> pendingDeliveryAccounts;
  final List<PendingDeliveryAccountModel> pendingTaxiCaptainAccounts;
  final List<PendingSettlementModel> pendingSettlements;
  final List<PendingTaxiCashPaymentModel> pendingTaxiCashPayments;
  final List<Map<String, dynamic>> pendingServiceProviderSubscriptionRequests;
  final List<Map<String, dynamic>> pendingServiceOfferings;
  final List<PendingTaxiProfileEditRequestModel> pendingTaxiProfileEditRequests;
  final List<ManagedMerchantModel> managedMerchants;
  final List<AdminApprovalInboxItemModel> approvalInbox;
  final int approvalInboxTotal;
  final Map<String, int> approvalInboxCounts;
  final List<AdminAuditEventModel> auditFeed;
  final int? auditFeedNextCursor;
  final List<Map<String, dynamic>> customerInsights;
  final int customerInsightsTotal;
  final String customerInsightsQuery;
  final Map<String, dynamic> merchantsReceivablesV2;
  final Map<String, dynamic> competitionsV2;
  final Map<String, dynamic> platformKpisV2;
  final Map<String, dynamic> adminFinancialKpisV3;
  final String? error;
  final String? success;

  const AdminState({
    this.loading = false,
    this.saving = false,
    this.insightsLoading = false,
    this.auditFeedLoadingMore = false,
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
    this.pendingTaxiCaptainAccounts = const [],
    this.pendingSettlements = const [],
    this.pendingTaxiCashPayments = const [],
    this.pendingServiceProviderSubscriptionRequests = const [],
    this.pendingServiceOfferings = const [],
    this.pendingTaxiProfileEditRequests = const [],
    this.managedMerchants = const [],
    this.approvalInbox = const [],
    this.approvalInboxTotal = 0,
    this.approvalInboxCounts = const {},
    this.auditFeed = const [],
    this.auditFeedNextCursor,
    this.customerInsights = const [],
    this.customerInsightsTotal = 0,
    this.customerInsightsQuery = '',
    this.merchantsReceivablesV2 = const {},
    this.competitionsV2 = const {},
    this.platformKpisV2 = const {},
    this.adminFinancialKpisV3 = const {},
    this.error,
    this.success,
  });

  AdminState copyWith({
    bool? loading,
    bool? saving,
    bool? insightsLoading,
    bool? auditFeedLoadingMore,
    PeriodMetricsModel? day,
    PeriodMetricsModel? month,
    PeriodMetricsModel? year,
    List<PendingMerchantModel>? pendingMerchants,
    List<PendingDeliveryAccountModel>? pendingDeliveryAccounts,
    List<PendingDeliveryAccountModel>? pendingTaxiCaptainAccounts,
    List<PendingSettlementModel>? pendingSettlements,
    List<PendingTaxiCashPaymentModel>? pendingTaxiCashPayments,
    List<Map<String, dynamic>>? pendingServiceProviderSubscriptionRequests,
    List<Map<String, dynamic>>? pendingServiceOfferings,
    List<PendingTaxiProfileEditRequestModel>? pendingTaxiProfileEditRequests,
    List<ManagedMerchantModel>? managedMerchants,
    List<AdminApprovalInboxItemModel>? approvalInbox,
    int? approvalInboxTotal,
    Map<String, int>? approvalInboxCounts,
    List<AdminAuditEventModel>? auditFeed,
    Object? auditFeedNextCursor = _sentinel,
    List<Map<String, dynamic>>? customerInsights,
    int? customerInsightsTotal,
    String? customerInsightsQuery,
    Map<String, dynamic>? merchantsReceivablesV2,
    Map<String, dynamic>? competitionsV2,
    Map<String, dynamic>? platformKpisV2,
    Map<String, dynamic>? adminFinancialKpisV3,
    Object? error = _sentinel,
    Object? success = _sentinel,
  }) {
    return AdminState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      insightsLoading: insightsLoading ?? this.insightsLoading,
      auditFeedLoadingMore: auditFeedLoadingMore ?? this.auditFeedLoadingMore,
      day: day ?? this.day,
      month: month ?? this.month,
      year: year ?? this.year,
      pendingMerchants: pendingMerchants ?? this.pendingMerchants,
      pendingDeliveryAccounts:
          pendingDeliveryAccounts ?? this.pendingDeliveryAccounts,
      pendingTaxiCaptainAccounts:
          pendingTaxiCaptainAccounts ?? this.pendingTaxiCaptainAccounts,
      pendingSettlements: pendingSettlements ?? this.pendingSettlements,
      pendingTaxiCashPayments:
          pendingTaxiCashPayments ?? this.pendingTaxiCashPayments,
      pendingServiceProviderSubscriptionRequests:
          pendingServiceProviderSubscriptionRequests ??
          this.pendingServiceProviderSubscriptionRequests,
      pendingServiceOfferings:
          pendingServiceOfferings ?? this.pendingServiceOfferings,
      pendingTaxiProfileEditRequests:
          pendingTaxiProfileEditRequests ?? this.pendingTaxiProfileEditRequests,
      managedMerchants: managedMerchants ?? this.managedMerchants,
      approvalInbox: approvalInbox ?? this.approvalInbox,
      approvalInboxTotal: approvalInboxTotal ?? this.approvalInboxTotal,
      approvalInboxCounts: approvalInboxCounts ?? this.approvalInboxCounts,
      auditFeed: auditFeed ?? this.auditFeed,
      auditFeedNextCursor: auditFeedNextCursor == _sentinel
          ? this.auditFeedNextCursor
          : auditFeedNextCursor as int?,
      customerInsights: customerInsights ?? this.customerInsights,
      customerInsightsTotal:
          customerInsightsTotal ?? this.customerInsightsTotal,
      customerInsightsQuery:
          customerInsightsQuery ?? this.customerInsightsQuery,
      merchantsReceivablesV2:
          merchantsReceivablesV2 ?? this.merchantsReceivablesV2,
      competitionsV2: competitionsV2 ?? this.competitionsV2,
      platformKpisV2: platformKpisV2 ?? this.platformKpisV2,
      adminFinancialKpisV3: adminFinancialKpisV3 ?? this.adminFinancialKpisV3,
      error: error == _sentinel ? this.error : error as String?,
      success: success == _sentinel ? this.success : success as String?,
    );
  }
}

/// المتحكم المركزي للوحة الأدمن.
///
/// Critical notes:
/// - هذا الملف يجمع عدة مصادر بيانات إدارية في state واحدة لتقليل عدد
///   الشاشات التي تحتاج منطق bootstrap متكرر.
/// - عند mismatch بين شاشات الأدمن والقيم الحقيقية من الـ API ابدأ هنا.
class AdminController extends StateNotifier<AdminState> {
  final Ref ref;

  AdminController(this.ref) : super(const AdminState());

  /// يحمل snapshot إدارية موحدة لصفحة البداية وباقي تبويبات الأدمن.
  ///
  /// Maintenance notes:
  /// - بعض الطلبات هنا intentionally safe-wrapped حتى لا يكسر فشل جزئية
  ///   واحدة كامل لوحة الأدمن.
  Future<void> bootstrap() async {
    state = state.copyWith(
      loading: true,
      insightsLoading: false,
      auditFeedLoadingMore: false,
      error: null,
      success: null,
    );

    try {
      final api = ref.read(adminApiProvider);
      final authState = ref.read(authControllerProvider);
      final isAdmin = authState.isAdmin;
      final isSuperAdmin = authState.isSuperAdmin;

      final results = await Future.wait<dynamic>([
        _safeMap(
          () => api.analytics(),
          fallback: const {'day': {}, 'month': {}, 'year': {}},
        ),
        _safeList(() => api.pendingMerchants()),
        _safeList(() => api.pendingDeliveryAccounts()),
        _safeList(() => api.pendingTaxiCaptainAccounts()),
        _safeList(() => api.pendingSettlements()),
        if (isAdmin)
          _safeList(() => api.pendingTaxiCaptainCashPayments())
        else
          Future.value(const <dynamic>[]),
        if (isAdmin)
          _safeList(() => api.serviceProviderSubscriptionRequests(limit: 120))
        else
          Future.value(const <dynamic>[]),
        _safeMap(
          () => api.listPendingServiceOfferings(limit: 120, offset: 0),
          fallback: const <String, dynamic>{
            'items': <dynamic>[],
            'total': 0,
          },
        ),
        if (isAdmin)
          _safeList(() => api.pendingTaxiCaptainProfileEditRequests())
        else
          Future.value(const <dynamic>[]),
        _safeList(() => api.merchants()),
        _safeMap(
          () => api.approvalInbox(limit: 80),
          fallback: const <String, dynamic>{
            'items': <dynamic>[],
            'total': 0,
            'counts': <String, dynamic>{},
          },
        ),
        _safeMap(
          () => api.auditFeed(limit: 40),
          fallback: const <String, dynamic>{
            'items': <dynamic>[],
            'total': 0,
            'limit': 40,
          },
        ),
        if (isSuperAdmin)
          _safeMap(
            () => api.customerInsights(limit: 40),
            fallback: const <String, dynamic>{'items': <dynamic>[], 'total': 0},
          )
        else
          Future.value(null),
        _safeMap(
          () => api.merchantsReceivablesV2(limit: 120, offset: 0),
          fallback: const <String, dynamic>{'items': <dynamic>[], 'total': 0},
        ),
        _safeMap(
          () => api.competitionsV2(),
          fallback: const <String, dynamic>{'competitions': <dynamic>[]},
        ),
        _safeMap(
          () => api.platformKpisV2(period: 'all'),
          fallback: const <String, dynamic>{},
        ),
        _safeMap(
          () => api.adminFinancialKpis(period: 'all'),
          fallback: const <String, dynamic>{},
        ),
        _safeMap(
          () => api.adminReceivablesReport(period: 'all', limit: 1, offset: 0),
          fallback: const <String, dynamic>{'summary': <String, dynamic>{}},
        ),
      ]);

      final analytics = _asMap(results[0]);
      final pendingMerchantsRaw = _asList(results[1]);
      final pendingDeliveryRaw = _asList(results[2]);
      final pendingTaxiRaw = _asList(results[3]);
      final pendingSettlementsRaw = _asList(results[4]);
      final pendingTaxiCashRaw = _asList(results[5]);
      final pendingServiceSubscriptionsRaw = _toMapList(results[6])
          .where((row) {
            final status = '${row['status'] ?? ''}'.trim().toLowerCase();
            return status != 'account_created' &&
                status != 'rejected' &&
                status != 'cancelled';
          })
          .toList(growable: false);
      final pendingServiceOfferingsRaw = _toMapList(_asMap(results[7])['items'])
          .where((row) {
            final status = '${row['moderationStatus'] ?? row['moderation_status'] ?? ''}'
                .trim()
                .toLowerCase();
            return status == 'pending' || status == 'changes_requested';
          })
          .toList(growable: false);
      final pendingTaxiProfileEditRaw = _asList(results[8]);
      final merchantsRaw = _asList(results[9]);
      final approvalInboxRaw = _asMap(results[10]);
      final auditFeedRaw = _asMap(results[11]);
      final insightsRaw = (isSuperAdmin && results.length > 11)
          ? _asMap(results[12])
          : null;
      final merchantsReceivablesRaw = _asMap(results[13]);
      final competitionsRaw = _asMap(results[14]);
      final platformKpisRaw = _asMap(results[15]);
      final adminFinancialKpisRaw = _asMap(results[16]);
      final receivablesReportAllTimeRaw = _asMap(results[17]);
      final platformFinancialRaw = _asMap(platformKpisRaw['financial']);
      final receivablesAllTimeSummaryRaw = _asMap(
        receivablesReportAllTimeRaw['summary'],
      );
      final resolvedFinancialKpis =
          _asMap(adminFinancialKpisRaw['totals']).isNotEmpty
          ? adminFinancialKpisRaw
          : platformFinancialRaw.isNotEmpty
          ? <String, dynamic>{
              'window': const {'period': 'all'},
              'currency': platformFinancialRaw['currency'] ?? 'IQD',
              'totals': platformFinancialRaw,
            }
          : receivablesAllTimeSummaryRaw.isNotEmpty
          ? <String, dynamic>{
              'window': const {'period': 'all'},
              'currency': 'IQD',
              'totals': <String, dynamic>{
                'totalSales': receivablesAllTimeSummaryRaw['totalSales'] ?? 0,
                'totalCollected':
                    receivablesAllTimeSummaryRaw['totalCollected'] ?? 0,
                'netReceivables':
                    receivablesAllTimeSummaryRaw['netReceivables'] ?? 0,
                'outstandingToCollect':
                    receivablesAllTimeSummaryRaw['outstandingToCollect'] ?? 0,
                'totalSalesOrders': 0,
                'totalCollectionOperations': 0,
              },
            }
          : const <String, dynamic>{};

      state = state.copyWith(
        loading: false,
        insightsLoading: false,
        day: PeriodMetricsModel.fromJson(_asMap(analytics['day'])),
        month: PeriodMetricsModel.fromJson(_asMap(analytics['month'])),
        year: PeriodMetricsModel.fromJson(_asMap(analytics['year'])),
        pendingMerchants: pendingMerchantsRaw
            .map((e) => PendingMerchantModel.fromJson(_asMap(e)))
            .toList(growable: false),
        pendingDeliveryAccounts: pendingDeliveryRaw
            .map((e) => PendingDeliveryAccountModel.fromJson(_asMap(e)))
            .toList(growable: false),
        pendingTaxiCaptainAccounts: pendingTaxiRaw
            .map((e) => PendingDeliveryAccountModel.fromJson(_asMap(e)))
            .toList(growable: false),
        pendingSettlements: pendingSettlementsRaw
            .map((e) => PendingSettlementModel.fromJson(_asMap(e)))
            .toList(growable: false),
        pendingTaxiCashPayments: pendingTaxiCashRaw
            .map((e) => PendingTaxiCashPaymentModel.fromJson(_asMap(e)))
            .toList(growable: false),
        pendingServiceProviderSubscriptionRequests:
            pendingServiceSubscriptionsRaw,
        pendingServiceOfferings: pendingServiceOfferingsRaw,
        pendingTaxiProfileEditRequests: pendingTaxiProfileEditRaw
            .map((e) => PendingTaxiProfileEditRequestModel.fromJson(_asMap(e)))
            .toList(growable: false),
        managedMerchants: merchantsRaw
            .map((e) => ManagedMerchantModel.fromJson(_asMap(e)))
            .toList(growable: false),
        approvalInbox: _toApprovalInbox(approvalInboxRaw['items']),
        approvalInboxTotal: _readInt(approvalInboxRaw['total']),
        approvalInboxCounts: _toIntMap(approvalInboxRaw['counts']),
        auditFeed: _toAuditFeed(auditFeedRaw['items']),
        auditFeedNextCursor: _readNullableInt(auditFeedRaw['nextCursor']),
        customerInsights: _toMapList(insightsRaw?['items']),
        customerInsightsTotal: _readInt(insightsRaw?['total']),
        merchantsReceivablesV2: merchantsReceivablesRaw,
        competitionsV2: competitionsRaw,
        platformKpisV2: platformKpisRaw,
        adminFinancialKpisV3: resolvedFinancialKpis,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        loading: false,
        insightsLoading: false,
        auditFeedLoadingMore: false,
        error: _mapError(e),
      );
    } catch (_) {
      state = state.copyWith(
        loading: false,
        insightsLoading: false,
        auditFeedLoadingMore: false,
        error: _adminText('dashboard_load_failed'),
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
      state = state.copyWith(
        saving: false,
        success: _adminText('create_user_success'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('create_user_failed'),
      );
    }
  }

  Future<void> approveMerchant(
    int merchantId, {
    Map<String, dynamic>? body,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).approveMerchant(merchantId, body: body);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: _adminText('approve_merchant_terms_success'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('approve_merchant_terms_failed'),
      );
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
        success: _adminText(
          isDisabled ? 'merchant_disabled_success' : 'merchant_enabled_success',
        ),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('merchant_status_update_failed'),
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
        success: _adminText('settlement_approve_success'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('settlement_approve_failed'),
      );
    }
  }

  Future<void> approveDeliveryAccount(int deliveryUserId) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).approveDeliveryAccount(deliveryUserId);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: _adminText('delivery_account_approve_success'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('delivery_account_approve_failed'),
      );
    }
  }

  Future<void> approveTaxiCaptainAccount(int captainUserId) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).approveTaxiCaptainAccount(captainUserId);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: _adminText('taxi_captain_account_approve_success'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('taxi_captain_account_approve_failed'),
      );
    }
  }

  Future<void> updateDeliveryDriverProfile({
    required int deliveryUserId,
    required String driverType,
    int? merchantId,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .updateDeliveryDriverProfile(
            deliveryUserId: deliveryUserId,
            driverType: driverType,
            merchantId: merchantId,
          );
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: _adminText('delivery_type_update_success'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('delivery_type_update_failed'),
      );
    }
  }

  Future<void> confirmTaxiCaptainCashPayment(
    int captainUserId, {
    int cycleDays = 30,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .confirmTaxiCaptainCashPayment(captainUserId, cycleDays: cycleDays);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: _adminText('taxi_subscription_confirm_success'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('taxi_subscription_confirm_failed'),
      );
    }
  }

  Future<void> setTaxiCaptainDiscount(
    int captainUserId, {
    required int discountPercent,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .setTaxiCaptainDiscount(
            captainUserId,
            discountPercent: discountPercent,
          );
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: _adminText('taxi_subscription_discount_update_success'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('taxi_subscription_discount_update_failed'),
      );
    }
  }

  Future<void> approveTaxiCaptainProfileEditRequest(
    int requestId, {
    String? adminNote,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .approveTaxiCaptainProfileEditRequest(
            requestId,
            adminNote: adminNote,
          );
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: _adminText('taxi_profile_edit_approve_success'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('taxi_profile_edit_approve_failed'),
      );
    }
  }

  Future<void> rejectTaxiCaptainProfileEditRequest(
    int requestId, {
    String? adminNote,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .rejectTaxiCaptainProfileEditRequest(requestId, adminNote: adminNote);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        success: _adminText('taxi_profile_edit_reject_success'),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('taxi_profile_edit_reject_failed'),
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
        customerInsightsTotal: _readInt(raw['total']),
      );
    } on DioException catch (e) {
      state = state.copyWith(insightsLoading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        insightsLoading: false,
        error: _adminText('customer_insights_load_failed'),
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
      state = state.copyWith(error: _adminText('customer_details_load_failed'));
      return null;
    }
  }

  Future<void> loadMoreAuditFeed() async {
    final nextCursor = state.auditFeedNextCursor;
    if (state.auditFeedLoadingMore || nextCursor == null || nextCursor <= 0) {
      return;
    }

    state = state.copyWith(
      auditFeedLoadingMore: true,
      error: null,
      success: null,
    );

    try {
      final raw = await ref
          .read(adminApiProvider)
          .auditFeed(limit: 40, beforeId: nextCursor);
      final nextItems = _toAuditFeed(raw['items']);
      final merged = [...state.auditFeed, ...nextItems];
      state = state.copyWith(
        auditFeedLoadingMore: false,
        auditFeed: merged,
        auditFeedNextCursor: _readNullableInt(raw['nextCursor']),
      );
    } on DioException catch (e) {
      state = state.copyWith(auditFeedLoadingMore: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        auditFeedLoadingMore: false,
        error: _adminText('audit_feed_load_more_failed'),
      );
    }
  }

  Future<void> refreshMerchantsReceivablesV2({
    String? status,
    int limit = 120,
    int offset = 0,
  }) async {
    state = state.copyWith(loading: true, error: null, success: null);
    try {
      final raw = await ref
          .read(adminApiProvider)
          .merchantsReceivablesV2(status: status, limit: limit, offset: offset);
      state = state.copyWith(loading: false, merchantsReceivablesV2: raw);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: _adminText('receivables_load_failed'),
      );
    }
  }

  Future<Map<String, dynamic>?> fetchMerchantReceivablesDetailsV2(
    int merchantId,
  ) async {
    try {
      return await ref
          .read(adminApiProvider)
          .merchantReceivablesDetailsV2(merchantId);
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
      return null;
    } catch (_) {
      state = state.copyWith(
        error: _adminText('merchant_receivables_details_load_failed'),
      );
      return null;
    }
  }

  Future<bool> patchMerchantBillingProfileV2({
    required int merchantId,
    String? commissionType,
    double? commissionValue,
    double? commissionRate,
    String? commissionModel,
    double? monthlySubscriptionAmount,
    String? serviceFeeType,
    String? serviceFeeMode,
    double? serviceFeeValue,
    String? deliveryFeeMode,
    double? appDeliveryFeeValue,
    double? storeDeliveryFeeValue,
    double? deliveryFeeValue,
    bool? appDeliveryEnabled,
    bool? merchantDeliveryEnabled,
    String? settlementCycle,
    String? distributionPolicy,
    int? gracePeriodDays,
    String? effectiveFrom,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .patchMerchantBillingProfileV2(
            merchantId: merchantId,
            commissionType: commissionType,
            commissionValue: commissionValue,
            commissionRate: commissionRate,
            commissionModel: commissionModel,
            monthlySubscriptionAmount: monthlySubscriptionAmount,
            serviceFeeType: serviceFeeType,
            serviceFeeMode: serviceFeeMode,
            serviceFeeValue: serviceFeeValue,
            deliveryFeeMode: deliveryFeeMode,
            appDeliveryFeeValue: appDeliveryFeeValue,
            storeDeliveryFeeValue: storeDeliveryFeeValue,
            deliveryFeeValue: deliveryFeeValue,
            appDeliveryEnabled: appDeliveryEnabled,
            merchantDeliveryEnabled: merchantDeliveryEnabled,
            settlementCycle: settlementCycle,
            distributionPolicy: distributionPolicy,
            gracePeriodDays: gracePeriodDays,
            effectiveFrom: effectiveFrom,
          );
      await refreshMerchantsReceivablesV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('merchant_billing_update_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('merchant_billing_update_failed'),
      );
      return false;
    }
  }

  Future<bool> markPaymentRequestReceivedV2(
    int paymentRequestId, {
    String? reviewNote,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .markPaymentRequestReceivedV2(
            paymentRequestId,
            reviewNote: reviewNote,
          );
      await refreshMerchantsReceivablesV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('payment_received_approve_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('payment_received_approve_failed'),
      );
      return false;
    }
  }

  Future<bool> rejectPaymentRequestV2(
    int paymentRequestId, {
    String? reviewNote,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .rejectPaymentRequestV2(paymentRequestId, reviewNote: reviewNote);
      await refreshMerchantsReceivablesV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('payment_reject_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('payment_reject_failed'),
      );
      return false;
    }
  }

  Future<bool> approvePaymentRequestV2(
    int paymentRequestId, {
    String? reviewNote,
    String? internalAdminNote,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .approvePaymentRequestV2(
            paymentRequestId,
            reviewNote: reviewNote,
            internalAdminNote: internalAdminNote,
          );
      await refreshMerchantsReceivablesV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('payment_request_approve_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('payment_request_approve_failed'),
      );
      return false;
    }
  }

  Future<bool> assignPaymentRequestV2({
    required int paymentRequestId,
    int? assignedToUserId,
    String? assignedToName,
    String? reviewNote,
    String? internalAdminNote,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .assignPaymentRequestV2(
            paymentRequestId: paymentRequestId,
            assignedToUserId: assignedToUserId,
            assignedToName: assignedToName,
            reviewNote: reviewNote,
            internalAdminNote: internalAdminNote,
          );
      await refreshMerchantsReceivablesV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('payment_assign_executor_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('payment_assign_executor_failed'),
      );
      return false;
    }
  }

  Future<bool> markPaymentRequestPaidV2({
    required int paymentRequestId,
    double? paidAmount,
    String? paymentMethod,
    String? paymentDate,
    String? referenceCode,
    String? paymentActorName,
    int? assignedToUserId,
    String? assignedToName,
    String? reviewNote,
    String? internalAdminNote,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .markPaymentRequestPaidV2(
            paymentRequestId: paymentRequestId,
            paidAmount: paidAmount,
            paymentMethod: paymentMethod,
            paymentDate: paymentDate,
            referenceCode: referenceCode,
            paymentActorName: paymentActorName,
            assignedToUserId: assignedToUserId,
            assignedToName: assignedToName,
            reviewNote: reviewNote,
            internalAdminNote: internalAdminNote,
          );
      await refreshMerchantsReceivablesV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('payment_mark_paid_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('payment_mark_paid_failed'),
      );
      return false;
    }
  }

  Future<bool> returnPaymentRequestForRevisionV2(
    int paymentRequestId, {
    String? reviewNote,
    String? internalAdminNote,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .returnPaymentRequestForRevisionV2(
            paymentRequestId,
            reviewNote: reviewNote,
            internalAdminNote: internalAdminNote,
          );
      await refreshMerchantsReceivablesV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('payment_return_for_revision_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('payment_return_for_revision_failed'),
      );
      return false;
    }
  }

  Future<bool> createAppPayablesAdjustmentV2({
    required int merchantId,
    required double amount,
    required String direction,
    String entryType = 'adjustment',
    String? note,
    String? referenceCode,
    int? orderId,
  }) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref
          .read(adminApiProvider)
          .createAppPayablesAdjustmentV2(
            merchantId: merchantId,
            amount: amount,
            direction: direction,
            entryType: entryType,
            note: note,
            referenceCode: referenceCode,
            orderId: orderId,
          );
      await refreshMerchantsReceivablesV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('payables_adjustment_create_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('payables_adjustment_create_failed'),
      );
      return false;
    }
  }

  Future<void> refreshCompetitionsV2({
    bool activeOnly = false,
    String? status,
  }) async {
    try {
      final data = await ref
          .read(adminApiProvider)
          .competitionsV2(activeOnly: activeOnly, status: status);
      state = state.copyWith(competitionsV2: data);
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
    }
  }

  Future<bool> createCompetitionV2(Map<String, dynamic> body) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).createCompetitionV2(body);
      await refreshCompetitionsV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('competition_create_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('competition_create_failed'),
      );
      return false;
    }
  }

  Future<bool> patchCompetitionV2(
    int competitionId,
    Map<String, dynamic> body,
  ) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).patchCompetitionV2(competitionId, body);
      await refreshCompetitionsV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('competition_update_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('competition_update_failed'),
      );
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchCompetitionDetailsV2(
    int competitionId,
  ) async {
    try {
      return await ref
          .read(adminApiProvider)
          .competitionDetailsV2(competitionId);
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
      return null;
    } catch (_) {
      state = state.copyWith(
        error: _adminText('competition_details_load_failed'),
      );
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchCompetitionWinnersV2(
    int competitionId,
  ) async {
    try {
      return await ref
          .read(adminApiProvider)
          .competitionWinnersV2(competitionId);
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
      return null;
    } catch (_) {
      state = state.copyWith(
        error: _adminText('competition_winners_load_failed'),
      );
      return null;
    }
  }

  Future<bool> endCompetitionV2(int competitionId) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).endCompetitionV2(competitionId);
      await refreshCompetitionsV2(status: 'active');
      await refreshPlatformKpisV2();
      state = state.copyWith(
        saving: false,
        success: _adminText('competition_end_success'),
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _adminText('competition_end_failed'),
      );
      return false;
    }
  }

  Future<void> refreshPlatformKpisV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    try {
      final data = await ref
          .read(adminApiProvider)
          .platformKpisV2(period: period, from: from, to: to);
      state = state.copyWith(platformKpisV2: data);
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
    }
  }

  Future<void> refreshAdminFinancialKpisV3({
    String period = 'all',
    String? from,
    String? to,
  }) async {
    try {
      final data = await ref
          .read(adminApiProvider)
          .adminFinancialKpis(period: period, from: from, to: to);
      state = state.copyWith(adminFinancialKpisV3: _asMap(data));
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
    } catch (_) {
      state = state.copyWith(error: _adminText('financial_kpis_load_failed'));
    }
  }

  String _adminText(String code) {
    return resolveLocalizedText((l10n) {
      switch (code) {
        case 'dashboard_load_failed':
          return l10n.adminDashboardLoadFailed;
        case 'create_user_failed':
          return l10n.adminCreateUserFailed;
        case 'approve_merchant_terms_failed':
          return l10n.adminApproveMerchantTermsFailed;
        case 'merchant_status_update_failed':
          return l10n.adminMerchantStatusUpdateFailed;
        case 'settlement_approve_failed':
          return l10n.adminSettlementApproveFailed;
        case 'delivery_account_approve_failed':
          return l10n.adminDeliveryAccountApproveFailed;
        case 'taxi_captain_account_approve_failed':
          return l10n.adminTaxiCaptainAccountApproveFailed;
        case 'delivery_type_update_failed':
          return l10n.adminDeliveryTypeUpdateFailed;
        case 'taxi_subscription_confirm_failed':
          return l10n.adminTaxiSubscriptionConfirmFailed;
        case 'taxi_subscription_discount_update_failed':
          return l10n.adminTaxiSubscriptionDiscountUpdateFailed;
        case 'taxi_profile_edit_approve_failed':
          return l10n.adminTaxiProfileEditApproveFailed;
        case 'taxi_profile_edit_reject_failed':
          return l10n.adminTaxiProfileEditRejectFailed;
        case 'customer_insights_load_failed':
          return l10n.adminCustomerInsightsLoadFailed;
        case 'customer_details_load_failed':
          return l10n.adminCustomerInsightDetailsLoadFailed;
        case 'audit_feed_load_more_failed':
          return l10n.adminAuditFeedLoadMoreFailed;
        case 'receivables_load_failed':
          return l10n.adminReceivablesLoadFailed;
        case 'merchant_receivables_details_load_failed':
          return l10n.adminMerchantReceivablesDetailsLoadFailed;
        case 'merchant_billing_update_failed':
          return l10n.adminMerchantBillingSaveFailed;
        case 'payment_received_approve_failed':
          return l10n.adminPaymentReceivedApproveFailed;
        case 'payment_reject_failed':
          return l10n.adminPaymentRejectFailed;
        case 'payment_request_approve_failed':
          return l10n.adminPaymentApproveRequestFailed;
        case 'payment_assign_executor_failed':
          return l10n.adminPaymentAssignExecutorFailed;
        case 'payment_mark_paid_failed':
          return l10n.adminPaymentMarkPaidFailed;
        case 'payment_return_for_revision_failed':
          return l10n.adminPaymentReturnForRevisionFailed;
        case 'payables_adjustment_create_failed':
          return l10n.adminPayablesAdjustmentCreateFailed;
        case 'competition_create_failed':
          return l10n.adminCompetitionsCreateFailed;
        case 'competition_update_failed':
          return l10n.adminCompetitionsUpdateFailed;
        case 'competition_details_load_failed':
          return l10n.adminCompetitionDetailsLoadFailed;
        case 'competition_winners_load_failed':
          return l10n.adminCompetitionWinnersLoadFailed;
        case 'competition_end_failed':
          return l10n.adminCompetitionsEndFailed;
        case 'financial_kpis_load_failed':
          return l10n.adminFinancialKpisLoadFailed;
        case 'create_user_success':
          return l10n.adminCreateUserSuccess;
        case 'approve_merchant_terms_success':
          return l10n.adminApproveMerchantTermsSuccess;
        case 'merchant_disabled_success':
          return l10n.adminMerchantDisabledSuccess;
        case 'merchant_enabled_success':
          return l10n.adminMerchantEnabledSuccess;
        case 'settlement_approve_success':
          return l10n.adminSettlementApproveSuccess;
        case 'delivery_account_approve_success':
          return l10n.adminDeliveryAccountApproveSuccess;
        case 'taxi_captain_account_approve_success':
          return l10n.adminTaxiCaptainAccountApproveSuccess;
        case 'delivery_type_update_success':
          return l10n.adminDeliveryTypeUpdateSuccess;
        case 'taxi_subscription_confirm_success':
          return l10n.adminTaxiSubscriptionConfirmSuccess;
        case 'taxi_subscription_discount_update_success':
          return l10n.adminTaxiSubscriptionDiscountUpdateSuccess;
        case 'taxi_profile_edit_approve_success':
          return l10n.adminTaxiProfileEditApproveSuccess;
        case 'taxi_profile_edit_reject_success':
          return l10n.adminTaxiProfileEditRejectSuccess;
        case 'merchant_billing_update_success':
          return l10n.adminMerchantBillingSaveSuccess;
        case 'payment_received_approve_success':
          return l10n.adminPaymentReceivedApproveSuccess;
        case 'payment_reject_success':
          return l10n.adminPaymentRejectSuccess;
        case 'payment_request_approve_success':
          return l10n.adminPaymentApproveRequestSuccess;
        case 'payment_assign_executor_success':
          return l10n.adminPaymentAssignExecutorSuccess;
        case 'payment_mark_paid_success':
          return l10n.adminPaymentMarkPaidSuccess;
        case 'payment_return_for_revision_success':
          return l10n.adminPaymentReturnForRevisionSuccess;
        case 'payables_adjustment_create_success':
          return l10n.adminPayablesAdjustmentCreateSuccess;
        case 'competition_create_success':
          return l10n.adminCompetitionsCreateSuccess;
        case 'competition_update_success':
          return l10n.adminCompetitionsUpdateSuccess;
        case 'competition_end_success':
          return l10n.adminCompetitionsEndSuccess;
        default:
          return l10n.commonUnexpectedError;
      }
    });
  }

  String _mapError(DioException e) {
    return mapDioErrorL10n(
      e,
      fallbackBuilder: (l10n) => l10n.errorsServerFailure,
      appendRequestId: true,
    );
  }

  Future<List<dynamic>> _safeList(
    Future<List<dynamic>> Function() run, {
    List<dynamic> fallback = const <dynamic>[],
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await run();
      } catch (error) {
        if (attempt == 0 && _isTransientFetchError(error)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        return fallback;
      }
    }
    return fallback;
  }

  Future<Map<String, dynamic>> _safeMap(
    Future<Map<String, dynamic>> Function() run, {
    Map<String, dynamic> fallback = const <String, dynamic>{},
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await run();
      } catch (error) {
        if (attempt == 0 && _isTransientFetchError(error)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        return fallback;
      }
    }
    return fallback;
  }

  bool _isTransientFetchError(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401 || statusCode == 403 || statusCode == 408) {
        return true;
      }
      final data = error.response?.data;
      if (data is Map) {
        final message = '${data['message'] ?? data['error'] ?? ''}'
            .trim()
            .toUpperCase();
        return message.contains('INVALID_TOKEN') ||
            message.contains('TOKEN_EXPIRED') ||
            message.contains('UNAUTHORIZED') ||
            message.contains('SESSION');
      }
    }
    return false;
  }

  List<dynamic> _asList(dynamic raw) {
    if (raw is List) return raw;
    if (raw is Map && raw['items'] is List) {
      return List<dynamic>.from(raw['items'] as List);
    }
    return const <dynamic>[];
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _toMapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(_asMap).toList(growable: false);
  }

  List<AdminApprovalInboxItemModel> _toApprovalInbox(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => AdminApprovalInboxItemModel.fromJson(_asMap(e)))
        .toList(growable: false);
  }

  List<AdminAuditEventModel> _toAuditFeed(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => AdminAuditEventModel.fromJson(_asMap(e)))
        .toList(growable: false);
  }

  Map<String, int> _toIntMap(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, int>{};
    for (final entry in raw.entries) {
      result['${entry.key}'] = _readInt(entry.value);
    }
    return result;
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  int? _readNullableInt(dynamic value) {
    if (value == null) return null;
    final parsed = _readInt(value);
    return parsed > 0 ? parsed : null;
  }
}
