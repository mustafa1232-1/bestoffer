import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/files/local_image_file.dart';
import 'package:maslaki/core/network/dio_client.dart';
import 'package:maslaki/core/network/session_invalidation.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/features/auth/domain/auth_repo.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';

class _MemorySecureStore extends SecureStore {
  _MemorySecureStore({
    String? accessToken,
    String? refreshToken,
    String? deviceId,
    String? sessionId,
    String? deviceSessionId,
    String? deviceRecoverySecret,
  }) {
    if (accessToken != null) _values['access_token'] = accessToken;
    if (refreshToken != null) _values['refresh_token'] = refreshToken;
    _values['device_id'] = deviceId ?? 'device-1';
    if (sessionId != null) _values['session_id'] = sessionId;
    if (deviceSessionId != null) {
      _values['device_session_id'] = deviceSessionId;
    }
    if (deviceRecoverySecret != null) {
      _values['device_recovery_secret'] = deviceRecoverySecret;
    }
  }

  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> readString(String key) async {
    return _values[key];
  }

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
    if (refreshToken != null && refreshToken.trim().isNotEmpty) {
      _values['refresh_token'] = refreshToken.trim();
    }
    if (sessionId != null && sessionId.trim().isNotEmpty) {
      _values['session_id'] = sessionId.trim();
    }
    if (deviceSessionId != null && deviceSessionId.trim().isNotEmpty) {
      _values['device_session_id'] = deviceSessionId.trim();
    }
    if (deviceRecoverySecret != null &&
        deviceRecoverySecret.trim().isNotEmpty) {
      _values['device_recovery_secret'] = deviceRecoverySecret.trim();
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

  String? value(String key) => _values[key];
}

class _FakeAuthRepo implements AuthRepo {
  _FakeAuthRepo({this.user});

  final UserModel? user;

  @override
  Future<UserModel> me() {
    final currentUser = user;
    if (currentUser != null) return Future<UserModel>.value(currentUser);
    final requestOptions = RequestOptions(path: '/api/users/me');
    throw DioException(
      requestOptions: requestOptions,
      response: Response<Map<String, dynamic>>(
        requestOptions: requestOptions,
        statusCode: 401,
        data: <String, dynamic>{'message': 'INVALID_TOKEN'},
      ),
      type: DioExceptionType.badResponse,
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<UserModel> login({required String phone, required String pin}) =>
      throw UnimplementedError();

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
  Future<UserModel> registerDelivery({
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
    required String plateNumber,
    String? carColor,
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

class _RecoveryAdapter implements HttpClientAdapter {
  _RecoveryAdapter({this.failRecovery = false});

  final bool failRecovery;
  int recoverCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/api/auth/session/recover') {
      recoverCount++;
      if (failRecovery) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'offline',
        );
      }
      return _json(200, <String, dynamic>{
        'token': 'recovered-token',
        'refreshToken': 'refresh-recovered',
        'sessionId': 'session-recovered',
        'deviceSessionId': 'device-session-1',
        'deviceRecoverySecret': 'secret-1-012345678901234',
      });
    }
    return _json(404, <String, dynamic>{'message': 'NOT_FOUND'});
  }

  @override
  void close({bool force = false}) {}
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
  setUp(() {
    SessionRecoveryCoordinator.instance.reset();
  });

  test(
    'invalid stored token stays recoverable and does not downgrade to guest mode',
    () async {
      final store = _MemorySecureStore();
      await store.saveAuthTokens(
        accessToken: 'stale-token',
        refreshToken: 'refresh-token',
      );

      final container = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          authRepoProvider.overrideWithValue(_FakeAuthRepo()),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);
      await controller.bootstrap();

      final state = container.read(authControllerProvider);
      expect(state.isGuest, isFalse);
      expect(state.token, 'stale-token');
      expect(state.user, isNull);
      expect(await store.readGuestMode(), isFalse);
      expect(await store.readToken(), 'stale-token');
    },
  );

  test(
    'missing stored token recovers device session before deciding guest mode',
    () async {
      final store = _MemorySecureStore(
        deviceId: 'device-1',
        deviceSessionId: 'device-session-1',
        deviceRecoverySecret: 'secret-1-012345678901234',
      );
      await store.saveGuestMode(true);
      final adapter = _RecoveryAdapter();
      final dioClient = DioClient(store);
      dioClient.dio.httpClientAdapter = adapter;
      dioClient.dio.options.baseUrl = 'http://127.0.0.1';

      final container = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          dioClientProvider.overrideWithValue(dioClient),
          authRepoProvider.overrideWithValue(
            _FakeAuthRepo(
              user: UserModel.fromJson(const <String, dynamic>{
                'id': 7,
                'full_name': 'Recovered User',
                'phone': '07700000000',
                'role': 'delivery',
                'block': 'A',
                'building_number': '1',
                'apartment': '2',
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);
      await controller.bootstrap();

      final state = container.read(authControllerProvider);
      expect(adapter.recoverCount, 1);
      expect(state.isGuest, isFalse);
      expect(state.sessionRecoveryPending, isFalse);
      expect(state.token, 'recovered-token');
      expect(state.user?.id, 7);
      expect(await store.readGuestMode(), isFalse);
      expect(store.value('access_token'), 'recovered-token');
    },
  );

  test(
    'recovery failure stays pending and does not switch to guest automatically',
    () async {
      final store = _MemorySecureStore(
        deviceId: 'device-1',
        deviceSessionId: 'device-session-1',
        deviceRecoverySecret: 'secret-1-012345678901234',
      );
      final adapter = _RecoveryAdapter(failRecovery: true);
      final dioClient = DioClient(store);
      dioClient.dio.httpClientAdapter = adapter;
      dioClient.dio.options.baseUrl = 'http://127.0.0.1';

      final container = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          dioClientProvider.overrideWithValue(dioClient),
          authRepoProvider.overrideWithValue(_FakeAuthRepo()),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);
      await controller.bootstrap();

      final state = container.read(authControllerProvider);
      expect(adapter.recoverCount, 1);
      expect(state.isGuest, isFalse);
      expect(state.sessionRecoveryPending, isTrue);
      expect(store.value('device_session_id'), 'device-session-1');
      expect(store.value('device_recovery_secret'), 'secret-1-012345678901234');
      expect(await store.readGuestMode(), isFalse);
    },
  );
}
