import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/delivery/data/delivery_api.dart';
import 'package:maslaki/features/delivery/state/delivery_controller.dart'
    show deliveryApiProvider;
import 'package:maslaki/features/delivery/state/grouped_delivery_controller.dart';
import 'package:maslaki/features/delivery/ui/grouped_delivery_screens.dart';

/// Same in-memory fake used by the logic tests, driving the real widgets.
class FakeDeliveryApi extends DeliveryApi {
  FakeDeliveryApi() : super(Dio());
  int version = 1;
  String lifecycle = 'ASSIGNED';
  final Map<int, String> stopStatus = {101: 'READY', 102: 'READY'};
  bool get _terminal =>
      lifecycle == 'DELIVERED' || lifecycle == 'CANCELLED' || lifecycle == 'FAILED';

  Map<String, dynamic> _details() => {
        'deliveryJobId': 7,
        'assignmentId': 55,
        'orderGroupId': 3,
        'lifecycleStatus': lifecycle,
        'assignmentStatus': 'ASSIGNED',
        'paymentMethod': 'cash',
        'amountToCollect': 25000,
        'totalAmount': 25000,
        'courierEarning': 4000,
        'version': version,
        'customer': {
          'userId': 500,
          'displayName': 'زبون تجريبي',
          'phone': '07701234567',
          'address': 'بلوك A101، بناية 1',
          'latitude': 33.3,
          'longitude': 44.4,
          'deliveryNotes': 'اتركه عند الباب',
        },
        'pickupStops': [
          {'stopId': 101, 'childOrderId': 1001, 'storeId': 11, 'storeName': 'متجر ١', 'sequence': 1, 'preparationStatus': 'READY', 'pickupStatus': stopStatus[101], 'storePhone': '07801', 'latitude': 33.1, 'longitude': 44.1},
          {'stopId': 102, 'childOrderId': 1002, 'storeId': 12, 'storeName': 'متجر ٢', 'sequence': 2, 'preparationStatus': 'READY', 'pickupStatus': stopStatus[102]},
        ],
      };

  @override
  Future<Map<String, dynamic>?> currentGroupedJob({bool skipTerminalSessionInvalidation = false}) async =>
      _terminal ? null : {'delivery_job_id': 7};
  @override
  Future<Map<String, dynamic>> groupedJobDetails(int id) async => _details();
  @override
  Future<Map<String, dynamic>> stopCollected(int id, int stopId, {int? expectedVersion}) async {
    stopStatus[stopId] = 'COLLECTED';
    version++;
    return {'pickupStatus': 'COLLECTED'};
  }
  @override
  Future<Map<String, dynamic>> headingToCustomer(int id, {int? expectedVersion}) async {
    lifecycle = 'HEADING_TO_CUSTOMER';
    version++;
    return {'lifecycleStatus': lifecycle};
  }
  @override
  Future<Map<String, dynamic>> markGroupedDelivered(int id, {int? expectedVersion}) async {
    lifecycle = 'DELIVERED';
    version++;
    return {'lifecycleStatus': lifecycle};
  }
  @override
  Future<List<dynamic>> groupedJobHistory({int limit = 50}) async => [
        {'assignmentId': 9, 'deliveryJobId': 7, 'orderGroupId': 3, 'assignmentStatus': 'released', 'lifecycleStatus': 'ASSIGNED', 'storeCount': 2, 'endedAt': '2026-01-01T00:00:00Z', 'endedReason': 'OWNER_REASSIGN'},
      ];
}

ProviderContainer _container(DeliveryApi api) => ProviderContainer(
      overrides: [deliveryApiProvider.overrideWithValue(api)],
    );

Widget _wrap(ProviderContainer c, Widget child) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    );

