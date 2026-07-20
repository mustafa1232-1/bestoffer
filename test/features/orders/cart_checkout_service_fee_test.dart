import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:maslaki/core/files/local_image_file.dart';
import 'package:maslaki/core/platform/app_flavor.dart';
import 'package:maslaki/core/storage/secure_storage.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/orders/data/orders_api.dart';
import 'package:maslaki/features/orders/models/delivery_address_model.dart';
import 'package:maslaki/features/orders/state/cart_controller.dart';
import 'package:maslaki/features/orders/state/delivery_address_controller.dart';
import 'package:maslaki/features/orders/state/orders_controller.dart';
import 'package:maslaki/features/orders/ui/cart_screen.dart';
import 'package:maslaki/features/products/models/product_model.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeSecureStore extends SecureStore {
  _FakeSecureStore() : super(flavor: AppFlavor.user);

  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> clear() async {
    _values.clear();
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<bool?> readBool(String key) async {
    final raw = await readString(key);
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    if (normalized == '1' || normalized == 'true') return true;
    if (normalized == '0' || normalized == 'false') return false;
    return null;
  }

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<String?> readToken() async => _values['access_token'];

  @override
  Future<void> saveAuthTokens({
    required String accessToken,
    String? refreshToken,
    String? deviceSessionId,
    String? deviceRecoverySecret,
  }) async {
    await saveToken(accessToken);
    if (refreshToken != null && refreshToken.trim().isNotEmpty) {
      _values['refresh_token'] = refreshToken.trim();
    }
    if (deviceSessionId != null && deviceSessionId.trim().isNotEmpty) {
      _values['device_session_id'] = deviceSessionId.trim();
    }
    if (deviceRecoverySecret != null &&
        deviceRecoverySecret.trim().isNotEmpty) {
      _values['device_recovery_secret'] = deviceRecoverySecret.trim();
    }
  }

  @override
  Future<void> saveGuestMode(bool enabled) async {
    if (enabled) {
      _values['guest_mode_active'] = '1';
    } else {
      _values.remove('guest_mode_active');
    }
  }

  @override
  Future<void> saveToken(String token) async {
    _values['access_token'] = token;
  }

  @override
  Future<void> writeBool(String key, bool value) async {
    _values[key] = value ? '1' : '0';
  }

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, AuthState initialState) {
    state = initialState;
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeDeliveryAddressController extends DeliveryAddressController {
  _FakeDeliveryAddressController(super.ref, DeliveryAddressState initialState) {
    state = initialState;
  }

  @override
  Future<void> bootstrap({bool silent = false}) async {}
}

class _FakeOrdersApi extends OrdersApi {
  _FakeOrdersApi({required this.previewServiceFee, this.failPreview = false})
    : super(Dio());

  final int previewServiceFee;
  final bool failPreview;
  Map<String, dynamic>? previewErrorData;
  int previewCalls = 0;
  int createCalls = 0;
  Map<String, dynamic>? lastPreviewPayload;
  Map<String, dynamic>? lastCreatePayload;
  final List<Map<String, dynamic>> _orders = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> previewOrder(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    previewCalls += 1;
    lastPreviewPayload = Map<String, dynamic>.from(body);
    if (failPreview) {
      throw Exception('preview failed');
    }
    if (previewErrorData != null) {
      final requestOptions = RequestOptions(path: '/api/orders/preview');
      throw DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 400,
          data: previewErrorData,
        ),
      );
    }
    return _buildPreviewResponse();
  }

  @override
  Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> body, {
    LocalImageFile? imageFile,
  }) async {
    createCalls += 1;
    lastCreatePayload = Map<String, dynamic>.from(body);
    final order = _buildOrderResponse();
    _orders.add(order);
    return order;
  }

  @override
  Future<List<dynamic>> listMyOrders({int? limit, int offset = 0}) async {
    return List<dynamic>.from(_orders);
  }

  Map<String, dynamic> _buildPreviewResponse() {
    const subtotal = 10000;
    const deliveryFee = 1000;
    final totalAmount = subtotal + previewServiceFee + deliveryFee;

    return <String, dynamic>{
      'stores': <Map<String, dynamic>>[
        <String, dynamic>{
          'merchantId': 77,
          'merchantName': 'Test Merchant',
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'product_name': 'Test Product',
              'quantity': 1,
              'unit_price': subtotal,
              'line_total': subtotal,
            },
          ],
          'pricing': <String, dynamic>{'totalAmount': totalAmount},
        },
      ],
      'totals': <String, dynamic>{
        'grossSubtotal': subtotal,
        'productDiscountTotal': 0,
        'couponDiscountTotal': 0,
        'serviceFeeTotal': previewServiceFee,
        'deliveryFeeTotal': deliveryFee,
        'totalAmount': totalAmount,
      },
    };
  }

  Map<String, dynamic> _buildOrderResponse() {
    const subtotal = 10000;
    const deliveryFee = 1000;
    final totalAmount = subtotal + previewServiceFee + deliveryFee;

    return <String, dynamic>{
      'id': 9001,
      'merchant_id': 77,
      'customer_user_id': 15,
      'order_scope': 'single',
      'store_sequence': 1,
      'merchant_name': 'Test Merchant',
      'status': 'pending',
      'customer_full_name': 'Test Customer',
      'customer_phone': '0770000000',
      'customer_city': 'Basmaya',
      'customer_block': 'A1',
      'customer_building_number': '12',
      'customer_apartment': '3',
      'subtotal': subtotal,
      'gross_subtotal': subtotal,
      'product_discount_total': 0,
      'service_fee': previewServiceFee,
      'delivery_fee': deliveryFee,
      'coupon_discount_total': 0,
      'total_amount': totalAmount,
      'created_at': '2026-07-05T09:00:00.000Z',
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'order_id': 9001,
          'product_name': 'Test Product',
          'quantity': 1,
          'unit_price': subtotal,
          'line_total': subtotal,
        },
      ],
    };
  }
}

