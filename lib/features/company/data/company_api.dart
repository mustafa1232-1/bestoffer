import 'package:dio/dio.dart';

import '../../orders/models/order_model.dart';
import '../models/company_models.dart';

class CompanyApi {
  final Dio _dio;

  CompanyApi(this._dio);

  Options _scope(int companyId) =>
      Options(headers: {'X-Company-Id': companyId});

  Future<CompanyPortalLoginResult> login({
    required String phone,
    required String pin,
  }) async {
    final response = await _dio.post<dynamic>(
      '/api/company/auth/login',
      data: {'phone': phone, 'pin': pin},
    );
    return CompanyPortalLoginResult.fromJson(_responseMap(response.data));
  }

  Future<CompanyPortalBootstrap> bootstrap() async {
    final response = await _dio.get<dynamic>('/api/company/auth/bootstrap');
    return CompanyPortalBootstrap.fromJson(_responseMap(response.data));
  }

  Future<CompanyHomeData> dashboard(int companyId) async {
    final response = await _dio.get<dynamic>(
      '/api/company/dashboard',
      options: _scope(companyId),
    );
    return CompanyHomeData.fromJson(_responseMap(response.data));
  }

  Future<List<CompanyBranch>> branches(int companyId) async {
    final response = await _dio.get<dynamic>(
      '/api/company/branches',
      options: _scope(companyId),
    );
    final body = _responseMap(response.data);
    final rows = _mapList(
      body['branches'],
    ).map(CompanyBranch.fromJson).toList();
    return rows;
  }

  Future<CompanyBranchDetail> branchDetail(
    int companyId,
    int merchantId,
  ) async {
    final response = await _dio.get<dynamic>(
      '/api/company/branches/$merchantId',
      options: _scope(companyId),
    );
    return CompanyBranchDetail.fromJson(_responseMap(response.data));
  }

  Future<List<OrderModel>> currentOrders(
    int companyId, {
    int? merchantId,
  }) async {
    final queryParameters = <String, dynamic>{};
    if (merchantId != null) {
      queryParameters['merchantId'] = merchantId;
    }
    final response = await _dio.get<dynamic>(
      '/api/company/orders/current',
      queryParameters: queryParameters,
      options: _scope(companyId),
    );
    final rows = _responseMap(response.data)['orders'];
    return _mapList(rows).map(OrderModel.fromJson).toList();
  }

  Future<void> updateOrderStatus(
    int companyId,
    int orderId, {
    required String status,
    int? estimatedPrepMinutes,
    int? estimatedDeliveryMinutes,
  }) async {
    final data = <String, dynamic>{'status': status};
    if (estimatedPrepMinutes != null) {
      data['estimatedPrepMinutes'] = estimatedPrepMinutes;
    }
    if (estimatedDeliveryMinutes != null) {
      data['estimatedDeliveryMinutes'] = estimatedDeliveryMinutes;
    }
    await _dio.patch(
      '/api/company/orders/$orderId/status',
      options: _scope(companyId),
      data: data,
    );
  }

  Future<List<CompanyUserRecord>> users(int companyId) async {
    final response = await _dio.get<dynamic>(
      '/api/company/users',
      options: _scope(companyId),
    );
    return _mapList(
      _responseMap(response.data)['users'],
    ).map(CompanyUserRecord.fromJson).toList();
  }

  Future<void> createUser(
    int companyId, {
    required String fullName,
    required String phone,
    required String pin,
    required String role,
    String? workTitle,
    String? workCompany,
  }) async {
    await _dio.post(
      '/api/company/users',
      options: _scope(companyId),
      data: {
        'fullName': fullName,
        'phone': phone,
        'pin': pin,
        'role': role,
        'workTitle': workTitle,
        'workCompany': workCompany,
      },
    );
  }

  Future<CompanyInventoryOverview> inventoryOverview(int companyId) async {
    final response = await _dio.get<dynamic>(
      '/api/company/inventory/overview',
      options: _scope(companyId),
    );
    return CompanyInventoryOverview.fromJson(_responseMap(response.data));
  }

