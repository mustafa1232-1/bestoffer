import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/orders/models/order_revision_model.dart';
import 'package:maslaki/features/orders/ui/widgets/order_revision_widgets.dart';

void main() {
  testWidgets('revision panel shows approve/reject only when allowed', (
    tester,
  ) async {
    final revision = _revision(status: 'AWAITING_CUSTOMER');
    var approvals = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderRevisionPanel(
            title: 'تعديلات الطلب',
            emptyText: 'لا توجد تعديلات',
            loadRevisions: () async => [revision],
            canApprove: (item) => item.isWaitingForCustomer,
            canReject: (item) => item.isWaitingForCustomer,
            onApprove: (_) async {
              approvals++;
              await Future<void>.delayed(const Duration(milliseconds: 20));
            },
            onReject: (_) async {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('موافقة'), findsOneWidget);
    expect(find.text('رفض'), findsOneWidget);

    await tester.tap(find.text('موافقة'));
    await tester.tap(find.text('موافقة'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(approvals, 1);
  });

  testWidgets('revision panel keeps final courier view read-only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderRevisionPanel(
            title: 'تحديثات نهائية',
            emptyText: 'لا توجد',
            loadRevisions: () async => [_revision(status: 'APPLIED')],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('موافقة'), findsNothing);
    expect(find.text('رفض'), findsNothing);
    expect(find.text('تطبيق التعديل'), findsNothing);
    expect(find.text('مطبق'), findsOneWidget);
  });
}

OrderRevisionModel _revision({required String status}) {
  return OrderRevisionModel.fromJson({
    'id': 1,
    'order_id': 2,
    'support_ticket_id': 3,
    'version_number': 1,
    'base_order_version': 1,
    'status': status,
    'reason': 'تصحيح مواد الطلب',
    'price_difference': 500,
    'original_totals_json': {'totalAmount': 1000},
    'proposed_totals_json': {'totalAmount': 1500},
    'original_items_json': [
      {'productId': 10, 'productName': 'A', 'quantity': 1},
    ],
    'proposed_items_json': [
      {'productId': 10, 'productName': 'A', 'quantity': 2},
    ],
    'approvals_required_json': ['CUSTOMER'],
    'payment_effect_json': {},
  });
}
