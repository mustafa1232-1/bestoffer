import '../../../core/utils/parsers.dart';
import 'order_item_model.dart';

class OrderModel {
  final int id;
  final int merchantId;
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
  final double subtotal;
  final double deliveryFee;
  final double totalAmount;
  final int? estimatedPrepMinutes;
  final int? estimatedDeliveryMinutes;
  final int? deliveryUserId;
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
  final DateTime? deliveredAt;
  final DateTime? customerConfirmedAt;
  final List<OrderItemModel> items;

  const OrderModel({
    required this.id,
    required this.merchantId,
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
    required this.subtotal,
    required this.deliveryFee,
    required this.totalAmount,
    required this.estimatedPrepMinutes,
    required this.estimatedDeliveryMinutes,
    required this.deliveryUserId,
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
    required this.deliveredAt,
    required this.customerConfirmedAt,
    required this.items,
  });

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    final rawItems = (j['items'] as List?) ?? const [];
    return OrderModel(
      id: parseInt(j['id']),
      merchantId: parseInt(j['merchant_id'] ?? j['merchantId']),
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
      subtotal: parseDouble(j['subtotal']),
      deliveryFee: parseDouble(j['delivery_fee'] ?? j['deliveryFee']),
      totalAmount: parseDouble(j['total_amount'] ?? j['totalAmount']),
      estimatedPrepMinutes: j['estimated_prep_minutes'] == null
          ? null
          : parseInt(j['estimated_prep_minutes']),
      estimatedDeliveryMinutes: j['estimated_delivery_minutes'] == null
          ? null
          : parseInt(j['estimated_delivery_minutes']),
      deliveryUserId: j['delivery_user_id'] == null
          ? (j['delivery_id'] == null ? null : parseInt(j['delivery_id']))
          : parseInt(j['delivery_user_id']),
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
      deliveredAt: _parseDate(j['delivered_at']),
      customerConfirmedAt: _parseDate(j['customer_confirmed_at']),
      items: rawItems
          .map(
            (e) => OrderItemModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }

  double get serviceFee {
    final fee = totalAmount - subtotal - deliveryFee;
    if (fee <= 0) return 0;
    return fee;
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
