import '../../../core/utils/parsers.dart';

class DeliveryAgentModel {
  final int id;
  final String fullName;
  final String phone;

  const DeliveryAgentModel({
    required this.id,
    required this.fullName,
    required this.phone,
  });

  factory DeliveryAgentModel.fromJson(Map<String, dynamic> j) {
    return DeliveryAgentModel(
      id: parseInt(j['id']),
      fullName: parseString(j['full_name'] ?? j['fullName']),
      phone: parseString(j['phone']),
    );
  }
}
