import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/network/dio_client.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/auth/ui/merchants_list_screen.dart';
import 'package:maslaki/features/merchants/models/merchant_model.dart';
import 'package:maslaki/features/merchants/models/store_activity_model.dart';
import 'package:maslaki/features/merchants/state/customer_merchant_prefs_controller.dart';
import 'package:maslaki/features/merchants/state/merchant_discovery_controller.dart';
import 'package:maslaki/features/merchants/state/merchants_controller.dart';
import 'package:maslaki/features/notifications/state/notifications_controller.dart';
import 'package:maslaki/features/orders/state/delivery_address_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
}

class _MemorySecureStore extends SecureStore {
  final Map<String, String> _values = <String, String>{
    'device_id': 'test-device-id',
  };

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }
}

class _FakeMerchantsController extends MerchantsController {
  _FakeMerchantsController(super.ref, List<MerchantModel> items) {
    state = AsyncValue.data(items);
  }

  @override
  Future<void> load({String? type, String? search, bool force = false}) async {}

  @override
  Future<List<StoreActivityModel>> listActivities() async {
    return const <StoreActivityModel>[
      StoreActivityModel(
        activityType: 'pharmacy',
        baseType: 'market',
        displayNameEn: 'Pharmacy',
        displayNameAr: 'صيدلية',
        hasDiscoverySubcategories: true,
        supportsChat: true,
        supportsAttachments: true,
        supportsPharmacyWorkflow: true,
        internalCategoryMode: 'merchant_defined_with_templates_and_constraints',
        defaultServiceFlags: <String, dynamic>{},
        defaultBadges: <String>[],
      ),
      StoreActivityModel(
        activityType: 'restaurant',
        baseType: 'restaurant',
        displayNameEn: 'Restaurant',
        displayNameAr: 'مطعم',
        hasDiscoverySubcategories: true,
        supportsChat: false,
        supportsAttachments: false,
        supportsPharmacyWorkflow: false,
        internalCategoryMode: 'merchant_defined_with_templates',
        defaultServiceFlags: <String, dynamic>{},
        defaultBadges: <String>[],
      ),
    ];
  }

  @override
  Future<List<StoreDiscoveryOptionModel>> listDiscoveryOptions({
    required String activityType,
  }) async {
    if (activityType != 'pharmacy') return const <StoreDiscoveryOptionModel>[];
    return const <StoreDiscoveryOptionModel>[
      StoreDiscoveryOptionModel(
        id: 1,
        activityType: 'pharmacy',
        code: 'prescriptions',
        labelEn: 'Prescriptions',
        labelAr: 'وصفات طبية',
        orderIndex: 1,
        metadata: <String, dynamic>{},
      ),
    ];
  }
}

class _FakeMerchantDiscoveryController extends MerchantDiscoveryController {
  _FakeMerchantDiscoveryController(super.ref) {
    state = const AsyncValue.data(null);
  }

  @override
  Future<void> load({required String? type, bool force = false}) async {}

  @override
  Future<void> clear() async {
    state = const AsyncValue.data(null);
  }
}

class _FakeDeliveryAddressController extends DeliveryAddressController {
  _FakeDeliveryAddressController(super.ref);

  @override
  Future<void> bootstrap({bool silent = false}) async {
    state = const DeliveryAddressState();
  }
}

class _FakeCustomerMerchantPrefsController
    extends CustomerMerchantPrefsController {
  _FakeCustomerMerchantPrefsController(
    super.ref, {
    CustomerMerchantPrefsState initialState =
        const CustomerMerchantPrefsState(),
  }) {
    state = initialState;
  }

  @override
  Future<void> bootstrap({required int userId}) async {}
}

class _FakeNotificationsController extends NotificationsController {
  _FakeNotificationsController(super.ref) {
    state = const NotificationsState();
  }

  @override
  void startRealtime() {}

  @override
  Future<void> refreshUnreadCount() async {}
}

UserModel _customerUser() {
  return UserModel(
    id: 15,
    fullName: 'Customer User',
    phone: '07700000000',
    role: 'customer',
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
      hasDiscountOffer: false,
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
      hasDiscountOffer: true,
      hasFreeDeliveryOffer: false,
    ),
  ];
}

