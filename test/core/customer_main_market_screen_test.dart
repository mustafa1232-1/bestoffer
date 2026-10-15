import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/network/dio_client.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/customer/ui/customer_main_market_screen.dart';
import 'package:maslaki/features/merchants/models/merchant_model.dart';
import 'package:maslaki/features/merchants/models/store_activity_model.dart';
import 'package:maslaki/features/merchants/state/customer_merchant_prefs_controller.dart';
import 'package:maslaki/features/merchants/state/merchant_discovery_controller.dart';
import 'package:maslaki/features/merchants/state/merchants_controller.dart';
import 'package:maslaki/features/notifications/state/notifications_controller.dart';
import 'package:maslaki/features/notifications/ui/notifications_screen.dart';
import 'package:maslaki/features/orders/state/delivery_address_controller.dart';
import 'package:maslaki/features/orders/ui/cart_screen.dart';
import 'package:maslaki/features/orders/ui/delivery_addresses_screen.dart';
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
  final List<MerchantModel> _items;

  _FakeMerchantsController(super.ref, List<MerchantModel> items)
    : _items = items {
    state = AsyncValue.data(items);
  }

  String? lastType;
  String? lastActivityType;

  @override
  Future<void> loadWithFilters({
    String? type,
    String? search,
    String? activityType,
    String? discoverySubcategory,
    String? department,
    bool force = false,
  }) async {
    lastType = type;
    lastActivityType = activityType;
    state = AsyncValue.data(_items);
  }

  @override
  Future<List<StoreActivityModel>> listActivities() async {
    return const <StoreActivityModel>[
      StoreActivityModel(
        activityType: 'pharmacy',
        baseType: 'market',
        displayNameEn: 'Pharmacy',
        displayNameAr: 'صيدلية',
        hasDiscoverySubcategories: false,
        supportsChat: true,
        supportsAttachments: true,
        supportsPharmacyWorkflow: true,
        internalCategoryMode: 'merchant_defined_with_templates',
        defaultServiceFlags: <String, dynamic>{},
        defaultBadges: <String>[],
      ),
      StoreActivityModel(
        activityType: 'restaurant',
        baseType: 'restaurant',
        displayNameEn: 'Restaurant',
        displayNameAr: 'مطعم',
        hasDiscoverySubcategories: false,
        supportsChat: false,
        supportsAttachments: false,
        supportsPharmacyWorkflow: false,
        internalCategoryMode: 'merchant_defined_with_templates',
        defaultServiceFlags: <String, dynamic>{},
        defaultBadges: <String>[],
      ),
      StoreActivityModel(
        activityType: 'fashion_clothing',
        baseType: 'market',
        displayNameEn: 'Fashion',
        displayNameAr: 'أزياء',
        hasDiscoverySubcategories: false,
        supportsChat: false,
        supportsAttachments: false,
        supportsPharmacyWorkflow: false,
        internalCategoryMode: 'merchant_defined_with_templates',
        defaultServiceFlags: <String, dynamic>{},
        defaultBadges: <String>[],
      ),
      StoreActivityModel(
        activityType: 'supermarket',
        baseType: 'market',
        displayNameEn: 'Supermarket',
        displayNameAr: 'سوبرماركت',
        hasDiscoverySubcategories: false,
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
    return const <StoreDiscoveryOptionModel>[];
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
  _FakeCustomerMerchantPrefsController(super.ref) {
    state = const CustomerMerchantPrefsState();
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

  @override
  Future<void> loadNotifications({
    bool unreadOnly = false,
    bool silent = false,
  }) async {
    state = state.copyWith(loading: false, notifications: const []);
  }
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
      activityType: 'coffee_drinks',
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
    MerchantModel(
      id: 3,
      name: 'Sweet House',
      type: 'restaurant',
      activityType: 'sweets_bakery',
      description: 'Desserts and pastry',
      phone: '07730000000',
      imageUrl: null,
      tagline: 'Fresh sweets',
      workingHours: null,
      serviceAreaNote: null,
      isOpen: true,
      hasDiscountOffer: false,
      hasFreeDeliveryOffer: false,
    ),
  ];
}

Future<void> _pumpMarket(WidgetTester tester) async {
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
        merchantBrowsePositionProvider.overrideWith((ref) async => null),
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
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: CustomerMainMarketScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('main market opens the store list directly with category cards', (
    tester,
  ) async {
    await _pumpMarket(tester);

    expect(find.text('Fresh Market'), findsWidgets);
    expect(find.text('Coffee Corner'), findsWidgets);
    expect(find.text('Sweet House'), findsWidgets);
    expect(find.text('Fashion'), findsWidgets);
    expect(find.text('Restaurants'), findsWidgets);
    expect(find.text('Supermarket'), findsWidgets);
    expect(find.text('Pharmacies'), findsWidgets);
  });

  testWidgets('category cards filter the same merchant surface', (
    tester,
  ) async {
    await _pumpMarket(tester);

    await tester.tap(find.text('Restaurants').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Coffee Corner'), findsWidgets);
    expect(find.text('Sweet House'), findsWidgets);
    expect(find.text('Fresh Market'), findsNothing);
  });

  testWidgets('market header drawer button opens the app drawer', (
    tester,
  ) async {
    await _pumpMarket(tester);

    await tester.tap(
      find.byKey(const Key('shopping_market_drawer_button')).hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Drawer), findsWidgets);
  });

  testWidgets('market header notification button opens notifications', (
    tester,
  ) async {
    await _pumpMarket(tester);

    await tester.tap(
      find
          .byKey(const Key('shopping_market_notifications_button'))
          .hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('market header cart button opens cart', (tester) async {
    await _pumpMarket(tester);

    await tester.tap(
      find.byKey(const Key('shopping_market_cart_button')).hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CartScreen), findsOneWidget);
  });

  testWidgets('market header location button opens delivery addresses', (
    tester,
  ) async {
    await _pumpMarket(tester);

    await tester.tap(
      find.byKey(const Key('shopping_market_location_button')).hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DeliveryAddressesScreen), findsOneWidget);
  });
}
