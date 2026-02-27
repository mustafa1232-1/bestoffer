import 'package:bestoffer/core/storage/secure_storage.dart';
import '../../../core/files/local_image_file.dart';

import '../domain/auth_repo.dart';
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
    final normalizedPhone = _normalizeInput(phone);
    final normalizedPin = _normalizeInput(pin);

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

    await store.saveToken(_readToken(data));
    return _readUser(data);
  }

  @override
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
  }) async {
    final normalizedPhone = _normalizeInput(phone);
    final normalizedPin = _normalizeInput(pin);
    final normalizedMerchantPhone = _normalizeInput(merchantPhone);

    final data = await api.registerOwner(
      {
        'fullName': fullName.trim(),
        'phone': normalizedPhone,
        'pin': normalizedPin,
        'block': block.trim(),
        'buildingNumber': buildingNumber.trim(),
        'apartment': apartment.trim(),
        'merchantName': merchantName.trim(),
        'merchantType': merchantType.trim(),
        'merchantDescription': merchantDescription.trim(),
        'merchantPhone': normalizedMerchantPhone,
        'merchantImageUrl': merchantImageUrl.trim(),
        'analyticsConsentAccepted': analyticsConsentAccepted,
        'analyticsConsentVersion': analyticsConsentVersion,
      },
      ownerImageFile: ownerImageFile,
      merchantImageFile: merchantImageFile,
    );

    await store.saveToken(_readToken(data));
    return _readUser(data);
  }

  @override
  Future<UserModel> registerDelivery({
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
    final normalizedPhone = _normalizeInput(phone);
    final normalizedPin = _normalizeInput(pin);

    final data = await api.registerDelivery({
      'fullName': fullName.trim(),
      'phone': normalizedPhone,
      'pin': normalizedPin,
      'block': block.trim(),
      'buildingNumber': buildingNumber.trim(),
      'apartment': apartment.trim(),
      'analyticsConsentAccepted': analyticsConsentAccepted,
      'analyticsConsentVersion': analyticsConsentVersion,
    }, imageFile: imageFile);

    await store.saveToken(_readToken(data));
    return _readUser(data);
  }

  @override
  Future<UserModel> login({required String phone, required String pin}) async {
    final normalizedPhone = _normalizeInput(phone);
    final normalizedPin = _normalizeInput(pin);

    final data = await api.login({
      'phone': normalizedPhone,
      'pin': normalizedPin,
    });

    await store.saveToken(_readToken(data));
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
    final body = <String, dynamic>{'currentPin': _normalizeInput(currentPin)};

    if (newPhone != null && newPhone.trim().isNotEmpty) {
      body['newPhone'] = _normalizeInput(newPhone);
    }
    if (newPin != null && newPin.trim().isNotEmpty) {
      body['newPin'] = _normalizeInput(newPin);
    }

    final data = await api.updateAccount(body);
    return _readUser(data);
  }

  @override
  Future<void> logout() => store.clear();
}

String _readToken(Map<String, dynamic> payload) {
  final rawToken = payload['token'];
  if (rawToken is String && rawToken.trim().isNotEmpty) {
    return rawToken;
  }
  throw const FormatException('INVALID_TOKEN_PAYLOAD');
}

UserModel _readUser(Map<String, dynamic> payload) {
  final rawUser = payload['user'];
  if (rawUser is Map) {
    return UserModel.fromJson(Map<String, dynamic>.from(rawUser));
  }
  throw const FormatException('INVALID_USER_PAYLOAD');
}

String _normalizeInput(String value) => _normalizeArabicDigits(value).trim();

String _normalizeArabicDigits(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + (rune - 0x0660));
      continue;
    }
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + (rune - 0x06F0));
      continue;
    }
    out.writeCharCode(rune);
  }
  return out.toString();
}
