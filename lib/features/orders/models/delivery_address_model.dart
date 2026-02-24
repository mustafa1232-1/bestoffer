import '../../../core/utils/parsers.dart';

class DeliveryAddressModel {
  final int id;
  final String label;
  final String city;
  final String block;
  final String buildingNumber;
  final String apartment;
  final bool isDefault;

  const DeliveryAddressModel({
    required this.id,
    required this.label,
    required this.city,
    required this.block,
    required this.buildingNumber,
    required this.apartment,
    required this.isDefault,
  });

  factory DeliveryAddressModel.fromJson(Map<String, dynamic> j) {
    return DeliveryAddressModel(
      id: parseInt(j['id']),
      label: parseString(j['label']),
      city: parseString(j['city'], fallback: 'مدينة بسماية'),
      block: parseString(j['block']),
      buildingNumber: parseString(j['building_number'] ?? j['buildingNumber']),
      apartment: parseString(j['apartment']),
      isDefault: j['is_default'] ?? j['isDefault'] ?? false,
    );
  }

  String get shortText => '$city - بلوك $block، عمارة $buildingNumber، شقة $apartment';
}
