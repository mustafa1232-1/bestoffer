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

  Future<Map<String, dynamic>> extractResidenceCard({
    required LocalImageFile cardImageFile,
  }) async {
    final requestData = await _withOptionalFiles(
      const <String, dynamic>{},
      files: {'cardImageFile': cardImageFile},
    );
    final response = await dio.post(
      '/api/auth/ocr/extract-residence-card',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> registerWithCard(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
    required LocalImageFile cardImageFile,
  }) async {
    final requestData = await _withOptionalFiles(
      body,
      files: {'imageFile': imageFile, 'cardImageFile': cardImageFile},
    );
    final response = await dio.post(
      '/api/auth/register-with-card',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> login(Map<String, dynamic> body) async {
    final response = await dio.post('/api/auth/login', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> recoverSession(Map<String, dynamic> body) async {
    final response = await dio.post(
      '/api/auth/session/recover',
      data: body,
      options: Options(
        extra: const {
          'skipSigning': true,
          'skipAuthRefresh': true,
          'skipTerminalSessionInvalidation': true,
        },
      ),
    );
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
    LocalImageFile? profileImageFile,
    LocalImageFile? carImageFile,
  }) async {
    final requestData = await _withOptionalFiles(
      body,
      files: {
        'profileImageFile': profileImageFile,
        'carImageFile': carImageFile,
      },
    );
    final response = await dio.post(
      '/api/taxi/captain/register',
      data: requestData,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> me() async {
    try {
      final response = await dio.get('/api/users/me');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      final fallback = await dio.get('/api/me');
      return Map<String, dynamic>.from(fallback.data as Map);
    }
  }

  Future<Map<String, dynamic>> updateAccount(Map<String, dynamic> body) async {
    try {
      final response = await dio.patch('/api/users/me', data: body);
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      final fallback = await dio.patch('/api/auth/account', data: body);
      return Map<String, dynamic>.from(fallback.data as Map);
    }
  }

  Future<void> logout() async {
    await dio.post('/api/auth/logout');
  }

  Future<void> logoutAll() async {
    await dio.post('/api/auth/logout-all');
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    try {
      final response = await dio.get('/api/users/me/sessions');
      final rows = List<dynamic>.from(response.data as List? ?? const []);
      return rows
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      final fallback = await dio.get('/api/auth/sessions');
      final rows = List<dynamic>.from(fallback.data as List? ?? const []);
      return rows
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    }
  }

  Future<void> revokeSession(int sessionId) async {
    await dio.delete('/api/users/me/sessions/$sessionId');
  }

  Future<Map<String, dynamic>> deleteMyAccount({
    String? reasonCode,
    String? note,
  }) async {
    final response = await dio.delete(
      '/api/users/me',
      data: {
        if (reasonCode != null && reasonCode.trim().isNotEmpty)
          'reasonCode': reasonCode.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response.data as Map? ?? const {});
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
