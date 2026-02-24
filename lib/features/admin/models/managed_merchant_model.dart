import '../../../core/utils/parsers.dart';

class ManagedMerchantModel {
  final int id;
  final String name;
  final String type;
  final String? phone;
  final bool isOpen;
  final bool isApproved;
  final bool isDisabled;
  final String? ownerFullName;
  final String? ownerPhone;
  final int todayOrdersCount;

  const ManagedMerchantModel({
    required this.id,
    required this.name,
    required this.type,
    this.phone,
    required this.isOpen,
    required this.isApproved,
    required this.isDisabled,
    this.ownerFullName,
    this.ownerPhone,
    required this.todayOrdersCount,
  });

  factory ManagedMerchantModel.fromJson(Map<String, dynamic> j) {
    return ManagedMerchantModel(
      id: parseInt(j['id']),
      name: parseString(j['name']),
      type: parseString(j['type']),
      phone: parseNullableString(j['phone']),
      isOpen: j['is_open'] ?? j['isOpen'] ?? true,
      isApproved: j['is_approved'] ?? j['isApproved'] ?? false,
      isDisabled: j['is_disabled'] ?? j['isDisabled'] ?? false,
      ownerFullName: parseNullableString(j['owner_full_name'] ?? j['ownerFullName']),
      ownerPhone: parseNullableString(j['owner_phone'] ?? j['ownerPhone']),
      todayOrdersCount: parseInt(j['today_orders_count'] ?? j['todayOrdersCount']),
    );
  }
}
