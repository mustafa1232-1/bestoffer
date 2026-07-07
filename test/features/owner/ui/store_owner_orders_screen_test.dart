import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maslaki/features/delivery/models/delivery_agent_model.dart';
import 'package:maslaki/features/owner/data/owner_api.dart';
import 'package:maslaki/features/orders/models/order_model.dart';
import 'package:maslaki/features/owner/state/owner_controller.dart';
import 'package:maslaki/features/owner/ui/store_owner_orders_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeOwnerApi extends OwnerApi {
  _FakeOwnerApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> merchantCustomerReliability({
    required int customerUserId,
  }) async {
    return const {
      'warningRequired': false,
      'score': 100,
      'tier': 'good',
    };
  }
}

class _FakeOwnerController extends OwnerController {
  _FakeOwnerController(super.ref) {
    state = OwnerState(
      currentOrders: [_buildOrder()],
      deliveryAgents: [_buildDeliveryAgent()],
    );
  }

  int? lastPreparedOrderId;
  int? lastPreferredCourierUserId;
  int? lastAssignedOrderId;
  int? lastAssignedCourierUserId;
  String? lastAssignmentMode;

  @override
  Future<void> bootstrap({String? period, bool force = false}) async {}

  @override
  void startLiveOrders({Duration interval = const Duration(seconds: 15)}) {}

  @override
  void stopLiveOrders() {}

  @override
  Future<void> refreshOrders({
    String? historyDate,
    bool silent = false,
    bool includeHistory = true,
  }) async {}

  @override
  Future<bool> startPreparingFlowV2({
    required int orderId,
    int? preferredCourierUserId,
    int? estimatedPrepMinutes,
    String? note,
  }) async {
    lastPreparedOrderId = orderId;
    lastPreferredCourierUserId = preferredCourierUserId;
    return true;
  }

  @override
  Future<bool> assignCourierFlowV2({
    required int orderId,
    int? courierUserId,
    String assignmentMode = 'manual',
    String? note,
  }) async {
    lastAssignedOrderId = orderId;
    lastAssignedCourierUserId = courierUserId;
    lastAssignmentMode = assignmentMode;
    return true;
  }

  OrderModel _buildOrder() {
    return OrderModel.fromJson({
      'id': 101,
      'merchant_id': 9,
      'customer_user_id': 7001,
      'order_scope': 'single',
      'store_sequence': 1,
      'merchant_name': 'Test Store',
      'status': 'approved',
      'customer_full_name': 'Test Customer',
      'customer_phone': '07700000000',
      'customer_city': 'Baghdad',
      'customer_block': 'A',
      'customer_building_number': '12',
      'customer_apartment': '3',
      'gross_subtotal': 10000,
      'product_discount_total': 0,
      'subtotal': 10000,
      'service_fee': 500,
      'delivery_fee': 1000,
      'coupon_discount_total': 0,
      'total_amount': 11500,
      'delivery_user_id': 21,
      'is_merchant_delivery': false,
      'courier_source': 'app',
      'delivery_driver_type': 'app_driver',
      'archived_by_delivery': false,
      'items': [
        {
          'id': 1,
          'order_id': 101,
          'product_id': 55,
          'product_name': 'Water',
          'base_unit_price': 10000,
          'unit_price': 10000,
          'quantity': 1,
          'line_discount_total': 0,
          'line_total': 10000,
          'variant_price_delta_total': 0,
        },
      ],
    });
  }

  DeliveryAgentModel _buildDeliveryAgent() {
    return DeliveryAgentModel.fromJson({
      'id': 21,
      'full_name': 'Courier A',
      'phone': '07800000000',
    });
  }
}

void main() {
  testWidgets(
    'store owner orders screen uses store_selected for courier assignment',
    (tester) async {
      late _FakeOwnerController controller;

      await tester.pumpWidget(
      ProviderScope(
          overrides: [
            ownerApiProvider.overrideWithValue(_FakeOwnerApi()),
            ownerControllerProvider.overrideWith((ref) {
              controller = _FakeOwnerController(ref);
              return controller;
            }),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: StoreOwnerOrdersScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Start preparing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start preparing'));
      await tester.pumpAndSettle();
      expect(controller.lastPreparedOrderId, 101);
      expect(controller.lastPreferredCourierUserId, 21);

      await tester.ensureVisible(find.text('Change courier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change courier'));
      await tester.pumpAndSettle();
      expect(controller.lastAssignedOrderId, 101);
      expect(controller.lastAssignedCourierUserId, 21);
      expect(controller.lastAssignmentMode, 'store_selected');
    },
  );
}
