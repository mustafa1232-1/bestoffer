// Regression tests for non-destructive session recovery.
//
// SessionRecoveryBus is NOT a logout channel. A recovery tick means "the token
// was silently refreshed" — every listener must keep its state and re-sync in
// the background. These tests pin that contract for the delivery, store and
// customer surfaces, which previously reset themselves to an empty state and
// blanked the screen mid-order.

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/network/session_invalidation.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/delivery/data/delivery_api.dart';
import 'package:maslaki/features/delivery/state/delivery_controller.dart';
import 'package:maslaki/features/orders/data/orders_api.dart';
import 'package:maslaki/features/orders/state/orders_controller.dart';
import 'package:maslaki/features/owner/data/owner_api.dart';
import 'package:maslaki/features/owner/state/owner_controller.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
}

AuthState _authState({required String role, required int id}) {
  return AuthState(
    user: UserModel(
      id: id,
      fullName: 'Recovery $role',
      phone: '0771000000$id',
      role: role,
      block: 'A1',
      buildingNumber: '12',
      apartment: '3',
      imageUrl: null,
      workTitle: null,
      workCompany: null,
      preferredLocale: null,
      isSuperAdmin: false,
    ),
    token: '$role-token',
  );
}

Map<String, dynamic> _order(int id) => <String, dynamic>{
  'id': id,
  'status': 'on_the_way',
  'total_amount': 15000,
};

// ---------------------------------------------------------------------------
// Delivery
// ---------------------------------------------------------------------------

class _FakeDeliveryApi extends DeliveryApi {
  _FakeDeliveryApi() : super(Dio()) {
    dio.options.baseUrl = 'https://example.invalid';
  }

  int ordersCalls = 0;
  int requestsCalls = 0;
  int dashboardCalls = 0;

