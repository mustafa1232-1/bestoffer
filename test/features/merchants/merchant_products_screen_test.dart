import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/behavior/data/behavior_api.dart';
import 'package:maslaki/features/merchants/data/merchants_api.dart';
import 'package:maslaki/features/merchants/models/merchant_model.dart';
import 'package:maslaki/features/merchants/state/merchants_controller.dart';
import 'package:maslaki/features/merchants/ui/merchant_products_screen.dart';
import 'package:maslaki/features/orders/state/cart_controller.dart';
import 'package:maslaki/features/orders/state/orders_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeMerchantsApi extends MerchantsApi {
  _FakeMerchantsApi() : super(Dio());

  @override
  Future<List<dynamic>> listProducts(
    int merchantId, {
    int limit = 80,
    int offset = 0,
  }) async {
    return [
      {
        'id': 11,
        'merchant_id': merchantId,
        'category_id': 1,
        'category_name': 'cloths',
        'name': 'Blue Shirt',
        'price': 10000,
        'image_url': null,
        'sort_order': 0,
        'is_available': true,
        'free_delivery': false,
        'variant_groups': [
          {
            'group_id': 1,
            'code': 'color',
            'label_ar': 'اللون',
            'label_en': 'Color',
            'display_mode': 'swatches',
            'selection_mode': 'single',
            'required': true,
            'sort_order': 0,
            'options': [
              {
                'option_id': 101,
                'code': 'red',
                'label_ar': 'أحمر',
                'label_en': 'Red',
                'swatch_hex': '#FF0000',
                'is_available': true,
                'sort_order': 0,
              },
              {
                'option_id': 102,
                'code': 'blue',
                'label_ar': 'أزرق',
                'label_en': 'Blue',
                'swatch_hex': '#0000FF',
                'is_available': true,
                'sort_order': 1,
              },
              {
                'option_id': 103,
                'code': 'black',
                'label_ar': 'أسود',
                'label_en': 'Black',
                'swatch_hex': '#000000',
                'is_available': false,
                'sort_order': 2,
              },
            ],
          },
          {
            'group_id': 2,
            'code': 'size',
            'label_ar': 'المقاس',
            'label_en': 'Size',
            'display_mode': 'chips',
            'selection_mode': 'single',
            'required': true,
            'sort_order': 1,
            'options': [
              {
                'option_id': 201,
                'code': 's',
                'label_ar': 'S',
                'label_en': 'S',
                'is_available': true,
                'sort_order': 0,
              },
              {
                'option_id': 202,
                'code': 'm',
                'label_ar': 'M',
                'label_en': 'M',
                'is_available': true,
                'sort_order': 1,
              },
              {
                'option_id': 203,
                'code': 'l',
                'label_ar': 'L',
                'label_en': 'L',
                'is_available': true,
                'sort_order': 2,
              },
            ],
          },
        ],
        'variants': [
          {
            'id': 1011,
            'signature': 'color:red|size:s',
            'selections': [
              {'groupCode': 'color', 'optionCode': 'red'},
              {'groupCode': 'size', 'optionCode': 's'},
            ],
            'stock_quantity': 3,
            'is_available': true,
          },
          {
            'id': 1012,
            'signature': 'color:red|size:m',
            'selections': [
              {'groupCode': 'color', 'optionCode': 'red'},
              {'groupCode': 'size', 'optionCode': 'm'},
            ],
            'stock_quantity': 2,
            'is_available': true,
          },
          {
            'id': 1013,
            'signature': 'color:blue|size:l',
            'selections': [
              {'groupCode': 'color', 'optionCode': 'blue'},
              {'groupCode': 'size', 'optionCode': 'l'},
            ],
            'stock_quantity': 5,
            'is_available': true,
          },
        ],
      },
      {
        'id': 12,
        'merchant_id': merchantId,
        'category_id': 2,
        'category_name': 'Chargers',
        'name': 'USB Charger',
        'price': 15000,
        'sort_order': 1,
        'is_available': true,
        'free_delivery': false,
      },
    ];
  }

  @override
  Future<List<dynamic>> listCategories(int merchantId) async {
    return const [
      {
        'id': 1,
        'merchant_id': 5,
        'name': 'cloths',
        'catalog_type': 'clothes',
        'sort_order': 0,
        'available_products_count': 1,
      },
      {
        'id': 2,
        'merchant_id': 5,
        'name': 'Chargers',
        'catalog_type': 'electronics',
        'sort_order': 1,
        'available_products_count': 1,
      },
    ];
  }
}

