import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:maslaki/features/orders/models/cart_item_model.dart';
import 'package:maslaki/features/orders/models/order_item_presentation_model.dart';
import 'package:maslaki/features/orders/ui/widgets/order_item_widgets.dart';
import 'package:maslaki/features/products/models/product_model.dart';

ProductModel _product({
  required String name,
  double price = 10000,
  String? imageUrl,
}) {
  return ProductModel.fromJson(<String, dynamic>{
    'id': 100,
    'merchant_id': 7,
    'category_id': 1,
    'category_name': 'cloths',
    'name': name,
    'price': price,
    'image_url': imageUrl,
    'free_delivery': false,
    'is_available': true,
    'sort_order': 0,
  });
}

OrderItemPresentationModel _legacyPresentation() {
  return OrderItemPresentationModel.fromRawMap(<String, dynamic>{
    'id': 55,
    'order_id': 77,
    'product_id': 100,
    'product_name': 'Legacy Shirt',
    'quantity': 2,
    'unit_price': 5000,
    'line_total': 10000,
    'currency': 'IQD',
    'selected_variant_json': <String, dynamic>{
      'colorLabel': 'Black',
      'sizeLabel': 'XL',
    },
    'selected_variant_options_json': <Map<String, dynamic>>[
      <String, dynamic>{
        'groupCode': 'color',
        'groupLabel': 'Color',
        'optionCode': 'black',
        'optionLabel': 'Black',
        'hex': '#000000',
      },
      <String, dynamic>{
        'groupCode': 'size',
        'groupLabel': 'Size',
        'optionCode': 'xl',
        'optionLabel': 'XL',
      },
    ],
    'selected_modifiers_json': <Map<String, dynamic>>[
      <String, dynamic>{'label': 'Warranty', 'value': '2 years'},
    ],
    'user_note': 'Please pack carefully',
    'activity_type': 'fashion_clothing',
    'store_id': 7,
    'store_name': 'Legacy Store',
  });
}

