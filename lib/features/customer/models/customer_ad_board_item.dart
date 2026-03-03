import '../../../core/utils/parsers.dart';

class CustomerAdBoardItem {
  final int id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String? badgeLabel;
  final String? ctaLabel;
  final String ctaTargetType;
  final String? ctaTargetValue;
  final int? merchantId;
  final String? merchantName;
  final String? merchantType;
  final bool merchantIsOpen;
  final int priority;

  const CustomerAdBoardItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.badgeLabel,
    required this.ctaLabel,
    required this.ctaTargetType,
    required this.ctaTargetValue,
    required this.merchantId,
    required this.merchantName,
    required this.merchantType,
    required this.merchantIsOpen,
    required this.priority,
  });

  factory CustomerAdBoardItem.fromJson(Map<String, dynamic> json) {
    return CustomerAdBoardItem(
      id: parseInt(json['id']),
      title: parseString(json['title']),
      subtitle: parseString(json['subtitle']),
      imageUrl: parseNullableString(json['imageUrl']),
      badgeLabel: parseNullableString(json['badgeLabel']),
      ctaLabel: parseNullableString(json['ctaLabel']),
      ctaTargetType: parseString(json['ctaTargetType'], fallback: 'none'),
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
