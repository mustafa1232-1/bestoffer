import '../../../core/utils/parsers.dart';

class PeriodMetricsModel {
  final int ordersCount;
  final int deliveredOrdersCount;
  final int cancelledOrdersCount;
  final double deliveryFees;
  final double totalAmount;
  final double appFees;
  final double avgDeliveryRating;
  final double avgMerchantRating;

  const PeriodMetricsModel({
    required this.ordersCount,
    required this.deliveredOrdersCount,
    required this.cancelledOrdersCount,
    required this.deliveryFees,
    required this.totalAmount,
    required this.appFees,
    required this.avgDeliveryRating,
    required this.avgMerchantRating,
  });

  factory PeriodMetricsModel.fromJson(Map<String, dynamic> j) {
    return PeriodMetricsModel(
      ordersCount: parseInt(j['orders_count'] ?? j['ordersCount']),
      deliveredOrdersCount: parseInt(
        j['delivered_orders_count'] ?? j['deliveredOrdersCount'],
      ),
      cancelledOrdersCount: parseInt(
        j['cancelled_orders_count'] ?? j['cancelledOrdersCount'],
      ),
      deliveryFees: parseDouble(j['delivery_fees'] ?? j['deliveryFees']),
      totalAmount: parseDouble(j['total_amount'] ?? j['totalAmount']),
      appFees: parseDouble(j['app_fees'] ?? j['appFees']),
      avgDeliveryRating: parseDouble(
        j['avg_delivery_rating'] ?? j['avgDeliveryRating'],
      ),
      avgMerchantRating: parseDouble(
        j['avg_merchant_rating'] ?? j['avgMerchantRating'],
      ),
    );
  }
}
