import '../../../core/utils/parsers.dart';

class AdBoardItemModel {
  final int id;
  final String placement;
  final String title;
  final String? titleAr;
  final String? titleEn;
  final String subtitle;
  final String? subtitleAr;
  final String? subtitleEn;
  final String? imageUrl;
  final String? mobileImageUrl;
  final String? badgeLabel;
  final String? ctaLabel;
  final String? ctaLabelAr;
  final String? ctaLabelEn;
  final String type;
  final int? targetId;
  final String? targetRoute;
  final String? promoCode;
  final String? category;
  final String? activityType;
  final String? externalLink;
  final String ctaTargetType;
  final String? ctaTargetValue;
  final int? merchantId;
  final String? merchantName;
  final String? merchantType;
  final int priority;
  final bool isActive;
  final int impressionCount;
  final int clickCount;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AdBoardItemModel({
    required this.id,
    this.placement = 'HOME_MAIN',
    required this.title,
    this.titleAr,
    this.titleEn,
    required this.subtitle,
    this.subtitleAr,
    this.subtitleEn,
    required this.imageUrl,
    this.mobileImageUrl,
    required this.badgeLabel,
    required this.ctaLabel,
    this.ctaLabelAr,
    this.ctaLabelEn,
    required this.type,
    required this.targetId,
    required this.targetRoute,
    required this.promoCode,
    required this.category,
    this.activityType,
    required this.externalLink,
    required this.ctaTargetType,
    required this.ctaTargetValue,
    required this.merchantId,
    required this.merchantName,
    required this.merchantType,
    required this.priority,
    required this.isActive,
    this.impressionCount = 0,
    this.clickCount = 0,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Click-through rate in percent (0 when there are no impressions).
  double get ctrPercent =>
      impressionCount <= 0 ? 0 : (clickCount / impressionCount) * 100;

  /// Lifecycle bucket derived from schedule + active flag (evaluated at [now]).
  bool isScheduled(DateTime now) =>
      isActive && startsAt != null && startsAt!.isAfter(now);

  bool isExpired(DateTime now) =>
      endsAt != null && endsAt!.isBefore(now);

  bool isLive(DateTime now) =>
      isActive &&
      !isExpired(now) &&
      (startsAt == null || !startsAt!.isAfter(now));

  factory AdBoardItemModel.fromJson(Map<String, dynamic> json) {
    return AdBoardItemModel(
      id: parseInt(json['id']),
      placement: parseString(json['placement'], fallback: 'HOME_MAIN'),
      title: parseString(json['title']),
      titleAr: parseNullableString(json['titleAr']),
      titleEn: parseNullableString(json['titleEn']),
      subtitle: parseString(json['subtitle']),
      subtitleAr: parseNullableString(json['subtitleAr']),
      subtitleEn: parseNullableString(json['subtitleEn']),
      imageUrl: parseNullableString(json['imageUrl']),
      mobileImageUrl: parseNullableString(json['mobileImageUrl']),
      badgeLabel: parseNullableString(json['badgeLabel']),
      ctaLabel: parseNullableString(json['ctaLabel']),
      ctaLabelAr: parseNullableString(json['ctaLabelAr']),
      ctaLabelEn: parseNullableString(json['ctaLabelEn']),
      type: parseString(
        json['type'] ?? json['ctaTargetType'],
        fallback: 'none',
      ),
      targetId: parseNullableInt(json['targetId']),
      targetRoute: parseNullableString(json['targetRoute']),
      promoCode: parseNullableString(json['promoCode']),
      category: parseNullableString(json['category']),
      activityType: parseNullableString(json['activityType']),
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
      impressionCount: parseInt(json['impressionCount']),
      clickCount: parseInt(json['clickCount']),
      startsAt: parseNullableDateTime(json['startsAt']),
      endsAt: parseNullableDateTime(json['endsAt']),
      createdAt: parseNullableDateTime(json['createdAt']),
      updatedAt: parseNullableDateTime(json['updatedAt']),
    );
  }
}
