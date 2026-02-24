import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/files/local_image_file.dart';

class AuthApi {
  final Dio dio;

  AuthApi(this.dio);

  Future<Map<String, dynamic>> register(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final requestData = await _withOptionalFiles(
      body,
      files: {'imageFile': imageFile},
    );
    final response = await dio.post('/api/auth/register', data: requestData);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> login(Map<String, dynamic> body) async {
    final response = await dio.post('/api/auth/login', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> registerOwner(
    Map<String, dynamic> body, {
    LocalImageFile? ownerImageFile,
    LocalImageFile? merchantImageFile,
  }) async {
    final requestData = await _withOptionalFiles(
      body,
      files: {
        'ownerImageFile': ownerImageFile,
        'merchantImageFile': merchantImageFile,
      },
    );
    final response = await dio.post('/api/owner/register', data: requestData);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> registerDelivery(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    final requestData = await _withOptionalFiles(
      body,
      files: {'imageFile': imageFile},
    );
    final response = await dio.post(
      '/api/delivery/register',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> me() async {
    final response = await dio.get('/api/me');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateAccount(Map<String, dynamic> body) async {
    final response = await dio.patch('/api/auth/account', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }
}

Future<Object> _withOptionalFiles(
  Map<String, dynamic> body, {
  required Map<String, LocalImageFile?> files,
}) async {
  final hasAnyFile = files.values.any((f) => f != null);
  if (!hasAnyFile) return body;

  final map = <String, dynamic>{};
  body.forEach((key, value) {
    if (value == null) return;
    if (value is Map || value is List) {
      map[key] = jsonEncode(value);
      return;
    }
    map[key] = value;
  });

  for (final entry in files.entries) {
    final file = entry.value;
    if (file == null) continue;
    map[entry.key] = await file.toMultipartFile();
  }

  return FormData.fromMap(map);
}
