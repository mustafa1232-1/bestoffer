import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/orders/models/delivery_assignment_model.dart';
import 'package:maslaki/features/orders/ui/widgets/order_delivery_assignment_card.dart';

void main() {
  testWidgets('PENDING_STORES waits for remaining stores, not courier supply', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_card(status: 'PENDING_STORES', visibleWhenNoAssignment: true)),
    );

    expect(find.text('Waiting for the remaining stores'), findsOneWidget);
    expect(find.textContaining('No courier is available'), findsNothing);
  });

  testWidgets('READY_FOR_ASSIGNMENT shows assignment in progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _card(status: 'READY_FOR_ASSIGNMENT', visibleWhenNoAssignment: true),
      ),
    );

    expect(find.text('Assigning a courier'), findsOneWidget);
    expect(find.textContaining('Courier details will appear'), findsOneWidget);
  });

  testWidgets('PENDING_NO_DRIVER explains automatic retry', (tester) async {
    await tester.pumpWidget(
      _wrap(_card(status: 'PENDING_NO_DRIVER', visibleWhenNoAssignment: true)),
    );

    expect(
      find.text(
        'No courier is available right now, retries will continue automatically',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('No store action is required'), findsOneWidget);
  });

  testWidgets('ASSIGNED shows courier details and action buttons', (
    tester,
  ) async {
    var called = false;
    var chatted = false;

    await tester.pumpWidget(
      _wrap(
        OrderDeliveryAssignmentCard(
          assignment: _assignment(
            status: 'ASSIGNED',
            driver: const DeliveryAssignmentDriverModel(
              id: 77,
              name: 'Courier One',
              photoUrl: null,
              phone: '07800000000',
              rating: 4.8,
              availabilityStatus: 'available',
              coverageBlock: 'A',
              courierSource: 'app',
              isMerchantDelivery: false,
              vehicleType: 'Bike',
              vehicleModel: 'Honda',
              vehicleColor: 'Red',
              vehiclePlateNumber: 'ABC-123',
            ),
          ),
          waitingCopy: 'Waiting',
          helperText: 'Driver assigned',
          onCall: () => called = true,
          onChat: () => chatted = true,
        ),
      ),
    );

    expect(find.text('Courier One'), findsOneWidget);
    expect(find.text('07800000000'), findsOneWidget);
    expect(find.textContaining('Bike'), findsOneWidget);
    expect(find.byIcon(Icons.call_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call_outlined));
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));

    expect(called, isTrue);
    expect(chatted, isTrue);
  });

  testWidgets('Arabic locale renders store-waiting copy', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _card(status: 'PENDING_STORES', visibleWhenNoAssignment: true),
        locale: const Locale('ar'),
      ),
    );

    expect(find.text('بانتظار قبول بقية المتاجر'), findsOneWidget);
  });
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(
      body: Directionality(
        textDirection: locale.languageCode == 'ar'
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: Center(child: child),
      ),
    ),
  );
}

OrderDeliveryAssignmentCard _card({
  required String status,
  bool visibleWhenNoAssignment = false,
}) {
  return OrderDeliveryAssignmentCard(
    assignment: _assignment(status: status),
    waitingCopy: 'Legacy waiting',
    helperText: 'Legacy helper',
    visibleWhenNoAssignment: visibleWhenNoAssignment,
  );
}

OrderDeliveryAssignmentModel _assignment({
  required String status,
  DeliveryAssignmentDriverModel? driver,
}) {
  return OrderDeliveryAssignmentModel(
    assignmentStatus: status,
    assignmentId: driver == null ? null : 55,
    assignedAt: driver == null ? null : DateTime.utc(2026),
    endedAt: null,
    endedReason: null,
    orderId: 10,
    driver: driver,
  );
}
