import '../../../core/utils/parsers.dart';

class PendingDeliveryAccountModel {
  final int id;
  final String fullName;
  final String phone;
  final String block;
  final String buildingNumber;
  final String apartment;
  final DateTime? createdAt;
  final String vehicleType;
  final String carMake;
  final String carModel;
  final int carYear;
  final String? carColor;
  final String plateNumber;
  final String? profileImageUrl;
  final String? carImageUrl;

  const PendingDeliveryAccountModel({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.block,
    required this.buildingNumber,
    required this.apartment,
    required this.createdAt,
    required this.vehicleType,
    required this.carMake,
    required this.carModel,
    required this.carYear,
    required this.carColor,
    required this.plateNumber,
    required this.profileImageUrl,
    required this.carImageUrl,
  });

  factory PendingDeliveryAccountModel.fromJson(Map<String, dynamic> json) {
    return PendingDeliveryAccountModel(
      id: parseInt(json['id']),
      fullName: parseString(json['fullName'] ?? json['full_name']),
      phone: parseString(json['phone']),
      block: parseString(json['block']),
      buildingNumber: parseString(
        json['buildingNumber'] ?? json['building_number'],
      ),
      apartment: parseString(json['apartment']),
      createdAt: parseNullableDateTime(json['createdAt'] ?? json['created_at']),
      vehicleType: parseString(json['vehicleType'] ?? json['vehicle_type']),
      carMake: parseString(json['carMake'] ?? json['car_make']),
      carModel: parseString(json['carModel'] ?? json['car_model']),
      carYear: parseInt(json['carYear'] ?? json['car_year']),
      carColor: parseNullableString(json['carColor'] ?? json['car_color']),
      plateNumber: parseString(json['plateNumber'] ?? json['plate_number']),
      profileImageUrl: parseNullableString(
        json['profileImageUrl'] ?? json['profile_image_url'],
      ),
      carImageUrl: parseNullableString(
        json['carImageUrl'] ?? json['car_image_url'],
      ),
    );
  }
}
