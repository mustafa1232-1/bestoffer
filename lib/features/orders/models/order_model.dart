import '../../../core/utils/parsers.dart';
import 'order_item_model.dart';

class OrderModel {
  final int id;
  final int merchantId;
  final int customerUserId;
  final int? orderGroupId;
  final String? subOrderId;
  final String orderScope;
  final int storeSequence;
  final String merchantName;
  final String status;
  final String customerFullName;
  final String customerPhone;
  final String customerCity;
  final String customerBlock;
  final String customerBuildingNumber;
  final String customerApartment;
  final String? customerImageUrl;
  final String? imageUrl;
  final String? note;
  final double grossSubtotal;
  final double productDiscountTotal;
  final double subtotal;
  final double _serviceFee;
  final double deliveryFee;
  final int? couponId;
  final String? couponCode;
  final double couponDiscountTotal;
  final double totalAmount;
  final Map<String, dynamic>? pricingBreakdown;
  final String? sourceType;
  final String? orderFlowType;
  final int? pharmacyConversationId;
  final String? pharmacyFlowStatus;
  final int? estimatedPrepMinutes;
  final int? estimatedDeliveryMinutes;
  final int? deliveryUserId;
  final bool isMerchantDelivery;
  final String? courierSource;
  final String? deliveryDriverType;
  final String? deliveryFullName;
  final String? deliveryPhone;
  final bool archivedByDelivery;
  final int? deliveryRating;
  final String? deliveryReview;
  final int? merchantRating;
  final String? merchantReview;
  final DateTime? merchantRatedAt;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? preparingStartedAt;
  final DateTime? preparedAt;
  final DateTime? pickedUpAt;
  final DateTime? arrivedAt;
  final DateTime? deliveredAt;
  final DateTime? customerConfirmedAt;
  final List<OrderItemModel> items;

