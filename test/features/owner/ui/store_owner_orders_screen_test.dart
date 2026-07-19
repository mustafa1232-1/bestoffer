import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maslaki/features/delivery/models/delivery_agent_model.dart';
import 'package:maslaki/features/owner/data/owner_api.dart';
import 'package:maslaki/features/orders/models/order_model.dart';
import 'package:maslaki/features/orders/ui/widgets/order_item_widgets.dart';
import 'package:maslaki/features/owner/state/owner_controller.dart';
import 'package:maslaki/features/owner/ui/store_owner_orders_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeOwnerApi extends OwnerApi {
  _FakeOwnerApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> merchantCustomerReliability({
    required int customerUserId,
  }) async {
    return const {'warningRequired': false, 'score': 100, 'tier': 'good'};
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
          'product_name': 'Fashion Hoodie',
          'merchant_name': 'Test Store',
          'merchant_id': 9,
          'base_unit_price': 10000,
          'unit_price': 10000,
          'quantity': 1,
          'line_discount_total': 0,
          'line_total': 10000,
          'variant_price_delta_total': 0,
          'selected_variant_options_json': [
            {'groupLabel': 'Color', 'optionLabel': 'Black', 'hex': '#000000'},
            {'groupLabel': 'Size', 'optionLabel': 'XL'},
          ],
          'display_snapshot_json': {
            'version': 1,
            'productId': 55,
            'productName': 'Fashion Hoodie',
            'productImageUrl': 'https://example.com/fashion-hoodie.jpg',
            'thumbnailUrl': 'https://example.com/fashion-hoodie-thumb.jpg',
            'sku': 'HOODIE-001',
            'variantId': 1012,
            'variantName': 'Black / XL',
            'variantSku': 'HOODIE-BLACK-XL',
            'quantity': 1,
            'unitPrice': 10000,
            'lineTotal': 10000,
            'currency': 'IQD',
            'selectedColor': {
              'label': 'Color',
              'value': 'Black',
              'hex': '#000000',
            },
            'selectedSize': {'label': 'Size', 'value': 'XL'},
            'specs': [
              {'label': 'Color', 'value': 'Black', 'hex': '#000000'},
              {'label': 'Size', 'value': 'XL'},
            ],
            'options': [],
            'addons': [],
            'removals': [],
            'userNote': 'Handle carefully',
            'activityType': 'fashion_clothing',
            'storeId': 9,
            'storeName': 'Test Store',
          },
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
    'store owner orders screen auto-assigns delivery without store courier selection',
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

      // The store no longer selects a delivery type or a courier: the
      // delivery-type dropdown and the manual assign/change-courier button must
      // be gone, leaving auto-assignment as the only path.
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.text('Change courier'), findsNothing);
      expect(find.text('Assign courier'), findsNothing);

      await tester.ensureVisible(find.text('Start preparing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start preparing'));
      await tester.pumpAndSettle();

      // Preparing starts and the backend auto-assigns: no preferred courier is
      // sent from the store screen.
      expect(controller.lastPreparedOrderId, 101);
      expect(controller.lastPreferredCourierUserId, isNull);
      expect(controller.lastAssignedOrderId, isNull);
    },
  );

  testWidgets(
    'store owner orders screen shows item snapshot details before actions',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ownerApiProvider.overrideWithValue(_FakeOwnerApi()),
            ownerControllerProvider.overrideWith((ref) {
              return _FakeOwnerController(ref);
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

      expect(
        find.text('راجع المنتجات والمواصفات قبل الموافقة'),
        findsOneWidget,
      );
      expect(find.byType(OrderItemsSummaryList), findsOneWidget);
      expect(find.byType(OrderItemMiniCard), findsOneWidget);
      expect(find.byType(OrderItemThumbnail), findsOneWidget);
      expect(find.text('Color: Black'), findsOneWidget);
      expect(find.text('Size: XL'), findsOneWidget);
      expect(find.textContaining('Handle carefully'), findsOneWidget);
    },
  );

  testWidgets(
    'store owner orders screen opens store coupon management from drawer',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1280, 1800));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ownerApiProvider.overrideWithValue(_FakeOwnerApi()),
            ownerControllerProvider.overrideWith((ref) {
              return _FakeOwnerController(ref);
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

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      final couponsEntry = find.text(l10n.ownerMenuCouponsTitle);
      await tester.ensureVisible(couponsEntry);
      await tester.tap(couponsEntry, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(find.text(l10n.couponManagementTitleOwner), findsOneWidget);
      expect(find.text(l10n.couponManagementCreateAction), findsOneWidget);

      await tester.tap(find.text(l10n.couponManagementCreateAction));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(
        find.text(
          l10n.validationRequiredField(l10n.couponManagementCodeLabel),
        ),
        findsOneWidget,
      );
    },
  );
}
