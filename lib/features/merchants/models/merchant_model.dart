import '../../../core/utils/parsers.dart';

double? _toNullableDouble(dynamic raw) {
  return tryParseLocalizedDouble(raw);
}

class MerchantModel {
  final int id;
  final String name;
  final String type; // restaurant | market
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
  final double? latitude;
  final double? longitude;
  final double? distanceKm;
  final double? avgMerchantRating;
  final int ratingCount;
  final bool isOpen;
  final bool hasDiscountOffer;
  final bool hasFreeDeliveryOffer;
  final bool supportsChat;
  final bool supportsAttachments;
  final bool supportsPharmacyWorkflow;
  final Map<String, dynamic> serviceFlags;
  final List<String> badges;

  MerchantModel({
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
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.avgMerchantRating,
    this.ratingCount = 0,
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
              )
              .map((e) => parseString(e, fallback: '').trim().toLowerCase())
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
    latitude: _toNullableDouble(j['latitude']),
    longitude: _toNullableDouble(j['longitude']),
    distanceKm: _toNullableDouble(j['distance_km'] ?? j['distanceKm']),
    avgMerchantRating: _toNullableDouble(
      j['avg_merchant_rating'] ?? j['avgMerchantRating'],
    ),
    ratingCount: parseInt(j['rating_count'] ?? j['ratingCount']),
    isOpen: j['is_open'] ?? j['isOpen'] ?? true,
    hasDiscountOffer: j['has_discount_offer'] ?? j['hasDiscountOffer'] ?? false,
    hasFreeDeliveryOffer:
        j['has_free_delivery_offer'] ?? j['hasFreeDeliveryOffer'] ?? false,
    supportsChat: j['supports_chat'] ?? j['supportsChat'] ?? false,
    supportsAttachments:
        j['supports_attachments'] ?? j['supportsAttachments'] ?? false,
    supportsPharmacyWorkflow:
        j['supports_pharmacy_workflow'] ??
        j['supportsPharmacyWorkflow'] ??
        false,
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
