import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/files/local_image_file.dart';

class MerchantsApi {
  final Dio dio;

  MerchantsApi(this.dio);

  static final _publicOptions = Options(extra: {'skipAuth': true});

  Future<List<dynamic>> list({
    String? type,
    String? search,
    String? activityType,
    String? discoverySubcategory,
  }) async {
    final normalizedSearch = search?.trim();
    final params = <String, dynamic>{};
    if (type != null && type.trim().isNotEmpty) {
      params['type'] = type;
    }
    if (activityType != null && activityType.trim().isNotEmpty) {
      params['activityType'] = activityType.trim();
    }
    if (discoverySubcategory != null &&
        discoverySubcategory.trim().isNotEmpty) {
      params['discoverySubcategory'] = discoverySubcategory.trim();
    }
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      params['search'] = normalizedSearch;
    }
    final response = await dio.get(
      '/api/merchants',
      queryParameters: params.isEmpty ? null : params,
      options: _publicOptions,
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> customerDiscovery({required String type}) async {
    final response = await dio.get(
      '/api/merchants/discovery',
      queryParameters: {'type': type},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> listActivities() async {
    final response = await dio.get(
      '/api/merchants/activities',
      options: _publicOptions,
    );
    final data = response.data;
    if (data is Map && data['items'] is List) {
      return List<dynamic>.from(data['items'] as List);
    }
    if (data is List) return List<dynamic>.from(data);
    return const <dynamic>[];
  }

  Future<List<dynamic>> listDiscoveryOptions({
    required String activityType,
  }) async {
    final response = await dio.get(
      '/api/merchants/discovery/options',
      queryParameters: {'activityType': activityType},
      options: _publicOptions,
    );
    final data = response.data;
    if (data is Map && data['items'] is List) {
      return List<dynamic>.from(data['items'] as List);
    }
    if (data is List) return List<dynamic>.from(data);
    return const <dynamic>[];
  }

  Future<List<dynamic>> adBoard({String? type}) async {
    final response = await dio.get(
      '/api/merchants/ad-board',
      queryParameters: type == null ? null : {'type': type},
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> create(
    Map<String, dynamic> body, {
    LocalImageFile? merchantImageFile,
    LocalImageFile? ownerImageFile,
  }) async {
    final requestData = await _withOptionalFiles(
      body,
      merchantImageFile: merchantImageFile,
      ownerImageFile: ownerImageFile,
    );

    final response = await dio.post('/api/merchants', data: requestData);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> listProducts(
    int merchantId, {
    int limit = 80,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '/api/merchants/$merchantId/products',
      queryParameters: {'limit': limit, 'offset': offset},
      options: _publicOptions,
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> listCategories(int merchantId) async {
    final response = await dio.get(
      '/api/merchants/$merchantId/categories',
      options: _publicOptions,
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> getById(int merchantId) async {
    final response = await dio.get(
      '/api/merchants/$merchantId',
      options: _publicOptions,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> nearby({
    required double latitude,
    required double longitude,
    double? radiusKm,
    int? limit,
    String? type,
  }) async {
    final response = await dio.get(
      '/api/merchants/nearby',
      queryParameters: {
        'lat': latitude,
        'lng': longitude,
        // ignore: use_null_aware_elements
        if (radiusKm != null) 'radiusKm': radiusKm,
        // ignore: use_null_aware_elements
        if (limit != null) 'limit': limit,
        if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
      },
    );
    return List<dynamic>.from(response.data as List);
  }
}

Future<Object> _withOptionalFiles(
  Map<String, dynamic> body, {
  required LocalImageFile? merchantImageFile,
  required LocalImageFile? ownerImageFile,
}) async {
  if (merchantImageFile == null && ownerImageFile == null) return body;

  final map = <String, dynamic>{};
  final owner = body['owner'];

  body.forEach((key, value) {
    if (value == null || key == 'owner') return;
    if (value is Map || value is List) {
      map[key] = jsonEncode(value);
      return;
    }
    map[key] = value;
  });

  if (owner is Map<String, dynamic>) {
    map['ownerFullName'] = owner['fullName'];
    map['ownerPhone'] = owner['phone'];
    map['ownerPin'] = owner['pin'];
    map['ownerBlock'] = owner['block'];
    map['ownerBuildingNumber'] = owner['buildingNumber'];
    map['ownerApartment'] = owner['apartment'];
    map['ownerImageUrl'] = owner['imageUrl'];
  }

  if (merchantImageFile != null) {
    map['merchantImageFile'] = await merchantImageFile.toMultipartFile();
  }

  if (ownerImageFile != null) {
    map['ownerImageFile'] = await ownerImageFile.toMultipartFile();
  }

  return FormData.fromMap(map);
}
