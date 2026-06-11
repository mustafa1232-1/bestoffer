import 'dart:math';

import 'package:dio/dio.dart';

import '../../../core/constants/api.dart';
import 'company_secure_store.dart';

class CompanyDioClient {
  final Dio dio;
  final CompanySecureStore store;

  CompanyDioClient(this.store)
    : dio = Dio(
        BaseOptions(
          baseUrl: Api.baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          responseType: ResponseType.json,
          headers: {'Accept': 'application/json; charset=utf-8'},
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await store.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          final deviceId = await _ensureDeviceId();
          options.headers['X-Device-Id'] = deviceId;
          options.headers['X-Client-Platform'] = 'company_portal_flutter';
          handler.next(options);
        },
      ),
    );
  }

  Future<String> _ensureDeviceId() async {
    final existing = await store.readDeviceId();
    if (existing != null && existing.trim().isNotEmpty) return existing.trim();
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await store.writeDeviceId(value);
    return value;
  }
}
