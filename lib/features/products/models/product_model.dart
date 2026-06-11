import '../../../core/utils/parsers.dart';

class ProductModel {
  final int id;
  final int merchantId;
  final int? categoryId;
  final String? categoryName;
  final int? categorySortOrder;
  final String name;
  final String? description;
  final double price;
  final double? discountedPrice;
  final String? imageUrl;
  final bool freeDelivery;
  final String? offerLabel;
  final bool requiresPrescription;
  final bool requiresReview;
  final int? activeOfferId;
  final String? activeOfferType;
  final String? activeOfferTitle;
  final double? activeOfferDiscountValue;
  final int? activeOfferBuyQuantity;
  final int? activeOfferGetQuantity;
  final bool isAvailable;
  final int sortOrder;

  const ProductModel({
    required this.id,
    required this.merchantId,
    this.categoryId,
    this.categoryName,
    this.categorySortOrder,
    required this.name,
    this.description,
    required this.price,
    this.discountedPrice,
    this.imageUrl,
    required this.freeDelivery,
    this.offerLabel,
    this.requiresPrescription = false,
    this.requiresReview = false,
    this.activeOfferId,
    this.activeOfferType,
    this.activeOfferTitle,
    this.activeOfferDiscountValue,
    this.activeOfferBuyQuantity,
    this.activeOfferGetQuantity,
    required this.isAvailable,
    required this.sortOrder,
  });

  factory ProductModel.fromJson(Map<String, dynamic> j) {
    final discounted = j['discounted_price'] ?? j['discountedPrice'];
    return ProductModel(
      id: parseInt(j['id']),
      merchantId: parseInt(j['merchant_id'] ?? j['merchantId']),
      categoryId: _parseNullableInt(j['category_id'] ?? j['categoryId']),
      categoryName: parseNullableString(
        j['category_name'] ?? j['categoryName'],
      ),
      categorySortOrder: _parseNullableInt(
        j['category_sort_order'] ?? j['categorySortOrder'],
      ),
      name: parseString(j['name']),
      description: parseNullableString(j['description']),
      price: parseDouble(j['price']),
      discountedPrice: discounted == null ? null : parseDouble(discounted),
      imageUrl: parseNullableString(j['image_url'] ?? j['imageUrl']),
      freeDelivery: j['free_delivery'] ?? j['freeDelivery'] ?? false,
      offerLabel: parseNullableString(j['offer_label'] ?? j['offerLabel']),
      requiresPrescription: parseBool(
        j['requires_prescription'] ?? j['requiresPrescription'],
      ),
      requiresReview: parseBool(
        j['requires_review'] ?? j['requiresReview'],
      ),
      activeOfferId: _parseNullableInt(
        j['active_offer_id'] ?? j['activeOfferId'],
      ),
      activeOfferType: parseNullableString(
        j['active_offer_type'] ?? j['activeOfferType'],
      ),
      activeOfferTitle: parseNullableString(
        j['active_offer_title'] ?? j['activeOfferTitle'],
      ),
      activeOfferDiscountValue:
          (j['active_offer_discount_value'] ?? j['activeOfferDiscountValue']) ==
              null
          ? null
          : parseDouble(
              j['active_offer_discount_value'] ?? j['activeOfferDiscountValue'],
            ),
      activeOfferBuyQuantity: _parseNullableInt(
        j['active_offer_buy_quantity'] ?? j['activeOfferBuyQuantity'],
      ),
      activeOfferGetQuantity: _parseNullableInt(
        j['active_offer_get_quantity'] ?? j['activeOfferGetQuantity'],
      ),
      isAvailable: j['is_available'] ?? j['isAvailable'] ?? true,
      sortOrder: parseInt(j['sort_order'] ?? j['sortOrder']),
    );
  }

  bool get hasActiveOffer => activeOfferId != null;

  bool get requiresPharmacyConversation =>
      requiresPrescription || requiresReview;

  bool get isBuyXGetYOffer => activeOfferType == 'buy_x_get_y';

  bool get hasDiscount =>
      discountedPrice != null &&
      discountedPrice! > 0 &&
      discountedPrice! < price;

  int? get discountPercent {
    if (!hasDiscount || price <= 0) return null;
    return ((1 - (discountedPrice! / price)) * 100).round();
  }
}

int? _parseNullableInt(dynamic value) {
  if (value == null) return null;
  final parsed = parseInt(value, fallback: 0);
  if (parsed <= 0) return null;
  return parsed;
}
