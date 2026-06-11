// ignore_for_file: use_null_aware_elements

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../auth/state/auth_controller.dart';

final servicesApiProvider = Provider<ServicesApi>(
  (ref) => ServicesApi(ref.read(dioClientProvider).dio),
);

class ServicesApi {
  final Dio _dio;

  ServicesApi(this._dio);

  Future<List<Map<String, dynamic>>> listPublicCategories() async {
    final response = await _dio.get('/api/services/public/categories');
    return _asMapList(response.data);
  }

  Future<List<Map<String, dynamic>>> searchPublicOfferings({
    String? q,
    int? categoryId,
    int? subcategoryId,
    String? city,
    String? area,
    String sort = 'newest',
    num? minPrice,
    num? maxPrice,
    num? ratingMin,
    bool? availableNow,
    bool? homeService,
    bool? emergency,
    bool? offersOnly,
    String? pricingModel,
    String? pricingUnit,
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _dio.get(
      '/api/services/public/search',
      queryParameters: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (categoryId != null && categoryId > 0) 'categoryId': categoryId,
        if (subcategoryId != null && subcategoryId > 0)
          'subcategoryId': subcategoryId,
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        if (area != null && area.trim().isNotEmpty) 'area': area.trim(),
        if (minPrice != null) 'minPrice': minPrice,
        if (maxPrice != null) 'maxPrice': maxPrice,
        if (ratingMin != null) 'ratingMin': ratingMin,
        if (availableNow != null) 'availableNow': availableNow,
        if (homeService != null) 'homeService': homeService,
        if (emergency != null) 'emergency': emergency,
        if (offersOnly != null) 'offersOnly': offersOnly,
        if (pricingModel != null && pricingModel.trim().isNotEmpty)
          'pricingModel': pricingModel.trim(),
        if (pricingUnit != null && pricingUnit.trim().isNotEmpty)
          'pricingUnit': pricingUnit.trim(),
        'sort': sort,
        'limit': limit,
        'offset': offset,
      },
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> getPublicProvider(int providerId) async {
    final response = await _dio.get(
      '/api/services/public/providers/$providerId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getPublicOffering(int offeringId) async {
    final response = await _dio.get(
      '/api/services/public/offerings/$offeringId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createServiceRequest(
    Map<String, dynamic> body, {
    List<LocalImageFile> attachmentFiles = const [],
  }) async {
    final requestData = await _withOptionalFiles(
      body,
      fileFieldName: 'attachmentFiles',
      files: attachmentFiles,
    );
    final response = await _dio.post(
      '/api/services/requests',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listMyRequests({
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _dio.get(
      '/api/services/requests/mine',
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> getMyRequest(int requestId) async {
    final response = await _dio.get('/api/services/requests/$requestId');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateMyRequestStatus({
    required int requestId,
    required String status,
    String? note,
  }) async {
    final response = await _dio.post(
      '/api/services/requests/$requestId/status',
      data: {
        'status': status,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> respondToQuote({
    required int requestId,
    required int quoteId,
    required String action,
    String? note,
  }) async {
    final response = await _dio.post(
      '/api/services/requests/$requestId/quotes/$quoteId/respond',
      data: {
        'action': action,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getProviderWorkspace() async {
    final response = await _dio.get('/api/services/provider/workspace');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createProviderSubscriptionRequest(
    Map<String, dynamic> body, {
    LocalImageFile? logoFile,
    LocalImageFile? coverFile,
    LocalImageFile? profileImageFile,
  }) async {
    final requestData = await _withOptionalNamedFiles(
      body,
      files: {
        'logoFile': logoFile,
        'coverFile': coverFile,
        'profileImageFile': profileImageFile,
      },
    );
    final response = await _dio.post(
      '/api/services/provider/register',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getProviderSubscriptionStatus({
    required String phone,
    required String pin,
  }) async {
    final response = await _dio.post(
      '/api/services/provider/subscription/status',
      data: {'phone': phone, 'pin': pin},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> respondProviderSubscriptionOffer({
    required int requestId,
    required String phone,
    required String pin,
    required String action,
    int? offerId,
    String? note,
  }) async {
    final response = await _dio.post(
      '/api/services/provider/subscription/requests/$requestId/respond-offer',
      data: {
        'phone': phone,
        'pin': pin,
        'action': action,
        if (offerId != null) 'offerId': offerId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getProviderProfile() async {
    final response = await _dio.get('/api/services/provider/profile');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateProviderProfile(
    Map<String, dynamic> body, {
    LocalImageFile? logoFile,
    LocalImageFile? coverFile,
  }) async {
    final requestData = await _withOptionalNamedFiles(
      body,
      files: {
        'logoFile': logoFile,
        'coverFile': coverFile,
      },
    );
    final response = await _dio.patch(
      '/api/services/provider/profile',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createOffering(
    Map<String, dynamic> body, {
    List<LocalImageFile> mediaFiles = const [],
  }) async {
    final requestData = await _withOptionalFiles(
      body,
      fileFieldName: 'mediaFiles',
      files: mediaFiles,
    );
    final response = await _dio.post(
      '/api/services/provider/offerings',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateOffering(
    int offeringId,
    Map<String, dynamic> body, {
    List<LocalImageFile> mediaFiles = const [],
  }) async {
    final requestData = await _withOptionalFiles(
      body,
      fileFieldName: 'mediaFiles',
      files: mediaFiles,
    );
    final response = await _dio.patch(
      '/api/services/provider/offerings/$offeringId',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> replaceOfferingPricing({
    required int offeringId,
    required List<Map<String, dynamic>> pricingOptions,
  }) async {
    final response = await _dio.put(
      '/api/services/provider/offerings/$offeringId/pricing',
      data: {'pricingOptions': pricingOptions},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createPromotion(
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.post(
      '/api/services/provider/promotions',
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createPortfolioItem(
    Map<String, dynamic> body, {
    LocalImageFile? mediaFile,
  }) async {
    final requestData = await _withOptionalNamedFiles(
      body,
      files: {'mediaFile': mediaFile},
    );
    final response = await _dio.post(
      '/api/services/provider/portfolio',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> deletePortfolioItem(int portfolioId) async {
    final response = await _dio.delete(
      '/api/services/provider/portfolio/$portfolioId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createCategorySuggestion(
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.post(
      '/api/services/provider/category-suggestions',
      data: body,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listMyCategorySuggestions({
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _dio.get(
      '/api/services/provider/category-suggestions',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return _asMapList(response.data);
  }

  Future<List<Map<String, dynamic>>> listProviderRequests({
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _dio.get(
      '/api/services/provider/requests',
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> updateProviderRequestStatus({
    required int requestId,
    required String status,
    String? note,
    DateTime? scheduledStartAt,
    DateTime? scheduledEndAt,
  }) async {
    final response = await _dio.post(
      '/api/services/provider/requests/$requestId/status',
      data: {
        'status': status,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (scheduledStartAt != null)
          'scheduledStartAt': scheduledStartAt.toUtc().toIso8601String(),
        if (scheduledEndAt != null)
          'scheduledEndAt': scheduledEndAt.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createQuote({
    required int requestId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _dio.post(
      '/api/services/provider/requests/$requestId/quotes',
      data: payload,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> saveProvider(int providerId) async {
    final response = await _dio.post(
      '/api/services/public/providers/$providerId/save',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> unsaveProvider(int providerId) async {
    final response = await _dio.delete(
      '/api/services/public/providers/$providerId/save',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> saveOffering(int offeringId) async {
    final response = await _dio.post(
      '/api/services/public/offerings/$offeringId/save',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> unsaveOffering(int offeringId) async {
    final response = await _dio.delete(
      '/api/services/public/offerings/$offeringId/save',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listSavedProviders({
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _dio.get(
      '/api/services/public/saved/providers',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return _asMapList(response.data);
  }

  Future<List<Map<String, dynamic>>> listSavedOfferings({
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _dio.get(
      '/api/services/public/saved/offerings',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return _asMapList(response.data);
  }

  Future<List<Map<String, dynamic>>> listRecentViews({int limit = 20}) async {
    final response = await _dio.get(
      '/api/services/public/recent-views',
      queryParameters: {'limit': limit},
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> createReview(Map<String, dynamic> body) async {
    final response = await _dio.post('/api/services/reviews', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }
}

List<Map<String, dynamic>> _asMapList(dynamic data) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  if (data is Map && data['items'] is List) {
    final rows = List<dynamic>.from(data['items'] as List);
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  return const <Map<String, dynamic>>[];
}

Future<Object> _withOptionalFiles(
  Map<String, dynamic> body, {
  required String fileFieldName,
  required List<LocalImageFile> files,
}) async {
  if (files.isEmpty) return body;

  final data = <String, dynamic>{};
  body.forEach((key, value) {
    if (value == null) return;
    if (value is Map || value is List) {
      data[key] = jsonEncode(value);
      return;
    }
    data[key] = value;
  });

  final mappedFiles = <MultipartFile>[];
  for (final file in files) {
    mappedFiles.add(await file.toMultipartFile());
  }
  data[fileFieldName] = mappedFiles;

  return FormData.fromMap(data);
}

Future<Object> _withOptionalNamedFiles(
  Map<String, dynamic> body, {
  required Map<String, LocalImageFile?> files,
}) async {
  final hasAnyFile = files.values.any((f) => f != null);
  if (!hasAnyFile) return body;

  final data = <String, dynamic>{};
  body.forEach((key, value) {
    if (value == null) return;
    if (value is Map || value is List) {
      data[key] = jsonEncode(value);
      return;
    }
    data[key] = value;
  });

  for (final entry in files.entries) {
    final file = entry.value;
    if (file == null) continue;
    data[entry.key] = await file.toMultipartFile();
  }
  return FormData.fromMap(data);
}
