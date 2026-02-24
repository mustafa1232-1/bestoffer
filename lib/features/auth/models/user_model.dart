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

  UserModel({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.block,
    required this.buildingNumber,
    required this.apartment,
    required this.imageUrl,
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
  );
}
