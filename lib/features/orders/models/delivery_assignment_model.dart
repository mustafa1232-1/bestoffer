import '../../../core/utils/parsers.dart';

class DeliveryAssignmentDriverModel {
  final int id;
  final String? name;
  final String? photoUrl;
  final String? phone;
  final double? rating;
  final String? availabilityStatus;
  final String? coverageBlock;
  final String? courierSource;
  final bool isMerchantDelivery;
  final String? vehicleType;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? vehiclePlateNumber;

  const DeliveryAssignmentDriverModel({
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.phone,
    required this.rating,
    required this.availabilityStatus,
    required this.coverageBlock,
    required this.courierSource,
    required this.isMerchantDelivery,
    required this.vehicleType,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.vehiclePlateNumber,
  });

  factory DeliveryAssignmentDriverModel.fromJson(Map<String, dynamic> json) {
    return DeliveryAssignmentDriverModel(
      id: parseInt(json['id'] ?? json['userId'] ?? json['user_id']),
      name: parseNullableString(json['name'] ?? json['fullName'] ?? json['full_name']),
      photoUrl: parseNullableString(
        json['photoUrl'] ?? json['photo_url'] ?? json['imageUrl'] ?? json['image_url'],
      ),
      phone: parseNullableString(json['phone']),
      rating: json['rating'] == null ? null : parseDouble(json['rating']),
      availabilityStatus: parseNullableString(
        json['availabilityStatus'] ?? json['availability_status'],
      ),
      coverageBlock: parseNullableString(
        json['coverageBlock'] ?? json['coverage_block'],
      ),
      courierSource: parseNullableString(
        json['courierSource'] ?? json['courier_source'],
      ),
      isMerchantDelivery:
          (json['isMerchantDelivery'] ?? json['is_merchant_delivery']) == true,
      vehicleType: parseNullableString(
        json['vehicleType'] ?? json['vehicle_type'],
      ),
      vehicleModel: parseNullableString(
        json['vehicleModel'] ?? json['vehicle_model'],
      ),
      vehicleColor: parseNullableString(
        json['vehicleColor'] ?? json['vehicle_color'],
      ),
      vehiclePlateNumber: parseNullableString(
        json['vehiclePlateNumber'] ?? json['vehicle_plate_number'],
      ),
    );
  }
}

class OrderDeliveryAssignmentModel {
  final String assignmentStatus;
  final int? assignmentId;
  final DateTime? assignedAt;
  final DateTime? endedAt;
  final String? endedReason;
  final int? orderId;
  final DeliveryAssignmentDriverModel? driver;

  const OrderDeliveryAssignmentModel({
    required this.assignmentStatus,
    required this.assignmentId,
    required this.assignedAt,
    required this.endedAt,
    required this.endedReason,
    required this.orderId,
    required this.driver,
  });

  bool get isAssigned => assignmentStatus == 'ASSIGNED' && driver != null;

  bool get isPendingNoDriver => assignmentStatus == 'PENDING_NO_DRIVER';

  bool get isTerminal =>
      assignmentStatus == 'COMPLETED' || assignmentStatus == 'CANCELLED';

  factory OrderDeliveryAssignmentModel.fromJson(Map<String, dynamic> json) {
    final driverRaw = json['driver'];
    return OrderDeliveryAssignmentModel(
      assignmentStatus: parseString(
        json['assignmentStatus'] ?? json['assignment_status'],
        fallback: 'NOT_REQUIRED',
      ).trim().toUpperCase(),
      assignmentId: json['assignmentId'] == null
          ? (json['assignment_id'] == null ? null : parseInt(json['assignment_id']))
          : parseInt(json['assignmentId']),
      assignedAt: _parseDate(
        json['assignedAt'] ?? json['assigned_at'] ?? json['requested_at'],
      ),
      endedAt: _parseDate(json['endedAt'] ?? json['ended_at']),
      endedReason: parseNullableString(
        json['endedReason'] ?? json['ended_reason'],
      ),
      orderId: json['orderId'] == null
          ? (json['order_id'] == null ? null : parseInt(json['order_id']))
          : parseInt(json['orderId']),
      driver: driverRaw is Map
          ? DeliveryAssignmentDriverModel.fromJson(
              Map<String, dynamic>.from(driverRaw),
            )
          : null,
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final text = '$value';
  if (text.trim().isEmpty) return null;
  return DateTime.tryParse(text);
}
