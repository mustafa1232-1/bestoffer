import '../../../core/utils/parsers.dart';

class MerchantOfferProductModel {
  final int id;
  final String name;
  final double price;
  final double? discountedPrice;
  final String? offerLabel;
  final bool isAvailable;

  const MerchantOfferProductModel({
    required this.id,
    required this.name,
    required this.price,
    required this.discountedPrice,
    required this.offerLabel,
    required this.isAvailable,
  });

  factory MerchantOfferProductModel.fromJson(Map<String, dynamic> json) {
    return MerchantOfferProductModel(
      id: parseInt(json['id']),
      name: parseString(json['name']),
      price: parseDouble(json['price']),
      discountedPrice: json['discountedPrice'] == null
          ? null
          : parseDouble(json['discountedPrice']),
      offerLabel: parseNullableString(json['offerLabel']),
      isAvailable: json['isAvailable'] ?? true,
    );
  }
}

class MerchantOfferModel {
  final int id;
  final int merchantId;
  final String title;
  final String? description;
  final String offerType;
  final double? discountValue;
  final int? buyQuantity;
  final int? getQuantity;
  final String status;
  final String configuredStatus;
  final String? label;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? maxUsage;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<MerchantOfferProductModel> products;

  const MerchantOfferModel({
    required this.id,
    required this.merchantId,
    required this.title,
    required this.description,
    required this.offerType,
    required this.discountValue,
    required this.buyQuantity,
    required this.getQuantity,
    required this.status,
    required this.configuredStatus,
    required this.label,
    required this.startsAt,
    required this.endsAt,
    required this.maxUsage,
    required this.createdAt,
    required this.updatedAt,
    required this.products,
  });

  factory MerchantOfferModel.fromJson(Map<String, dynamic> json) {
    final rawProducts = List<dynamic>.from(
      json['products'] as List? ?? const [],
    );
    return MerchantOfferModel(
      id: parseInt(json['id']),
      merchantId: parseInt(json['merchantId'] ?? json['merchant_id']),
      title: parseString(json['title']),
      description: parseNullableString(json['description']),
      offerType: parseString(json['offerType'] ?? json['offer_type']),
      discountValue:
          json['discountValue'] == null && json['discount_value'] == null
          ? null
          : parseDouble(json['discountValue'] ?? json['discount_value']),
      buyQuantity: _parseNullableInt(
        json['buyQuantity'] ?? json['buy_quantity'],
      ),
      getQuantity: _parseNullableInt(
        json['getQuantity'] ?? json['get_quantity'],
      ),
      status: parseString(json['status']),
      configuredStatus: parseString(
        json['configuredStatus'] ?? json['configured_status'] ?? json['status'],
      ),
      label: parseNullableString(json['label']),
      startsAt: _parseDate(json['startsAt'] ?? json['starts_at']),
      endsAt: _parseDate(json['endsAt'] ?? json['ends_at']),
      maxUsage: _parseNullableInt(json['maxUsage'] ?? json['max_usage']),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
      products: rawProducts
          .map(
            (item) => MerchantOfferProductModel.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }

  bool get isBuyXGetY => offerType == 'buy_x_get_y';
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.toString());
  return parsed;
}

int? _parseNullableInt(dynamic value) {
  if (value == null) return null;
  final parsed = parseInt(value, fallback: 0);
  return parsed <= 0 ? null : parsed;
}
