import '../../../core/utils/parsers.dart';

class AdBoardItemModel {
  final int id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String? badgeLabel;
  final String? ctaLabel;
  final String type;
  final int? targetId;
  final String? targetRoute;
  final String? promoCode;
  final String? category;
  final String? externalLink;
  final String ctaTargetType;
  final String? ctaTargetValue;
  final int? merchantId;
  final String? merchantName;
  final String? merchantType;
  final int priority;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AdBoardItemModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.badgeLabel,
    required this.ctaLabel,
    required this.type,
    required this.targetId,
    required this.targetRoute,
    required this.promoCode,
    required this.category,
    required this.externalLink,
    required this.ctaTargetType,
    required this.ctaTargetValue,
    required this.merchantId,
    required this.merchantName,
    required this.merchantType,
    required this.priority,
    required this.isActive,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AdBoardItemModel.fromJson(Map<String, dynamic> json) {
    return AdBoardItemModel(
      id: parseInt(json['id']),
      title: parseString(json['title']),
      subtitle: parseString(json['subtitle']),
      imageUrl: parseNullableString(json['imageUrl']),
      badgeLabel: parseNullableString(json['badgeLabel']),
      ctaLabel: parseNullableString(json['ctaLabel']),
      type: parseString(
        json['type'] ?? json['ctaTargetType'],
        fallback: 'none',
      ),
      targetId: parseNullableInt(json['targetId']),
      targetRoute: parseNullableString(json['targetRoute']),
      promoCode: parseNullableString(json['promoCode']),
      category: parseNullableString(json['category']),
      externalLink: parseNullableString(json['externalLink']),
      ctaTargetType: parseString(
        json['ctaTargetType'] ?? json['type'],
        fallback: 'none',
      ),
      ctaTargetValue: parseNullableString(json['ctaTargetValue']),
      merchantId: json['merchantId'] == null
          ? null
          : parseInt(json['merchantId']),
      merchantName: parseNullableString(json['merchantName']),
      merchantType: parseNullableString(json['merchantType']),
      priority: parseInt(json['priority']),
      isActive: parseBool(json['isActive'], fallback: true),
      startsAt: parseNullableDateTime(json['startsAt']),
      endsAt: parseNullableDateTime(json['endsAt']),
      createdAt: parseNullableDateTime(json['createdAt']),
      updatedAt: parseNullableDateTime(json['updatedAt']),
    );
  }
}
