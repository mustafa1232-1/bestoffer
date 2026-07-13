import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/delivery/state/delivery_controller.dart';
import 'package:maslaki/features/delivery/ui/courier_pages.dart';
import 'package:maslaki/features/orders/models/order_model.dart';
import 'package:maslaki/l10n/app_localizations.dart';

/// Seeds the delivery controller with a fixed order list and disables all
/// network/live behavior so the order-list filters can be tested in isolation.
class _SeededDeliveryController extends DeliveryController {
  _SeededDeliveryController(super.ref, List<OrderModel> orders) {
    state = state.copyWith(currentOrders: orders, loading: false);
  }

  @override
  Future<void> bootstrap({String? historyDate}) async {}

  @override
  void startLiveOrders({Duration interval = const Duration(seconds: 6)}) {}

  @override
  Future<void> refreshCurrentOrders({
    bool silent = false,
    bool forcePresenceSync = false,
  }) async {}
}

OrderModel _order(int id, String status) => OrderModel.fromJson({
  'id': id,
  'merchant_id': 1,
  'customer_user_id': 2,
  'merchant_name': 'Merchant',
  'status': status,
  'customer_full_name': 'Customer',
  'customer_phone': '0770000000',
  'customer_city': 'Basmaya',
  'customer_block': 'A1',
  'customer_building_number': '12',
  'customer_apartment': '3',
  'delivery_user_id': 9,
  'total_amount': 1000,
  'items': const <dynamic>[],
});

Widget _wrap(Widget child, List<OrderModel> orders) => ProviderScope(
  overrides: [
    deliveryControllerProvider.overrideWith(
      (ref) => _SeededDeliveryController(ref, orders),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: AppTheme.dark(),
    home: child,
  ),
);

void main() {
  final orders = [
    _order(101, 'on_the_way'),
    _order(102, 'ready_for_delivery'),
    _order(103, 'delivered'),
  ];

  testWidgets('in-delivery page shows only in-transit orders', (tester) async {
    await tester.pumpWidget(_wrap(const CourierOrdersInDeliveryPage(), orders));
    await tester.pumpAndSettle();

    expect(find.textContaining('#101'), findsOneWidget); // on_the_way
    expect(find.textContaining('#102'), findsNothing); // ready (not in transit)
    expect(find.textContaining('#103'), findsNothing); // delivered
  });

  testWidgets(
    'waiting-pickup page shows only accepted/ready-not-picked orders',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const CourierOrdersWaitingPickupPage(), orders),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('#102'), findsOneWidget); // ready_for_delivery
      expect(find.textContaining('#101'), findsNothing); // already on the way
      expect(find.textContaining('#103'), findsNothing); // delivered
    },
  );
}
