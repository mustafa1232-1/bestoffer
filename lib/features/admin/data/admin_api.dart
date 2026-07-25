import 'package:dio/dio.dart';

import '../../../core/files/local_image_file.dart';

class AdminApi {
  final Dio dio;

  AdminApi(this.dio);

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  Map<String, dynamic> _buildFinancialWindowQuery({
    required String period,
    String? from,
    String? to,
  }) {
    final normalized = period.trim().toLowerCase();
    final safeFrom = (from ?? '').trim();
    final safeTo = (to ?? '').trim();
    if (normalized == 'all') {
      return <String, dynamic>{
        'period': 'custom',
        'from': safeFrom.isNotEmpty ? safeFrom : '1970-01-01T00:00:00.000Z',
        'to': safeTo.isNotEmpty
            ? safeTo
            : DateTime.now().toUtc().toIso8601String(),
      };
    }
    final query = <String, dynamic>{'period': normalized};
    if (safeFrom.isNotEmpty) query['from'] = safeFrom;
    if (safeTo.isNotEmpty) query['to'] = safeTo;
    return query;
  }

  Future<Map<String, dynamic>> analytics() async {
    try {
      final response = await dio.get('/api/admin/analytics');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      return const {'day': {}, 'month': {}, 'year': {}};
    }
  }

