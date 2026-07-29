import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';

final couponsApiProvider = Provider<CouponsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return CouponsApi(dio);
});

class CouponsApi {
  final Dio dio;

  CouponsApi(this.dio);

  Future<List<Map<String, dynamic>>> listCoupons({
    bool activeOnly = false,
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/coupons',
      queryParameters: {
        'activeOnly': activeOnly,
        'limit': limit,
        'offset': offset,
      },
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['coupons'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listMyCoupons({
    int? merchantId,
    int limit = 80,
  }) async {
    final response = await dio.get(
      '/api/coupons/mine',
      queryParameters: {
        if (merchantId != null && merchantId > 0) 'merchantId': merchantId,
        'limit': limit,
      },
    );
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['coupons'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> getCouponStats({
    int? merchantId,
    bool includeGlobal = true,
    int days = 30,
  }) async {
    final response = await dio.get(
      '/api/coupons/stats',
      queryParameters: {
        if (merchantId != null && merchantId > 0) 'merchantId': merchantId,
        'includeGlobal': includeGlobal,
        'days': days,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createCoupon(Map<String, dynamic> body) async {
    final response = await dio.post('/api/coupons', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> toggleCouponActive({
    required int couponId,
    required bool isActive,
  }) async {
    await dio.patch(
      '/api/coupons/$couponId/active',
      data: {'isActive': isActive},
    );
  }

  Future<void> deleteCoupon(int couponId) async {
    await dio.delete('/api/coupons/$couponId');
  }

  // ── Employee referral / sales-attribution coupons ──────────────────────────

  /// Super-admin report: coupons grouped by employee with attribution stats.
  Future<List<Map<String, dynamic>>> listAgentReferralCoupons() async {
    final response = await dio.get('/api/coupons/agents');
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['agents'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// The customers/orders that used a specific agent coupon.
  Future<List<Map<String, dynamic>>> getAgentCouponRedemptions(
    int couponId,
  ) async {
    final response = await dio.get('/api/coupons/$couponId/redemptions');
    final map = Map<String, dynamic>.from(response.data as Map);
    final raw = map['redemptions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// Admin edits the discount on a coupon (e.g. attach 5%/10%/fixed, or 0).
  Future<void> updateCouponDiscount({
    required int couponId,
    required String discountType, // 'percent' | 'fixed'
    required num discountValue,
  }) async {
    await dio.patch(
      '/api/coupons/$couponId/discount',
      data: {'discountType': discountType, 'discountValue': discountValue},
    );
  }
}