UserModel _testUser() {
  return UserModel(
    id: 15,
    fullName: 'Test Customer',
    phone: '0770000000',
    role: 'user',
    block: 'A1',
    buildingNumber: '12',
    apartment: '3',
    imageUrl: null,
    workTitle: null,
    workCompany: null,
    preferredLocale: 'en',
    isSuperAdmin: false,
  );
}

DeliveryAddressState _selectedAddressState() {
  const address = DeliveryAddressModel(
    id: 1,
    label: 'Home',
    city: 'Basmaya',
    block: 'A1',
    buildingNumber: '12',
    apartment: '3',
    isDefault: true,
  );
  return const DeliveryAddressState(
    addresses: <DeliveryAddressModel>[address],
    selectedAddressId: 1,
  );
}

ProductModel _testProduct() {
  return ProductModel.fromJson(<String, dynamic>{
    'id': 100,
    'merchant_id': 77,
    'name': 'Test Product',
    'price': 10000,
    'free_delivery': false,
    'is_available': true,
    'sort_order': 1,
  });
}

class _CartTestHarness {
  final _FakeOrdersApi api;
  final ProviderContainer container;

  const _CartTestHarness({required this.api, required this.container});
}

Future<_CartTestHarness> _pumpCartScreen(
  WidgetTester tester, {
  required _FakeOrdersApi api,
  CartController Function()? cartControllerBuilder,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 5200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(_FakeSecureStore()),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState(user: _testUser(), token: 'test-token'),
          ),
        ),
        deliveryAddressControllerProvider.overrideWith(
          (ref) => _FakeDeliveryAddressController(ref, _selectedAddressState()),
        ),
        ordersApiProvider.overrideWithValue(api),
        cartControllerProvider.overrideWith((ref) {
          final controller = cartControllerBuilder?.call() ?? CartController();
          if (cartControllerBuilder == null) {
            controller.addItem(
              product: _testProduct(),
              merchantId: 77,
              merchantName: 'Test Merchant',
            );
          }
          return controller;
        }),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: AppTheme.dark(),
        home: const CartScreen(),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));

  final element = tester.element(find.byType(CartScreen));
  final container = ProviderScope.containerOf(element);
  return _CartTestHarness(api: api, container: container);
}

