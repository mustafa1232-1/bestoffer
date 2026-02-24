import '../../../core/utils/parsers.dart';

class PendingMerchantModel {
  final int id;
  final String name;
  final String type;
  final String? phone;
  final String? description;
  final String? ownerName;
  final String? ownerPhone;

  const PendingMerchantModel({
    required this.id,
    required this.name,
    required this.type,
    required this.phone,
    required this.description,
    required this.ownerName,
    required this.ownerPhone,
  });

  factory PendingMerchantModel.fromJson(Map<String, dynamic> j) {
    return PendingMerchantModel(
      id: parseInt(j['id']),
      name: parseString(j['name']),
      type: parseString(j['type']),
      phone: parseNullableString(j['phone']),
      description: parseNullableString(j['description']),
      ownerName: parseNullableString(j['owner_full_name']),
      ownerPhone: parseNullableString(j['owner_phone']),
    );
  }
}
