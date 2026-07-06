import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/orders/logic/order_preview_errors.dart';

DioException _outOfStockError(Map<String, dynamic>? details) {
  final requestOptions = RequestOptions(path: '/api/orders/preview');
  return DioException(
    requestOptions: requestOptions,
    response: Response(
      requestOptions: requestOptions,
      statusCode: 400,
      data: {
        'message': 'PRODUCT_OUT_OF_STOCK',
        'requestId': 'req-1',
        'details': ?details,
      },
    ),
  );
}

void main() {
  test('parses structured PRODUCT_OUT_OF_STOCK details from backend', () {
    final parsed = OutOfStockDetails.fromError(
      _outOfStockError({
        'reason': 'OUT_OF_STOCK',
        'productId': 9,
        'productName': 'mm',
        'variantId': 101,
        'colorName': 'purpel',
        'size': 'xl',
        'requestedQuantity': 1,
        'availableQuantity': 0,
      }),
    );

    expect(parsed, isNotNull);
    expect(parsed!.productId, 9);
    expect(parsed.variantId, 101);
    expect(parsed.userMessage, contains('mm'));
    expect(parsed.userMessage, contains('باللون purpel'));
    expect(parsed.userMessage, contains('بالمقاس xl'));
    expect(parsed.userMessage, contains('غير متوفر'));
  });

  test('partial availability message exposes the available quantity', () {
    final parsed = OutOfStockDetails.fromError(
      _outOfStockError({
        'productName': 'mm',
        'requestedQuantity': 5,
        'availableQuantity': 3,
      }),
    );

    expect(parsed!.userMessage, contains('المتاح: 3'));
  });

  test('parses PRODUCT_UNAVAILABLE details from backend', () {
    final requestOptions = RequestOptions(path: '/api/orders/preview');
    final error = DioException(
      requestOptions: requestOptions,
      response: Response(
        requestOptions: requestOptions,
        statusCode: 400,
        data: {
          'message': 'PRODUCT_UNAVAILABLE',
          'details': {
            'reason': 'VARIANT_UNAVAILABLE',
            'productId': 8,
            'productName': 'Shirt',
            'variantId': 99,
            'requestedQuantity': 0,
            'availableQuantity': 0,
            'userMessageAr': 'المنتج "Shirt" غير متاح حالياً.',
            'userMessageEn': 'Product "Shirt" is currently unavailable.',
          },
        },
      ),
    );

    final parsed = OutOfStockDetails.fromError(error);
    expect(parsed, isNotNull);
    expect(parsed!.productId, 8);
    expect(parsed.variantId, 99);
    expect(parsed.userMessage, contains('غير متاح حالياً'));
    expect(parsed.userMessageEnglish, contains('currently unavailable'));
    expect(OutOfStockDetails.fromError(Exception('boom')), isNull);
  });

  test('matchesCartItem targets the exact variant line', () {
    const parsed = OutOfStockDetails(productId: 9, variantId: 101);

    expect(parsed.matchesCartItem(productId: 9, variantId: 101), isTrue);
    expect(parsed.matchesCartItem(productId: 9, variantId: 102), isFalse);
    expect(parsed.matchesCartItem(productId: 8, variantId: 101), isFalse);

    const productLevel = OutOfStockDetails(productId: 9);
    expect(productLevel.matchesCartItem(productId: 9, variantId: 55), isTrue);
    expect(productLevel.matchesCartItem(productId: 7), isFalse);
  });
}
