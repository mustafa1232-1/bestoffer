String orderStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'قيد الانتظار';
    case 'preparing':
      return 'قيد التحضير';
    case 'ready_for_delivery':
      return 'جاهز للتوصيل';
    case 'on_the_way':
      return 'في الطريق';
    case 'delivered':
      return 'تم التسليم';
    case 'cancelled':
      return 'ملغي';
    default:
      return status;
  }
}
