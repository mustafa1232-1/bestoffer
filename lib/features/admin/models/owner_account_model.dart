import '../../../core/utils/parsers.dart';

class OwnerAccountModel {
  final int id;
  final String fullName;
  final String phone;
  final String block;
  final String buildingNumber;
  final String apartment;

  const OwnerAccountModel({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.block,
    required this.buildingNumber,
    required this.apartment,
  });

  factory OwnerAccountModel.fromJson(Map<String, dynamic> j) {
    return OwnerAccountModel(
      id: parseInt(j['id']),
      fullName: parseString(j['full_name'] ?? j['fullName']),
      phone: parseString(j['phone']),
      block: parseString(j['block']),
      buildingNumber: parseString(j['building_number'] ?? j['buildingNumber']),
      apartment: parseString(j['apartment']),
    );
  }

  @override
  String toString() => '$fullName - $phone';
}
