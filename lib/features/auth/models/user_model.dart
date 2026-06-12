import '../../../core/utils/parsers.dart';

class UserModel {
  final int id;
  final String fullName;
  final String phone;
  final String role;
  final String block;
  final String buildingNumber;
  final String apartment;
  final String? imageUrl;
  final String? workTitle;
  final String? workCompany;
  final String? preferredLocale;
  final bool isSuperAdmin;
  final bool isTaxiCaptain;

  UserModel({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.block,
    required this.buildingNumber,
    required this.apartment,
    required this.imageUrl,
    required this.workTitle,
    required this.workCompany,
    required this.preferredLocale,
    required this.isSuperAdmin,
    this.isTaxiCaptain = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
    id: parseInt(j['id']),
    fullName: parseString(j['full_name'] ?? j['fullName']),
    phone: parseString(j['phone']),
    role: parseString(j['role'], fallback: 'user'),
    block: parseString(j['block']),
    buildingNumber: parseString(j['building_number'] ?? j['buildingNumber']),
    apartment: parseString(j['apartment']),
    imageUrl: parseNullableString(j['image_url'] ?? j['imageUrl']),
    workTitle: parseNullableString(j['work_title'] ?? j['workTitle']),
    workCompany: parseNullableString(j['work_company'] ?? j['workCompany']),
    preferredLocale: parseNullableString(
      j['preferred_locale'] ?? j['preferredLocale'],
    ),
    isSuperAdmin: parseBool(
      j['is_super_admin'] ?? j['isSuperAdmin'] ?? j['sa'],
      fallback: false,
    ),
    isTaxiCaptain: parseBool(
      j['is_taxi_captain'] ?? j['isTaxiCaptain'],
      fallback: false,
    ),
  );

  UserModel copyWith({
    String? fullName,
    String? phone,
    String? role,
    String? block,
    String? buildingNumber,
    String? apartment,
    String? imageUrl,
    String? workTitle,
    String? workCompany,
    String? preferredLocale,
    bool? isSuperAdmin,
    bool? isTaxiCaptain,
    bool clearImageUrl = false,
    bool clearWorkTitle = false,
    bool clearWorkCompany = false,
  }) {
    return UserModel(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      block: block ?? this.block,
      buildingNumber: buildingNumber ?? this.buildingNumber,
      apartment: apartment ?? this.apartment,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      workTitle: clearWorkTitle ? null : (workTitle ?? this.workTitle),
      workCompany: clearWorkCompany ? null : (workCompany ?? this.workCompany),
      preferredLocale: preferredLocale ?? this.preferredLocale,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      isTaxiCaptain: isTaxiCaptain ?? this.isTaxiCaptain,
    );
  }
}
