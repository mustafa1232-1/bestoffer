import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/platform/app_flavor.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/features/company/data/company_dio_client.dart';

class _FakeSecureStore extends SecureStore {
  _FakeSecureStore({
    String? token,
    String? deviceId,
  })  : _token = token,
        _deviceId = deviceId,
        super(flavor: AppFlavor.company);

  String? _token;
  String? _deviceId;

  @override
  Future<void> clear() async {
    _token = null;
    _deviceId = null;
  }

  @override
  Future<String?> readString(String key) async {
    if (key == 'device_id') return _deviceId;
    return null;
  }

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async {
    _token = token;
  }

  @override
  Future<void> writeString(String key, String value) async {
    if (key == 'device_id') {
      _deviceId = value;
    }
  }
}

class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('company dio client sends company surface headers', () async {
    final store = _FakeSecureStore(
      token: 'access-token',
      deviceId: 'company-device-1',
    );
    final adapter = _CapturingAdapter();
    final client = CompanyDioClient(store);
    client.dio.httpClientAdapter = adapter;
    client.dio.options.baseUrl = 'http://127.0.0.1';

    final response = await client.dio.get('/probe');

    expect(response.statusCode, 200);
    expect(adapter.lastOptions, isNotNull);
    expect(adapter.lastOptions!.headers['Authorization'], 'Bearer access-token');
    expect(adapter.lastOptions!.headers['X-App-Flavor'], 'company');
    expect(
      adapter.lastOptions!.headers['X-Client-Platform'],
      'flutter:company',
    );
    expect(adapter.lastOptions!.headers['X-Device-Id'], 'company-device-1');
  });
}
