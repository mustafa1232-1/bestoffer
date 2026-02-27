import '../models/user_model.dart';
import '../../../core/files/local_image_file.dart';

abstract class AuthRepo {
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
  });

  Future<UserModel> registerOwner({
    required String fullName,
    required String phone,
    required String pin,
    required String block,
    required String buildingNumber,
    required String apartment,
    required String merchantName,
    required String merchantType,
    required String merchantDescription,
    required String merchantPhone,
    required String merchantImageUrl,
    required bool analyticsConsentAccepted,
    String analyticsConsentVersion = 'analytics_v1',
    LocalImageFile? ownerImageFile,
    LocalImageFile? merchantImageFile,
  });

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
  });

  Future<UserModel> login({required String phone, required String pin});

  Future<UserModel> me();

  Future<UserModel> updateAccount({
    required String currentPin,
    String? newPhone,
    String? newPin,
  });

  Future<void> logout();
}
