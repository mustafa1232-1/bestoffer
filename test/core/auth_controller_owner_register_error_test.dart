import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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

class _ThrowingAuthRepo implements AuthRepo {
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
  }) async {
    final requestOptions = RequestOptions(path: '/api/owner/register');
    throw DioException(
      requestOptions: requestOptions,
      response: Response<Map<String, dynamic>>(
        requestOptions: requestOptions,
        statusCode: 409,
        data: <String, dynamic>{'message': 'OWNER_ALREADY_HAS_MERCHANT'},
      ),
      type: DioExceptionType.badResponse,
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<UserModel> login({required String phone, required String pin}) {
    throw UnimplementedError();
  }

  @override
  Future<UserModel> me() {
    throw UnimplementedError();
  }

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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> extractResidenceCard({
    required LocalImageFile cardImageFile,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserModel> registerWithCard({
    required Map<String, dynamic> payload,
    LocalImageFile? imageFile,
    required LocalImageFile cardImageFile,
  }) {
    throw UnimplementedError();
  }

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
    required String plateNumber,
    String? carColor,
    required bool analyticsConsentAccepted,
    String analyticsConsentVersion = 'analytics_v1',
    LocalImageFile? profileImageFile,
    LocalImageFile? carImageFile,
  }) async {}

  @override
  Future<UserModel> updateAccount({
    required String currentPin,
    String? newPhone,
    String? newPin,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  test(
    'owner register duplicate merchant surfaces a specific message',
    () async {
      final store = _MemorySecureStore();
      final container = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          authRepoProvider.overrideWithValue(_ThrowingAuthRepo()),
        ],
      );
      addTearDown(container.dispose);

      Intl.defaultLocale = 'en';

      final controller = container.read(authControllerProvider.notifier);
      await controller.registerOwner({
        'fullName': 'Owner Name',
        'phone': '07700000000',
        'pin': '1234',
        'merchantName': 'My Store',
        'merchantType': 'market',
        'merchantActivityType': 'grocery',
        'merchantDescription': 'Test store',
        'merchantPhone': '07700000000',
        'analyticsConsentAccepted': true,
        'analyticsConsentVersion': 'analytics_v1',
      });

      final state = container.read(authControllerProvider);
      expect(
        state.error,
        'This owner account is already linked to another store.',
      );
      expect(state.errorCode, 'OWNER_ALREADY_HAS_MERCHANT');
      expect(state.isAuthed, isFalse);
    },
  );
}
