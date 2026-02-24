import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/files/local_image_file.dart';

class MerchantsApi {
  final Dio dio;

  MerchantsApi(this.dio);

  Future<List<dynamic>> list({String? type}) async {
    final response = await dio.get(
      '/api/merchants',
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

  Future<List<dynamic>> listProducts(int merchantId) async {
    final response = await dio.get('/api/merchants/$merchantId/products');
    return List<dynamic>.from(response.data as List);
  }

  Future<List<dynamic>> listCategories(int merchantId) async {
    final response = await dio.get('/api/merchants/$merchantId/categories');
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

