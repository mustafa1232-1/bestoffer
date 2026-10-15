import '../../../../core/utils/order_status.dart';

bool shouldShowCustomerActiveOrderBanner({required String status}) {
  final normalizedStatus = normalizeOrderStatusForUi(status);
  if (const {
    'delivered',
    'received',
    'completed',
    'cancelled',
    'failed_delivery',
  }.contains(normalizedStatus)) {
    return false;
  }

  return const {
    'pending',
    'approved',
    'preparing',
    'ready_for_delivery',
    'on_the_way',
    'arrived',
  }.contains(normalizedStatus);
}
