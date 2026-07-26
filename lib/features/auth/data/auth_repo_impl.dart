import 'package:maslaki/core/platform/app_flavor.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import '../../../core/files/local_image_file.dart';

import '../domain/auth_repo.dart';
import '../domain/auth_input_normalizer.dart';
import '../models/user_model.dart';
import 'auth_api.dart';

class AuthRepoImpl implements AuthRepo {
  final AuthApi api;
  final SecureStore store;

  AuthRepoImpl({required this.api, required this.store});

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
  }) async {
    final normalizedPhone = normalizeIraqiPhoneForAuth(phone);
    final normalizedPin = normalizeAuthPin(pin);

    final data = await api.register({
      'fullName': fullName,
      'phone': normalizedPhone,
      'pin': normalizedPin,
      'block': block,
      'buildingNumber': buildingNumber,
      'apartment': apartment,
      'analyticsConsentAccepted': analyticsConsentAccepted,
      'analyticsConsentVersion': analyticsConsentVersion,
    }, imageFile: imageFile);

    await _saveAuthPayload(data, store);
    return _readUser(data);
  }

  @override
  Future<Map<String, dynamic>> extractResidenceCard({
    required LocalImageFile cardImageFile,
  }) {
    return api.extractResidenceCard(cardImageFile: cardImageFile);
  }

  @override
  Future<UserModel> registerWithCard({
    required Map<String, dynamic> payload,
    LocalImageFile? imageFile,
    required LocalImageFile cardImageFile,
  }) async {
    final data = await api.registerWithCard(
      payload,
      imageFile: imageFile,
      cardImageFile: cardImageFile,
    );
    await _saveAuthPayload(data, store);
    return _readUser(data);
  }

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
    final normalizedPhone = normalizeIraqiPhoneForAuth(phone);
    final normalizedPin = normalizeAuthPin(pin);
    final normalizedMerchantPhone = normalizeIraqiPhoneForAuth(merchantPhone);
    final payload = <String, dynamic>{
      'phone': normalizedPhone,
      'pin': normalizedPin,
      'merchantName': merchantName.trim(),
      'merchantType': merchantType.trim(),
      'merchantActivityType': merchantActivityType.trim(),
      'merchantDescription': merchantDescription.trim(),
      'merchantPhone': normalizedMerchantPhone,
      'analyticsConsentAccepted': analyticsConsentAccepted,
      'analyticsConsentVersion': analyticsConsentVersion,
    };

    if (fullName != null && fullName.trim().isNotEmpty) {
      payload['fullName'] = fullName.trim();
    }
    if (block != null && block.trim().isNotEmpty) {
      payload['block'] = block.trim();
    }
    if (buildingNumber != null && buildingNumber.trim().isNotEmpty) {
      payload['buildingNumber'] = buildingNumber.trim();
    }
    if (apartment != null && apartment.trim().isNotEmpty) {
      payload['apartment'] = apartment.trim();
    }
    if (merchantDepartment != null && merchantDepartment.trim().isNotEmpty) {
      payload['merchantDepartment'] = merchantDepartment.trim().toLowerCase();
    }
    if (merchantDiscoverySubcategory != null &&
        merchantDiscoverySubcategory.trim().isNotEmpty) {
      payload['merchantDiscoverySubcategory'] = merchantDiscoverySubcategory
          .trim();
    }
    if (merchantDiscoverySubcategories != null) {
      payload['merchantDiscoverySubcategories'] =
          merchantDiscoverySubcategories;
    }
    if (merchantDiscoverySelectAll != null) {
      payload['merchantDiscoverySelectAll'] = merchantDiscoverySelectAll;
    }
    if (merchantImageUrl != null && merchantImageUrl.trim().isNotEmpty) {
      payload['merchantImageUrl'] = merchantImageUrl.trim();
    }
    if (merchantServiceFlags != null) {
      payload['merchantServiceFlags'] = merchantServiceFlags;
    }
    if (merchantBadges != null) {
      payload['merchantBadges'] = merchantBadges;
    }
    if (merchantSupportsChat != null) {
      payload['merchantSupportsChat'] = merchantSupportsChat;
    }
    if (merchantSupportsAttachments != null) {
      payload['merchantSupportsAttachments'] = merchantSupportsAttachments;
    }
    if (merchantSupportsPharmacyWorkflow != null) {
      payload['merchantSupportsPharmacyWorkflow'] =
          merchantSupportsPharmacyWorkflow;
    }

    final data = await api.registerOwner(
      payload,
      ownerImageFile: ownerImageFile,
      merchantImageFile: merchantImageFile,
    );

    await _saveAuthPayload(data, store);
    return _readUser(data);
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
    String? plateGovernorate,
    String? plateCategory,
    String? plateLetter,
    String? plateDigits,
    String? carColor,
    required bool analyticsConsentAccepted,
    String analyticsConsentVersion = 'analytics_v1',
    LocalImageFile? profileImageFile,
    LocalImageFile? carImageFile,
  }) async {
    final normalizedPhone = normalizeIraqiPhoneForAuth(phone);
    final normalizedPin = normalizeAuthPin(pin);

    await api.registerDelivery(
      {
        'fullName': fullName.trim(),
        'phone': normalizedPhone,
        'pin': normalizedPin,
        'block': block.trim(),
        'buildingNumber': buildingNumber.trim(),
        'apartment': apartment.trim(),
        'vehicleType': vehicleType.trim(),
        'carMake': carMake.trim(),
        'carModel': carModel.trim(),
        'carYear': carYear,
        'plateNumber': plateNumber.trim(),
        'plateGovernorate': plateGovernorate?.trim(),
        'plateCategory': plateCategory?.trim(),
        'plateLetter': plateLetter?.trim(),
        'plateDigits': plateDigits?.trim(),
        'carColor': carColor?.trim(),
        'analyticsConsentAccepted': analyticsConsentAccepted,
        'analyticsConsentVersion': analyticsConsentVersion,
      },
      profileImageFile: profileImageFile,
      carImageFile: carImageFile,
    );
  }

  @override
  Future<UserModel> login({required String phone, required String pin}) async {
    final normalizedPhone = normalizeIraqiPhoneForAuth(phone);
    final normalizedPin = normalizeAuthPin(pin);

    final data = await api.login({
      'phone': normalizedPhone,
      'pin': normalizedPin,
    });

    await _saveAuthPayload(data, store);
    return _readUser(data);
  }

  Future<UserModel> recoverSession({
    required String deviceSessionId,
    required String deviceRecoverySecret,
    required String deviceId,
  }) async {
    final data = await api.recoverSession({
      'deviceSessionId': deviceSessionId,
      'deviceRecoverySecret': deviceRecoverySecret,
      'deviceId': deviceId,
      'appFlavor': store.flavor.key,
    });
    await _saveAuthPayload(data, store);
    return _readUser(data);
  }

  @override
  Future<UserModel> me() async {
    final data = await api.me();
    return _readUser(data);
  }

  @override
  Future<UserModel> updateAccount({
    required String currentPin,
    String? newPhone,
    String? newPin,
  }) async {
    final body = <String, dynamic>{'currentPin': normalizeAuthPin(currentPin)};

    if (newPhone != null && newPhone.trim().isNotEmpty) {
      body['newPhone'] = normalizeIraqiPhoneForAuth(newPhone);
    }
    if (newPin != null && newPin.trim().isNotEmpty) {
      body['newPin'] = normalizeAuthPin(newPin);
    }

    final data = await api.updateAccount(body);
    return _readUser(data);
  }

  @override
  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {
      // If network fails, clear local auth anyway.
    }
    await store.clear();
  }
}