class _FakeBehaviorApi extends BehaviorApi {
  _FakeBehaviorApi() : super(Dio());

  @override
  Future<void> trackEvent({
    required String eventName,
    String? category,
    String? action,
    String source = 'app_ui',
    String? entityType,
    int? entityId,
    Map<String, dynamic>? metadata,
  }) async {}
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }
}

class _FakeOrdersController extends OrdersController {
  _FakeOrdersController(super.ref) {
    state = const OrdersState();
  }

  @override
  Future<void> loadFavoriteProductIds() async {}
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

MerchantModel _merchant() {
  return MerchantModel(
    id: 5,
    name: 'Clothing House',
    type: 'market',
    activityType: 'fashion_clothing',
    description: 'Clothing only store',
    phone: '07710000000',
    imageUrl: null,
    tagline: null,
    workingHours: null,
    serviceAreaNote: null,
    isOpen: true,
    hasDiscountOffer: false,
    hasFreeDeliveryOffer: false,
  );
}

void main() {
  testWidgets('merchant products screen hides unrelated section categories', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(ref, AuthState(user: _customerUser())),
          ),
          merchantsApiProvider.overrideWithValue(_FakeMerchantsApi()),
          behaviorApiProvider.overrideWithValue(_FakeBehaviorApi()),
          ordersControllerProvider.overrideWith(
            (ref) => _FakeOrdersController(ref),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: MerchantProductsScreen(merchant: _merchant()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Clothes / ملابس'), findsOneWidget);
    expect(find.text('Blue Shirt'), findsOneWidget);
    expect(find.text('USB Charger'), findsNothing);
    expect(find.text('Chargers'), findsNothing);
  });

  testWidgets(
    'merchant products screen requires color and size before direct add and preserves variant selections',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) =>
                  _FakeAuthController(ref, AuthState(user: _customerUser())),
            ),
            merchantsApiProvider.overrideWithValue(_FakeMerchantsApi()),
            behaviorApiProvider.overrideWithValue(_FakeBehaviorApi()),
            ordersControllerProvider.overrideWith(
              (ref) => _FakeOrdersController(ref),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: MerchantProductsScreen(merchant: _merchant()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MerchantProductsScreen)),
      );
      final card = find.byKey(const ValueKey(11));
      final addButton = find.descendant(
        of: card,
        matching: find.byIcon(Icons.tune_rounded),
      );

      expect(
        find.descendant(of: card, matching: find.textContaining('غير متوفر')),
        findsWidgets,
      );
      expect(
        find.descendant(of: card, matching: find.text('اختر اللون')),
        findsWidgets,
      );
      expect(
        find.descendant(of: card, matching: find.text('اختر المقاس')),
        findsWidgets,
      );

      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.text('اختر اللون والمقاس أولاً'), findsOneWidget);
      expect(container.read(cartControllerProvider).items, isEmpty);

      await tester.tap(find.descendant(of: card, matching: find.text('أحمر')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: card, matching: find.text('M')));
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.text('تمت إضافة المنتج إلى السلة'), findsOneWidget);

      final cart = container.read(cartControllerProvider);
      expect(cart.items, hasLength(1));
      expect(cart.items.single.product.id, 11);
      expect(cart.items.single.selectedVariantId, 1012);
      expect(cart.items.single.selectedVariantSelections, hasLength(2));
      expect(
        cart.items.single.selectedVariantSelections.any(
          (entry) =>
              entry['groupCode'] == 'color' && entry['optionCode'] == 'red',
        ),
        isTrue,
      );
      expect(
        cart.items.single.selectedVariantSelections.any(
          (entry) => entry['groupCode'] == 'size' && entry['optionCode'] == 'm',
        ),
        isTrue,
      );
    },
  );
}
