import 'package:dio/dio.dart';

import '../models/company_models.dart';

class CompanyApi {
  final Dio _dio;

  CompanyApi(this._dio);

  Options _scope(int companyId) => Options(headers: {'X-Company-Id': companyId});

  Future<CompanyPortalLoginResult> login({
    required String phone,
    required String pin,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/company/auth/login',
      data: {'phone': phone, 'pin': pin},
    );
    return CompanyPortalLoginResult.fromJson(response.data ?? const {});
  }

  Future<CompanyPortalBootstrap> bootstrap() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/company/auth/bootstrap',
    );
    return CompanyPortalBootstrap.fromJson(response.data ?? const {});
  }

  Future<CompanyHomeData> dashboard(int companyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/company/dashboard',
      options: _scope(companyId),
    );
    return CompanyHomeData.fromJson(response.data ?? const {});
  }

  Future<List<CompanyBranch>> branches(int companyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/company/branches',
      options: _scope(companyId),
    );
    final rows = (response.data?['branches'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CompanyBranch.fromJson)
        .toList();
    return rows;
  }

  Future<CompanyBranchDetail> branchDetail(int companyId, int merchantId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/company/branches/$merchantId',
      options: _scope(companyId),
    );
    return CompanyBranchDetail.fromJson(response.data ?? const {});
  }

  Future<List<CompanyUserRecord>> users(int companyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/company/users',
      options: _scope(companyId),
    );
    return (response.data?['users'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CompanyUserRecord.fromJson)
        .toList();
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
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/company/inventory/overview',
      options: _scope(companyId),
    );
    return CompanyInventoryOverview.fromJson(response.data ?? const {});
  }

  Future<CompanyBranchDetail> branchInventory(int companyId, int merchantId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/company/inventory/branches/$merchantId',
      options: _scope(companyId),
    );
    final body = response.data ?? const {};
    return CompanyBranchDetail(
      branch: CompanyBranch.fromJson({'id': merchantId}),
      inventorySettings: body['settings'] == null
          ? null
          : CompanyInventorySettings.fromJson(
              Map<String, dynamic>.from(body['settings'] as Map),
            ),
      inventoryItems: (body['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CompanyInventoryItem.fromJson)
          .toList(),
      products: (body['products'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
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
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/company/coupons',
      options: _scope(companyId),
    );
    return (response.data?['coupons'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CompanyCoupon.fromJson)
        .toList();
  }

  Future<void> createCoupon(int companyId, Map<String, dynamic> body) async {
    await _dio.post(
      '/api/company/coupons',
      options: _scope(companyId),
      data: body,
    );
  }

  Future<List<CompanyCampaign>> campaigns(int companyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/company/campaigns',
      options: _scope(companyId),
    );
    return (response.data?['campaigns'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CompanyCampaign.fromJson)
        .toList();
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
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/company/branches/requests',
      options: _scope(companyId),
      data: body,
    );
    return CompanyBranchRequest.fromJson(
      (response.data?['request'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Future<List<CompanyBranchRequest>> branchRequests(int companyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/company/branch-requests',
      options: _scope(companyId),
    );
    return (response.data?['requests'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CompanyBranchRequest.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> copyProducts(
    int companyId,
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/company/products/copy',
      options: _scope(companyId),
      data: body,
    );
    return response.data ?? const {};
  }

  Future<CompanyPolicy> updatePolicy(
    int companyId,
    Map<String, dynamic> patch,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/company/settings/policy',
      options: _scope(companyId),
      data: patch,
    );
    return CompanyPolicy.fromJson(
      (response.data?['defaultPolicy'] as Map?)?.cast<String, dynamic>() ??
          const {},
    );
  }
}
