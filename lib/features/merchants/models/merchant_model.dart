import '../../../core/utils/parsers.dart';

class MerchantModel {
  final int id;
  final String name;
  final String type; // restaurant | market
  final String? description;
  final String? phone;
  final String? imageUrl;
  final bool isOpen;
  final bool hasDiscountOffer;
  final bool hasFreeDeliveryOffer;

  MerchantModel({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.phone,
    this.imageUrl,
    required this.isOpen,
    required this.hasDiscountOffer,
    required this.hasFreeDeliveryOffer,
  });

  factory MerchantModel.fromJson(Map<String, dynamic> j) => MerchantModel(
    id: parseInt(j['id']),
    name: parseString(j['name']),
    type: parseString(j['type']),
    description: parseNullableString(j['description']),
    phone: parseNullableString(j['phone']),
    imageUrl: parseNullableString(j['image_url'] ?? j['imageUrl']),
    isOpen: j['is_open'] ?? j['isOpen'] ?? true,
    hasDiscountOffer: j['has_discount_offer'] ?? j['hasDiscountOffer'] ?? false,
    hasFreeDeliveryOffer:
        j['has_free_delivery_offer'] ?? j['hasFreeDeliveryOffer'] ?? false,
  );
}
