import '../../../core/utils/parsers.dart';

class StoreActivityModel {
  final String activityType;
  final String baseType;
  final String displayNameEn;
  final String displayNameAr;
  final bool hasDiscoverySubcategories;
  final bool supportsChat;
  final bool supportsAttachments;
  final bool supportsPharmacyWorkflow;
  final String internalCategoryMode;
  final Map<String, dynamic> defaultServiceFlags;
  final List<String> defaultBadges;

  const StoreActivityModel({
    required this.activityType,
    required this.baseType,
    required this.displayNameEn,
    required this.displayNameAr,
    required this.hasDiscoverySubcategories,
    required this.supportsChat,
    required this.supportsAttachments,
    required this.supportsPharmacyWorkflow,
    required this.internalCategoryMode,
    required this.defaultServiceFlags,
    required this.defaultBadges,
  });

  factory StoreActivityModel.fromJson(Map<String, dynamic> json) {
    final badgesRaw = List<dynamic>.from(
      json['defaultBadges'] ?? json['default_badges_json'] ?? const <dynamic>[],
    );
    return StoreActivityModel(
      activityType: parseString(
        json['activityType'] ?? json['activity_type'],
        fallback: 'market',
      ),
      baseType: parseString(
        json['baseType'] ?? json['base_type'],
        fallback: 'market',
      ),
      displayNameEn: parseString(
        json['displayNameEn'] ?? json['display_name_en'],
      ),
      displayNameAr: parseString(
        json['displayNameAr'] ?? json['display_name_ar'],
      ),
      hasDiscoverySubcategories: parseBool(
        json['hasDiscoverySubcategories'] ?? json['has_discovery_subcategories'],
      ),
      supportsChat: parseBool(json['supportsChat'] ?? json['supports_chat']),
      supportsAttachments: parseBool(
        json['supportsAttachments'] ?? json['supports_attachments'],
      ),
      supportsPharmacyWorkflow: parseBool(
        json['supportsPharmacyWorkflow'] ?? json['supports_pharmacy_workflow'],
      ),
      internalCategoryMode: parseString(
        json['internalCategoryMode'] ?? json['internal_category_mode'],
        fallback: 'merchant_defined_with_templates',
      ),
      defaultServiceFlags:
          (json['defaultServiceFlags'] ?? json['default_service_flags_json'])
              is Map
          ? Map<String, dynamic>.from(
              (json['defaultServiceFlags'] ??
                      json['default_service_flags_json']) as Map,
            )
          : const <String, dynamic>{},
      defaultBadges: badgesRaw
          .map((e) => parseString(e, fallback: '').trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }

  String localizedLabel(bool isArabic) => isArabic ? displayNameAr : displayNameEn;
}

class StoreDiscoveryOptionModel {
  final int id;
  final String activityType;
  final String code;
  final String labelEn;
  final String labelAr;
  final int orderIndex;
  final Map<String, dynamic> metadata;

  const StoreDiscoveryOptionModel({
    required this.id,
    required this.activityType,
    required this.code,
    required this.labelEn,
    required this.labelAr,
    required this.orderIndex,
    required this.metadata,
  });

  factory StoreDiscoveryOptionModel.fromJson(Map<String, dynamic> json) {
    return StoreDiscoveryOptionModel(
      id: parseInt(json['id']),
      activityType: parseString(
        json['activityType'] ?? json['activity_type'],
        fallback: 'market',
      ),
      code: parseString(json['code']),
      labelEn: parseString(json['labelEn'] ?? json['label_en']),
      labelAr: parseString(json['labelAr'] ?? json['label_ar']),
      orderIndex: parseInt(json['orderIndex'] ?? json['order_index']),
      metadata: (json['metadata'] ?? json['metadata_json']) is Map
          ? Map<String, dynamic>.from(
              (json['metadata'] ?? json['metadata_json']) as Map,
            )
          : const <String, dynamic>{},
    );
  }

  String localizedLabel(bool isArabic) => isArabic ? labelAr : labelEn;
}
