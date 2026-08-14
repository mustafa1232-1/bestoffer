import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/media/cached_app_image.dart';
import 'package:maslaki/core/media/media_url.dart';
import 'package:maslaki/features/products/models/product_model.dart';
import 'package:maslaki/features/products/ui/product_summary_card.dart';

void main() {
  CachedAppImage cachedImage(WidgetTester tester, String url) {
    // The product model resolves media URLs to absolute (resolveMediaUrl), so
    // the CachedAppImage receives the resolved URL, not the raw relative path.
    final resolved = resolveMediaUrl(url);
    final finder = find.byWidgetPredicate(
      (widget) => widget is CachedAppImage && widget.imageUrl == resolved,
    );
    expect(finder, findsWidgets);
    return tester.widgetList<CachedAppImage>(finder).first;
  }

  ProductModel buildProduct({
    required String name,
    required String categoryName,
    String imageUrl = '/main.jpg',
    List<Map<String, dynamic>> attributes = const [],
    List<Map<String, dynamic>> variantGroups = const [],
    List<Map<String, dynamic>> variants = const [],
    List<Map<String, dynamic>> media = const [],
    bool trackStock = false,
    String? stockMode,
  }) {
    return ProductModel.fromJson({
      'id': 1,
      'merchantId': 2,
      'categoryId': 7,
      'categoryName': categoryName,
      'name': name,
      'price': 12000,
      'discountedPrice': 9000,
      'isAvailable': true,
      'isInStock': true,
      'sortOrder': 0,
      'imageUrl': imageUrl,
      'trackStock': trackStock,
      'stockMode': stockMode ?? (trackStock ? 'tracked' : 'untracked'),
      'attributes': attributes,
      'variantGroups': variantGroups,
      'variants': variants,
      'media': media,
    });
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(
            child: Center(child: SizedBox(width: 380, child: child)),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'product card is image-first and cloths display as Clothes / ملابس',
    (tester) async {
      final product = buildProduct(
        name: 'قميص صيفي',
        categoryName: 'cloths',
        attributes: const [
          {
            'code': 'material',
            'labelAr': 'الخامة',
            'labelEn': 'Material',
            'valueText': 'Cotton',
            'showInCard': true,
          },
        ],
      );

      await tester.pumpWidget(
        wrap(
          ProductSummaryCard.fromProduct(
            product,
            compact: false,
            showDescription: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final imageRect = tester.getRect(find.byType(AspectRatio).first);
      final categoryRect = tester.getRect(
        find.byKey(const ValueKey('product-summary-category')),
      );

      expect(imageRect.top < categoryRect.top, isTrue);
      expect(find.text('Clothes / ملابس'), findsWidgets);
      expect(find.text('قميص صيفي'), findsOneWidget);
      expect(find.textContaining('Cotton'), findsWidgets);
    },
  );

  testWidgets('tapping a color changes the image and filters sizes', (
    tester,
  ) async {
    final product = buildProduct(
      name: 'قميص متعدد الألوان',
      categoryName: 'cloths',
      variantGroups: const [
        {
          'code': 'color',
          'labelAr': 'اللون',
          'labelEn': 'Color',
          'displayMode': 'swatches',
          'selectionMode': 'single',
          'required': true,
          'options': [
            {
              'code': 'red',
              'labelAr': 'أحمر',
              'labelEn': 'Red',
              'swatchHex': '#FF0000',
              'isAvailable': true,
            },
            {
              'code': 'blue',
              'labelAr': 'أزرق',
              'labelEn': 'Blue',
              'swatchHex': '#0000FF',
              'isAvailable': true,
            },
          ],
        },
        {
          'code': 'size',
          'labelAr': 'المقاس',
          'labelEn': 'Size',
          'displayMode': 'chips',
          'selectionMode': 'single',
          'required': true,
          'options': [
            {'code': 's', 'labelAr': 'S', 'labelEn': 'S', 'isAvailable': true},
            {'code': 'm', 'labelAr': 'M', 'labelEn': 'M', 'isAvailable': true},
            {'code': 'l', 'labelAr': 'L', 'labelEn': 'L', 'isAvailable': true},
          ],
        },
      ],
      variants: const [
        {
          'id': 11,
          'signature': 'color:red|size:s',
          'selections': [
            {'groupCode': 'color', 'optionCode': 'red'},
            {'groupCode': 'size', 'optionCode': 's'},
          ],
          'stockQuantity': 3,
          'isAvailable': true,
        },
        {
          'id': 12,
          'signature': 'color:red|size:m',
          'selections': [
            {'groupCode': 'color', 'optionCode': 'red'},
            {'groupCode': 'size', 'optionCode': 'm'},
          ],
          'stockQuantity': 2,
          'isAvailable': true,
        },
        {
          'id': 13,
          'signature': 'color:blue|size:l',
          'selections': [
            {'groupCode': 'color', 'optionCode': 'blue'},
            {'groupCode': 'size', 'optionCode': 'l'},
          ],
          'stockQuantity': 5,
          'isAvailable': true,
        },
      ],
      media: const [
        {
          'imageUrl': '/red.jpg',
          'variantGroupCode': 'color',
          'variantOptionCode': 'red',
          'isPrimary': true,
          'sortOrder': 0,
        },
        {
          'imageUrl': '/blue.jpg',
          'variantGroupCode': 'color',
          'variantOptionCode': 'blue',
          'isPrimary': false,
          'sortOrder': 1,
        },
      ],
    );

    await tester.pumpWidget(
      wrap(ProductSummaryCard.fromProduct(product, compact: false)),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(cachedImage(tester, '/red.jpg').imageUrl, resolveMediaUrl('/red.jpg'));
    expect(find.text('S'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('L'), findsNothing);

    await tester.tap(find.text('أزرق'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(cachedImage(tester, '/blue.jpg').imageUrl, resolveMediaUrl('/blue.jpg'));
    expect(find.text('S'), findsNothing);
    expect(find.text('M'), findsNothing);
    expect(find.text('L'), findsOneWidget);
  });

  testWidgets('color without image uses the main image', (tester) async {
    final product = buildProduct(
      name: 'منتج بلا صورة لون',
      categoryName: 'cloths',
      variantGroups: const [
        {
          'code': 'color',
          'labelAr': 'اللون',
          'labelEn': 'Color',
          'displayMode': 'swatches',
          'selectionMode': 'single',
          'required': true,
          'options': [
            {
              'code': 'red',
              'labelAr': 'أحمر',
              'labelEn': 'Red',
              'swatchHex': '#FF0000',
            },
            {
              'code': 'blue',
              'labelAr': 'أزرق',
              'labelEn': 'Blue',
              'swatchHex': '#0000FF',
            },
          ],
        },
      ],
      variants: const [
        {
          'id': 21,
          'signature': 'color:red',
          'selections': [
            {'groupCode': 'color', 'optionCode': 'red'},
          ],
          'stockQuantity': 5,
          'isAvailable': true,
        },
        {
          'id': 22,
          'signature': 'color:blue',
          'selections': [
            {'groupCode': 'color', 'optionCode': 'blue'},
          ],
          'stockQuantity': 5,
          'isAvailable': true,
        },
      ],
    );

    await tester.pumpWidget(
      wrap(ProductSummaryCard.fromProduct(product, compact: false)),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(cachedImage(tester, '/main.jpg').imageUrl, resolveMediaUrl('/main.jpg'));

    await tester.tap(find.text('أزرق'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(cachedImage(tester, '/main.jpg').imageUrl, resolveMediaUrl('/main.jpg'));
  });

  test('selection resolves the exact variant id when color and size match', () {
    final product = buildProduct(
      name: 'منتج مطابق',
      categoryName: 'cloths',
      variantGroups: const [
        {
          'code': 'color',
          'labelAr': 'اللون',
          'labelEn': 'Color',
          'displayMode': 'swatches',
          'selectionMode': 'single',
          'required': true,
          'options': [
            {
              'code': 'red',
              'labelAr': 'أحمر',
              'labelEn': 'Red',
              'swatchHex': '#FF0000',
              'isAvailable': true,
            },
          ],
        },
        {
          'code': 'size',
          'labelAr': 'المقاس',
          'labelEn': 'Size',
          'displayMode': 'chips',
          'selectionMode': 'single',
          'required': true,
          'options': [
            {'code': 'm', 'labelAr': 'M', 'labelEn': 'M', 'isAvailable': true},
          ],
        },
      ],
      variants: const [
        {
          'id': 31,
          'signature': 'color:red|size:m',
          'selections': [
            {'groupCode': 'color', 'optionCode': 'red'},
            {'groupCode': 'size', 'optionCode': 'm'},
          ],
          'stockQuantity': 9,
          'isAvailable': true,
        },
      ],
    );

    final selection = ProductSummaryCardData.fromProduct(
      product,
    ).resolveSelection(selectedColorCode: 'red', selectedSizeCode: 'm');

    expect(selection.variantId, 31);
    expect(selection.selectedVariantSelections, hasLength(2));
    expect(selection.colorCode, 'red');
    expect(selection.sizeCode, 'm');
  });

  test(
    'selection resolves variant id from selections when signature diverges',
    () {
      final product = buildProduct(
        name: 'منتج بتوقيع قديم',
        categoryName: 'cloths',
        variantGroups: const [
          {
            'code': 'color',
            'labelAr': 'اللون',
            'labelEn': 'Color',
            'displayMode': 'swatches',
            'selectionMode': 'single',
            'required': true,
            'options': [
              {
                'code': 'نيلي',
                'labelAr': 'نيلي',
                'labelEn': 'Navy',
                'swatchHex': '#000080',
                'isAvailable': true,
              },
            ],
          },
          {
            'code': 'size',
            'labelAr': 'المقاس',
            'labelEn': 'Size',
            'displayMode': 'chips',
            'selectionMode': 'single',
            'required': true,
            'options': [
              {
                'code': 'XL',
                'labelAr': 'XL',
                'labelEn': 'XL',
                'isAvailable': true,
              },
            ],
          },
        ],
        variants: const [
          {
            'id': 77,
            'signature': 'SIZE=XL;COLOR=Navy',
            'selections': [
              {'groupCode': 'color', 'optionCode': 'نيلي '},
              {'groupCode': 'size', 'optionCode': ' xl'},
            ],
            'stockQuantity': 3,
            'isAvailable': true,
          },
        ],
      );

      final selection = ProductSummaryCardData.fromProduct(
        product,
      ).resolveSelection(selectedColorCode: 'نيلي', selectedSizeCode: 'XL');

      expect(selection.variantId, 77);
      expect(selection.selectedVariantSelections, hasLength(2));
    },
  );

  testWidgets('simple product without variants still renders normally', (
    tester,
  ) async {
    final product = buildProduct(
      name: 'منتج بسيط',
      categoryName: 'generic',
      attributes: const [
        {
          'code': 'brand',
          'labelAr': 'الماركة',
          'labelEn': 'Brand',
          'valueText': 'BestOffer',
          'showInCard': true,
        },
      ],
    );

    await tester.pumpWidget(
      wrap(ProductSummaryCard.fromProduct(product, compact: false)),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('منتج بسيط'), findsOneWidget);
    expect(find.text('اللون'), findsNothing);
    expect(find.text('المقاس'), findsNothing);
    expect(find.byType(CachedAppImage), findsOneWidget);
    expect(cachedImage(tester, '/main.jpg').imageUrl, resolveMediaUrl('/main.jpg'));
  });

  testWidgets(
    'detailed specifications render inside the card with item detail lines',
    (tester) async {
      final product = buildProduct(
        name: 'منتج مفصل',
        categoryName: 'cloths',
        attributes: const [
          {
            'code': 'material',
            'labelAr': 'الخامة',
            'labelEn': 'Material',
            'valueText': 'Cotton',
            'showInCard': true,
            'showInDetails': true,
          },
        ],
        variantGroups: const [
          {
            'code': 'color',
            'labelAr': 'اللون',
            'labelEn': 'Color',
            'displayMode': 'swatches',
            'selectionMode': 'single',
            'required': true,
            'options': [
              {
                'code': 'red',
                'labelAr': 'أحمر',
                'labelEn': 'Red',
                'swatchHex': '#FF0000',
                'isAvailable': true,
              },
            ],
          },
          {
            'code': 'size',
            'labelAr': 'المقاس',
            'labelEn': 'Size',
            'displayMode': 'chips',
            'selectionMode': 'single',
            'required': true,
            'options': [
              {
                'code': 'm',
                'labelAr': 'M',
                'labelEn': 'M',
                'isAvailable': true,
              },
            ],
          },
        ],
        variants: const [
          {
            'id': 51,
            'signature': 'color:red|size:m',
            'selections': [
              {'groupCode': 'color', 'optionCode': 'red'},
              {'groupCode': 'size', 'optionCode': 'm'},
            ],
            'stockQuantity': 7,
            'isAvailable': true,
          },
        ],
      );

      await tester.pumpWidget(
        wrap(
          ProductSummaryCard.fromProduct(
            product,
            compact: false,
            showDetailedSpecifications: true,
            detailedSpecificationLines: const [
              'المقاس: صغير / وسط / كبير',
              'الخامة: قطن 100%',
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final card = tester.widget<ProductSummaryCard>(
        find.byType(ProductSummaryCard),
      );
      expect(card.showDetailedSpecifications, isTrue);
      expect(card.data.detailedSpecificationLines, hasLength(2));
      expect(card.data.specificationBadges, isNotEmpty);
      expect(find.text('Full specifications'), findsOneWidget);
      expect(find.text('المقاس: صغير / وسط / كبير'), findsOneWidget);
      expect(find.text('الخامة: قطن 100%'), findsOneWidget);
      expect(find.textContaining('Cotton'), findsWidgets);
      expect(find.text('Color'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
    },
  );

  test('tracked zero-stock variants do not preselect in quick order flows', () {
    final product = buildProduct(
      name: 'Ù…Ù†ØªØ¬ ØºÙŠØ± Ù…ØªØ§Ø­',
      categoryName: 'cloths',
      trackStock: true,
      stockMode: 'tracked',
      variantGroups: const [
        {
          'code': 'color',
          'labelAr': 'Ø§Ù„Ù„ÙˆÙ†',
          'labelEn': 'Color',
          'displayMode': 'swatches',
          'selectionMode': 'single',
          'required': true,
          'options': [
            {
              'code': 'red',
              'labelAr': 'Ø£Ø­Ù…Ø±',
              'labelEn': 'Red',
              'swatchHex': '#FF0000',
              'isAvailable': true,
            },
          ],
        },
      ],
      variants: const [
        {
          'id': 41,
          'signature': 'color:red',
          'selections': [
            {'groupCode': 'color', 'optionCode': 'red'},
          ],
          'stockQuantity': 0,
          'isAvailable': true,
        },
      ],
    );

    final selection = ProductSummaryCardData.fromProduct(
      product,
    ).resolveSelection();

    expect(selection.variantId, isNull);
    expect(selection.selectedVariantSelections, isEmpty);
  });

  test('untracked zero-stock variants can still be preselected', () {
    final product = buildProduct(
      name: 'Ù…Ù†ØªØ¬ Ù…ØªØ§Ø­ Ù…Ø¹ ØªØªØ¨Ø¹ Ù…ØºÙ„Ù‚',
      categoryName: 'cloths',
      trackStock: false,
      stockMode: 'untracked',
      variantGroups: const [
        {
          'code': 'color',
          'labelAr': 'Ø§Ù„Ù„ÙˆÙ†',
          'labelEn': 'Color',
          'displayMode': 'swatches',
          'selectionMode': 'single',
          'required': true,
          'options': [
            {
              'code': 'red',
              'labelAr': 'Ø£Ø­Ù…Ø±',
              'labelEn': 'Red',
              'swatchHex': '#FF0000',
              'isAvailable': true,
            },
          ],
        },
      ],
      variants: const [
        {
          'id': 42,
          'signature': 'color:red',
          'selections': [
            {'groupCode': 'color', 'optionCode': 'red'},
          ],
          'stockQuantity': 0,
          'isAvailable': true,
        },
      ],
    );

    final selection = ProductSummaryCardData.fromProduct(
      product,
    ).resolveSelection();

    expect(selection.variantId, 42);
    expect(selection.selectedVariantSelections, isNotEmpty);
  });
}