  @override
  Future<List<dynamic>> ordersV2({
    String? status,
    int? merchantId,
    int limit = 60,
    int offset = 0,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    ordersCalls += 1;
    return <dynamic>[_order(9001)];
  }

  @override
  Future<List<dynamic>> requestsV2({
    int limit = 40,
    int offset = 0,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    requestsCalls += 1;
    return const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> dashboardV2({
    String period = 'day',
    String? from,
    String? to,
    bool skipTerminalSessionInvalidation = false,
  }) async {
    dashboardCalls += 1;
    return const <String, dynamic>{};
  }
}

// ---------------------------------------------------------------------------
// Owner
// ---------------------------------------------------------------------------

class _FakeOwnerApi extends OwnerApi {
  _FakeOwnerApi() : super(Dio()) {
    dio.options.baseUrl = 'https://example.invalid';
  }

  int merchantCalls = 0;
  int currentOrdersCalls = 0;

  @override
  Future<Map<String, dynamic>> getMerchant() async {
    merchantCalls += 1;
    return <String, dynamic>{
      'merchant': <String, dynamic>{'id': 77, 'name': 'Recovery Store'},
    };
  }

  @override
  Future<List<dynamic>> listCurrentOrders() async {
    currentOrdersCalls += 1;
    return <dynamic>[_order(8001)];
  }

  @override
  Future<List<dynamic>> listProducts() async => <dynamic>[
    <String, dynamic>{'id': 1, 'name': 'Product', 'price': 1000},
  ];

  @override
  Future<List<dynamic>> listCategories() async => const <dynamic>[];

  @override
  Future<List<dynamic>> listOffers() async => const <dynamic>[];

  @override
  Future<List<dynamic>> listOrderHistory({String? date}) async =>
      const <dynamic>[];

  @override
  Future<List<dynamic>> listDeliveryAgents() async => const <dynamic>[];

  @override
  Future<List<dynamic>> listAccountants() async => const <dynamic>[];

  @override
  Future<List<dynamic>> listHrStaff() async => const <dynamic>[];

  @override
  Future<Map<String, dynamic>> analytics() async => const <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> settlementSummary() async =>
      const <String, dynamic>{};
}

// ---------------------------------------------------------------------------
// Customer orders
// ---------------------------------------------------------------------------

class _FakeOrdersApi extends OrdersApi {
  _FakeOrdersApi() : super(Dio()) {
    dio.options.baseUrl = 'https://example.invalid';
  }

  int listCalls = 0;

  @override
  Future<List<dynamic>> listMyOrders({int? limit, int offset = 0}) async {
    listCalls += 1;
    return <dynamic>[_order(7001)];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    SessionRecoveryCoordinator.instance.reset();
  });

  group('delivery recovery', () {
    test('recovery keeps DeliveryState and re-arms the presence heartbeat', () async {
      final api = _FakeDeliveryApi();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref, _authState(role: 'delivery', id: 1)),
          ),
          deliveryApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(deliveryControllerProvider.notifier);
      await controller.refreshCurrentOrders(silent: true);
      expect(
        container.read(deliveryControllerProvider).currentOrders,
        isNotEmpty,
        reason: 'precondition: courier has a current order',
      );
      final ordersCallsBefore = api.ordersCalls;

      SessionRecoveryBus.instance.requestRecovery();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The assigned order must survive: no blank screen mid-delivery.
      expect(container.read(deliveryControllerProvider).currentOrders, isNotEmpty);
      // Presence must continue rather than be torn down.
      expect(controller.presenceHeartbeatActive, isTrue);
      // Current orders are re-fetched in the background.
      expect(api.ordersCalls, greaterThan(ordersCallsBefore));
    });

    test('duplicate recovery events resync once and do not stack timers', () async {
      final api = _FakeDeliveryApi();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref, _authState(role: 'delivery', id: 2)),
          ),
          deliveryApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(deliveryControllerProvider.notifier);
      await controller.refreshCurrentOrders(silent: true);
      final ordersCallsBefore = api.ordersCalls;

      // Three ticks in the same frame: the in-flight guard must collapse them
      // into a single background resync.
      SessionRecoveryBus.instance.requestRecovery();
      SessionRecoveryBus.instance.requestRecovery();
      SessionRecoveryBus.instance.requestRecovery();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        api.ordersCalls - ordersCallsBefore,
        1,
        reason: 'duplicate recovery ticks must resync exactly once',
      );
      expect(controller.presenceHeartbeatActive, isTrue);
    });
  });

  group('owner recovery', () {
    test('recovery keeps OwnerState and re-syncs the merchant snapshot', () async {
      final api = _FakeOwnerApi();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref, _authState(role: 'owner', id: 3)),
          ),
          ownerApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);

      await container.read(ownerControllerProvider.notifier).bootstrap();
      expect(
        container.read(ownerControllerProvider).merchant,
        isNotNull,
        reason: 'precondition: store snapshot loaded',
      );
      final merchantCallsBefore = api.merchantCalls;

      SessionRecoveryBus.instance.requestRecovery();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(ownerControllerProvider);
      // Store, orders and products must all survive the recovery.
      expect(state.merchant, isNotNull);
      expect(state.currentOrders, isNotEmpty);
      expect(state.products, isNotEmpty);
      expect(api.merchantCalls, greaterThan(merchantCallsBefore));
    });
  });

  group('customer recovery', () {
    test('recovery keeps the current order and does not fall back to guest', () async {
      final api = _FakeOrdersApi();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref, _authState(role: 'user', id: 4)),
          ),
          ordersApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(ordersControllerProvider.notifier);
      await controller.loadMyOrders();
      expect(
        container.read(ordersControllerProvider).orders,
        isNotEmpty,
        reason: 'precondition: customer has a live order',
      );
      final listCallsBefore = api.listCalls;

      SessionRecoveryBus.instance.requestRecovery();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(ordersControllerProvider).orders, isNotEmpty);
      expect(container.read(authControllerProvider).isAuthed, isTrue);
      expect(api.listCalls, greaterThan(listCallsBefore));

      controller.stopLiveOrders();
    });
  });
}
