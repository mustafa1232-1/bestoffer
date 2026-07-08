import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/customer/state/customer_ad_board_controller.dart';
import 'package:maslaki/features/merchants/data/merchants_api.dart';
import 'package:maslaki/features/merchants/state/merchants_controller.dart';

/// Records ad-board calls so we can assert non-customer sessions never hit the
/// customer-only endpoint (backend requireCustomer -> role 'user' only).
class _SpyMerchantsApi extends MerchantsApi {
  _SpyMerchantsApi() : super(Dio());

  int adBoardCalls = 0;

  @override
  Future<List<dynamic>> adBoard({String? type}) async {
    adBoardCalls += 1;
    return const <dynamic>[];
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initial) {
    state = initial;
  }

  @override
  Future<void> bootstrap() async {}
}

AuthState _sessionWithRole(String? role) {
  return AuthState(
    token: role == null ? null : 'test-token',
    user: role == null
        ? null
        : UserModel(
            id: 6,
            fullName: 'Tester',
            phone: '07700000006',
            role: role,
            block: '1',
            buildingNumber: '1',
            apartment: '1',
            imageUrl: null,
            workTitle: null,
            workCompany: null,
            preferredLocale: 'ar',
            isSuperAdmin: false,
          ),
  );
}

ProviderContainer _container(_SpyMerchantsApi spy, String? role) {
  final container = ProviderContainer(
    overrides: [
      merchantsApiProvider.overrideWithValue(spy),
      authControllerProvider.overrideWith(
        (ref) => _FakeAuthController(ref, _sessionWithRole(role)),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('non-customer (owner) session does NOT call /api/merchants/ad-board', () async {
    final spy = _SpyMerchantsApi();
    final container = _container(spy, 'owner');

    await container.read(customerAdBoardControllerProvider.notifier).load();

    expect(spy.adBoardCalls, 0);
    final state = container.read(customerAdBoardControllerProvider);
    expect(state.valueOrNull, isEmpty);
  });

  test('store/hr/delivery roles are all blocked from the ad-board endpoint', () async {
    for (final role in ['store', 'hr', 'delivery', 'captain', 'company', 'accountant', 'admin']) {
      final spy = _SpyMerchantsApi();
      final container = _container(spy, role);
      await container.read(customerAdBoardControllerProvider.notifier).load();
      expect(spy.adBoardCalls, 0, reason: 'role $role must not call ad-board');
    }
  });

  test('customer (role "user") session DOES load the ad-board', () async {
    final spy = _SpyMerchantsApi();
    final container = _container(spy, 'user');

    await container.read(customerAdBoardControllerProvider.notifier).load();

    expect(spy.adBoardCalls, 1);
  });
}