  Future<CompanyBranchDetail> branchInventory(
    int companyId,
    int merchantId,
  ) async {
    final response = await _dio.get<dynamic>(
      '/api/company/inventory/branches/$merchantId',
      options: _scope(companyId),
    );
    final body = _responseMap(response.data);
    return CompanyBranchDetail(
      branch: CompanyBranch.fromJson({'id': merchantId}),
      inventorySettings: body['settings'] == null
          ? null
          : CompanyInventorySettings.fromJson(
              Map<String, dynamic>.from(body['settings'] as Map),
            ),
      inventoryItems: _mapList(
        body['items'],
      ).map(CompanyInventoryItem.fromJson).toList(),
      products: _mapList(body['products']),
      categories: const [],
    );
  }

  Future<void> updateInventorySettings(
    int companyId,
    int merchantId,
    Map<String, dynamic> patch,
  ) async {
    await _dio.patch(
      '/api/company/inventory/branches/$merchantId/settings',
      options: _scope(companyId),
      data: patch,
    );
  }

  Future<void> patchInventoryItem(
    int companyId,
    int merchantId,
    int productId,
    Map<String, dynamic> patch,
  ) async {
    await _dio.patch(
      '/api/company/inventory/branches/$merchantId/items/$productId',
      options: _scope(companyId),
      data: patch,
    );
  }

  Future<void> confirmDailyCheck(
    int companyId,
    int merchantId, {
    String? note,
  }) async {
    await _dio.post(
      '/api/company/inventory/branches/$merchantId/daily-check',
      options: _scope(companyId),
      data: {'note': note},
    );
  }

  Future<List<CompanyCoupon>> coupons(int companyId) async {
    final response = await _dio.get<dynamic>(
      '/api/company/coupons',
      options: _scope(companyId),
    );
    return _mapList(
      _responseMap(response.data)['coupons'],
    ).map(CompanyCoupon.fromJson).toList();
  }

  Future<void> createCoupon(int companyId, Map<String, dynamic> body) async {
    await _dio.post(
      '/api/company/coupons',
      options: _scope(companyId),
      data: body,
    );
  }

  Future<List<CompanyCampaign>> campaigns(int companyId) async {
    final response = await _dio.get<dynamic>(
      '/api/company/campaigns',
      options: _scope(companyId),
    );
    return _mapList(
      _responseMap(response.data)['campaigns'],
    ).map(CompanyCampaign.fromJson).toList();
  }

  Future<void> createCampaign(int companyId, Map<String, dynamic> body) async {
    await _dio.post(
      '/api/company/campaigns',
      options: _scope(companyId),
      data: body,
    );
  }

  Future<CompanyBranchRequest> createBranchRequest(
    int companyId,
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.post<dynamic>(
      '/api/company/branches/requests',
      options: _scope(companyId),
      data: body,
    );
    return CompanyBranchRequest.fromJson(
      _mapValue(_responseMap(response.data)['request']),
    );
  }

  Future<List<CompanyBranchRequest>> branchRequests(int companyId) async {
    final response = await _dio.get<dynamic>(
      '/api/company/branch-requests',
      options: _scope(companyId),
    );
    return _mapList(
      _responseMap(response.data)['requests'],
    ).map(CompanyBranchRequest.fromJson).toList();
  }

  Future<Map<String, dynamic>> copyProducts(
    int companyId,
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.post<dynamic>(
      '/api/company/products/copy',
      options: _scope(companyId),
      data: body,
    );
    return _responseMap(response.data);
  }

  Future<CompanyPolicy> updatePolicy(
    int companyId,
    Map<String, dynamic> patch,
  ) async {
    final response = await _dio.patch<dynamic>(
      '/api/company/settings/policy',
      options: _scope(companyId),
      data: patch,
    );
    return CompanyPolicy.fromJson(
      _mapValue(_responseMap(response.data)['defaultPolicy']),
    );
  }
}

Map<String, dynamic> _responseMap(dynamic value) => _mapValue(value);

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value.map(_mapValue).toList(growable: false);
}

Map<String, dynamic> _mapValue(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }
  return const <String, dynamic>{};
}
