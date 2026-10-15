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
    String? workTitle,
    String? workCompany,
    double? latitude,
    double? longitude,
    String? referralCode,
    required bool analyticsConsentAccepted,
    String analyticsConsentVersion = 'analytics_v1',
    LocalImageFile? imageFile,
  });

  Future<Map<String, dynamic>> extractResidenceCard({
    required LocalImageFile cardImageFile,
  });

  Future<UserModel> registerWithCard({
    required Map<String, dynamic> payload,
    LocalImageFile? imageFile,
    required LocalImageFile cardImageFile,
  });

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
    double? latitude,
    double? longitude,
    required bool analyticsConsentAccepted,
    String analyticsConsentVersion = 'analytics_v1',
    LocalImageFile? ownerImageFile,
    LocalImageFile? merchantImageFile,
  });

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
    String? plateGovernorate,
    String? plateCategory,
    String? plateLetter,
    String? plateDigits,
    String? carColor,
    double? latitude,
    double? longitude,
    required bool analyticsConsentAccepted,
    String analyticsConsentVersion = 'analytics_v1',
    LocalImageFile? profileImageFile,
    LocalImageFile? carImageFile,
  });

  Future<UserModel> login({required String phone, required String pin});
  Future<void> requestPinReset({required String phone});
  Future<UserModel> completeTemporaryPinChange({
    required String currentPin,
    required String newPin,
  });

  Future<UserModel> me();

  Future<UserModel> updateAccount({
    required String currentPin,
    String? newPhone,
    String? newPin,
  });

  Future<void> logout();
}
