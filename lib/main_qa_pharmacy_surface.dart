import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/models/user_model.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/auth/ui/merchants_list_screen.dart';
import 'features/customer/models/customer_ad_board_item.dart';
import 'features/customer/models/customer_home_prefs.dart';
import 'features/customer/state/customer_ad_board_controller.dart';
import 'features/customer/state/customer_home_prefs_controller.dart';
import 'features/customer/ui/customer_discovery_screen.dart';
import 'features/merchants/models/merchant_model.dart';
import 'features/merchants/models/store_activity_model.dart';
import 'features/merchants/state/customer_merchant_prefs_controller.dart';
import 'features/merchants/state/merchant_discovery_controller.dart';
import 'features/merchants/state/merchants_controller.dart';
import 'features/notifications/state/notifications_controller.dart';
import 'features/orders/state/delivery_address_controller.dart';
import 'l10n/app_localizations.dart';

void runQaPharmacySurfaceApp() {
  runApp(const _QaPharmacySurfaceApp());
}

void main() {
  runQaPharmacySurfaceApp();
}

class _QaPharmacySurfaceApp extends StatelessWidget {
  const _QaPharmacySurfaceApp();

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => _QaAuthController(ref)),
        merchantsControllerProvider.overrideWith(
          (ref) => _QaMerchantsController(ref),
        ),
        merchantDiscoveryControllerProvider.overrideWith(
          (ref) => _QaMerchantDiscoveryController(ref),
        ),
        customerAdBoardControllerProvider.overrideWith(
          (ref) => _QaAdBoardController(ref),
        ),
        customerHomePrefsProvider.overrideWith(
          (ref) => _QaHomePrefsController(ref),
        ),
        deliveryAddressControllerProvider.overrideWith(
          (ref) => _QaDeliveryAddressController(ref),
        ),
        customerMerchantPrefsProvider.overrideWith(
          (ref) => _QaCustomerMerchantPrefsController(ref),
        ),
        notificationsControllerProvider.overrideWith(
          (ref) => _QaNotificationsController(ref),
        ),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: _QaHomeTabs(),
      ),
    );
  }
}

class _QaHomeTabs extends StatelessWidget {
  const _QaHomeTabs();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('QA Pharmacy Visibility'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Discovery'),
              Tab(text: 'Merchants'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CustomerDiscoveryScreen(),
            MerchantsListScreen(
              compactCustomerMode: true,
              initialType: 'market',
            ),
          ],
        ),
      ),
    );
  }
}

class _QaAuthController extends AuthController {
  _QaAuthController(super.ref) {
    state = AuthState(
      token: 'qa-token',
      user: UserModel(
        id: 501,
        fullName: 'QA Customer',
        phone: '07700000000',
        role: 'user',
        block: 'A1',
        buildingNumber: '11',
        apartment: '5',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: 'en',
        isSuperAdmin: false,
      ),
    );
  }
}

class _QaMerchantsController extends MerchantsController {
  _QaMerchantsController(super.ref) {
    state = AsyncValue.data(<MerchantModel>[
      MerchantModel(
        id: 1,
        name: 'Alif Pharmacy',
        type: 'market',
        activityType: 'pharmacy',
        discoverySubcategory: 'prescriptions',
        description: '24h pharmacy',
        phone: '07700000000',
        imageUrl: null,
        tagline: 'Pharmacy',
        workingHours: null,
        serviceAreaNote: null,
        isOpen: true,
        hasDiscountOffer: false,
        hasFreeDeliveryOffer: false,
        supportsChat: true,
        supportsAttachments: true,
        supportsPharmacyWorkflow: true,
      ),
      MerchantModel(
        id: 2,
        name: 'Fresh Market',
        type: 'market',
        activityType: 'supermarket',
        description: 'Neighborhood essentials',
        phone: '07710000000',
        imageUrl: null,
        tagline: 'Fast groceries',
        workingHours: null,
        serviceAreaNote: null,
        isOpen: true,
        hasDiscountOffer: false,
        hasFreeDeliveryOffer: false,
      ),
    ]);
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
        displayNameAr: 'Pharmacy',
        hasDiscoverySubcategories: true,
        supportsChat: true,
        supportsAttachments: true,
        supportsPharmacyWorkflow: true,
        internalCategoryMode: 'merchant_defined_with_templates_and_constraints',
        defaultServiceFlags: <String, dynamic>{},
        defaultBadges: <String>[],
      ),
      StoreActivityModel(
        activityType: 'supermarket',
        baseType: 'market',
        displayNameEn: 'Supermarket',
        displayNameAr: 'Supermarket',
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
    if (activityType != 'pharmacy') return const <StoreDiscoveryOptionModel>[];
    return const <StoreDiscoveryOptionModel>[
      StoreDiscoveryOptionModel(
        id: 1,
        activityType: 'pharmacy',
        code: 'prescriptions',
        labelEn: 'Prescriptions',
        labelAr: 'Prescriptions',
        orderIndex: 1,
        metadata: <String, dynamic>{},
      ),
      StoreDiscoveryOptionModel(
        id: 2,
        activityType: 'pharmacy',
        code: 'otc',
        labelEn: 'OTC',
        labelAr: 'OTC',
        orderIndex: 2,
        metadata: <String, dynamic>{},
      ),
    ];
  }
}

class _QaMerchantDiscoveryController extends MerchantDiscoveryController {
  _QaMerchantDiscoveryController(super.ref) {
    state = const AsyncValue.data(null);
  }

  @override
  Future<void> load({required String? type, bool force = false}) async {}

  @override
  Future<void> clear() async {
    state = const AsyncValue.data(null);
  }
}

class _QaAdBoardController extends CustomerAdBoardController {
  _QaAdBoardController(super.ref) {
    state = const AsyncValue.data(<CustomerAdBoardItem>[]);
  }

  @override
  Future<void> load({
    String? type,
    String placement = 'HOME_MAIN',
    bool force = false,
  }) async {}
}

class _QaHomePrefsController extends CustomerHomePrefsController {
  _QaHomePrefsController(super.ref) {
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

class _QaDeliveryAddressController extends DeliveryAddressController {
  _QaDeliveryAddressController(super.ref);

  @override
  Future<void> bootstrap({bool silent = false}) async {
    state = const DeliveryAddressState();
  }
}

class _QaCustomerMerchantPrefsController
    extends CustomerMerchantPrefsController {
  _QaCustomerMerchantPrefsController(super.ref);

  @override
  Future<void> bootstrap({required int userId}) async {}
}

class _QaNotificationsController extends NotificationsController {
  _QaNotificationsController(super.ref) {
    state = const NotificationsState();
  }

  @override
  void startRealtime() {}

  @override
  Future<void> refreshUnreadCount() async {}
}