Future<void> _startFinalReview(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.done_all_rounded));
  await tester.pump();
}

Future<void> _waitForReviewModal(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('تأكيد نهائي').evaluate().isNotEmpty) return;
  }
  expect(find.text('تأكيد نهائي'), findsOneWidget);
}

Future<void> _waitForCheckoutCompletion(
  WidgetTester tester,
  _CartTestHarness harness,
) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (harness.api.createCalls == 1 &&
        harness.container.read(ordersControllerProvider).orders.length == 1) {
      return;
    }
  }
  expect(harness.api.createCalls, 1);
  expect(harness.container.read(ordersControllerProvider).orders, hasLength(1));
}

Future<void> _waitForPreviewFailure(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('تعذر مراجعة الطلب الآن').evaluate().isNotEmpty) return;
  }
  expect(find.text('تعذر مراجعة الطلب الآن'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? previousLocale;

  setUp(() {
    previousLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'en';
  });

  tearDown(() {
    Intl.defaultLocale = previousLocale;
  });

  test('cart controller merges same specs and splits different specs', () {
    final controller = CartController();
    final product = _testProduct();
    final sameSpecs = const <Map<String, dynamic>>[
      {'groupCode': 'color', 'optionCode': 'red'},
      {'groupCode': 'size', 'optionCode': 'm'},
    ];
    final differentSpecs = const <Map<String, dynamic>>[
      {'groupCode': 'color', 'optionCode': 'blue'},
      {'groupCode': 'size', 'optionCode': 'm'},
    ];

    controller.addItem(
      product: product,
      merchantId: 77,
      merchantName: 'Test Merchant',
      quantity: 1,
      selectedVariantId: 11,
      selectedVariantSelections: sameSpecs,
    );
    controller.addItem(
      product: product,
      merchantId: 77,
      merchantName: 'Test Merchant',
      quantity: 2,
      selectedVariantId: 11,
      selectedVariantSelections: sameSpecs,
    );

    expect(controller.state.items, hasLength(1));
    expect(controller.state.items.first.quantity, 3);

    controller.addItem(
      product: product,
      merchantId: 77,
      merchantName: 'Test Merchant',
      quantity: 1,
      selectedVariantId: 12,
      selectedVariantSelections: differentSpecs,
    );

    expect(controller.state.items, hasLength(2));
    expect(controller.state.items[1].selectedVariantId, 12);
    expect(
      controller.state.items[1].selectedVariantSelections,
      equals(differentSpecs),
    );
  });

  testWidgets(
    'backend preview returns service fee 750 and checkout confirms 750, not 500',
    (tester) async {
      final harness = await _pumpCartScreen(
        tester,
        api: _FakeOrdersApi(previewServiceFee: 750),
      );

      await _startFinalReview(tester);
      await _waitForReviewModal(tester);

      expect(find.text('IQD750'), findsOneWidget);
      expect(find.text('IQD500'), findsNothing);
      expect(find.text('IQD11,750'), findsAtLeastNWidgets(2));

      await harness.container
          .read(ordersControllerProvider.notifier)
          .checkout();
      await _waitForCheckoutCompletion(tester, harness);

      expect(harness.api.previewCalls, 1);
      expect(harness.api.createCalls, 1);
      expect(harness.api.lastCreatePayload, isNotNull);
      expect(
        harness.api.lastCreatePayload!.containsKey('service_fee'),
        isFalse,
      );

      final ordersState = harness.container.read(ordersControllerProvider);
      expect(ordersState.orders, hasLength(1));
      expect(ordersState.orders.single.serviceFee, 750);
    },
  );

  testWidgets(
    'backend preview returns service fee 500 and checkout displays 500',
    (tester) async {
      final harness = await _pumpCartScreen(
        tester,
        api: _FakeOrdersApi(previewServiceFee: 500),
      );

      await _startFinalReview(tester);
      await _waitForReviewModal(tester);

      expect(find.text('IQD500'), findsOneWidget);
      expect(find.text('IQD11,500'), findsAtLeastNWidgets(2));

      await harness.container
          .read(ordersControllerProvider.notifier)
          .checkout();
      await _waitForCheckoutCompletion(tester, harness);

      expect(harness.api.createCalls, 1);
      final ordersState = harness.container.read(ordersControllerProvider);
      expect(ordersState.orders, hasLength(1));
      expect(ordersState.orders.single.serviceFee, 500);
    },
  );

  testWidgets('preview failure prevents order submission', (tester) async {
    final harness = await _pumpCartScreen(
      tester,
      api: _FakeOrdersApi(previewServiceFee: 750, failPreview: true),
    );

    await _startFinalReview(tester);
    await _waitForPreviewFailure(tester);

    expect(find.text('تعذر مراجعة الطلب الآن'), findsOneWidget);
    expect(harness.api.previewCalls, 1);
    expect(harness.api.createCalls, 0);
    expect(harness.container.read(ordersControllerProvider).orders, isEmpty);
  });

  testWidgets(
    'preview PRODUCT_UNAVAILABLE blocks checkout and shows the exact item',
    (tester) async {
      final api = _FakeOrdersApi(previewServiceFee: 750)
        ..previewErrorData = <String, dynamic>{
          'message': 'PRODUCT_UNAVAILABLE',
          'details': <String, dynamic>{
            'reason': 'MANUAL_DISABLED',
            'productId': 100,
            'productName': 'Test Product',
            'variantId': null,
            'requestedQuantity': 1,
            'availableQuantity': 0,
            'userMessageAr': 'المنتج "Test Product" غير متاح حالياً.',
            'userMessageEn': 'Product "Test Product" is currently unavailable.',
          },
        };

      final harness = await _pumpCartScreen(tester, api: api);

      await _startFinalReview(tester);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find
            .textContaining('currently unavailable')
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }

      expect(find.textContaining('Test Product'), findsWidgets);
      expect(find.textContaining('currently unavailable'), findsWidgets);
      expect(api.previewCalls, 1);
      expect(api.createCalls, 0);
      expect(harness.container.read(ordersControllerProvider).orders, isEmpty);
    },
  );

  testWidgets('cart and checkout preserve selected variant specs', (
    tester,
  ) async {
    final harness = await _pumpCartScreen(
      tester,
      api: _FakeOrdersApi(previewServiceFee: 500),
      cartControllerBuilder: () {
        final controller = CartController();
        controller.addItem(
          product: _testProduct(),
          merchantId: 77,
          merchantName: 'Test Merchant',
          selectedVariantId: 11,
          selectedVariantSelections: const [
            {
              'groupCode': 'color',
              'groupLabel': 'Color',
              'optionCode': 'black',
              'optionLabel': 'Black',
              'hex': '#000000',
            },
            {
              'groupCode': 'size',
              'groupLabel': 'Size',
              'optionCode': 'xl',
              'optionLabel': 'XL',
            },
          ],
        );
        return controller;
      },
    );

    expect(find.textContaining('Color: Black'), findsWidgets);
    expect(find.textContaining('Size: XL'), findsWidgets);

    await _startFinalReview(tester);
    await _waitForReviewModal(tester);

    expect(find.textContaining('Color: Black'), findsWidgets);
    expect(find.textContaining('Size: XL'), findsWidgets);
    expect(harness.api.previewCalls, 1);
    expect(harness.api.lastPreviewPayload, isNotNull);

    final items = List<Map<String, dynamic>>.from(
      harness.api.lastPreviewPayload!['items'] as List,
    );
    expect(items, hasLength(1));
    expect(items.single['selectedVariantSelections'], isA<List>());
    expect((items.single['selectedVariantSelections'] as List).length, 2);
    expect(
      (items.single['selectedVariantSelections'] as List).any(
        (entry) =>
            entry['groupCode'] == 'color' && entry['optionCode'] == 'black',
      ),
      isTrue,
    );
    expect(
      (items.single['selectedVariantSelections'] as List).any(
        (entry) => entry['groupCode'] == 'size' && entry['optionCode'] == 'xl',
      ),
      isTrue,
    );
  });
}
