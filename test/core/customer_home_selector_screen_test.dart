import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/customer/models/customer_ad_board_item.dart';
import 'package:maslaki/features/customer/models/recent_activity.dart';
import 'package:maslaki/features/customer/state/customer_ad_board_controller.dart';
import 'package:maslaki/features/customer/state/customer_smart_experience_provider.dart';
import 'package:maslaki/features/customer/state/recent_activity_controller.dart';
import 'package:maslaki/features/customer/ui/customer_home_selector_screen.dart';
import 'package:maslaki/features/merchants/data/merchants_api.dart';
import 'package:maslaki/features/merchants/state/merchants_controller.dart';
import 'package:maslaki/features/orders/models/delivery_address_model.dart';
import 'package:maslaki/features/orders/state/delivery_address_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
}

class _FakeAdBoardController extends CustomerAdBoardController {
  _FakeAdBoardController(
    super.ref, {
    List<CustomerAdBoardItem> items = const <CustomerAdBoardItem>[],
  }) {
    state = AsyncValue.data(items);
  }

  @override
  Future<void> load({String? type, bool force = false}) async {}
}

class _FakeDeliveryAddressController extends DeliveryAddressController {
  _FakeDeliveryAddressController(
    super.ref, {
    DeliveryAddressState initialState = const DeliveryAddressState(),
  }) {
    state = initialState;
  }

  @override
  Future<void> bootstrap({bool silent = false}) async {}
}

class _FakeRecentActivityController extends RecentActivityController {
  _FakeRecentActivityController(
    super.ref, {
    AsyncValue<RecentActivityModel?> initialState = const AsyncValue.data(null),
  }) {
    state = initialState;
  }

  @override
  Future<void> load({bool force = false}) async {}
}

class _FakeMerchantsApi extends MerchantsApi {
  final List<Map<String, dynamic>> items;

  _FakeMerchantsApi({required this.items}) : super(Dio());

  @override
  Future<List<dynamic>> list({
    String? type,
    String? search,
    String? activityType,
    String? discoverySubcategory,
  }) async {
    return items;
  }
}

class _TestNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

UserModel _user({
  String block = 'A1',
  String buildingNumber = '11',
  String apartment = '5',
}) {
  return UserModel(
    id: 15,
    fullName: 'Customer User',
    phone: '07700000000',
    role: 'user',
    block: block,
    buildingNumber: buildingNumber,
    apartment: apartment,
    imageUrl: null,
    workTitle: null,
    workCompany: null,
    preferredLocale: 'ar',
    isSuperAdmin: false,
  );
}

CustomerAdBoardItem _adItem({
  int id = 1,
  String title = 'Ad title',
  String subtitle = 'Ad subtitle',
  String ctaTargetType = 'none',
}) {
  return CustomerAdBoardItem(
    id: id,
    title: title,
    subtitle: subtitle,
    imageUrl: null,
    badgeLabel: null,
    ctaLabel: 'Open',
    ctaTargetType: ctaTargetType,
    ctaTargetValue: null,
    merchantId: null,
    merchantName: 'Ad merchant',
    merchantType: 'market',
    merchantIsOpen: true,
    priority: 5,
  );
}

DeliveryAddressState _selectedAddressState() {
  const address = DeliveryAddressModel(
    id: 10,
    label: 'Home',
    city: 'Baghdad',
    block: '12',
    buildingNumber: '4',
    apartment: '8',
    isDefault: true,
  );
  return const DeliveryAddressState(
    addresses: <DeliveryAddressModel>[address],
    selectedAddressId: 10,
  );
}

Map<String, dynamic> _merchantItem({
  required int id,
  required String name,
  bool isOpen = true,
  String type = 'market',
  double rating = 4.7,
  int ratingCount = 80,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'type': type,
    'activityType': type,
    'is_open': isOpen,
    'avg_merchant_rating': rating,
    'rating_count': ratingCount,
    'has_discount_offer': false,
    'has_free_delivery_offer': false,
  };
}