Future<void> _pumpMerchantsList(
  WidgetTester tester, {
  required MerchantsListScreen screen,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(ref, AuthState(user: _customerUser())),
        ),
        dioClientProvider.overrideWithValue(DioClient(_MemorySecureStore())),
        merchantsControllerProvider.overrideWith(
          (ref) => _FakeMerchantsController(ref, _merchants()),
        ),
        merchantDiscoveryControllerProvider.overrideWith(
          (ref) => _FakeMerchantDiscoveryController(ref),
        ),
        deliveryAddressControllerProvider.overrideWith(
          (ref) => _FakeDeliveryAddressController(ref),
        ),
        customerMerchantPrefsProvider.overrideWith(
          (ref) => _FakeCustomerMerchantPrefsController(ref),
        ),
        notificationsControllerProvider.overrideWith(
          (ref) => _FakeNotificationsController(ref),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: screen,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _pumpMerchantsFlowWithRoot(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(ref, AuthState(user: _customerUser())),
        ),
        dioClientProvider.overrideWithValue(DioClient(_MemorySecureStore())),
        merchantsControllerProvider.overrideWith(
          (ref) => _FakeMerchantsController(ref, _merchants()),
        ),
        merchantDiscoveryControllerProvider.overrideWith(
          (ref) => _FakeMerchantDiscoveryController(ref),
        ),
        deliveryAddressControllerProvider.overrideWith(
          (ref) => _FakeDeliveryAddressController(ref),
        ),
        customerMerchantPrefsProvider.overrideWith(
          (ref) => _FakeCustomerMerchantPrefsController(ref),
        ),
        notificationsControllerProvider.overrideWith(
          (ref) => _FakeNotificationsController(ref),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MerchantsListScreen(),
                      ),
                    );
                  },
                  child: const Text('open-merchants'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets(
    'seeded category intent keeps the main merchants list visible on first load',
    (tester) async {
      await _pumpMerchantsList(
        tester,
        screen: const MerchantsListScreen(
          compactCustomerMode: true,
          initialType: 'market',
          initialSearchQuery: 'fast food',
          requiredAnyKeywords: <String>['burger', 'pizza'],
        ),
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MerchantsListScreen)),
      );

      expect(find.text('Fresh Market'), findsWidgets);
      expect(find.text(l10n.merchantListNoMatching), findsNothing);
      expect(find.text(l10n.merchantListNoStores), findsNothing);
    },
  );

  testWidgets('strictCategoryMode never appends unrelated fallback stores', (
    tester,
  ) async {
    // Same seeded-keyword setup as the non-strict test above, but strict:
    // none of the seeded merchants match burger/pizza, so a strict category
    // page must stay clean instead of falling back to all market stores.
    await _pumpMerchantsList(
      tester,
      screen: const MerchantsListScreen(
        compactCustomerMode: true,
        initialType: 'market',
        initialSearchQuery: 'fast food',
        requiredAnyKeywords: <String>['burger', 'pizza'],
        strictCategoryMode: true,
      ),
    );

    expect(find.text('Fresh Market'), findsNothing);
    expect(find.text('Coffee Corner'), findsNothing);
  });

  testWidgets('explicit search still shows the no matching state', (
    tester,
  ) async {
    await _pumpMerchantsList(
      tester,
      screen: const MerchantsListScreen(
        compactCustomerMode: true,
        initialType: 'market',
        initialSearchQuery: 'zzzz-not-found',
      ),
    );

    final l10n = AppLocalizations.of(
      tester.element(find.byType(MerchantsListScreen)),
    );

    expect(find.text(l10n.merchantListNoMatching), findsOneWidget);
    expect(find.text(l10n.commonReset), findsOneWidget);
  });

  testWidgets('activity type rail renders pharmacy in customer list', (
    tester,
  ) async {
    await _pumpMerchantsList(
      tester,
      screen: const MerchantsListScreen(compactCustomerMode: true),
    );

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pharmacy'), findsWidgets);
  });

  testWidgets(
    'activity strip shows in root market context and hides in locked activity context',
    (tester) async {
      await _pumpMerchantsList(
        tester,
        screen: const MerchantsListScreen(
          compactCustomerMode: true,
          initialType: 'market',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(MerchantsListScreen)),
      );
      expect(find.text(l10n.customerDiscoveryBannerOfferTitle), findsNothing);
      expect(find.text('Pharmacy'), findsWidgets);
      expect(find.text('Restaurants'), findsNothing);
      expect(find.text('Markets'), findsNothing);

      await _pumpMerchantsList(
        tester,
        screen: const MerchantsListScreen(
          compactCustomerMode: true,
          initialType: 'market',
          initialActivityType: 'pharmacy',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Prescriptions'), findsNothing);
    },
  );

  testWidgets('strict category pages hide global type filters', (tester) async {
    await _pumpMerchantsList(
      tester,
      screen: const MerchantsListScreen(
        compactCustomerMode: true,
        initialActivityType: 'pharmacy',
        strictCategoryMode: true,
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Restaurants'), findsNothing);
    expect(find.text('Markets'), findsNothing);

    // Unmount so any periodic timer in the discovery view (e.g. an ad carousel)
    // is cancelled in dispose() before the test ends (Flutter 3.47's test
    // binding flags a still-pending timer otherwise).
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('drawer home item returns to root stack', (tester) async {
    await _pumpMerchantsFlowWithRoot(tester);

    await tester.tap(find.text('open-merchants'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(MerchantsListScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(MerchantsListScreen)),
    );

    await tester.tap(find.text(l10n.drawerHome));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('open-merchants'), findsOneWidget);
    expect(find.byType(MerchantsListScreen), findsNothing);
  });

  testWidgets('customer drawer does not show merchant tools labels', (
    tester,
  ) async {
    await _pumpMerchantsList(tester, screen: const MerchantsListScreen());

    await tester.tap(find.byTooltip('Open navigation menu').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(MerchantsListScreen)),
    );

    expect(find.text(l10n.customerHomeDrawerSubtitle), findsOneWidget);
    expect(find.text(l10n.drawerMerchantsSub), findsNothing);
    expect(find.text(l10n.drawerWorkspace), findsNothing);
  });
}