  const OrderModel({
    required this.id,
    required this.merchantId,
    required this.customerUserId,
    required this.orderGroupId,
    required this.subOrderId,
    required this.orderScope,
    required this.storeSequence,
    required this.merchantName,
    required this.status,
    required this.customerFullName,
    required this.customerPhone,
    required this.customerCity,
    required this.customerBlock,
    required this.customerBuildingNumber,
    required this.customerApartment,
    required this.customerImageUrl,
    required this.imageUrl,
    required this.note,
    required this.grossSubtotal,
    required this.productDiscountTotal,
    required this.subtotal,
    required double serviceFee,
    required this.deliveryFee,
    required this.couponId,
    required this.couponCode,
    required this.couponDiscountTotal,
    required this.totalAmount,
    required this.pricingBreakdown,
    required this.sourceType,
    required this.orderFlowType,
    required this.pharmacyConversationId,
    required this.pharmacyFlowStatus,
    required this.estimatedPrepMinutes,
    required this.estimatedDeliveryMinutes,
    required this.deliveryUserId,
    required this.isMerchantDelivery,
    required this.courierSource,
    required this.deliveryDriverType,
    required this.deliveryFullName,
    required this.deliveryPhone,
    required this.archivedByDelivery,
    required this.deliveryRating,
    required this.deliveryReview,
    required this.merchantRating,
    required this.merchantReview,
    required this.merchantRatedAt,
    required this.createdAt,
    required this.approvedAt,
    required this.preparingStartedAt,
    required this.preparedAt,
    required this.pickedUpAt,
    required this.arrivedAt,
    required this.deliveredAt,
    required this.customerConfirmedAt,
    required this.items,
  }) : _serviceFee = serviceFee;

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    final rawItems = (j['items'] as List?) ?? const [];
    final pricingRaw = j['pricing_breakdown_json'] ?? j['pricingBreakdown'];
    return OrderModel(
      id: parseInt(j['id']),
      merchantId: parseInt(j['merchant_id'] ?? j['merchantId']),
      customerUserId: parseInt(j['customer_user_id'] ?? j['customerUserId']),
      orderGroupId: j['order_group_id'] == null
          ? null
          : parseInt(j['order_group_id']),
      subOrderId: parseNullableString(j['sub_order_id'] ?? j['subOrderId']),
      orderScope: parseString(
        j['order_scope'] ?? j['orderScope'],
        fallback: 'single',
      ),
      storeSequence: parseInt(
        j['store_sequence'] ?? j['storeSequence'],
        fallback: 1,
      ),
      merchantName: parseString(j['merchant_name'] ?? j['merchantName']),
      status: parseString(j['status']),
      customerFullName: parseString(
        j['customer_full_name'] ?? j['customerFullName'],
      ),
      customerPhone: parseString(j['customer_phone'] ?? j['customerPhone']),
      customerCity: parseString(
        j['customer_city'] ?? j['customerCity'],
        fallback: 'مدينة بسماية',
      ),
      customerBlock: parseString(j['customer_block'] ?? j['customerBlock']),
      customerBuildingNumber: parseString(
        j['customer_building_number'] ?? j['customerBuildingNumber'],
      ),
      customerApartment: parseString(
        j['customer_apartment'] ?? j['customerApartment'],
      ),
      customerImageUrl: parseNullableString(
        j['customer_image_url'] ?? j['customerImageUrl'],
      ),
      imageUrl: parseNullableString(j['image_url'] ?? j['imageUrl']),
      note: parseNullableString(j['note']),
      grossSubtotal: parseDouble(
        j['gross_subtotal'] ?? j['grossSubtotal'] ?? j['subtotal'],
      ),
      productDiscountTotal: parseDouble(
        j['product_discount_total'] ?? j['productDiscountTotal'],
      ),
      subtotal: parseDouble(j['subtotal']),
      serviceFee: parseDouble(j['service_fee'] ?? j['serviceFee']),
      deliveryFee: parseDouble(j['delivery_fee'] ?? j['deliveryFee']),
      couponId: j['coupon_id'] == null
          ? (j['couponId'] == null ? null : parseInt(j['couponId']))
          : parseInt(j['coupon_id']),
      couponCode: parseNullableString(j['coupon_code'] ?? j['couponCode']),
      couponDiscountTotal: parseDouble(
        j['coupon_discount_total'] ?? j['couponDiscountTotal'],
      ),
      totalAmount: parseDouble(j['total_amount'] ?? j['totalAmount']),
      pricingBreakdown: pricingRaw is Map
          ? Map<String, dynamic>.from(pricingRaw)
          : null,
      sourceType: parseNullableString(j['source_type'] ?? j['sourceType']),
      orderFlowType: parseNullableString(
        j['order_flow_type'] ?? j['orderFlowType'],
      ),
      pharmacyConversationId:
          j['pharmacy_conversation_id'] == null &&
              j['pharmacyConversationId'] == null
          ? null
          : parseInt(
              j['pharmacy_conversation_id'] ?? j['pharmacyConversationId'],
            ),
      pharmacyFlowStatus: parseNullableString(
        j['pharmacy_flow_status'] ?? j['pharmacyFlowStatus'],
      ),
      estimatedPrepMinutes: j['estimated_prep_minutes'] == null
          ? null
          : parseInt(j['estimated_prep_minutes']),
      estimatedDeliveryMinutes: j['estimated_delivery_minutes'] == null
          ? null
          : parseInt(j['estimated_delivery_minutes']),
      deliveryUserId: j['delivery_user_id'] == null
          ? (j['delivery_id'] == null ? null : parseInt(j['delivery_id']))
          : parseInt(j['delivery_user_id']),
      isMerchantDelivery:
          (j['is_merchant_delivery'] ?? j['isMerchantDelivery']) == true,
      courierSource: parseNullableString(
        j['courier_source'] ?? j['courierSource'],
      ),
      deliveryDriverType: parseNullableString(
        j['delivery_driver_type'] ?? j['deliveryDriverType'],
      ),
      deliveryFullName: parseNullableString(j['delivery_full_name']),
      deliveryPhone: parseNullableString(j['delivery_phone']),
      archivedByDelivery: j['archived_by_delivery'] ?? false,
      deliveryRating: j['delivery_rating'] == null
          ? null
          : parseInt(j['delivery_rating']),
      deliveryReview: parseNullableString(j['delivery_review']),
      merchantRating: j['merchant_rating'] == null
          ? null
          : parseInt(j['merchant_rating']),
      merchantReview: parseNullableString(j['merchant_review']),
      merchantRatedAt: _parseDate(j['merchant_rated_at']),
      createdAt: _parseDate(j['created_at']),
      approvedAt: _parseDate(j['approved_at']),
      preparingStartedAt: _parseDate(j['preparing_started_at']),
      preparedAt: _parseDate(j['prepared_at']),
      pickedUpAt: _parseDate(j['picked_up_at']),
      arrivedAt: _parseDate(j['arrived_at']),
      deliveredAt: _parseDate(j['delivered_at']),
      customerConfirmedAt: _parseDate(j['customer_confirmed_at']),
      items: rawItems
          .map(
            (e) => OrderItemModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }

  double get serviceFee => _serviceFee;

  double get subtotalAfterCoupon {
    final value = subtotal - couponDiscountTotal;
    if (value <= 0) return 0;
    return value;
  }

  double get totalDiscounts => productDiscountTotal + couponDiscountTotal;

  bool get isAppDriverDelivery =>
      courierSource == 'app' ||
      (courierSource == null && deliveryDriverType == 'app_driver');

  bool get isStoreDriverDelivery =>
      courierSource == 'merchant' ||
      deliveryDriverType == 'store_driver' ||
      isMerchantDelivery;

  bool get isPharmacyFlow =>
      sourceType == 'pharmacy_chat_cart' ||
      orderFlowType == 'pharmacy' ||
      pharmacyConversationId != null;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
