import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/customer/models/customer_ad_board_item.dart';
import 'package:maslaki/features/customer/models/customer_home_prefs.dart';
import 'package:maslaki/features/customer/state/customer_ad_board_controller.dart';
import 'package:maslaki/features/customer/state/customer_home_prefs_controller.dart';
import 'package:maslaki/features/customer/ui/customer_discovery_screen.dart';
import 'package:maslaki/features/merchants/models/merchant_model.dart';
import 'package:maslaki/features/merchants/state/merchants_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
}

class _FakeMerchantsController extends MerchantsController {
  _FakeMerchantsController(super.ref, List<MerchantModel> items) {
    state = AsyncValue.data(items);
  }

  @override
  Future<void> load({String? type, String? search, bool force = false}) async {}
}

class _FakeAdBoardController extends CustomerAdBoardController {
  int loadCalls = 0;

  _FakeAdBoardController(
    super.ref, {
    List<CustomerAdBoardItem> items = const <CustomerAdBoardItem>[],
  }) {
    state = AsyncValue.data(items);
  }

  @override
  Future<void> load({String? type, bool force = false}) async {
    loadCalls += 1;
  }
}

class _FakeHomePrefsController extends CustomerHomePrefsController {
  _FakeHomePrefsController(super.ref) {
    state = const AsyncValue.data(
      CustomerHomePrefs(
        completed: true,
        audience: 'any',
        priority: 'balanced',
        interests: <String>[],
        updatedAt: null,
      ),
    );
  }

  @override
  Future<void> bootstrap({required int userId}) async {}
}

UserModel _customerUser() {
  return UserModel(
    id: 15,
    fullName: 'Customer User',
    phone: '07700000000',
    role: 'user',
    block: 'A1',
    buildingNumber: '11',
    apartment: '5',
    imageUrl: null,
    workTitle: null,
    workCompany: null,
    preferredLocale: 'ar',
    isSuperAdmin: false,
  );
}

List<MerchantModel> _merchants() {
  return <MerchantModel>[
    MerchantModel(
      id: 1,
      name: 'Fresh Market',
      type: 'market',
      description: 'Neighborhood essentials',
      phone: '07710000000',
      imageUrl: null,
      tagline: 'Fast groceries',
      workingHours: null,
      serviceAreaNote: null,
      isOpen: true,
      hasDiscountOffer: true,
      hasFreeDeliveryOffer: true,
    ),
    MerchantModel(
      id: 2,
      name: 'Coffee Corner',
      type: 'restaurant',
      description: 'Daily coffee and snacks',
      phone: '07720000000',
      imageUrl: null,
      tagline: 'Hot drinks',
      workingHours: null,
      serviceAreaNote: null,
      isOpen: false,
      hasDiscountOffer: false,
      hasFreeDeliveryOffer: false,
    ),
  ];
}

CustomerAdBoardItem _adItem({
  int id = 1,
  String title = 'Offer title',
  String subtitle = 'Offer subtitle',
  String ctaTargetType = 'none',
  String? ctaTargetValue,
  String? merchantName,
  String? merchantType,
}) {
  return CustomerAdBoardItem(
    id: id,
    title: title,
    subtitle: subtitle,
    imageUrl: null,
    badgeLabel: null,
    ctaLabel: null,
    ctaTargetType: ctaTargetType,
    ctaTargetValue: ctaTargetValue,
    merchantId: null,
    merchantName: merchantName,
    merchantType: merchantType,
    merchantIsOpen: true,
    priority: 10,
  );
}

Future<_FakeAdBoardController> _pumpDiscovery(
  WidgetTester tester, {
  CustomerDiscoveryMode mode = CustomerDiscoveryMode.full,
  List<CustomerAdBoardItem> adItems = const <CustomerAdBoardItem>[],
}) async {
  late _FakeAdBoardController adController;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState(user: _customerUser(), token: 'test-token'),
          ),
        ),
        merchantsControllerProvider.overrideWith(
          (ref) => _FakeMerchantsController(ref, _merchants()),
        ),
        customerAdBoardControllerProvider.overrideWith(
          (ref) => adController = _FakeAdBoardController(ref, items: adItems),
        ),
        customerHomePrefsProvider.overrideWith(
          (ref) => _FakeHomePrefsController(ref),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: CustomerDiscoveryScreen(mode: mode),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return adController;
}

void main() {
  testWidgets(
    'customer discovery keeps required order and removes live market pulse section',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpDiscovery(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(CustomerDiscoveryScreen)),
      );

      expect(find.text(l10n.customerDiscoveryLiveMarketPulse), findsNothing);

      final heroFinder = find.text(l10n.customerDiscoveryHeroCloserTagline);
      final bannerFinder = find.byType(PageView).first;
      final searchFinder = find.byType(TextField).first;
      final categoriesFinder = find.text(l10n.customerDiscoveryMainCategories);
      final taxiSpotlightFinder = find.text(
        l10n.customerDiscoveryTaxiSpotlightTitle,
      );
      final pharmacyHubFinder = find.text(
        l10n.customerDiscoveryHubPharmacyTitle,
      );

      expect(heroFinder, findsOneWidget);
      expect(bannerFinder, findsOneWidget);
      expect(searchFinder, findsOneWidget);
      expect(categoriesFinder, findsOneWidget);

      final heroY = tester.getTopLeft(heroFinder).dy;
      final bannerY = tester.getTopLeft(bannerFinder).dy;
      final searchY = tester.getTopLeft(searchFinder).dy;
      final categoriesY = tester.getTopLeft(categoriesFinder).dy;

      expect(heroY, lessThan(bannerY));
      expect(bannerY, lessThan(searchY));
      expect(searchY, lessThan(categoriesY));
      await tester.scrollUntilVisible(
        taxiSpotlightFinder,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(taxiSpotlightFinder, findsOneWidget);
      await tester.scrollUntilVisible(
        pharmacyHubFinder,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(pharmacyHubFinder, findsOneWidget);
    },
  );

  testWidgets(
    'shoppingOnly hides ads and non-shopping launchers while keeping shopping actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final adController = await _pumpDiscovery(
        tester,
        mode: CustomerDiscoveryMode.shoppingOnly,
        adItems: <CustomerAdBoardItem>[
          _adItem(
            id: 7,
            title: 'Taxi promo',
            subtitle: 'Fast rides',
            ctaTargetType: 'taxi',
          ),
        ],
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(CustomerDiscoveryScreen)),
      );

      expect(find.byType(PageView), findsNothing);
      expect(find.text(l10n.customerDiscoveryTaxiSpotlightTitle), findsNothing);
      expect(find.text(l10n.customerDiscoveryRequestTaxi), findsNothing);
      expect(adController.loadCalls, equals(0));

      await tester.tap(find.byIcon(Icons.menu_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Shopping'), findsOneWidget);
      expect(find.text('Addresses'), findsOneWidget);
      expect(find.text('My account'), findsOneWidget);
      expect(find.text('Taxi'), findsOneWidget);
      expect(find.text(l10n.customerDiscoveryBasmayaFeed), findsNothing);
      expect(find.text(l10n.customerDiscoverySocialSearch), findsNothing);
      expect(find.text(l10n.customerDiscoveryChats), findsNothing);
    },
  );

  testWidgets('shoppingOnly refresh does not trigger ad-board reload', (
    tester,
  ) async {
    final adController = await _pumpDiscovery(
      tester,
      mode: CustomerDiscoveryMode.shoppingOnly,
      adItems: <CustomerAdBoardItem>[_adItem()],
    );

    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refresh.onRefresh();

    expect(adController.loadCalls, equals(0));
  });
}