String _readToken(Map<String, dynamic> payload) {
  final rawToken =
      payload['token'] ?? payload['accessToken'] ?? payload['access_token'];
  if (rawToken is String && rawToken.trim().isNotEmpty) {
    return rawToken;
  }
  throw const FormatException('INVALID_TOKEN_PAYLOAD');
}

String? _readRefreshToken(Map<String, dynamic> payload) {
  final rawToken = payload['refreshToken'] ?? payload['refresh_token'];
  if (rawToken is String && rawToken.trim().isNotEmpty) {
    return rawToken.trim();
  }
  return null;
}

String? _readDeviceSessionId(Map<String, dynamic> payload) {
  final raw = payload['deviceSessionId'] ?? payload['device_session_id'];
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  return null;
}

String? _readSessionId(Map<String, dynamic> payload) {
  final raw = payload['sessionId'] ?? payload['session_id'];
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  if (raw is num) return raw.toString();
  return null;
}

String? _readDeviceRecoverySecret(Map<String, dynamic> payload) {
  final raw =
      payload['deviceRecoverySecret'] ?? payload['device_recovery_secret'];
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  return null;
}

Future<void> _saveAuthPayload(
  Map<String, dynamic> payload,
  SecureStore store,
) async {
  await store.saveAuthTokens(
    accessToken: _readToken(payload),
    refreshToken: _readRefreshToken(payload),
    sessionId: _readSessionId(payload),
    deviceSessionId: _readDeviceSessionId(payload),
    deviceRecoverySecret: _readDeviceRecoverySecret(payload),
  );
}

UserModel _readUser(Map<String, dynamic> payload) {
  final rawUser = payload['user'];
  if (rawUser is Map) {
    return UserModel.fromJson(Map<String, dynamic>.from(rawUser));
  }
  throw const FormatException('INVALID_USER_PAYLOAD');
}