Future<void> _pumpHomeSelector(
  WidgetTester tester, {
  required UserModel user,
  List<CustomerAdBoardItem> ads = const <CustomerAdBoardItem>[],
  List<Map<String, dynamic>> merchants = const <Map<String, dynamic>>[],
  DeliveryAddressState deliveryState = const DeliveryAddressState(),
  CustomerSmartExperienceSnapshot? smartSnapshot,
  AsyncValue<RecentActivityModel?> recentActivityState = const AsyncValue.data(
    null,
  ),
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState(user: user, token: 'test-token'),
          ),
        ),
        customerAdBoardControllerProvider.overrideWith(
          (ref) => _FakeAdBoardController(ref, items: ads),
        ),
        deliveryAddressControllerProvider.overrideWith(
          (ref) =>
              _FakeDeliveryAddressController(ref, initialState: deliveryState),
        ),
        recentActivityControllerProvider.overrideWith(
          (ref) => _FakeRecentActivityController(
            ref,
            initialState: recentActivityState,
          ),
        ),
        if (smartSnapshot != null)
          customerSmartExperienceProvider.overrideWith(
            (ref) async => smartSnapshot,
          ),
        merchantsApiProvider.overrideWith(
          (ref) => _FakeMerchantsApi(items: merchants),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        navigatorObservers: observer == null
            ? const <NavigatorObserver>[]
            : <NavigatorObserver>[observer],
        home: const CustomerHomeSelectorScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('shows ad carousel when ad-board has items', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpHomeSelector(
      tester,
      user: _user(),
      ads: <CustomerAdBoardItem>[
        _adItem(id: 1, title: 'Admin Banner', ctaTargetType: 'merchant'),
      ],
      merchants: <Map<String, dynamic>>[
        _merchantItem(id: 1, name: 'Open Store'),
      ],
    );

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('Admin Banner'), findsOneWidget);
  });

  testWidgets('hides ad carousel when ad-board is empty', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpHomeSelector(
      tester,
      user: _user(),
      ads: const <CustomerAdBoardItem>[],
      merchants: <Map<String, dynamic>>[
        _merchantItem(id: 1, name: 'Open Store'),
      ],
    );

    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('tapping taxi banner triggers navigation push', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final observer = _TestNavigatorObserver();

    await _pumpHomeSelector(
      tester,
      user: _user(),
      observer: observer,
      ads: <CustomerAdBoardItem>[
        _adItem(id: 2, title: 'Taxi Banner', ctaTargetType: 'taxi'),
      ],
      merchants: <Map<String, dynamic>>[
        _merchantItem(id: 1, name: 'Open Store'),
      ],
    );

    final beforeTapPushes = observer.pushedRoutes.length;
    await tester.tap(find.text('Taxi Banner'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(observer.pushedRoutes.length, greaterThan(beforeTapPushes));
  });

  testWidgets('home header location uses selected address city', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpHomeSelector(
      tester,
      user: _user(),
      deliveryState: _selectedAddressState(),
      merchants: <Map<String, dynamic>>[
        _merchantItem(id: 1, name: 'Open Store'),
      ],
    );

    expect(find.textContaining('Baghdad'), findsOneWidget);
    expect(find.textContaining('25-35'), findsNothing);
  });

  testWidgets('home header location falls back to default city when needed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpHomeSelector(
      tester,
      user: _user(block: '', buildingNumber: '', apartment: ''),
      merchants: <Map<String, dynamic>>[
        _merchantItem(id: 1, name: 'Open Store'),
      ],
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(CustomerHomeSelectorScreen)),
    );
    expect(
      find.textContaining(l10n.deliveryAddressesDefaultCity),
      findsOneWidget,
    );
  });

  testWidgets('shows open-now section and best-store spotlight', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpHomeSelector(
      tester,
      user: _user(),
      merchants: <Map<String, dynamic>>[
        _merchantItem(
          id: 1,
          name: 'Open Market',
          rating: 4.9,
          ratingCount: 120,
        ),
        _merchantItem(
          id: 2,
          name: 'Closed Store',
          isOpen: false,
          rating: 5,
          ratingCount: 300,
        ),
      ],
    );

    expect(find.byKey(const Key('best-store-spotlight-card')), findsOneWidget);
    expect(find.byKey(const Key('open-now-stores-section')), findsOneWidget);
    expect(find.text('Open Market'), findsWidgets);
    expect(find.text('Closed Store'), findsNothing);
  });

  testWidgets('tapping best-store spotlight opens shopping discovery', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final observer = _TestNavigatorObserver();

    await _pumpHomeSelector(
      tester,
      user: _user(),
      observer: observer,
      merchants: <Map<String, dynamic>>[
        _merchantItem(
          id: 1,
          name: 'Open Market',
          rating: 4.9,
          ratingCount: 120,
        ),
      ],
    );

    final beforeTapPushes = observer.pushedRoutes.length;
    await tester.tap(find.byKey(const Key('best-store-spotlight-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(observer.pushedRoutes.length, greaterThan(beforeTapPushes));
  });

  testWidgets('home smart shortcuts render on narrow mobile without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpHomeSelector(
      tester,
      user: _user(),
      smartSnapshot: const CustomerSmartExperienceSnapshot(
        insights: <String, dynamic>{},
        savedPlaces: <Map<String, dynamic>>[
          <String, dynamic>{'label': 'البيت', 'placeType': 'home'},
          <String, dynamic>{'label': 'العمل', 'placeType': 'work'},
        ],
        rideHistory: <Map<String, dynamic>>[
          <String, dynamic>{
            'pickup': <String, dynamic>{'label': 'البيت'},
            'dropoff': <String, dynamic>{'label': 'العمل'},
            'agreedFareIqd': 12000,
          },
        ],
      ),
      recentActivityState: AsyncValue.data(
        RecentActivityModel(
          id: 1,
          type: RecentActivityType.shopping,
          targetId: 14,
          targetType: 'merchant',
          title: 'كنت تتصفح قسم التسوق',
          subtitle: 'افتح آخر ما شاهدته بسرعة',
          imageUrl: null,
          route: 'shopping',
          metadata: const <String, dynamic>{},
          createdAt: DateTime(2026, 6, 9),
        ),
      ),
      merchants: <Map<String, dynamic>>[
        _merchantItem(id: 1, name: 'Open Store'),
      ],
    );

    final error = tester.takeException();
    expect(error, isNull);
    expect(find.byType(CustomerHomeSelectorScreen), findsOneWidget);
  });
}