OrderItemPresentationModel _arabicVariantPresentation() {
  return OrderItemPresentationModel.fromRawMap(<String, dynamic>{
    'id': 56,
    'order_id': 78,
    'product_id': 4,
    'product_name': 'هاتف سامسونك',
    'quantity': 1,
    'unit_price': 590000,
    'line_total': 590000,
    'currency': 'IQD',
    'selected_variant_json': <String, dynamic>{
      'variantId': 3,
      'signature': 'color:ابيض|size:ذاكرة_512',
    },
    'selected_variant_options_json': <Map<String, dynamic>>[
      <String, dynamic>{
        'groupCode': 'color',
        'groupLabel': 'اللون',
        'optionCode': 'ابيض',
        'optionLabel': 'ابيض',
        'hex': '#FFFFFF',
      },
      <String, dynamic>{
        'groupCode': 'size',
        'groupLabel': 'المقاس',
        'optionCode': 'ذاكرة_512',
        'optionLabel': 'ذاكرة 512',
      },
    ],
    'activity_type': 'electronics_mobile',
    'store_id': 34,
    'store_name': 'الضمان التقني للموبايلات',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? previousLocale;

  setUp(() {
    previousLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'en';
  });

  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  tearDown(() {
    Intl.defaultLocale = previousLocale;
  });

  test('cart item adapter preserves selected color and size', () {
    final cartItem = CartItemModel(
      product: _product(name: 'Adapter Shirt', imageUrl: '/shirt.jpg'),
      quantity: 2,
      merchantId: 7,
      merchantName: 'Adapter Store',
      selectedVariantId: 4242,
      selectedVariantSelections: const <Map<String, dynamic>>[
        <String, dynamic>{
          'groupCode': 'color',
          'groupLabel': 'Color',
          'optionCode': 'black',
          'optionLabel': 'Black',
          'hex': '#000000',
        },
        <String, dynamic>{
          'groupCode': 'size',
          'groupLabel': 'Size',
          'optionCode': 'xl',
          'optionLabel': 'XL',
        },
      ],
    );

    final presentation = OrderItemPresentationModel.fromCartItemModel(cartItem);

    expect(presentation.productName, 'Adapter Shirt');
    expect(presentation.quantity, 2);
    expect(presentation.selectedColor?.value, 'Black');
    expect(presentation.selectedSize?.value, 'XL');
    expect(presentation.visibleSpecs, hasLength(2));
    expect(presentation.displayImageUrl, '/shirt.jpg');
  });

  test('legacy order item without snapshot hydrates fallback fields', () {
    final presentation = _legacyPresentation();

    expect(presentation.displaySnapshotJson, isNotNull);
    expect(presentation.productName, 'Legacy Shirt');
    expect(presentation.storeName, 'Legacy Store');
    expect(presentation.selectedColor?.value, 'Black');
    expect(presentation.selectedSize?.value, 'XL');
    expect(presentation.specs, hasLength(2));
    expect(presentation.hasNote, isTrue);
    expect(presentation.displayImageUrl, isNull);
  });

  testWidgets('order item thumbnail falls back by activity type', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrderItemThumbnail(
              imageUrl: null,
              activityType: 'restaurant',
              size: 56,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
  });

  testWidgets('order item mini card renders details and fallback thumbnail', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: Directionality(
            textDirection: ui.TextDirection.rtl,
            child: OrderItemMiniCard(
              item: _legacyPresentation(),
              compact: false,
              showStoreName: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.checkroom_rounded), findsOneWidget);
    expect(find.text('Legacy Shirt'), findsOneWidget);
    expect(find.text('Legacy Store'), findsOneWidget);
    expect(find.textContaining('Color: Black'), findsWidgets);
    expect(find.textContaining('Size: XL'), findsWidgets);
    expect(find.textContaining('Warranty: 2 years'), findsWidgets);
    expect(find.textContaining('Please pack carefully'), findsWidgets);
    expect(find.textContaining('2 x IQD5,000'), findsOneWidget);
    expect(find.textContaining('IQD5,000'), findsWidgets);
    expect(find.textContaining('IQD10,000'), findsWidgets);
  });

  testWidgets('store order item shows Arabic color and size selections', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: Scaffold(
          body: Directionality(
            textDirection: ui.TextDirection.rtl,
            child: OrderItemMiniCard(
              item: _arabicVariantPresentation(),
              compact: false,
              showStoreName: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('هاتف سامسونك'), findsOneWidget);
    expect(find.text('الضمان التقني للموبايلات'), findsOneWidget);
    expect(find.textContaining('اللون: ابيض'), findsWidgets);
    expect(find.textContaining('المقاس: ذاكرة 512'), findsWidgets);
  });

  testWidgets('order invoice section groups by store and shows totals', (
    tester,
  ) async {
    final items = <OrderItemPresentationModel>[
      OrderItemPresentationModel.fromRawMap(<String, dynamic>{
        'version': 1,
        'productId': 1,
        'productName': 'Store A Shirt',
        'quantity': 1,
        'unitPrice': 5000,
        'lineTotal': 5000,
        'currency': 'IQD',
        'specs': const <Map<String, dynamic>>[
          <String, dynamic>{'label': 'Color', 'value': 'Black'},
        ],
        'storeId': 1,
        'storeName': 'Store A',
      }),
      OrderItemPresentationModel.fromRawMap(<String, dynamic>{
        'version': 1,
        'productId': 2,
        'productName': 'Store B Socks',
        'quantity': 2,
        'unitPrice': 2500,
        'lineTotal': 5000,
        'currency': 'IQD',
        'specs': const <Map<String, dynamic>>[
          <String, dynamic>{'label': 'Size', 'value': 'M'},
        ],
        'storeId': 2,
        'storeName': 'Store B',
      }),
    ];

    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: Directionality(
            textDirection: ui.TextDirection.rtl,
            child: SingleChildScrollView(
              child: OrderInvoiceSection(
                items: items,
                groupByStore: true,
                title: 'Invoice',
                orderNumber: '#77',
                orderTime: DateTime.utc(2026, 7, 10, 12, 30),
                paymentMethod: 'Cash',
                subtotal: 10000,
                serviceFee: 500,
                deliveryFee: 1000,
                couponDiscountTotal: 250,
                totalAmount: 11250,
                helperText: 'تحقق من عدد المنتجات قبل الاستلام',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Invoice'), findsOneWidget);
    expect(find.text('Store A'), findsOneWidget);
    expect(find.text('Store B'), findsOneWidget);
    expect(find.textContaining('#77'), findsWidgets);
    expect(find.textContaining('Cash'), findsWidgets);
    expect(find.textContaining('IQD10,000'), findsWidgets);
    expect(find.textContaining('IQD500'), findsWidgets);
    expect(find.textContaining('IQD1,000'), findsWidgets);
    expect(find.textContaining('IQD11,250'), findsWidgets);
    expect(find.text('تحقق من عدد المنتجات قبل الاستلام'), findsOneWidget);
  });
}
