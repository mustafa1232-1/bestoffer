import 'parsers.dart';

class MerchantModel {
  final int id;
  final String name;
  final String type;
  final String activityType;
  final String? discoverySubcategory;
  final List<String> discoverySubcategories;
  final bool discoverySelectAll;
  final String? description;
  final String? phone;
  final String? imageUrl;
  final String? tagline;
  final String? workingHours;
  final String? serviceAreaNote;
  final bool isOpen;
  final bool hasDiscountOffer;
  final bool hasFreeDeliveryOffer;
  final bool supportsChat;
  final bool supportsAttachments;
  final bool supportsPharmacyWorkflow;
  final Map<String, dynamic> serviceFlags;
  final List<String> badges;

  const MerchantModel({
    required this.id,
    required this.name,
    required this.type,
    this.activityType = 'market',
    this.discoverySubcategory,
    this.discoverySubcategories = const <String>[],
    this.discoverySelectAll = false,
    this.description,
    this.phone,
    this.imageUrl,
    this.tagline,
    this.workingHours,
    this.serviceAreaNote,
    required this.isOpen,
    required this.hasDiscountOffer,
    required this.hasFreeDeliveryOffer,
    this.supportsChat = false,
    this.supportsAttachments = false,
    this.supportsPharmacyWorkflow = false,
    this.serviceFlags = const <String, dynamic>{},
    this.badges = const <String>[],
  });

  factory MerchantModel.fromJson(Map<String, dynamic> j) => MerchantModel(
    id: parseInt(j['id']),
    name: parseString(j['name']),
    type: parseString(j['type']),
    activityType: parseString(
      j['activityType'] ?? j['activity_type'],
      fallback: parseString(j['type'], fallback: 'market'),
    ),
    discoverySubcategory: parseNullableString(
      j['discoverySubcategory'] ?? j['discovery_subcategory'],
    ),
    discoverySubcategories:
        (j['discoverySubcategories'] ?? j['discovery_subcategories']) is List
        ? List<dynamic>.from(
            (j['discoverySubcategories'] ?? j['discovery_subcategories'])
                as List,
          ).map((e) => parseString(e, fallback: '').trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[],
    discoverySelectAll: parseBool(
      j['discoverySelectAll'] ?? j['discovery_select_all'],
      fallback: false,
    ),
    description: parseNullableString(j['description']),
    phone: parseNullableString(j['phone']),
    imageUrl: parseNullableString(j['image_url'] ?? j['imageUrl']),
    tagline: parseNullableString(j['tagline']),
    workingHours: parseNullableString(j['working_hours'] ?? j['workingHours']),
    serviceAreaNote: parseNullableString(
      j['service_area_note'] ?? j['serviceAreaNote'],
    ),
    isOpen: parseBool(j['is_open'] ?? j['isOpen'], fallback: true),
    hasDiscountOffer: parseBool(
      j['has_discount_offer'] ?? j['hasDiscountOffer'],
      fallback: false,
    ),
    hasFreeDeliveryOffer: parseBool(
      j['has_free_delivery_offer'] ?? j['hasFreeDeliveryOffer'],
      fallback: false,
    ),
    supportsChat: parseBool(
      j['supports_chat'] ?? j['supportsChat'],
      fallback: false,
    ),
    supportsAttachments: parseBool(
      j['supports_attachments'] ?? j['supportsAttachments'],
      fallback: false,
    ),
    supportsPharmacyWorkflow: parseBool(
      j['supports_pharmacy_workflow'] ?? j['supportsPharmacyWorkflow'],
      fallback: false,
    ),
    serviceFlags: (j['serviceFlags'] ?? j['service_flags_json']) is Map
        ? Map<String, dynamic>.from(
            (j['serviceFlags'] ?? j['service_flags_json']) as Map,
          )
        : const <String, dynamic>{},
    badges: (j['badges'] ?? j['badges_json']) is List
        ? List<dynamic>.from((j['badges'] ?? j['badges_json']) as List)
              .map((e) => parseString(e, fallback: ''))
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[],
  );
}
