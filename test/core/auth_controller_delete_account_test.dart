import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/files/local_image_file.dart';
import 'package:maslaki/core/network/dio_client.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/features/auth/domain/auth_repo.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';

class _MemorySecureStore extends SecureStore {
  final Map<String, String> _values = <String, String>{
    'access_token': 'access-token',
    'refresh_token': 'refresh-token',
  };

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> saveToken(String token) async {
    _values['access_token'] = token;
  }

  @override
  Future<void> saveAuthTokens({
    required String accessToken,
    String? refreshToken,
    String? sessionId,
    String? deviceSessionId,
    String? deviceRecoverySecret,
  }) async {
    _values['access_token'] = accessToken;
    if (refreshToken != null) _values['refresh_token'] = refreshToken;
    if (sessionId != null) _values['session_id'] = sessionId;
    if (deviceSessionId != null) {
      _values['device_session_id'] = deviceSessionId;
    }
    if (deviceRecoverySecret != null) {
      _values['device_recovery_secret'] = deviceRecoverySecret;
    }
  }

  @override
  Future<String?> readToken() async => _values['access_token'];

  @override
  Future<String?> readRefreshToken() async => _values['refresh_token'];

  @override
  Future<String?> readSessionId() async => _values['session_id'];

  @override
  Future<String?> readDeviceSessionId() async => _values['device_session_id'];

  @override
  Future<String?> readDeviceRecoverySecret() async =>
      _values['device_recovery_secret'];

  @override
  Future<void> saveGuestMode(bool enabled) async {
    if (enabled) {
      _values['guest_mode_active'] = '1';
    } else {
      _values.remove('guest_mode_active');
    }
  }

  @override
  Future<bool> readGuestMode() async => _values['guest_mode_active'] == '1';

  @override
  Future<void> clear() async {
    _values.clear();
  }
}

class _FakeAuthRepo implements AuthRepo {
  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }

  @override
  Future<UserModel> login({required String phone, required String pin}) =>
      throw UnimplementedError();

  @override
  Future<UserModel> me() => throw UnimplementedError();

  @override
  Future<UserModel> register({
    required String fullName,
    required String phone,
    required String pin,
    required String block,
    required String buildingNumber,
    required String apartment,
    required bool analyticsConsentAccepted,
    String analyticsConsentVersion = 'analytics_v1',
    LocalImageFile? imageFile,
  }) => throw UnimplementedError();

  @override
  Future<void> registerDelivery({
    required String fullName,
    required String phone,
    required String pin,
    required String block,
    required String buildingNumber,
    required String apartment,
    required String vehicleType,
    required String carMake,
    required String carModel,
    required int carYear,
    String? plateGovernorate,
    String? plateCategory,
    String? plateLetter,
    String? plateDigits,
    String? carColor,
    required String plateNumber,
    required bool analyticsConsentAccepted,
    String analyticsConsentVersion = 'analytics_v1',
    LocalImageFile? profileImageFile,
    LocalImageFile? carImageFile,
  }) => throw UnimplementedError();

  @override
  Future<UserModel> registerOwner({
    String? fullName,
    required String phone,
    required String pin,
    String? block,
    String? buildingNumber,
    String? apartment,
    required String merchantName,
    required String merchantType,
    required String merchantActivityType,
    String? merchantDepartment,
    String? merchantDiscoverySubcategory,
    List<String>? merchantDiscoverySubcategories,
    bool? merchantDiscoverySelectAll,
    required String merchantDescription,
    required String merchantPhone,
    String? merchantImageUrl,
    Map<String, dynamic>? merchantServiceFlags,
    List<String>? merchantBadges,
    bool? merchantSupportsChat,
    bool? merchantSupportsAttachments,
    bool? merchantSupportsPharmacyWorkflow,
    required bool analyticsConsentAccepted,
    String analyticsConsentVersion = 'analytics_v1',
    LocalImageFile? ownerImageFile,
    LocalImageFile? merchantImageFile,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> extractResidenceCard({
    required LocalImageFile cardImageFile,
  }) => throw UnimplementedError();

  @override
  Future<UserModel> registerWithCard({
    required Map<String, dynamic> payload,
    LocalImageFile? imageFile,
    required LocalImageFile cardImageFile,
  }) => throw UnimplementedError();

  @override
  Future<UserModel> updateAccount({
    required String currentPin,
    String? newPhone,
    String? newPin,
  }) => throw UnimplementedError();
}

class _DeleteAccountAdapter implements HttpClientAdapter {
  _DeleteAccountAdapter(this.statusCode);

  final int statusCode;
  int deleteCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'DELETE' && options.path == '/api/users/me') {
      deleteCalls += 1;
      return _json(statusCode, <String, dynamic>{'success': true});
    }
    if (options.method == 'POST' && options.path == '/api/auth/logout') {
      return _json(200, <String, dynamic>{'success': true});
    }
    return _json(404, <String, dynamic>{'message': 'NOT_FOUND'});
  }

  @override
  void close({bool force = false}) {}
}

class _SeededAuthController extends AuthController {
  _SeededAuthController(super.ref) {
    state = const AuthState(token: 'access-token');
  }
}

ResponseBody _json(int status, Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json; charset=utf-8'],
    },
  );
}

void main() {
  test(
    'deleteAccount clears local session only after backend success',
    () async {
      final store = _MemorySecureStore();
      final repo = _FakeAuthRepo();
      final adapter = _DeleteAccountAdapter(200);
      final dioClient = DioClient(store);
      dioClient.dio.options.baseUrl = 'http://127.0.0.1';
      dioClient.dio.httpClientAdapter = adapter;

      late _SeededAuthController controller;
      final container = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          dioClientProvider.overrideWithValue(dioClient),
          authRepoProvider.overrideWithValue(repo),
          authControllerProvider.overrideWith((ref) {
            controller = _SeededAuthController(ref);
            return controller;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(authControllerProvider.notifier);

      expect(await controller.deleteAccount(), isTrue);
      expect(adapter.deleteCalls, 1);
      expect(repo.logoutCalls, 1);
      expect(container.read(authControllerProvider).isAuthed, isFalse);
      expect(await store.readToken(), isNull);
    },
  );

  test(
    'deleteAccount keeps local session when backend rejects deletion',
    () async {
      final store = _MemorySecureStore();
      final repo = _FakeAuthRepo();
      final adapter = _DeleteAccountAdapter(500);
      final dioClient = DioClient(store);
      dioClient.dio.options.baseUrl = 'http://127.0.0.1';
      dioClient.dio.httpClientAdapter = adapter;

      late _SeededAuthController controller;
      final container = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          dioClientProvider.overrideWithValue(dioClient),
          authRepoProvider.overrideWithValue(repo),
          authControllerProvider.overrideWith((ref) {
            controller = _SeededAuthController(ref);
            return controller;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(authControllerProvider.notifier);

      expect(await controller.deleteAccount(), isFalse);
      expect(adapter.deleteCalls, 1);
      expect(repo.logoutCalls, 0);
      expect(container.read(authControllerProvider).isAuthed, isTrue);
      expect(await store.readToken(), 'access-token');
      expect(container.read(authControllerProvider).error, isNotEmpty);
    },
  );
}
