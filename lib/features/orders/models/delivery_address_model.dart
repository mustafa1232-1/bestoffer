import '../../../core/utils/parsers.dart';

class DeliveryAddressModel {
  final int id;
  final String label;
  final String city;
  final String block;
  final String buildingNumber;
  final String apartment;
  final double? latitude;
  final double? longitude;
  final bool isDefault;

  const DeliveryAddressModel({
    required this.id,
    required this.label,
    required this.city,
    required this.block,
    required this.buildingNumber,
    required this.apartment,
    this.latitude,
    this.longitude,
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
      latitude: _parseOptionalDouble(j['latitude']),
      longitude: _parseOptionalDouble(j['longitude']),
      isDefault: j['is_default'] ?? j['isDefault'] ?? false,
    );
  }

  String get shortText =>
      '$city - بلوك $block، عمارة $buildingNumber، شقة $apartment';
}

double? _parseOptionalDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final parsed = double.tryParse('$value');
  return parsed?.isFinite == true ? parsed : null;
}
