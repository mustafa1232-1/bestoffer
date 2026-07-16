import '../../../core/utils/parsers.dart';

class CustomerAdBoardItem {
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
  final bool merchantIsOpen;
  final int priority;

  const CustomerAdBoardItem({
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
    this.type = 'none',
    this.targetId,
    this.targetRoute,
    this.promoCode,
    this.category,
    this.activityType,
    this.externalLink,
    required this.ctaTargetType,
    required this.ctaTargetValue,
    required this.merchantId,
    required this.merchantName,
    required this.merchantType,
    required this.merchantIsOpen,
    required this.priority,
  });

  /// Prefers the mobile-optimized image, then the general image.
  String? get displayImageUrl => mobileImageUrl ?? imageUrl;

  /// Resolves the best title for [isArabic], falling back to the legacy title.
  String resolvedTitle(bool isArabic) {
    final localized = isArabic ? titleAr : titleEn;
    final value = (localized ?? '').trim();
    return value.isNotEmpty ? value : title;
  }

  /// Resolves the best subtitle for [isArabic], falling back to the legacy one.
  String resolvedSubtitle(bool isArabic) {
    final localized = isArabic ? subtitleAr : subtitleEn;
    final value = (localized ?? '').trim();
    return value.isNotEmpty ? value : subtitle;
  }

  /// Resolves the best CTA label for [isArabic], falling back to the legacy one.
  String? resolvedCtaLabel(bool isArabic) {
    final localized = isArabic ? ctaLabelAr : ctaLabelEn;
    final value = (localized ?? '').trim();
    if (value.isNotEmpty) return value;
    return ctaLabel;
  }

  factory CustomerAdBoardItem.fromJson(Map<String, dynamic> json) {
    return CustomerAdBoardItem(
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
      merchantIsOpen: parseBool(json['merchantIsOpen'], fallback: false),
      priority: parseInt(json['priority']),
    );
  }
}
