import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/services/models/service_models.dart';
import 'package:maslaki/features/services/ui/service_my_requests_screen.dart';

void main() {
  test('service request keeps the V2 lifecycle metadata', () {
    final request = ServiceRequestModel.fromJson(<String, dynamic>{
      'id': 91,
      'requestCode': 'SR-91',
      'customerUserId': 4,
      'providerId': 8,
      'offeringId': 12,
      'status': 'provider_completed',
      'bookingStatus': 'PROVIDER_COMPLETED',
      'bookingFlowKind': 'V2',
      'bookingVersion': 5,
      'contactPhone': '07700000000',
      'medicalInfo': <String, dynamic>{'allergies': 'لا توجد'},
      'customerCancelAvailableAt': '2026-09-29T12:15:00.000Z',
      'invoiceAdminDiscountIqd': 1000,
      'invoiceCouponCode': 'MASLAK3',
      'invoiceCouponDiscountIqd': 2000,
      'invoiceTotalIqd': 17000,
      'paymentSubmittedAt': '2026-09-29T13:00:00.000Z',
    });

    expect(request.bookingFlowKind, 'V2');
    expect(request.bookingStatus, 'PROVIDER_COMPLETED');
    expect(request.bookingVersion, 5);
    expect(request.contactPhone, '07700000000');
    expect(request.medicalInfo['allergies'], 'لا توجد');
    expect(request.invoiceAdminDiscountIqd, 1000);
    expect(request.invoiceCouponCode, 'MASLAK3');
    expect(request.invoiceCouponDiscountIqd, 2000);
    expect(request.invoiceTotalIqd, 17000);
    expect(request.paymentSubmittedAt, isNotNull);
  });

  test('canonical booking states have clear Arabic labels', () {
    expect(
      serviceRequestStatusLabel('PENDING_PROVIDER_CONFIRMATION'),
      'بانتظار قبول مقدم الخدمة',
    );
    expect(serviceRequestStatusLabel('CONFIRMED'), 'تم قبول الطلب');
    expect(serviceRequestStatusLabel('IN_PROGRESS'), 'قيد التنفيذ');
    expect(
      serviceRequestStatusLabel('PROVIDER_COMPLETED'),
      'أنجز مقدم الخدمة - بانتظار تأكيدك',
    );
    expect(serviceRequestStatusLabel('COMPLETED'), 'مكتمل');
  });

  test('central request keeps routing and assigned professional details', () {
    final request = ServiceRequestModel.fromJson(<String, dynamic>{
      'id': 112,
      'requestCode': 'MS-112',
      'customerUserId': 4,
      'providerId': 8,
      'offeringId': 19,
      'status': 'accepted',
      'serviceKey': 'home_maintenance',
      'serviceTitle': 'صيانة منزلية',
      'urgency': 'urgent',
      'routingStatus': 'assigned',
      'assignedProfessionalName': 'الفني المناوب',
      'assignedProfessionalPhone': '07700000000',
      'preferredContact': 'phone',
      'intakeAnswers': <String, dynamic>{'faultType': 'كهرباء'},
    });

    expect(request.serviceKey, 'home_maintenance');
    expect(request.urgency, 'urgent');
    expect(request.routingStatus, 'assigned');
    expect(request.assignedProfessionalName, 'الفني المناوب');
    expect(request.intakeAnswers['faultType'], 'كهرباء');
  });
}
