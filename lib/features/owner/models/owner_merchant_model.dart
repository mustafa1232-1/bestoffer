import '../../../core/utils/parsers.dart';

class OwnerMerchantModel {
  final int id;
  final String name;
  final String type;
  final String? description;
  final String? phone;
  final String? imageUrl;
  final bool isOpen;
  final bool isApproved;
  final DateTime? createdAt;

  const OwnerMerchantModel({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.phone,
    this.imageUrl,
    required this.isOpen,
    required this.isApproved,
    required this.createdAt,
  });

  factory OwnerMerchantModel.fromJson(Map<String, dynamic> j) {
    return OwnerMerchantModel(
      id: parseInt(j['id']),
      name: parseString(j['name']),
      type: parseString(j['type']),
      description: parseNullableString(j['description']),
      phone: parseNullableString(j['phone']),
      imageUrl: parseNullableString(j['image_url'] ?? j['imageUrl']),
      isOpen: j['is_open'] ?? j['isOpen'] ?? true,
      isApproved: j['is_approved'] ?? j['isApproved'] ?? false,
      createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
