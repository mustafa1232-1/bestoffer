import '../../../core/media/media_url.dart';
import '../../../core/utils/parsers.dart';

double? _toNullableDouble(dynamic raw) {
  return tryParseLocalizedDouble(raw);
}

DateTime? _toNullableDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  final str = raw.toString().trim();
  if (str.isEmpty) return null;
  return DateTime.tryParse(str);
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
  final bool hasActiveOffer;
  final bool supportsChat;
  final bool supportsAttachments;
  final bool supportsPharmacyWorkflow;
  final Map<String, dynamic> serviceFlags;
  final List<String> badges;
  // Storefront contract (nullable = unknown; never fabricated on the client).
  final String? logoUrl;
  final String? coverImageUrl;
  final bool isVerified;
  final DateTime? nextOpenAt;
  final int? deliveryEtaMinMinutes;
  final int? deliveryEtaMaxMinutes;
  final double? deliveryFee;
  final double? minimumOrder;

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
    this.hasActiveOffer = false,
    this.supportsChat = false,
    this.supportsAttachments = false,
    this.supportsPharmacyWorkflow = false,
    this.serviceFlags = const <String, dynamic>{},
    this.badges = const <String>[],
    this.logoUrl,
    this.coverImageUrl,
    this.isVerified = false,
    this.nextOpenAt,
    this.deliveryEtaMinMinutes,
    this.deliveryEtaMaxMinutes,
    this.deliveryFee,
    this.minimumOrder,
  });

  /// True when the store advertises any real ETA (min or max minutes present).
  bool get hasDeliveryEta =>
      deliveryEtaMinMinutes != null || deliveryEtaMaxMinutes != null;

  /// True when a real delivery fee value is present (including 0 = free).
  bool get hasDeliveryFee => deliveryFee != null;

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
    imageUrl: resolveMediaUrl(
      parseNullableString(j['image_url'] ?? j['imageUrl']),
    ),
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
    hasActiveOffer:
        j['has_active_offer'] ??
        j['hasActiveOffer'] ??
        ((j['has_discount_offer'] ?? j['hasDiscountOffer'] ?? false) ||
            (j['has_free_delivery_offer'] ??
                j['hasFreeDeliveryOffer'] ??
                false)),
    logoUrl: resolveMediaUrl(
      parseNullableString(j['logo_url'] ?? j['logoUrl']),
    ),
    coverImageUrl: resolveMediaUrl(
      parseNullableString(j['cover_image_url'] ?? j['coverImageUrl']),
    ),
    isVerified: j['is_verified'] ?? j['isVerified'] ?? false,
    nextOpenAt: _toNullableDate(j['next_open_at'] ?? j['nextOpenAt']),
    deliveryEtaMinMinutes: parseNullableInt(
      j['delivery_eta_min_minutes'] ?? j['deliveryEtaMinMinutes'],
    ),
    deliveryEtaMaxMinutes: parseNullableInt(
      j['delivery_eta_max_minutes'] ?? j['deliveryEtaMaxMinutes'],
    ),
    deliveryFee: _toNullableDouble(j['delivery_fee'] ?? j['deliveryFee']),
    minimumOrder: _toNullableDouble(j['minimum_order'] ?? j['minimumOrder']),
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
