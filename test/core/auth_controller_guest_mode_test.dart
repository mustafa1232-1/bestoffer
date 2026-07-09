import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maslaki/core/files/local_image_file.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/features/auth/domain/auth_repo.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';

class _MemorySecureStore extends SecureStore {
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
}

class _FakeAuthRepo implements AuthRepo {
  @override
  Future<UserModel> me() {
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
  }) =>
      throw UnimplementedError();

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
  }) =>
      throw UnimplementedError();

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
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> extractResidenceCard({
    required LocalImageFile cardImageFile,
  }) =>
      throw UnimplementedError();

  @override
  Future<UserModel> registerWithCard({
    required Map<String, dynamic> payload,
    LocalImageFile? imageFile,
    required LocalImageFile cardImageFile,
  }) =>
      throw UnimplementedError();

  @override
  Future<UserModel> updateAccount({
    required String currentPin,
    String? newPhone,
    String? newPin,
  }) =>
      throw UnimplementedError();
}

void main() {
  test('invalid stored token downgrades to guest mode and clears auth token', () async {
    final store = _MemorySecureStore();
    await store.saveAuthTokens(accessToken: 'stale-token');

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
    expect(state.isGuest, isTrue);
    expect(state.token, isNull);
    expect(state.user, isNull);
    expect(await store.readGuestMode(), isTrue);
    expect(await store.readToken(), isNull);
  });
}
