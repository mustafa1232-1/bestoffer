import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/platform/app_flavor.dart';
import '../../../core/storage/secure_storage.dart';

class CompanyDioClient {
  CompanyDioClient([SecureStore? store])
      : _client = DioClient(store ?? SecureStore(flavor: AppFlavor.company));

  final DioClient _client;

  Dio get dio => _client.dio;
}