  Future<Map<String, dynamic>> approvalInbox({int limit = 60}) async {
    try {
      final response = await dio.get(
        '/api/admin/approval-inbox',
        queryParameters: {'limit': limit},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      return {
        'items': const <dynamic>[],
        'total': 0,
        'counts': const <String, dynamic>{},
        'limit': limit,
      };
    }
  }

  Future<Map<String, dynamic>> auditFeed({
    int limit = 40,
    int? beforeId,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (beforeId != null) {
      queryParameters['beforeId'] = beforeId;
    }

    try {
      final response = await dio.get(
        '/api/admin/audit-feed',
        queryParameters: queryParameters,
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      return {
        'items': const <dynamic>[],
        'total': 0,
        'limit': limit,
        'beforeId': beforeId,
      };
    }
  }

  Future<List<dynamic>> ordersPrintReport({required String period}) async {
    final response = await dio.get(
      '/api/admin/orders/print-report',
      queryParameters: {'period': period},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> ordersOverview({
    String status = 'all',
    String period = 'all',
    String? from,
    String? to,
    String? search,
    int limit = 60,
    int offset = 0,
  }) async {
    final query = {
      'status': status,
      ..._buildFinancialWindowQuery(period: period, from: from, to: to),
      if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
      'limit': limit,
      'offset': offset,
    };
    try {
      final response = await dio.get(
        '/api/admin/orders/overview',
        queryParameters: query,
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 403) rethrow;
      return _fallbackOrdersOverview(
        status: status,
        period: period,
        from: from,
        to: to,
        limit: limit,
        offset: offset,
      );
    }
  }

  Future<Map<String, dynamic>> merchantOrdersOverview(
    int merchantId, {
    String status = 'all',
    String period = 'all',
    String? from,
    String? to,
    int limit = 80,
    int offset = 0,
  }) async {
    try {
      final response = await dio.get(
        '/api/admin/orders/overview/$merchantId',
        queryParameters: {
          'status': status,
          ..._buildFinancialWindowQuery(period: period, from: from, to: to),
          'limit': limit,
          'offset': offset,
        },
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 403) rethrow;
      return {
        'merchantId': merchantId,
        'items': const <dynamic>[],
        'summary': const <String, dynamic>{},
        'total': 0,
        'limit': limit,
        'offset': offset,
      };
    }
  }

  Future<List<dynamic>> pendingMerchants() async {
    try {
      final response = await dio.get('/api/admin/merchants/pending');
      return List<dynamic>.from(response.data as List);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      return const <dynamic>[];
    }
  }

  Future<List<dynamic>> merchants() async {
    try {
      final response = await dio.get('/api/admin/merchants');
      return List<dynamic>.from(response.data as List);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      return const <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> updateMerchantProfile({
    required int merchantId,
    String? name,
    String? phone,
    String? description,
    String? type,
    String? activityType,
    String? storeDepartment,
    String? discoverySubcategory,
    List<String>? discoverySubcategories,
    bool? discoverySelectAll,
  }) async {
    final response = await dio.patch(
      '/api/admin/merchants/$merchantId/profile',
      data: {
        'name': name,
        'phone': phone,
        'description': description,
        'type': type,
        'activityType': activityType,
        'storeDepartment': storeDepartment,
        'discoverySubcategory': discoverySubcategory,
        'discoverySubcategories': discoverySubcategories,
        'discoverySelectAll': discoverySelectAll,
      }..removeWhere((_, value) => value == null),
    );
    return _safeMapResponse(response.data);
  }

  Future<List<dynamic>> adminStoreActivities() async {
    final response = await dio.get('/api/admin/store-activities');
    final data = response.data;
    if (data is Map && data['items'] is List) {
      return List<dynamic>.from(data['items'] as List);
    }
    if (data is List) return List<dynamic>.from(data);
    return const <dynamic>[];
  }

  Future<Map<String, dynamic>> upsertStoreActivity({
    required String activityType,
    required String baseType,
    required String displayNameAr,
    required String displayNameEn,
    bool hasDiscoverySubcategories = false,
    bool supportsChat = false,
    bool supportsAttachments = false,
    bool supportsPharmacyWorkflow = false,
    bool isActive = true,
  }) async {
    final response = await dio.post(
      '/api/admin/store-activities',
      data: {
        'activityType': activityType,
        'baseType': baseType,
        'displayNameAr': displayNameAr,
        'displayNameEn': displayNameEn,
        'hasDiscoverySubcategories': hasDiscoverySubcategories,
        'supportsChat': supportsChat,
        'supportsAttachments': supportsAttachments,
        'supportsPharmacyWorkflow': supportsPharmacyWorkflow,
        'isActive': isActive,
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<void> approveMerchant(
    int merchantId, {
    Map<String, dynamic>? body,
  }) async {
    await dio.patch('/api/admin/merchants/$merchantId/approve', data: body);
  }

  Future<void> toggleMerchantDisabled({
    required int merchantId,
    required bool isDisabled,
  }) async {
    await dio.patch(
      '/api/admin/merchants/$merchantId/disabled',
      data: {'isDisabled': isDisabled},
    );
  }

  Future<List<dynamic>> pendingSettlements() async {
    try {
      final response = await dio.get('/api/admin/settlements/pending');
      return List<dynamic>.from(response.data as List);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      return const <dynamic>[];
    }
  }

  Future<List<dynamic>> pendingDeliveryAccounts() async {
    final response = await dio.get('/api/admin/delivery/pending');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> pendingTaxiCaptainAccounts() async {
    final response = await dio.get('/api/admin/taxi-captains/pending');
    return List<dynamic>.from(response.data as List);
  }

  Future<void> approveDeliveryAccount(int deliveryUserId) async {
    await dio.patch('/api/admin/delivery/$deliveryUserId/approve');
  }

  Future<void> approveTaxiCaptainAccount(int captainUserId) async {
    await dio.patch('/api/admin/taxi-captains/$captainUserId/approve');
  }

  Future<Map<String, dynamic>> updateDeliveryDriverProfile({
    required int deliveryUserId,
    required String driverType,
    int? merchantId,
  }) async {
    final response = await dio.patch(
      '/api/admin/delivery/$deliveryUserId/profile',
      data: {'driverType': driverType, 'merchantId': merchantId},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> pendingTaxiCaptainCashPayments({
    int limit = 100,
  }) async {
    try {
      final response = await dio.get(
        '/api/admin/taxi-captains/subscription/pending-payments',
        queryParameters: {'limit': limit},
      );
      final data = response.data;
      if (data is Map && data['items'] is List) {
        return List<dynamic>.from(data['items'] as List);
      }
      if (data is List) return List<dynamic>.from(data);
      return const [];
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 403) rethrow;
      return const <dynamic>[];
    }
  }

  Future<void> confirmTaxiCaptainCashPayment(
    int captainUserId, {
    int cycleDays = 30,
  }) async {
    await dio.patch(
      '/api/admin/taxi-captains/$captainUserId/subscription/confirm-cash-payment',
      data: {'cycleDays': cycleDays},
    );
  }

  Future<void> setTaxiCaptainDiscount(
    int captainUserId, {
    required int discountPercent,
  }) async {
    await dio.patch(
      '/api/admin/taxi-captains/$captainUserId/subscription/discount',
      data: {'discountPercent': discountPercent},
    );
  }

  Future<List<dynamic>> serviceProviderSubscriptionRequests({
    String? status,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/admin/services/subscription-requests',
      queryParameters: {
        if ((status ?? '').trim().isNotEmpty)
          'subscriptionRequestStatus': status!.trim(),
        if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    final data = response.data;
    if (data is List) return List<dynamic>.from(data);
    if (data is Map && data['items'] is List) {
      return List<dynamic>.from(data['items'] as List);
    }
    return const <dynamic>[];
  }

  Future<Map<String, dynamic>> sendServiceProviderSubscriptionOffer({
    required int requestId,
    required num amount,
    String currency = 'IQD',
    String? title,
    String? description,
    String? validUntilIso,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/admin/services/subscription-requests/$requestId/offer',
      data: {
        'amount': amount,
        'currency': currency,
        if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
        if ((description ?? '').trim().isNotEmpty)
          'description': description!.trim(),
        if ((validUntilIso ?? '').trim().isNotEmpty)
          'validUntil': validUntilIso!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> rejectServiceProviderSubscriptionRequest({
    required int requestId,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/admin/services/subscription-requests/$requestId/reject',
      data: {if ((note ?? '').trim().isNotEmpty) 'note': note!.trim()},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> confirmServiceProviderSubscriptionCashPayment({
    required int requestId,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/admin/services/subscription-requests/$requestId/confirm-cash-payment',
      data: {if ((note ?? '').trim().isNotEmpty) 'note': note!.trim()},
    );
    return _safeMapResponse(response.data);
  }

  Future<List<dynamic>> listSectionAvailability({
    String surfaceScope = 'user',
  }) async {
    final response = await dio.get(
      '/api/admin/sections/availability',
      queryParameters: {'surfaceScope': surfaceScope},
    );
    final data = response.data;
    if (data is Map && data['items'] is List) {
      return List<dynamic>.from(data['items'] as List);
    }
    if (data is List) return List<dynamic>.from(data);
    return const <dynamic>[];
  }

  Future<List<dynamic>> listSectionAvailabilityAudit({
    String surfaceScope = 'user',
    String? sectionKey,
    int limit = 80,
  }) async {
    final response = await dio.get(
      '/api/admin/sections/availability/audit',
      queryParameters: {
        'surfaceScope': surfaceScope,
        if ((sectionKey ?? '').trim().isNotEmpty) 'sectionKey': sectionKey,
        'limit': limit,
      },
    );
    final data = response.data;
    if (data is Map && data['items'] is List) {
      return List<dynamic>.from(data['items'] as List);
    }
    if (data is List) return List<dynamic>.from(data);
    return const <dynamic>[];
  }

  Future<Map<String, dynamic>> updateSectionAvailability({
    required String sectionKey,
    required String displayName,
    required String status,
    required bool isVisible,
    String surfaceScope = 'user',
    String? parentSectionKey,
    String? userMessage,
    int sortOrder = 0,
    required bool allowExistingActiveAccess,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await dio.patch(
      '/api/admin/sections/availability/$sectionKey',
      data: {
        'displayName': displayName.trim(),
        'status': status.trim(),
        'surfaceScope': surfaceScope,
        'isVisible': isVisible,
        'parentSectionKey': (parentSectionKey ?? '').trim().isEmpty
            ? null
            : parentSectionKey!.trim(),
        'userMessage': (userMessage ?? '').trim().isEmpty
            ? null
            : userMessage!.trim(),
        'sortOrder': sortOrder,
        'allowExistingActiveAccess': allowExistingActiveAccess,
        'metadata': metadata ?? const <String, dynamic>{},
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> listPendingServiceProviders({
    String providerStatus = 'pending',
    int limit = 80,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/admin/services/providers/pending',
      queryParameters: {
        'providerStatus': providerStatus,
        'limit': limit,
        'offset': offset,
      },
    );
    return _itemsEnvelopeResponse(response.data);
  }

  Future<Map<String, dynamic>> updateServiceProviderModeration({
    required int providerId,
    required String status,
    String? note,
  }) async {
    final response = await dio.patch(
      '/api/admin/services/providers/$providerId/status',
      data: {
        'status': status,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> listPendingServiceOfferings({
    String offeringStatus = 'pending',
    int limit = 80,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/admin/services/offerings/pending',
      queryParameters: {
        'offeringStatus': offeringStatus,
        'limit': limit,
        'offset': offset,
      },
    );
    return _itemsEnvelopeResponse(response.data);
  }

  Future<Map<String, dynamic>> updateServiceOfferingModeration({
    required int offeringId,
    required String status,
    String? note,
  }) async {
    final response = await dio.patch(
      '/api/admin/services/offerings/$offeringId/status',
      data: {
        'status': status,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> listServiceCategorySuggestions({
    String categorySuggestionStatus = 'pending',
    int limit = 80,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/admin/services/categories/suggestions',
      queryParameters: {
        'categorySuggestionStatus': categorySuggestionStatus,
        'limit': limit,
        'offset': offset,
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> reviewServiceCategorySuggestion({
    required int suggestionId,
    required String action,
    String? reviewNote,
  }) async {
    final response = await dio.patch(
      '/api/admin/services/categories/suggestions/$suggestionId/review',
      data: {
        'action': action,
        if ((reviewNote ?? '').trim().isNotEmpty)
          'reviewNote': reviewNote!.trim(),
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> listServiceReports({
    String status = 'pending',
    int limit = 80,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/admin/services/reports',
      queryParameters: {'status': status, 'limit': limit, 'offset': offset},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> reviewServiceReport({
    required int reportId,
    required String status,
    String? reviewNote,
  }) async {
    final response = await dio.patch(
      '/api/admin/services/reports/$reportId/review',
      data: {
        'status': status,
        if ((reviewNote ?? '').trim().isNotEmpty)
          'reviewNote': reviewNote!.trim(),
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> listServiceAdminRequests({
    String? requestStatus,
    int limit = 80,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/admin/services/requests',
      queryParameters: {
        if ((requestStatus ?? '').trim().isNotEmpty)
          'requestStatus': requestStatus,
        'limit': limit,
        'offset': offset,
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> getServiceAdminStats() async {
    final response = await dio.get('/api/admin/services/stats');
    return _safeMapResponse(response.data);
  }

  Future<List<dynamic>> listServiceModuleSettings() async {
    final response = await dio.get('/api/admin/services/settings');
    final data = response.data;
    if (data is List) return List<dynamic>.from(data);
    if (data is Map && data['items'] is List) {
      return List<dynamic>.from(data['items'] as List);
    }
    return const <dynamic>[];
  }

  Future<Map<String, dynamic>> upsertServiceModuleSetting({
    required String key,
    required dynamic value,
  }) async {
    final response = await dio.put(
      '/api/admin/services/settings',
      data: {'key': key, 'value': value},
    );
    return _safeMapResponse(response.data);
  }

  Future<List<dynamic>> pendingTaxiCaptainProfileEditRequests({
    int limit = 100,
  }) async {
    try {
      final response = await dio.get(
        '/api/admin/taxi-captains/profile-edit-requests/pending',
        queryParameters: {'limit': limit},
      );
      final data = response.data;
      if (data is Map && data['items'] is List) {
        return List<dynamic>.from(data['items'] as List);
      }
      if (data is List) return List<dynamic>.from(data);
      return const [];
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 403) rethrow;
      return const [];
    }
  }

  Future<void> approveTaxiCaptainProfileEditRequest(
    int requestId, {
    String? adminNote,
  }) async {
    await dio.patch(
      '/api/admin/taxi-captains/profile-edit-requests/$requestId/approve',
      data: {'adminNote': adminNote},
    );
  }

  Future<void> rejectTaxiCaptainProfileEditRequest(
    int requestId, {
    String? adminNote,
  }) async {
    await dio.patch(
      '/api/admin/taxi-captains/profile-edit-requests/$requestId/reject',
      data: {'adminNote': adminNote},
    );
  }

  Future<void> approveSettlement(int settlementId, {String? adminNote}) async {
    await dio.patch(
      '/api/admin/settlements/$settlementId/approve',
      data: {'adminNote': adminNote},
    );
  }

  Future<Map<String, dynamic>> socialPostReports({
    String status = 'open',
    int limit = 80,
    int? beforePostId,
  }) async {
    final query = <String, dynamic>{'status': status, 'limit': limit};
    if (beforePostId != null) query['beforePostId'] = beforePostId;
    final response = await dio.get(
      '/api/admin/social-reports/posts',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> socialStoryReports({
    String status = 'open',
    int limit = 80,
    int? beforeStoryId,
  }) async {
    final query = <String, dynamic>{'status': status, 'limit': limit};
    if (beforeStoryId != null) query['beforeStoryId'] = beforeStoryId;
    final response = await dio.get(
      '/api/admin/social-reports/stories',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> socialUserReports({
    int limit = 80,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (beforeId != null) query['beforeId'] = beforeId;
    final response = await dio.get(
      '/api/admin/social-reports/users',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> reviewSocialPostReport({
    required int postId,
    required String action,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/admin/social-reports/posts/$postId/review',
      data: {
        'action': action,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> approveEditedSocialPost(int postId) async {
    final response = await dio.post(
      '/api/admin/social-reports/posts/$postId/approve-edit',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> reviewSocialStoryReport({
    required int storyId,
    required String action,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/admin/social-reports/stories/$storyId/review',
      data: {
        'action': action,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> approveEditedSocialStory(int storyId) async {
    final response = await dio.post(
      '/api/admin/social-reports/stories/$storyId/approve-edit',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> residenceChangeRequests({
    String status = 'pending',
    int limit = 80,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'status': status, 'limit': limit};
    if (beforeId != null) query['beforeId'] = beforeId;
    final response = await dio.get(
      '/api/admin/residence-change-requests',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> approveResidenceChangeRequest(
    int requestId, {
    String? reviewNote,
  }) async {
    final response = await dio.patch(
      '/api/admin/residence-change-requests/$requestId/approve',
      data: {
        if ((reviewNote ?? '').trim().isNotEmpty)
          'reviewNote': reviewNote!.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> rejectResidenceChangeRequest(
    int requestId, {
    String? reviewNote,
  }) async {
    final response = await dio.patch(
      '/api/admin/residence-change-requests/$requestId/reject',
      data: {
        if ((reviewNote ?? '').trim().isNotEmpty)
          'reviewNote': reviewNote!.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> socialRestrictionsForUser(int userId) async {
    final response = await dio.get(
      '/api/admin/social-restrictions/users/$userId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> socialUsersForModeration({
    String? search,
    int limit = 60,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if ((search ?? '').trim().isNotEmpty) query['search'] = search!.trim();
    if (beforeId != null && beforeId > 0) query['beforeId'] = beforeId;
    final response = await dio.get(
      '/api/admin/social-users',
      queryParameters: query,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> setSocialUserAccountStatus({
    required int userId,
    required bool isDisabled,
    String? note,
  }) async {
    final response = await dio.patch(
      '/api/admin/social-users/$userId/account-status',
      data: {
        'isDisabled': isDisabled,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createSocialRestriction({
    required int userId,
    required String capabilityKey,
    String? reason,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final response = await dio.post(
      '/api/admin/social-restrictions/users/$userId',
      data: {
        'capabilityKey': capabilityKey,
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
        if (startsAt != null) 'startsAt': startsAt.toUtc().toIso8601String(),
        if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> revokeSocialRestriction(
    int restrictionId,
  ) async {
    final response = await dio.post(
      '/api/admin/social-restrictions/$restrictionId/revoke',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createUser(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final data = imageFile == null
        ? body
        : FormData.fromMap({
            ...body,
            'imageFile': await imageFile.toMultipartFile(),
          });
    final response = await dio.post('/api/admin/users', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> availableOwners() async {
    final response = await dio.get('/api/admin/owners/available');
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> customerInsights({
    String? search,
    int limit = 30,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/admin/customers/insights',
      queryParameters: {
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> customerInsightDetails(
    int customerUserId,
  ) async {
    final response = await dio.get(
      '/api/admin/customers/$customerUserId/insights',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> adBoardItems() async {
    final response = await dio.get('/api/admin/ad-board/items');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> adBoardMerchantProducts(
    int merchantId, {
    int limit = 300,
  }) async {
    final response = await dio.get(
      '/api/admin/ad-board/merchants/$merchantId/products',
      queryParameters: {'limit': limit},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createAdBoardItem(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final payload = imageFile == null
        ? body
        : FormData.fromMap({
            ...body,
            'imageFile': await imageFile.toMultipartFile(),
          });
    final response = await dio.post('/api/admin/ad-board/items', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateAdBoardItem(
    int itemId,
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final payload = imageFile == null
        ? body
        : FormData.fromMap({
            ...body,
            'imageFile': await imageFile.toMultipartFile(),
          });
    final response = await dio.patch(
      '/api/admin/ad-board/items/$itemId',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteAdBoardItem(int itemId) async {
    await dio.delete('/api/admin/ad-board/items/$itemId');
  }

  Future<Map<String, dynamic>> merchantsReceivablesV2({
    String? status,
    int limit = 120,
    int offset = 0,
  }) async {
    try {
      final response = await dio.get(
        '/api/admin/merchants/receivables',
        queryParameters: {
          if (status != null && status.trim().isNotEmpty)
            'status': status.trim(),
          'limit': limit,
          'offset': offset,
        },
      );
      return _safeMapResponse(response.data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 403) rethrow;
      return const <String, dynamic>{'merchants': <dynamic>[]};
    }
  }

  Future<Map<String, dynamic>> merchantReceivablesDetailsV2(
    int merchantId,
  ) async {
    try {
      final response = await dio.get(
        '/api/admin/merchants/$merchantId/receivables',
      );
      return _safeMapResponse(response.data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 403) rethrow;
      return const <String, dynamic>{
        'merchant': null,
        'breakdown': <String, dynamic>{},
        'paymentRequests': <dynamic>[],
        'ledger': <dynamic>[],
      };
    }
  }

  Future<Map<String, dynamic>> patchMerchantBillingProfileV2({
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
    final response = await dio.patch(
      '/api/admin/merchants/$merchantId/billing-profile',
      data: {
        'commissionType': commissionType,
        'commissionValue': commissionValue,
        'commissionRate': commissionRate,
        'commissionModel': commissionModel,
        'monthlySubscriptionAmount': monthlySubscriptionAmount,
        'serviceFeeType': serviceFeeType,
        'serviceFeeMode': serviceFeeMode,
        'serviceFeeValue': serviceFeeValue,
        'deliveryFeeMode': deliveryFeeMode,
        'appDeliveryFeeValue': appDeliveryFeeValue,
        'storeDeliveryFeeValue': storeDeliveryFeeValue,
        'deliveryFeeValue': deliveryFeeValue,
        'appDeliveryEnabled': appDeliveryEnabled,
        'merchantDeliveryEnabled': merchantDeliveryEnabled,
        'settlementCycle': settlementCycle,
        'distributionPolicy': distributionPolicy,
        'gracePeriodDays': gracePeriodDays,
        'effectiveFrom': effectiveFrom,
      }..removeWhere((_, value) => value == null),
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> markPaymentRequestReceivedV2(
    int paymentRequestId, {
    String? reviewNote,
  }) async {
    final response = await dio.post(
      '/api/admin/payment-requests/$paymentRequestId/mark-received',
      data: {'note': reviewNote},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> approvePaymentRequestV2(
    int paymentRequestId, {
    String? reviewNote,
    String? internalAdminNote,
  }) async {
    final response = await dio.post(
      '/api/admin/payment-requests/$paymentRequestId/approve',
      data: {'reviewNote': reviewNote, 'internalAdminNote': internalAdminNote}
        ..removeWhere((_, value) => value == null),
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> assignPaymentRequestV2({
    required int paymentRequestId,
    int? assignedToUserId,
    String? assignedToName,
    String? reviewNote,
    String? internalAdminNote,
  }) async {
    final response = await dio.post(
      '/api/admin/payment-requests/$paymentRequestId/assign',
      data: {
        'assignedToUserId': assignedToUserId,
        'assignedToName': assignedToName,
        'reviewNote': reviewNote,
        'internalAdminNote': internalAdminNote,
      }..removeWhere((_, value) => value == null),
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> markPaymentRequestPaidV2({
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
    final response = await dio.post(
      '/api/admin/payment-requests/$paymentRequestId/mark-paid',
      data: {
        'paidAmount': paidAmount,
        'paymentMethod': paymentMethod,
        'paymentDate': paymentDate,
        'referenceCode': referenceCode,
        'paymentActorName': paymentActorName,
        'assignedToUserId': assignedToUserId,
        'assignedToName': assignedToName,
        'reviewNote': reviewNote,
        'internalAdminNote': internalAdminNote,
      }..removeWhere((_, value) => value == null),
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> returnPaymentRequestForRevisionV2(
    int paymentRequestId, {
    String? reviewNote,
    String? internalAdminNote,
  }) async {
    final response = await dio.post(
      '/api/admin/payment-requests/$paymentRequestId/return-for-revision',
      data: {'reviewNote': reviewNote, 'internalAdminNote': internalAdminNote}
        ..removeWhere((_, value) => value == null),
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> rejectPaymentRequestV2(
    int paymentRequestId, {
    String? reviewNote,
  }) async {
    final response = await dio.post(
      '/api/admin/payment-requests/$paymentRequestId/reject',
      data: {'note': reviewNote},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> createAppPayablesAdjustmentV2({
    required int merchantId,
    required double amount,
    required String direction,
    String entryType = 'adjustment',
    String? note,
    String? referenceCode,
    int? orderId,
  }) async {
    final response = await dio.post(
      '/api/admin/merchants/$merchantId/app-payables/adjustment',
      data: {
        'amount': amount,
        'direction': direction,
        'entryType': entryType,
        'note': note,
        'referenceCode': referenceCode,
        'orderId': orderId,
      }..removeWhere((_, value) => value == null),
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> competitionsV2({
    bool activeOnly = false,
    String? status,
  }) async {
    try {
      final query = <String, dynamic>{};
      if (activeOnly) query['activeOnly'] = true;
      if (status != null && status.trim().isNotEmpty) {
        query['status'] = status.trim().toLowerCase();
      }
      final response = await dio.get(
        '/api/admin/competitions',
        queryParameters: query,
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 403) rethrow;
      return const <String, dynamic>{'competitions': <dynamic>[]};
    }
  }

  Future<Map<String, dynamic>> createCompetitionV2(
    Map<String, dynamic> body,
  ) async {
    final response = await dio.post('/api/admin/competitions', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> patchCompetitionV2(
    int competitionId,
    Map<String, dynamic> body,
  ) async {
    final response = await dio.patch(
      '/api/admin/competitions/$competitionId',
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> competitionDetailsV2(int competitionId) async {
    final response = await dio.get('/api/admin/competitions/$competitionId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> competitionWinnersV2(int competitionId) async {
    final response = await dio.get(
      '/api/admin/competitions/$competitionId/winners',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> endCompetitionV2(int competitionId) async {
    final response = await dio.post(
      '/api/admin/competitions/$competitionId/end',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> platformKpisV2({
    String period = 'day',
    String? from,
    String? to,
  }) async {
    final query = _buildFinancialWindowQuery(
      period: period,
      from: from,
      to: to,
    );
    try {
      final response = await dio.get(
        '/api/admin/platform-kpis',
        queryParameters: query,
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 403) rethrow;
      return const <String, dynamic>{'platform': <String, dynamic>{}};
    }
  }

  Map<String, dynamic> _safeMapResponse(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _itemsEnvelopeResponse(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final normalized = raw;
      final items = normalized['items'];
      if (items is List) {
        return normalized;
      }
      if (normalized['data'] is List) {
        return <String, dynamic>{
          ...normalized,
          'items': List<dynamic>.from(normalized['data'] as List),
          'total': _toInt(
            normalized['total'] ??
                normalized['count'] ??
                normalized['itemsCount'],
          ),
        };
      }
      return normalized;
    }
    if (raw is Map) {
      final normalized = raw.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      );
      final items = normalized['items'];
      if (items is List) {
        return normalized;
      }
      if (normalized['data'] is List) {
        return <String, dynamic>{
          ...normalized,
          'items': List<dynamic>.from(normalized['data'] as List),
          'total': _toInt(
            normalized['total'] ??
                normalized['count'] ??
                normalized['itemsCount'],
          ),
        };
      }
      return normalized;
    }
    if (raw is List) {
      return <String, dynamic>{
        'items': List<dynamic>.from(raw),
        'total': raw.length,
      };
    }
    return const <String, dynamic>{'items': <dynamic>[], 'total': 0};
  }

  Future<Map<String, dynamic>> adminFinancialKpis({
    String period = 'all',
    String? from,
    String? to,
  }) async {
    final query = _buildFinancialWindowQuery(
      period: period,
      from: from,
      to: to,
    );
    try {
      final response = await dio.get(
        '/api/admin/financial/kpis',
        queryParameters: query,
      );
      return _safeMapResponse(response.data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 403) rethrow;
      final platform = await platformKpisV2(period: period, from: from, to: to);
      final financial = _safeMapResponse(platform['financial']);
      return {
        'window': {
          'period': period,
          if (query['from'] != null) 'start': query['from'],
          if (query['to'] != null) 'end': query['to'],
        },
        'currency': financial['currency'] ?? 'IQD',
        'totals': financial,
      };
    }
  }

  Future<Map<String, dynamic>> _fallbackOrdersOverview({
    required String status,
    required String period,
    String? from,
    String? to,
    required int limit,
    required int offset,
  }) async {
    final platform = await platformKpisV2(period: period, from: from, to: to);
    final platformSummary = _safeMapResponse(platform['platform']);
    if (platformSummary.isNotEmpty) {
      final totalOrders = _toInt(platformSummary['totalOrders']);
      final completedOrders = _toInt(platformSummary['completedOrders']);
      final cancelledOrders = _toInt(platformSummary['cancelledOrders']);
      final inProgressOrders =
          totalOrders - completedOrders - cancelledOrders > 0
          ? totalOrders - completedOrders - cancelledOrders
          : 0;
      return {
        'summary': {
          'totalOrders': totalOrders,
          'completedOrders': completedOrders,
          'cancelledOrders': cancelledOrders,
          'inProgressOrders': inProgressOrders,
        },
        'items': const <dynamic>[],
        'total': 0,
        'limit': limit,
        'offset': offset,
        'status': status,
      };
    }

    final analyticsData = await analytics();
    final analyticsBucket = switch (period) {
      'day' => _safeMapResponse(analyticsData['day']),
      'month' => _safeMapResponse(analyticsData['month']),
      'year' => _safeMapResponse(analyticsData['year']),
      _ => const <String, dynamic>{},
    };
    final totalOrders = _toInt(analyticsBucket['orders_count']);
    final completedOrders = _toInt(analyticsBucket['delivered_orders_count']);
    final cancelledOrders = _toInt(analyticsBucket['cancelled_orders_count']);
    final inProgressOrders = totalOrders - completedOrders - cancelledOrders > 0
        ? totalOrders - completedOrders - cancelledOrders
        : 0;
    return {
      'summary': {
        'totalOrders': totalOrders,
        'completedOrders': completedOrders,
        'cancelledOrders': cancelledOrders,
        'inProgressOrders': inProgressOrders,
      },
      'items': const <dynamic>[],
      'total': 0,
      'limit': limit,
      'offset': offset,
      'status': status,
    };
  }

  Future<Map<String, dynamic>> adminSalesReport({
    String period = 'day',
    String? from,
    String? to,
    String? search,
    int limit = 120,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{
      ..._buildFinancialWindowQuery(period: period, from: from, to: to),
      'limit': limit,
      'offset': offset,
    };
    if ((search ?? '').trim().isNotEmpty) query['search'] = search!.trim();
    final response = await dio.get(
      '/api/admin/reports/sales',
      queryParameters: query,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> adminSalesMerchantDetails({
    required int merchantId,
    String period = 'day',
    String? from,
    String? to,
    int limit = 120,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{
      ..._buildFinancialWindowQuery(period: period, from: from, to: to),
      'limit': limit,
      'offset': offset,
    };
    final response = await dio.get(
      '/api/admin/reports/sales/$merchantId',
      queryParameters: query,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> adminCollectionsReport({
    String period = 'day',
    String? from,
    String? to,
    String? search,
    int limit = 120,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{
      ..._buildFinancialWindowQuery(period: period, from: from, to: to),
      'limit': limit,
      'offset': offset,
    };
    if ((search ?? '').trim().isNotEmpty) query['search'] = search!.trim();
    final response = await dio.get(
      '/api/admin/reports/collections',
      queryParameters: query,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> adminCollectionsMerchantDetails({
    required int merchantId,
    String period = 'day',
    String? from,
    String? to,
    int limit = 120,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{
      ..._buildFinancialWindowQuery(period: period, from: from, to: to),
      'limit': limit,
      'offset': offset,
    };
    final response = await dio.get(
      '/api/admin/reports/collections/$merchantId',
      queryParameters: query,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> adminReceivablesReport({
    String period = 'day',
    String? from,
    String? to,
    String? search,
    int limit = 120,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{
      ..._buildFinancialWindowQuery(period: period, from: from, to: to),
      'limit': limit,
      'offset': offset,
    };
    if ((search ?? '').trim().isNotEmpty) query['search'] = search!.trim();
    final response = await dio.get(
      '/api/admin/reports/receivables',
      queryParameters: query,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> adminReceivablesMerchantStatement({
    required int merchantId,
    String period = 'day',
    String? from,
    String? to,
    int limit = 120,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{
      ..._buildFinancialWindowQuery(period: period, from: from, to: to),
      'limit': limit,
      'offset': offset,
    };
    final response = await dio.get(
      '/api/admin/reports/receivables/$merchantId/statement',
      queryParameters: query,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> companyAdminCompanies({
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/company/admin/companies',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> companyAdminCreateCompany(
    Map<String, dynamic> body,
  ) async {
    final response = await dio.post('/api/company/admin/companies', data: body);
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> companyAdminUpdateCompany({
    required int companyId,
    required Map<String, dynamic> body,
  }) async {
    final response = await dio.patch(
      '/api/company/admin/companies/$companyId',
      data: body,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> companyAdminDeleteCompany({
    required int companyId,
  }) async {
    final response = await dio.delete(
      '/api/company/admin/companies/$companyId',
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> companyAdminLinkBranch({
    required int companyId,
    required int merchantId,
  }) async {
    final response = await dio.post(
      '/api/company/admin/companies/$companyId/branches/link',
      data: {'merchantId': merchantId},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> companyAdminUnlinkBranch({
    required int companyId,
    required int merchantId,
  }) async {
    final response = await dio.delete(
      '/api/company/admin/companies/$companyId/branches/$merchantId',
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> companyAdminPendingBranchRequests() async {
    final response = await dio.get('/api/company/admin/branch-requests');
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> companyAdminApproveBranchRequest({
    required int requestId,
    Map<String, dynamic> body = const {},
  }) async {
    final response = await dio.post(
      '/api/company/admin/branch-requests/$requestId/approve',
      data: body,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> companyAdminRejectBranchRequest({
    required int requestId,
    Map<String, dynamic> body = const {},
  }) async {
    final response = await dio.post(
      '/api/company/admin/branch-requests/$requestId/reject',
      data: body,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> opsAlerts({
    String status = 'open',
    String severity = 'all',
    int limit = 80,
    int? beforeId,
  }) async {
    final query = <String, dynamic>{
      'status': status,
      'severity': severity,
      'limit': limit,
      ...?(beforeId == null ? null : {'beforeId': beforeId}),
    };
    final response = await dio.get(
      '/api/admin/ops/alerts',
      queryParameters: query,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> ackOpsAlert(
    int alertId, {
    String status = 'acknowledged',
    String? note,
  }) async {
    final response = await dio.post(
      '/api/admin/ops/alerts/$alertId/ack',
      data: {'status': status, 'note': note},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> opsNotificationOverview({
    int windowHours = 24,
  }) async {
    final response = await dio.get(
      '/api/admin/ops/notifications/overview',
      queryParameters: {'windowHours': windowHours},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> opsDevicePushHealth({
    String status = 'all',
    int limit = 120,
  }) async {
    final response = await dio.get(
      '/api/admin/ops/device-push-health',
      queryParameters: {'status': status, 'limit': limit},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> opsCrashEvents({
    String platform = 'all',
    int limit = 120,
    int? beforeId,
  }) async {
    final response = await dio.get(
      '/api/admin/ops/crashes',
      queryParameters: {
        'platform': platform,
        'limit': limit,
        ...?(beforeId == null ? null : {'beforeId': beforeId}),
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> opsFeatureFlags() async {
    final response = await dio.get('/api/admin/ops/feature-flags');
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> upsertOpsFeatureFlag({
    required String flagKey,
    required bool isEnabled,
    int rolloutPercent = 0,
    String? description,
    List<String> targetRoles = const [],
    Map<String, dynamic> config = const {},
  }) async {
    final response = await dio.post(
      '/api/admin/ops/feature-flags',
      data: {
        'flagKey': flagKey,
        'isEnabled': isEnabled,
        'rolloutPercent': rolloutPercent,
        'description': description,
        'targetRoles': targetRoles,
        'config': config,
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> opsPermissionsMatrix() async {
    final response = await dio.get('/api/admin/ops/permissions-matrix');
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> upsertOpsPermissionOverride({
    required String roleKey,
    required String capabilityKey,
    required bool isEnabled,
    String? notes,
  }) async {
    final response = await dio.post(
      '/api/admin/ops/permissions-matrix',
      data: {
        'roleKey': roleKey,
        'capabilityKey': capabilityKey,
        'isEnabled': isEnabled,
        'notes': notes,
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> customerReliabilityPolicy() async {
    try {
      final response = await dio.get('/api/admin/customer-reliability/policy');
      return _safeMapResponse(response.data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 403) rethrow;
      return const <String, dynamic>{
        'policyKey': 'default',
        'config': {
          'windowDays': 180,
          'baseScore': 70,
          'weights': {
            'completed': 4,
            'cancelledByCustomer': -8,
            'failedDelivery': -10,
            'noAnswer': -9,
            'complaints': -12,
          },
          'thresholds': {'trustedMin': 80, 'needsAttentionMax': 45},
          'warningThreshold': 50,
        },
      };
    }
  }

  Future<Map<String, dynamic>> updateCustomerReliabilityPolicy({
    required Map<String, dynamic> config,
  }) async {
    final response = await dio.put(
      '/api/admin/customer-reliability/policy',
      data: {'config': config},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> reviewCourierCancelRequestV2({
    required int orderId,
    required String decision,
    String? note,
  }) async {
    final response = await dio.post(
      '/api/orders/$orderId/admin/review-cancel-request',
      data: {
        'decision': decision,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> getDeliveryDispatchPolicy() async {
    final response = await dio.get('/api/admin/delivery-dispatch/policy');
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> updateDeliveryDispatchPolicy({
    required Map<String, dynamic> policy,
  }) async {
    final response = await dio.put(
      '/api/admin/delivery-dispatch/policy',
      data: policy,
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> adminPaymentRequestInvoices(
    int paymentRequestId,
  ) async {
    final response = await dio.get(
      '/api/admin/payment-requests/$paymentRequestId/invoices',
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> listProfileCoreChangeRequests({
    String status = 'pending',
    int limit = 40,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/admin/profile-core-change-requests',
      queryParameters: {'status': status, 'limit': limit, 'offset': offset},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> approveProfileCoreChangeRequest({
    required int requestId,
    String? note,
  }) async {
    final response = await dio.patch(
      '/api/admin/profile-core-change-requests/$requestId/approve',
      data: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
    return _safeMapResponse(response.data);
  }

  Future<Map<String, dynamic>> rejectProfileCoreChangeRequest({
    required int requestId,
    required String reason,
  }) async {
    final response = await dio.patch(
      '/api/admin/profile-core-change-requests/$requestId/reject',
      data: {'reason': reason},
    );
    return _safeMapResponse(response.data);
  }
}
