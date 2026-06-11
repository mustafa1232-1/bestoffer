import '../../../core/utils/parsers.dart';

class AdminOrdersOverviewSummary {
  final int totalOrders;
  final int completedOrders;
  final int cancelledOrders;
  final int inProgressOrders;

  const AdminOrdersOverviewSummary({
    required this.totalOrders,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.inProgressOrders,
  });

  factory AdminOrdersOverviewSummary.fromJson(Map<String, dynamic> json) {
    return AdminOrdersOverviewSummary(
      totalOrders: parseInt(json['totalOrders'] ?? json['total_orders']),
      completedOrders: parseInt(
        json['completedOrders'] ?? json['completed_orders'],
      ),
      cancelledOrders: parseInt(
        json['cancelledOrders'] ?? json['cancelled_orders'],
      ),
      inProgressOrders: parseInt(
        json['inProgressOrders'] ?? json['in_progress_orders'],
      ),
    );
  }
}

class AdminOrdersOverviewMerchant {
  final int merchantId;
  final String merchantName;
  final String? merchantType;
  final String? merchantPhone;
  final int? ownerUserId;
  final String? ownerFullName;
  final String? ownerPhone;
  final int ordersCount;
  final DateTime? lastOrderAt;

  const AdminOrdersOverviewMerchant({
    required this.merchantId,
    required this.merchantName,
    required this.merchantType,
    required this.merchantPhone,
    required this.ownerUserId,
    required this.ownerFullName,
    required this.ownerPhone,
    required this.ordersCount,
    required this.lastOrderAt,
  });

  factory AdminOrdersOverviewMerchant.fromJson(Map<String, dynamic> json) {
    return AdminOrdersOverviewMerchant(
      merchantId: parseInt(json['merchantId'] ?? json['merchant_id']),
      merchantName: parseString(json['merchantName'] ?? json['merchant_name']),
      merchantType: parseNullableString(
        json['merchantType'] ?? json['merchant_type'],
      ),
      merchantPhone: parseNullableString(
        json['merchantPhone'] ?? json['merchant_phone'],
      ),
      ownerUserId: (json['ownerUserId'] ?? json['owner_user_id']) == null
          ? null
          : parseInt(json['ownerUserId'] ?? json['owner_user_id']),
      ownerFullName: parseNullableString(
        json['ownerFullName'] ?? json['owner_full_name'],
      ),
      ownerPhone: parseNullableString(json['ownerPhone'] ?? json['owner_phone']),
      ordersCount: parseInt(json['ordersCount'] ?? json['orders_count']),
      lastOrderAt: parseNullableDateTime(
        json['lastOrderAt'] ?? json['last_order_at'],
      ),
    );
  }
}