void main() {
  // Detail screens are content-tall; give widget tests a large surface so the
  // lazy ListView lays everything out (no off-screen tap/find misses).
  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('dashboard section shows the grouped job card', (tester) async {
    final api = FakeDeliveryApi();
    final c = _container(api);
    await c.read(groupedDeliveryControllerProvider.notifier).bootstrap();
    await tester.pumpWidget(_wrap(c, const Scaffold(body: GroupedDeliveryDashboardSection())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grouped_job_card')), findsOneWidget);
    expect(find.textContaining('طلب من 2 متاجر'), findsWidgets);
  });

  testWidgets('details: collect store 1 leaves store 2; heading gated then enabled', (tester) async {
    await tallSurface(tester);
    final api = FakeDeliveryApi();
    final c = _container(api);
    await c.read(groupedDeliveryControllerProvider.notifier).bootstrap();
    await tester.pumpWidget(_wrap(c, const GroupedDeliveryDetailsScreen()));
    await tester.pumpAndSettle();

    // Both stops rendered.
    expect(find.byKey(const Key('stop_card_101')), findsOneWidget);
    expect(find.byKey(const Key('stop_card_102')), findsOneWidget);

    // Heading-to-customer is disabled before all collected.
    ElevatedButton headingBtn() =>
        tester.widget<ElevatedButton>(find.byKey(const Key('act_heading_customer')));
    expect(headingBtn().onPressed, isNull);

    // Collect store 1 → store 2 remains pending, heading still disabled.
    await tester.tap(find.byKey(const Key('stop_collected_101')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stop_status_102')), findsOneWidget);
    expect(headingBtn().onPressed, isNull);

    // Collect store 2 → heading enabled.
    await tester.tap(find.byKey(const Key('stop_collected_102')));
    await tester.pumpAndSettle();
    expect(headingBtn().onPressed, isNotNull);

    // Head to customer → deliver enabled.
    await tester.tap(find.byKey(const Key('act_heading_customer')));
    await tester.pumpAndSettle();
    final deliverBtn = tester.widget<ElevatedButton>(find.byKey(const Key('act_delivered')));
    expect(deliverBtn.onPressed, isNotNull);
  });

  testWidgets('delivered clears the card from the dashboard section', (tester) async {
    final api = FakeDeliveryApi()
      ..stopStatus[101] = 'COLLECTED'
      ..stopStatus[102] = 'COLLECTED'
      ..lifecycle = 'HEADING_TO_CUSTOMER';
    final c = _container(api);
    final ctrl = c.read(groupedDeliveryControllerProvider.notifier);
    await ctrl.bootstrap();
    await tester.pumpWidget(_wrap(c, const Scaffold(body: GroupedDeliveryDashboardSection())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grouped_job_card')), findsOneWidget);

    await ctrl.markDelivered();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grouped_job_card')), findsNothing);
  });

  testWidgets('history shows a reassigned-away assignment', (tester) async {
    final api = FakeDeliveryApi();
    final c = _container(api);
    await tester.pumpWidget(_wrap(c, const GroupedDeliveryHistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history_row_9')), findsOneWidget);
    expect(find.textContaining('أُعيد تعيينها'), findsOneWidget);
  });

  testWidgets('details show one customer destination with navigate/call', (tester) async {
    await tallSurface(tester);
    final api = FakeDeliveryApi();
    final c = _container(api);
    await c.read(groupedDeliveryControllerProvider.notifier).bootstrap();
    await tester.pumpWidget(_wrap(c, const GroupedDeliveryDetailsScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer_destination_card')), findsOneWidget);
    expect(find.textContaining('زبون تجريبي'), findsOneWidget);
    expect(find.textContaining('اتركه عند الباب'), findsOneWidget);
    // Navigate enabled (coords present); store 1 has a call button.
    expect(
      tester.widget<ElevatedButton>(find.byKey(const Key('customer_navigate'))).onPressed,
      isNotNull,
    );
    expect(find.byKey(const Key('stop_navigate_101')), findsOneWidget);
  });

  testWidgets('details AppBar opens the grouped history', (tester) async {
    await tallSurface(tester);
    final api = FakeDeliveryApi();
    final c = _container(api);
    await c.read(groupedDeliveryControllerProvider.notifier).bootstrap();
    await tester.pumpWidget(_wrap(c, const GroupedDeliveryDetailsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_history_from_details')));
    await tester.pumpAndSettle();
    expect(find.text('سجل المهام المجمّعة'), findsOneWidget);
  });

  testWidgets('error without job shows error card + retry (not "no job")', (tester) async {
    final api = ThrowingDeliveryApi();
    final c = _container(api);
    await c.read(groupedDeliveryControllerProvider.notifier).bootstrap();
    await tester.pumpWidget(_wrap(c, const Scaffold(body: GroupedDeliveryDashboardSection())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grouped_error_card')), findsOneWidget);
    expect(find.byKey(const Key('grouped_retry')), findsOneWidget);
    expect(find.byKey(const Key('grouped_job_card')), findsNothing);
  });
}

/// An API whose bootstrap always fails — used to exercise the error state.
class ThrowingDeliveryApi extends DeliveryApi {
  ThrowingDeliveryApi() : super(Dio());
  @override
  Future<Map<String, dynamic>?> currentGroupedJob({bool skipTerminalSessionInvalidation = false}) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/x'),
      error: 'offline',
      type: DioExceptionType.connectionError,
    );
  }
}
