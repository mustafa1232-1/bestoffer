import 'package:flutter/material.dart';

String normalizeOrderStatusForUi(String status) {
  switch (status.trim().toLowerCase()) {
    case 'accepted_by_store':
      return 'approved';
    case 'courier_requested':
    case 'courier_assigned':
      return 'preparing';
    case 'ready_for_pickup':
      return 'ready_for_delivery';
    case 'picked_up':
      return 'on_the_way';
    case 'delivered_by_courier':
      return 'delivered';
    case 'received_by_customer':
    case 'completed':
      return 'received';
    case 'cancelled_by_customer':
    case 'cancelled_by_store':
    case 'cancelled_by_admin':
      return 'cancelled';
    case 'failed_delivery':
    case 'returned_if_needed':
      return 'failed_delivery';
    default:
      return status.trim().toLowerCase();
  }
}

String orderStatusLabel(String status) {
  final s = normalizeOrderStatusForUi(status);
  switch (s) {
    case 'pending':
      return 'قيد الانتظار';
    case 'approved':
      return 'تمت الموافقة';
    case 'preparing':
      return 'قيد التحضير';
    case 'ready_for_delivery':
      return 'جاهز للتوصيل';
    case 'on_the_way':
      return 'في الطريق';
    case 'arrived':
      return 'وصل السائق';
    case 'delivered':
      return 'تم التسليم';
    case 'cancelled':
      return 'ملغي';
    case 'received':
      return 'تم استلامه';
    case 'failed_delivery':
      return 'فشل التوصيل';
    default:
      return s;
  }
}

String orderStatusLabelForCustomer(
  String status, {
  required bool customerConfirmed,
}) {
  final s = normalizeOrderStatusForUi(status);
  if (customerConfirmed && s == 'delivered') {
    return orderStatusLabel('received');
  }
  return orderStatusLabel(s);
}

String? ownerOrderStatusHint(
  String status, {
  required bool hasDeliveryAssigned,
  required bool customerConfirmed,
  bool isMerchantDelivery = false,
}) {
  final s = normalizeOrderStatusForUi(status);
  switch (s) {
    case 'approved':
      return hasDeliveryAssigned
          ? 'الدلفري معين ويمكنك بدء التحضير الآن.'
          : 'تمت الموافقة على الطلب. ابدأ التحضير مباشرة، وسيتم تعيين أول دلفري متاح تلقائياً.';
    case 'preparing':
      return 'المتجر يجهز الطلب حالياً.';
    case 'ready_for_delivery':
      if (isMerchantDelivery) {
        return 'دلفري المطعم مفعل. حدّث الحالة إلى في الطريق عند خروج الطلب.';
      }
      return 'بانتظار أن يضغط الدلفري: استلمت الطلب.';
    case 'on_the_way':
      return 'الدلفري في الطريق إلى الزبون.';
    case 'arrived':
      return 'الدلفري وصل إلى الزبون وبانتظار التسليم.';
    case 'delivered':
      return customerConfirmed
          ? null
          : 'تم التسليم وبانتظار تأكيد الزبون للاستلام.';
    case 'failed_delivery':
      return 'تعذر التوصيل. يجب مراجعة الطلب.';
    default:
      return null;
  }
}

String? deliveryOrderStatusHint(
  String status, {
  required bool customerConfirmed,
}) {
  final s = normalizeOrderStatusForUi(status);
  switch (s) {
    case 'approved':
      return 'تم تعيينك على الطلب وبانتظار بدء تجهيز المتجر.';
    case 'preparing':
      return 'المتجر يجهز الطلب الآن. جهّز نفسك للاستلام.';
    case 'ready_for_delivery':
      return 'الطلب جاهز. اضغط استلمت الطلب عندما تستلمه من المتجر.';
    case 'on_the_way':
      return 'أنت في الطريق إلى الزبون. الخطوة التالية: وصلت.';
    case 'arrived':
      return 'أنت عند الزبون الآن. أكمل التسليم ثم اضغط تم تسليم الطلب.';
    case 'delivered':
      return customerConfirmed
          ? null
          : 'تم التسليم وبانتظار أن يؤكد الزبون الاستلام.';
    case 'failed_delivery':
      return 'تعذر تسليم الطلب. أضف ملاحظة وارجع للمتجر.';
    default:
      return null;
  }
}

String? customerOrderTrackingHint(
  String status, {
  required bool hasDeliveryAssigned,
  required bool customerConfirmed,
}) {
  final s = normalizeOrderStatusForUi(status);
  switch (s) {
    case 'pending':
      return 'بانتظار موافقة المتجر على الطلب';
    case 'approved':
      return hasDeliveryAssigned
          ? 'تمت الموافقة على طلبك وجاري التحضير.'
          : 'تمت الموافقة على طلبك. المتجر يبدأ التحضير مباشرة، وسيتم تعيين دلفري عند جاهزية الطلب.';
    case 'preparing':
      return 'المتجر يحضّر طلبك الآن.';
    case 'ready_for_delivery':
      return hasDeliveryAssigned
          ? 'الطلب جاهز وبانتظار استلامه من الدلفري.'
          : 'الطلب جاهز للتوصيل ويجري الآن إشعار الدلفريين المتاحين.';
    case 'on_the_way':
      return 'الدلفري في الطريق إليك.';
    case 'arrived':
      return 'الدلفري وصل إلى موقعك.';
    case 'delivered':
      return customerConfirmed
          ? null
          : 'تم تسليم الطلب. يرجى تأكيد الاستلام لإغلاق الطلب.';
    case 'failed_delivery':
      return 'تعذر التوصيل. سيتواصل معك فريق الدعم.';
    default:
      return null;
  }
}

Color orderStatusColor(String status) {
  final s = normalizeOrderStatusForUi(status);
  switch (s) {
    case 'pending':
      return Colors.orange;
    case 'approved':
      return Colors.blue;
    case 'preparing':
      return Colors.amber;
    case 'ready_for_delivery':
      return Colors.purple;
    case 'on_the_way':
      return Colors.indigo;
    case 'arrived':
      return Colors.teal;
    case 'delivered':
      return Colors.green;
    case 'cancelled':
      return Colors.red;
    case 'received':
      return Colors.greenAccent;
    case 'failed_delivery':
      return Colors.redAccent;
    default:
      return Colors.grey;
  }
}

Color orderStatusColorForCustomer(
  String status, {
  required bool customerConfirmed,
}) {
  final s = normalizeOrderStatusForUi(status);
  if (customerConfirmed && s == 'delivered') {
    return orderStatusColor('received');
  }
  return orderStatusColor(s);
}
